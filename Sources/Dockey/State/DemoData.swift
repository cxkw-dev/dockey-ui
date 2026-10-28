import DockeyCore
import Foundation

/// Synthetic fixtures for documentation and design review. Demo mode never constructs a Docker client.
enum DemoData {
    static let context = DockerContext(name: "Demo workspace", endpoint: "unix:///demo/docker.sock", isCurrent: true)
    static let engine = EngineInfo(
        serverVersion: "29.0 · demo", architecture: "aarch64", operatingSystem: "Demo Linux VM", cpus: 6,
        memoryBytes: 8 * 1024 * 1024 * 1024)
    static let containers: [DockerContainer] = [
        container("web", project: "storefront", image: "node:22-alpine", port: 3000),
        container("api", project: "storefront", image: "storefront-api:dev", port: 8080),
        container("postgres", project: "storefront", image: "postgres:17-alpine", port: 5432),
        container("worker", project: "storefront", image: "storefront-worker:dev", state: .exited),
        container("langfuse", project: "analytics", image: "langfuse/langfuse:3", health: .unhealthy, port: 3001),
        container("clickhouse", project: "analytics", image: "clickhouse:25-alpine", port: 8123),
        container("temporal", project: "analytics", image: "temporalio/server:1.29", port: 7233),
        container("redis-local", image: "redis:8-alpine", port: 6379),
        container("ai-focus", image: "ai-focus:latest", port: 4444),
        container("documents-local", image: "mongo:8", port: 27017),
        container("mailpit", image: "axllent/mailpit:latest", state: .exited, port: 8025),
    ]

    private static func container(
        _ service: String, project: String? = nil, image: String, state: ContainerState = .running,
        health: ContainerHealth? = .healthy, port: Int? = nil
    ) -> DockerContainer {
        DockerContainer(
            id: "demo-\(project ?? "standalone")-\(service)", name: project.map { "\($0)-\(service)-1" } ?? service,
            image: image, state: state, health: state == .running ? health : nil, project: project,
            service: project == nil ? nil : service,
            ports: port.map { [PortBinding(hostPort: $0, containerPort: $0)] } ?? [],
            createdAt: "2026-01-01T12:00:00Z", status: state == .running ? "Up 2 hours" : "Exited (0)")
    }

    static var stats: [String: ContainerStats] {
        Dictionary(
            uniqueKeysWithValues: containers.enumerated().filter { $0.element.isRunning }.map { offset, c in
                let cpu = [0.24, 0.68, 0.12, 0, 1.42, 0.36, 0.02, 0.04][min(offset, 7)]
                return (
                    c.id,
                    ContainerStats(
                        id: c.id, cpuPercent: cpu, memoryUsage: "\(64 + offset * 24) MiB",
                        memoryPercent: 12, networkIO: "2.4 MB / 1.1 MB", blockIO: "8.2 MB / 412 kB")
                )
            })
    }

    static let images = [
        ImageSummary(id: "demo-node", repository: "node", tag: "22-alpine", size: "168 MB", createdSince: "2 days ago"),
        ImageSummary(
            id: "demo-api", repository: "storefront-api", tag: "dev", size: "284 MB", createdSince: "3 hours ago"),
        ImageSummary(
            id: "demo-postgres", repository: "postgres", tag: "17-alpine", size: "277 MB", createdSince: "4 days ago"),
        ImageSummary(id: "demo-redis", repository: "redis", tag: "8-alpine", size: "42 MB", createdSince: "1 week ago"),
        ImageSummary(id: "demo-mongo", repository: "mongo", tag: "8", size: "312 MB", createdSince: "3 days ago"),
        ImageSummary(id: "demo-ai-focus", repository: "ai-focus", tag: "latest", size: "186 MB", createdSince: "1 day ago"),
        ImageSummary(
            id: "demo-clickhouse", repository: "clickhouse", tag: "25-alpine", size: "284 MB",
            createdSince: "2 days ago"),
        ImageSummary(
            id: "demo-langfuse", repository: "langfuse/langfuse", tag: "3", size: "612 MB",
            createdSince: "1 day ago"),
        ImageSummary(
            id: "demo-temporal", repository: "temporalio/server", tag: "1.29", size: "206 MB",
            createdSince: "3 days ago"),
    ]
    static let volumes = [
        VolumeSummary(
            id: "demo-postgres", name: "storefront_postgres_data", driver: "local",
            mountpoint: "/var/lib/docker/volumes/storefront_postgres_data/_data"),
        VolumeSummary(id: "demo-analytics", name: "analytics_clickhouse_data", driver: "local"),
        VolumeSummary(id: "demo-redis", name: "redis_data", driver: "local"),
    ]
    static let networks = [
        NetworkSummary(id: "demo-storefront", name: "storefront_default", driver: "bridge"),
        NetworkSummary(id: "demo-analytics", name: "analytics_default", driver: "bridge"),
        NetworkSummary(id: "demo-bridge", name: "bridge", driver: "bridge"),
    ]

    static func inspection(for container: DockerContainer) -> ContainerInspection {
        let json = """
            {
              "Name": "\(container.name)",
              "Image": "\(container.image)",
              "State": { "Status": "\(container.state.rawValue)" },
              "Environment": ["APP_ENV=[redacted]", "DATABASE_URL=[redacted]"],
              "RestartPolicy": "unless-stopped",
              "Demo": true
            }
            """
        return ContainerInspection(
            json: json, environmentKeys: ["APP_ENV", "DATABASE_URL"],
            mounts: ["Named volume: \(container.project ?? "local")_data → /var/lib/data (read/write)"])
    }

    static let logs = """
        2026-01-01T14:32:04Z  INFO  Starting application service
        2026-01-01T14:32:04Z  INFO  Configuration loaded · environment=development
        2026-01-01T14:32:04Z  INFO  Database connection established
        2026-01-01T14:32:04Z  INFO  Ready in 248ms
        2026-01-01T14:32:11Z  INFO  GET /health 200 2ms
        2026-01-01T14:32:18Z  INFO  GET /api/products 200 14ms
        2026-01-01T14:32:25Z  INFO  GET /api/products?page=2 200 11ms
        2026-01-01T14:32:31Z  WARN  Slow query · inventory_lookup · 142ms
        2026-01-01T14:32:38Z  INFO  GET /api/cart 200 8ms
        2026-01-01T14:32:42Z  INFO  POST /api/cart/items 201 18ms
        2026-01-01T14:32:44Z  INFO  GET /health 200 1ms
        2026-01-01T14:32:49Z  INFO  GET /api/products/sku-1024 200 12ms
        """
}
