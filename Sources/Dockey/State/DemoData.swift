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

    static let storage = StorageReport(
        usage: [
            StorageUsage(category: .images, count: 14, activeCount: 9, bytes: nil),
            StorageUsage(category: .containers, count: 11, activeCount: 9, bytes: 96_400_000),
            StorageUsage(category: .volumes, count: 7, activeCount: 3, bytes: 3_920_000_000),
            StorageUsage(category: .buildCache, count: 42, activeCount: 0, bytes: 1_640_000_000),
        ],
        candidates: [
            image("node:20-alpine", id: "demo-node-20", bytes: 162_000_000, created: "3 months ago"),
            image("postgres:16-alpine", id: "demo-postgres-16", bytes: 271_000_000, created: "2 months ago"),
            image("langfuse/langfuse:2", id: "demo-langfuse-2", bytes: 598_000_000, created: "5 weeks ago"),
            image(nil, id: "3f2a9c1d0b7e", bytes: 412_000_000, created: "6 days ago"),
            image(nil, id: "9b41e07ac2d5", bytes: 286_000_000, created: "2 weeks ago"),
            CleanupCandidate(
                kind: .stoppedContainer, identifier: "demo-storefront-worker", name: "storefront-worker-1",
                detail: "storefront-worker:dev · Exited (0)", bytes: 48_200_000, project: "storefront",
                removalArguments: ["container", "rm", "--", "demo-storefront-worker"]),
            CleanupCandidate(
                kind: .stoppedContainer, identifier: "demo-standalone-mailpit", name: "mailpit",
                detail: "axllent/mailpit:latest · Exited (0)", bytes: 1_300_000,
                removalArguments: ["container", "rm", "--", "demo-standalone-mailpit"]),
            volume("a81c4f0e92d7", anonymous: true, bytes: 734_000_000),
            volume("5e06bd31f7a8", anonymous: true, bytes: 88_000_000),
            volume("storefront_postgres_data_old", anonymous: false, bytes: 1_210_000_000, project: "storefront"),
            volume("scratch_uploads", anonymous: false, bytes: 12_400_000),
            CleanupCandidate(
                kind: .buildCache, identifier: "demo-cache-1", name: "[api 4/6] RUN npm ci",
                detail: "regular · Last used 9 days ago", bytes: 912_000_000),
            CleanupCandidate(
                kind: .buildCache, identifier: "demo-cache-2", name: "[worker 3/5] RUN pip install -r requirements.txt",
                detail: "regular · Last used 3 weeks ago", bytes: 507_000_000),
            CleanupCandidate(
                kind: .buildCache, identifier: "demo-cache-3", name: "local source for context",
                detail: "source.local · Last used 9 days ago", bytes: 221_000_000),
        ].sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) })

    private static func image(_ reference: String?, id: String, bytes: UInt64, created: String) -> CleanupCandidate {
        CleanupCandidate(
            kind: reference == nil ? .danglingImage : .unusedImage, identifier: id,
            name: reference ?? "<none> · \(id)", detail: "Created \(created)", bytes: bytes,
            removalArguments: ["image", "rm", "--", reference ?? id])
    }

    private static func volume(_ name: String, anonymous: Bool, bytes: UInt64, project: String? = nil)
        -> CleanupCandidate
    {
        CleanupCandidate(
            kind: anonymous ? .anonymousVolume : .namedVolume, identifier: name, name: name, detail: "local",
            bytes: bytes, project: project, removalArguments: ["volume", "rm", "--", name])
    }

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
