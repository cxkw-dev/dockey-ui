import Foundation
import Testing

@testable import DockeyCore

private actor StubRunner: CommandRunning {
    var requests: [CommandRequest] = []
    var outputs: [CommandOutput]
    init(_ outputs: [CommandOutput]) { self.outputs = outputs }
    func run(_ request: CommandRequest) async throws -> CommandOutput {
        requests.append(request)
        guard !outputs.isEmpty else { throw DockerError.commandFailed("Unexpected test command") }
        return outputs.removeFirst()
    }
    nonisolated func stream(_ request: CommandRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream {
            $0.yield("fixture log\n")
            $0.finish()
        }
    }
}

@Suite("Docker client scope and lifecycle safety")
struct DockerClientTests {
    let idA = String(repeating: "a", count: 64)
    let idB = String(repeating: "b", count: 64)
    let local = CommandOutput(stdout: #""unix:///tmp/dockey-fixture.sock""#)

    private func client(_ runner: StubRunner) -> DockerClient {
        DockerClient(executableURL: URL(fileURLWithPath: "/bin/echo"), runner: runner)
    }

    @Test func rejectsRemoteEndpointBeforeAnEngineCommand() async throws {
        let runner = StubRunner([CommandOutput(stdout: #""ssh://fixture.example""#)])
        do {
            _ = try await client(runner).containers(context: "remote")
            Issue.record("Remote endpoint was accepted")
        } catch {
            #expect(error as? DockerError == .remoteContextUnsupported("remote"))
        }
        let requests = await runner.requests
        #expect(requests.count == 1)
        #expect(requests.first?.arguments.prefix(2) == ["context", "inspect"])
    }

    @Test func validatesTheEntireMutationPlanBeforeExecuting() async throws {
        let runner = StubRunner([])
        do {
            _ = try await client(runner).perform(.stop, containerIDs: [idA, "--all"], context: "local")
            Issue.record("An invalid identifier was accepted")
        } catch {
            #expect(error as? DockerError == .invalidContainerID)
        }
        let requests = await runner.requests
        #expect(requests.isEmpty)
    }

    @Test func partialFailureIsReportedPerContainerAndDoesNotChangeGlobalContext() async throws {
        let runner = StubRunner([
            local, CommandOutput(stdout: idA),
            CommandOutput(stderr: "fixture container disappeared", exitCode: 1),
        ])
        let report = try await client(runner).perform(
            .stop, containerIDs: [idB, idA, idA], context: "fixture", stopTimeout: 20)
        #expect(!report.succeeded)
        #expect(report.results.map(\.succeeded) == [true, false])
        #expect(report.results[1].message == "fixture container disappeared")
        let requests = await runner.requests
        #expect(requests.count == 3)
        #expect(requests[1].arguments == ["--context", "fixture", "container", "stop", "--timeout", "20", "--", idA])
        #expect(requests[2].arguments.last == idB)
        #expect(
            !requests.contains {
                $0.arguments.contains("use") || $0.arguments.contains("prune") || $0.arguments.contains("rm")
            })
    }

    @Test func untaggedAndMultiTaggedImagesHaveStableDistinctDisplayIDs() async throws {
        let runner = StubRunner([
            local,
            CommandOutput(
                stdout: """
                    {"ID":"sha256:fixture","Repository":"fixture","Tag":"v1","Size":"12MB","CreatedSince":"1 day ago"}
                    {"ID":"sha256:fixture","Repository":"fixture","Tag":"latest","Size":"12MB","CreatedSince":"1 day ago"}
                    """),
        ])
        let images = try await client(runner).images(context: "fixture")
        #expect(images.count == 2)
        #expect(Set(images.map(\.id)).count == 2)
        #expect(images.map(\.displayName) == ["fixture:latest", "fixture:v1"])
    }

    @Test func nonFollowingLogsIncludeContainerStderr() async throws {
        let runner = StubRunner([local, CommandOutput(stdout: "ready\n", stderr: "application error\n")])
        let logs = try await client(runner).logs(containerID: idA, context: "fixture", tail: 50_000)
        #expect(logs.contains("ready"))
        #expect(logs.contains("application error"))
        let requests = await runner.requests
        #expect(requests.last?.arguments.contains("10000") == true)
    }

    @Test func emptyEngineNeedsNoInspectProcess() async throws {
        let runner = StubRunner([local, CommandOutput()])
        let containers = try await client(runner).containers(context: "fixture")
        let requests = await runner.requests
        #expect(containers.isEmpty)
        #expect(requests.count == 2)
    }
}

@Suite("Structured parsing and redaction")
struct DockerParsingTests {
    let fixture = #"""
        [{
          "Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "Name":"/fixture-api-1","Created":"2026-01-01T00:00:00Z",
          "Config":{"Image":"fixture:dev","Env":["API_KEY=super-secret-value","MODE=development"],
            "Cmd":["serve","--password=also-private"],
            "Healthcheck":{"Test":["CMD-SHELL","curl -H 'Authorization: private-health-token'"]},
            "Labels":{"com.docker.compose.project":"fixture,project","com.docker.compose.service":"api","auth.token":"private-label-token"}},
          "State":{"Status":"running","Health":{"Status":"unhealthy"}},
          "NetworkSettings":{"Ports":{"8080/tcp":[{"HostIp":"127.0.0.1","HostPort":"8088"},{"HostIp":"::1","HostPort":"8088"}],"53/udp":[{"HostIp":"127.0.0.1","HostPort":"5353"}],"9000/tcp":null}},
          "Mounts":[{"Type":"volume","Source":"fixture_data","Destination":"/data","RW":true}]
        }]
        """#

    @Test func inspectLabelsAreParsedWithoutCommaSplitting() throws {
        let result = try DockerParsing.containers(fixture)
        #expect(result.count == 1)
        #expect(result[0].project == "fixture,project")
        #expect(result[0].name == "fixture-api-1")
        #expect(result[0].isUnhealthy)
        #expect(result[0].ports.count == 3)
        #expect(Set(result[0].ports.map(\.id)).count == 3)
        #expect(result[0].ports.contains { $0.transport == "udp" && $0.display == "5353:53/udp" })
    }

    @Test func inspectionDoesNotExposeEnvironmentOrCommandSecrets() throws {
        let result = try DockerParsing.inspection(fixture)
        #expect(result.environmentKeys == ["API_KEY", "MODE"])
        #expect(!result.json.contains("super-secret-value"))
        #expect(!result.json.contains("development"))
        #expect(!result.json.contains("also-private"))
        #expect(!result.json.contains("private-health-token"))
        #expect(!result.json.contains("private-label-token"))
        #expect(result.json.contains("<redacted>"))
        #expect(result.mounts == ["volume: fixture_data → /data (read/write)"])
    }

    @Test func malformedJsonIsAnErrorRatherThanAnEmptyHealthyEngine() {
        #expect(throws: DockerError.self) { try DockerParsing.containers("not-json") }
        #expect(throws: DockerError.self) { try DockerParsing.containers("[{}]") }
    }

    @Test func healthHistoryOutputIsRedactedThroughNestedArrays() throws {
        let raw =
            #"[{"State":{"Health":{"Status":"unhealthy","Log":[{"Start":"2026-01-01","ExitCode":1,"Output":"Authorization: Bearer fixture-health-secret"}]}}}]"#
        let inspection = try DockerParsing.inspection(raw)
        #expect(!inspection.json.contains("fixture-health-secret"))
        #expect(!inspection.json.contains("Authorization"))
        #expect(inspection.json.contains("<redacted>"))
        #expect(inspection.json.contains("2026-01-01"))
        #expect(inspection.json.contains("ExitCode"))
    }

    @Test func percentagesUseNumbersAndMalformedValuesStayFinite() throws {
        let stats = try DockerParsing.stats(
            #"{"ID":"fixture","CPUPerc":"125.50%","MemUsage":"256MiB / 8GiB","MemPerc":"3.125%","NetIO":"2MB / 1MB","BlockIO":"3MB / 0B"}"#
        )
        #expect(stats.first?.cpuPercent == 125.5)
        #expect(stats.first?.memoryUsage == "256MiB")
        #expect(stats.first?.memoryPercent == 3.125)
        let invalid = try DockerParsing.stats(#"{"ID":"fixture","CPUPerc":"NaN%","MemPerc":"-5%"}"#)
        #expect(invalid.first?.cpuPercent == 0)
        #expect(invalid.first?.memoryPercent == 0)
    }
}
