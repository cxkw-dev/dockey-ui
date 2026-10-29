import Foundation
import Testing

@testable import DockeyCore

@Suite("Storage analysis")
struct StorageTests {
    let usedImage = "sha256:" + String(repeating: "1", count: 64)
    let unusedImage = "sha256:" + String(repeating: "2", count: 64)
    let danglingImage = "sha256:" + String(repeating: "3", count: 64)
    let anonymousVolume = String(repeating: "c", count: 64)

    private var fixture: String {
        """
        {"Images":[
          {"ID":"\(usedImage)","Repository":"fixture-used","Tag":"latest","Containers":"1","Size":"300MB","UniqueSize":"20MB"},
          {"ID":"\(unusedImage)","Repository":"fixture-old","Tag":"v1","Containers":"0","Size":"200MB","UniqueSize":"150MB","CreatedSince":"3 weeks ago"},
          {"ID":"\(unusedImage)","Repository":"fixture-old","Tag":"v2","Containers":"0","Size":"200MB","UniqueSize":"150MB"},
          {"ID":"\(danglingImage)","Repository":"<none>","Tag":"<none>","Containers":"0","Size":"90MB","UniqueSize":"90MB"}
        ],
        "Containers":[
          {"ID":"\(String(repeating: "a", count: 64))","Names":"fixture-running","State":"running","Size":"1MB","Labels":""},
          {"ID":"\(String(repeating: "b", count: 64))","Names":"fixture-stopped","Image":"fixture-used","State":"exited","Status":"Exited (0) 2 days ago","Size":"4.5MB (virtual 300MB)","Labels":"com.docker.compose.project=fixture,com.docker.compose.service=worker"}
        ],
        "Volumes":[
          {"Name":"fixture_attached","Driver":"local","Links":"1","Size":"2GB","Labels":""},
          {"Name":"\(anonymousVolume)","Driver":"local","Links":"0","Size":"700MB","Labels":"com.docker.volume.anonymous="},
          {"Name":"fixture_data","Driver":"local","Links":"0","Size":"1.2GB","Labels":"com.docker.compose.project=fixture,com.docker.compose.volume=data"},
          {"Name":"fixture_unknown","Driver":"local","Links":"-1","Size":"N/A","Labels":""}
        ],
        "BuildCache":[
          {"ID":"cache-active","CacheType":"regular","Size":"10MB","InUse":true,"Shared":false},
          {"ID":"cache-idle","CacheType":"regular","Description":"[fixture 2/3] RUN make","Size":"40MB","InUse":"false","LastUsedSince":"9 days ago"}
        ]}
        """
    }

    @Test func classifiesCandidatesByKindAndSortsBySize() throws {
        let report = try DockerParsing.storage(fixture)
        #expect(
            report.candidates.map(\.kind) == [
                .namedVolume, .anonymousVolume, .unusedImage, .danglingImage, .buildCache, .stoppedContainer,
            ])
        #expect(
            report.reclaimableBytes
                == 1_200_000_000 + 700_000_000 + 150_000_000 + 90_000_000 + 40_000_000 + 4_500_000)
        #expect(report.lowRiskReclaimableBytes == 700_000_000 + 150_000_000 + 90_000_000 + 40_000_000)
        #expect(!report.candidates.contains { $0.identifier == usedImage || $0.identifier == "fixture_unknown" })
    }

    @Test func multiTaggedImagesAreOneCandidateRemovedByReference() throws {
        let report = try DockerParsing.storage(fixture)
        let images = report.candidates(.unusedImage)
        #expect(images.count == 1)
        #expect(images.first?.name == "fixture-old:v1, fixture-old:v2")
        #expect(images.first?.removalArguments == ["image", "rm", "--", "fixture-old:v1", "fixture-old:v2"])
        #expect(report.candidates(.danglingImage).first?.removalArguments == ["image", "rm", "--", danglingImage])
    }

    @Test func composeOwnershipComesFromLabels() throws {
        let report = try DockerParsing.storage(fixture)
        #expect(report.candidates(.stoppedContainer).first?.project == "fixture")
        #expect(report.candidates(.namedVolume).first?.project == "fixture")
        #expect(report.candidates(.anonymousVolume).first?.project == nil)
    }

    @Test func usageTotalsCountActiveResources() throws {
        let usage = try DockerParsing.storage(fixture).usage
        #expect(usage.map(\.count) == [3, 2, 4, 2])
        #expect(usage.map(\.activeCount) == [1, 1, 1, 1])
        #expect(usage.first?.bytes == nil)
        #expect(usage[2].bytes == 3_900_000_000)
    }

    @Test func namedVolumesAndBuildCacheHaveNoBulkOrItemRemoval() throws {
        #expect(CleanupKind.namedVolume.bulkArguments == nil)
        #expect(CleanupKind.anonymousVolume.bulkArguments == ["volume", "prune"])
        #expect(try DockerParsing.storage(fixture).candidates(.buildCache).allSatisfy { $0.removalArguments == nil })
    }

    @Test func parsesDockerHumanSizes() {
        #expect(ByteSize.parse("0B") == 0)
        #expect(ByteSize.parse("4.096kB") == 4_096)
        #expect(ByteSize.parse("1.167GB (6%)") == 1_167_000_000)
        #expect(ByteSize.parse("16.4kB (virtual 256MB)") == 16_400)
        #expect(ByteSize.parse("12 MiB") == 12 * 1_048_576)
        #expect(ByteSize.parse("N/A") == nil)
        #expect(ByteSize.parse("-1B") == nil)
    }

    @Test func commandsArePinnedToTheContextAndShellQuoted() {
        #expect(CleanupCommand.render(["image", "prune"], context: "colima") == "docker --context colima image prune")
        #expect(
            CleanupCommand.render(["volume", "rm", "--", "it's data"], context: "Demo workspace")
                == #"docker --context 'Demo workspace' volume rm -- 'it'\''s data'"#)
        #expect(CleanupCommand.render(["volume", "rm", "--", "$(touch x)"], context: "c").hasSuffix("'$(touch x)'"))
    }

    @Test func rejectsUnreadableOutput() {
        #expect(throws: DockerError.invalidResponse("disk usage")) { try DockerParsing.storage("not json") }
    }
}
