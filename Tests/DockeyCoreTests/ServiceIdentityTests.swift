import Testing

@testable import DockeyCore

@Suite("Conservative service identity")
struct ServiceIdentityTests {
    @Test func recognizesDockerOfficialImagesAndVendorRepositories() {
        let examples: [(String, ServiceIdentity)] = [
            ("postgres", .postgresql), ("postgres:17-alpine", .postgresql),
            ("redis:8", .redis), ("mongo:8", .mongodb), ("clickhouse:latest", .clickhouse),
            ("clickhouse/clickhouse-server:25.8", .clickhouse),
            ("redis/redis-stack:latest", .redis), ("redis/redis-stack-server:latest", .redis),
            ("mongodb/mongodb-community-server:8.0-ubi9-slim", .mongodb),
            ("mongodb/mongodb-enterprise-server:8.0-ubi9-slim", .mongodb),
            ("mongodb/mongodb-atlas-local:8.0", .mongodb),
        ]
        for (image, identity) in examples {
            #expect(ServiceIdentity(imageReference: image) == identity, "Image: \(image)")
        }
    }

    @Test func normalizesTagsDigestsAndKnownDockerHubHosts() {
        let sha256 = "sha256:" + String(repeating: "a", count: 64)
        let sha512 = "sha512:" + String(repeating: "B", count: 128)
        let examples: [(String, ServiceIdentity)] = [
            ("docker.io/library/postgres:17", .postgresql),
            ("index.docker.io/library/mongo:8", .mongodb),
            ("registry-1.docker.io/library/redis:8", .redis),
            ("DOCKER.IO/clickhouse/clickhouse-server:25.8", .clickhouse),
            ("docker.io/mongodb/mongodb-atlas-local@\(sha256)", .mongodb),
            ("redis:8@\(sha256)", .redis),
            ("postgres@\(sha512)", .postgresql),
            ("mongo:Release_8.0", .mongodb),
            ("  docker.io/library/redis:8\n", .redis),
        ]
        for (image, identity) in examples {
            #expect(ServiceIdentity(imageReference: image) == identity, "Image: \(image)")
        }
    }

    @Test func recognizesOnlyExactLibraryAndArchitectureNamespaces() {
        let examples: [(String, ServiceIdentity)] = [
            ("library/postgres:17", .postgresql), ("library/mongo:8", .mongodb),
            ("arm64v8/postgres:17", .postgresql), ("amd64/redis:8", .redis),
            ("docker.io/arm64v8/mongo:8", .mongodb),
            ("docker.io/arm64v8/clickhouse:latest", .clickhouse),
            ("arm64/postgres:17", .generic), ("my-arm64v8/redis:8", .generic),
            ("arm64v8/library/postgres:17", .generic),
            ("arm64v8/mongodb/mongodb-atlas-local:8", .generic),
            ("library/redis/redis-stack:latest", .generic),
        ]
        for (image, identity) in examples {
            #expect(ServiceIdentity(imageReference: image) == identity, "Image: \(image)")
        }
    }

    @Test func preservesRegistryAndNamespaceOwnershipInsteadOfStrippingPrefixes() {
        let examples = [
            "evilregistry/redis:8", "acme/postgres:17", "acme/mongo:8", "acme/clickhouse:latest",
            "registry.example.com/library/redis:8", "localhost:5000/postgres:17",
            "ghcr.io/clickhouse/clickhouse-server:25.8", "docker.io.evil.test/library/redis:8",
            "evil.test/docker.io/library/mongo:8", "docker.io:5000/library/postgres:17",
            "index.docker.io:443/library/redis:8", "registry-1.docker.io.evil.test/mongo:8",
            "docker.io/acme/redis:8", "mongodb/redis:8", "redis/mongo:8",
        ]
        for image in examples {
            #expect(ServiceIdentity(imageReference: image) == .generic, "Untrusted repository: \(image)")
        }
    }

    @Test func customServicesAndNamesThatContainVendorWordsStayGeneric() {
        let examples = [
            "postgresql:17", "mongodb:8", "redis-stack:latest", "clickhouse-server:latest",
            "bitnami/postgresql:17", "bitnami/mongodb:8", "bitnami/redis:8", "altinity/clickhouse-server:latest",
            "shop-redis-cache:latest", "my-mongo-api:latest", "postgres-backup:latest",
            "mongo-express:latest", "redis/redisinsight:latest", "mongodb/mongodb-community-server-evil:8",
            "clickhouse/clickhouse-server-backup:latest", "postgres/analytics:latest",
            "company/mongodb/mongodb-atlas-local:8", "library/postgresql:17", "library/mongodb:8",
        ]
        for image in examples {
            #expect(ServiceIdentity(imageReference: image) == .generic, "Custom service: \(image)")
        }
    }

    @Test func malformedReferencesDoNotAcquireBrandIdentity() {
        let validDigest = "sha256:" + String(repeating: "a", count: 64)
        let examples = [
            "", "  ", "redis:", "redis:bad tag", "redis:-bad", "redis:tag:extra", "redis:é",
            "redis:" + String(repeating: "t", count: 129),
            "redis@", "redis@sha256:short", "redis@sha256:" + String(repeating: "z", count: 64),
            "redis@\(validDigest)@\(validDigest)", "redis@@\(validDigest)",
            "/redis:8", "docker.io//library/redis:8", "docker.io/library/redis/", "library/../redis:8",
            "https://docker.io/library/redis:8", "user@docker.io/library/redis:8",
            "Redis:8", "docker.io/Library/redis:8", "redis\u{0000}:8", "redis\n:8",
            "sha256:" + String(repeating: "a", count: 64), String(repeating: "a", count: 4_097),
        ]
        for image in examples {
            #expect(ServiceIdentity(imageReference: image) == .generic)
        }
    }
}
