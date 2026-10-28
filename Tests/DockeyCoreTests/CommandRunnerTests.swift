import Darwin
import Foundation
import Testing

@testable import DockeyCore

@Suite("Process execution", .serialized)
struct CommandRunnerTests {
    let runner = ProcessCommandRunner()
    let python = URL(fileURLWithPath: "/usr/bin/python3")

    @Test func drainsBothPipesWithoutDeadlocking() async throws {
        let output = try await runner.run(
            CommandRequest(
                executableURL: python,
                arguments: ["-c", "import os; os.write(1,b'o'*200000); os.write(2,b'e'*200000)"], timeout: 5))
        #expect(output.exitCode == 0)
        #expect(output.stdout.utf8.count == 200_000)
        #expect(output.stderr.utf8.count == 200_000)
    }

    @Test func excessiveOutputIsBounded() async {
        do {
            _ = try await runner.run(
                CommandRequest(
                    executableURL: python,
                    arguments: ["-c", "import os; os.write(1,b'x'*200000)"], timeout: 5, outputLimitBytes: 2_048))
            Issue.record("Unbounded process output was accepted")
        } catch {
            #expect(error as? DockerError == .outputLimitExceeded)
        }
    }

    @Test func timeoutCompletesPromptly() async {
        let start = ContinuousClock.now
        do {
            _ = try await runner.run(
                CommandRequest(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.05))
            Issue.record("Sleeping process did not time out")
        } catch {
            #expect(error as? DockerError == .timedOut)
        }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func taskCancellationStopsWaitingForTheChild() async throws {
        let start = ContinuousClock.now
        let task = Task {
            try await runner.run(
                CommandRequest(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 10))
        }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled process returned success")
        } catch { #expect(error is CancellationError) }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func streamingIncludesBothLogChannelsAndUnicode() async throws {
        let request = CommandRequest(
            executableURL: python,
            arguments: ["-c", "import os; os.write(1,'ready 🐳\\n'.encode()); os.write(2,b'application error\\n')"],
            timeout: 5)
        var text = ""
        for try await chunk in runner.stream(request) { text += chunk }
        #expect(text.contains("ready 🐳"))
        #expect(text.contains("application error"))
    }

    @Test func argumentsAreNotInterpretedAsShellSyntax() async throws {
        let value = "$(printf unsafe); `printf unsafe` & | >"
        let output = try await runner.run(
            CommandRequest(executableURL: URL(fileURLWithPath: "/bin/echo"), arguments: [value]))
        #expect(output.stdout == value + "\n")
    }

    @Test func structuredStreamsRetainDiagnosticsWithoutDecodingStderr() async throws {
        var text = ""
        for try await chunk in runner.stream(
            CommandRequest(
                executableURL: python,
                arguments: ["-c", "import os; os.write(1,b'{}\\n'); os.write(2,b'fixture warning\\n')"],
                timeout: 5, streamStderr: false))
        { text += chunk }
        #expect(text == "{}\n")
        do {
            for try await _ in runner.stream(
                CommandRequest(
                    executableURL: python,
                    arguments: ["-c", "import sys; print('fixture failure',file=sys.stderr); sys.exit(1)"],
                    timeout: 5, streamStderr: false))
            {}
            Issue.record("Nonzero structured stream exit was accepted")
        } catch { #expect(error as? DockerError == .commandFailed("fixture failure\n")) }
    }

    @Test func streamLifetimeOutputIsNotCumulativelyLimited() async throws {
        var count = 0
        for try await chunk in runner.stream(
            CommandRequest(
                executableURL: python,
                arguments: ["-c", "import os; os.write(1,b'fixture\\n'*4000)"],
                timeout: 5, outputLimitBytes: 1_024, streamStderr: false))
        { count += chunk.utf8.count }
        #expect(count == 32_000)
    }

    @Test func cancelAllTerminatesAnIdleStreamWithoutTouchingAnotherRunner() async throws {
        let owned = ProcessCommandRunner()
        let other = ProcessCommandRunner()
        let start = ContinuousClock.now
        let stream = owned.stream(
            CommandRequest(
                executableURL: python,
                arguments: ["-c", "import os,time; print(os.getpid(),flush=True); time.sleep(30)"], timeout: 2))
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        #expect(
            start.duration(to: .now) < .seconds(1),
            "Sparse output must arrive while the child is still idle, not only at EOF.")
        let pid = try #require(first.flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        #expect(kill(pid, 0) == 0)
        owned.cancelAll()
        do { _ = try await iterator.next() } catch { #expect(error is CancellationError) }
        for _ in 0..<20 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(kill(pid, 0) != 0)
        let output = try await other.run(
            CommandRequest(executableURL: URL(fileURLWithPath: "/bin/echo"), arguments: ["still independent"]))
        #expect(output.stdout == "still independent\n")
    }
}
