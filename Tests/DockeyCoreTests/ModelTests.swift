import Foundation
import Testing

@testable import DockeyCore

@Suite("Grouping and public models")
struct ModelTests {
    private func container(
        _ name: String, project: String? = nil, state: ContainerState = .running,
        health: ContainerHealth? = nil
    ) -> DockerContainer {
        DockerContainer(
            id: String(repeating: "a", count: 64) + name, name: name, image: "fixture:latest",
            state: state, health: health, project: project)
    }

    @Test func composeLabelsDetermineOwnershipNotNames() {
        let items = [
            container("shop-api-1"), container("unrelated", project: "shop"),
            container("analytics-api", project: "analytics"), container("tool", project: ""),
        ]
        let groups = ContainerGrouping.groups(containers: items, context: "fixture")
        #expect(groups.map(\.name) == ["analytics", "shop", "Standalone containers"])
        #expect(groups.last?.containers.map(\.name) == ["shop-api-1", "tool"])
        #expect(groups[1].containers.map(\.name) == ["unrelated"])
        #expect(groups.last?.isCompose == false)
    }

    @Test func groupCountsDoNotCallStoppedContainersUnhealthy() {
        let items = [
            container("web", project: "shop", health: .healthy),
            container("api", project: "shop", health: .unhealthy),
            container("worker", project: "shop", state: .exited, health: .unhealthy),
        ]
        let group = ContainerGrouping.groups(containers: items, context: "fixture")[0]
        #expect(group.runningCount == 2)
        #expect(group.unhealthyCount == 1)
        #expect(group.containers.map(\.name) == ["api", "web", "worker"])
        #expect(group.id != ContainerGrouping.groups(containers: items, context: "other")[0].id)
    }

    @Test func onlyUnixSocketContextsAreLocal() {
        #expect(DockerContext(name: "local", endpoint: "unix:///tmp/docker.sock").isLocal)
        #expect(!DockerContext(name: "remote", endpoint: "ssh://server").isLocal)
        #expect(!DockerContext(name: "tcp", endpoint: "tcp://127.0.0.1:2375").isLocal)
        #expect(!DockerContext(name: "empty", endpoint: "unix://").isLocal)
    }
}
