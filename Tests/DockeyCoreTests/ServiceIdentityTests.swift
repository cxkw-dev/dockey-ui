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

    @Test func recognizesLangfuseWebAndWorkerOnVerifiedRegistryPaths() {
        let digest = "sha256:" + String(repeating: "a", count: 64)
        let examples = [
            "langfuse/langfuse:3", "langfuse/langfuse-worker:3",
            "docker.io/langfuse/langfuse:4", "index.docker.io/langfuse/langfuse-worker:4",
            "ghcr.io/langfuse/langfuse:3", "ghcr.io/langfuse/langfuse-worker:4",
            "GHCR.IO/langfuse/langfuse:4", "ghcr.io/langfuse/langfuse-worker@\(digest)",
            "docker.langfuse.com/langfuse/langfuse:4",
            "docker.langfuse.com/langfuse/langfuse-worker:4@\(digest)",
        ]
        for image in examples {
            #expect(ServiceIdentity(imageReference: image) == .langfuse, "Image: \(image)")
        }
    }

    @Test func recognizesExactTemporalServerDevelopmentToolsAndUIRepositories() {
        let digest = "sha256:" + String(repeating: "b", count: 64)
        let examples = [
            "temporalio/auto-setup:1.29", "temporalio/server:1.30", "temporalio/temporal:latest",
            "temporalio/admin-tools:1.30", "temporalio/ui:2",
            "docker.io/temporalio/server:1.30@\(digest)",
            "registry-1.docker.io/temporalio/ui@\(digest)",
        ]
        for image in examples {
            #expect(ServiceIdentity(imageReference: image) == .temporal, "Image: \(image)")
        }
    }

    @Test func additionalRegistriesDoNotExtendTrustToOtherRepositoriesOrConfusableBrands() {
        let examples = [
            "langfuse:3", "langfuse-worker:3", "temporal:latest", "temporalio:latest",
            "company/langfuse:3", "company/temporal:latest", "langfuse/langfuse-worker-backup:3",
            "temporalio/server-custom:1", "temporalio/ui-evil:2", "company/temporalio/server:1",
            "ghcr.io/company/langfuse:3", "ghcr.io/temporalio/server:1", "ghcr.io/library/redis:8",
            "ghcr.io.evil.test/langfuse/langfuse:3", "ghcr.io:5000/langfuse/langfuse:3",
            "evil.test/langfuse/langfuse:3", "evil.test/temporalio/server:1",
            "docker.langfuse.com.evil.test/langfuse/langfuse:4",
            "docker.langfuse.com:443/langfuse/langfuse:4", "docker.langfuse.com/library/postgres:17",
            "docker.langfuse.com/temporalio/server:1", "docker.langfuse.com/langfuse/langfuse-evil:4",
            "library/langfuse:3", "arm64v8/langfuse:3", "arm64v8/temporal:latest",
        ]
        for image in examples {
            #expect(ServiceIdentity(imageReference: image) == .generic, "Unverified repository: \(image)")
        }
    }

    @Test func recognizesTheConfirmedLocalAIFocusImageWithTagsAndDigests() {
        let digest = "sha256:" + String(repeating: "c", count: 64)
        for image in ["ai-focus", "ai-focus:latest", "ai-focus:v1.0.0", "ai-focus@\(digest)", "ai-focus:latest@\(digest)"] {
            #expect(ServiceIdentity(imageReference: image) == .aiFocus, "Image: \(image)")
        }
        #expect(ServiceIdentity.aiFocus.id == "ai-focus")
        #expect(ServiceIdentity.aiFocus.displayName == "AI Focus")
    }

    @Test func localAIFocusIdentityDoesNotApplyToRegistryCopiesOrSimilarServiceNames() {
        let examples = [
            "my-ai-focus:latest", "ai-focus-backend:latest", "ai-focus-mcp:latest", "aifocus:latest",
            "acme/ai-focus:latest", "ai-focus/api:latest", "library/ai-focus:latest", "arm64v8/ai-focus:latest",
            "docker.io/ai-focus:latest", "docker.io/library/ai-focus:latest", "index.docker.io/ai-focus:latest",
            "registry.example.com/ai-focus:latest", "localhost:5000/ai-focus:latest", "ghcr.io/acme/ai-focus:latest",
            "docker.langfuse.com/ai-focus:latest", "ai-focus:", "AI-FOCUS:latest",
        ]
        for image in examples {
            #expect(ServiceIdentity(imageReference: image) == .generic, "Different or malformed app image: \(image)")
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
