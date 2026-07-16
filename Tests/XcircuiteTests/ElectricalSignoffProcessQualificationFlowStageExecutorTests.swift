import Testing
@testable import Xcircuite

@Suite("Electrical signoff package authority boundary")
struct ElectricalSignoffPackageAuthorityBoundaryTests {
    @Test("electrical package exposes corpus observation execution")
    func electricalPackageExposesCorpusObservationExecution() async throws {
        let descriptor = try #require(
            XcircuiteEnginePackageCatalog.descriptors.first { $0.packageID == "ElectricalSignoffEngine" }
        )

        #expect(descriptor.stageIDs.contains("electrical-signoff.corpus"))
        #expect(descriptor.outputArtifactRoles.contains { $0.rawValue == "electrical-corpus-report" })
    }

    @Test("electrical package does not own qualification or release stages")
    func electricalPackageDoesNotOwnQualificationOrReleaseStages() async throws {
        let descriptor = try #require(
            XcircuiteEnginePackageCatalog.descriptors.first { $0.packageID == "ElectricalSignoffEngine" }
        )

        #expect(descriptor.stageIDs.contains { $0.contains("qualification") } == false)
        #expect(descriptor.stageIDs.contains { $0.contains("release") } == false)
    }

    @Test("release package owns release lifecycle stages")
    func releasePackageOwnsReleaseLifecycleStages() async throws {
        let descriptor = try #require(
            XcircuiteEnginePackageCatalog.descriptors.first { $0.packageID == "ReleaseEngine" }
        )

        #expect(descriptor.stageIDs == ["release.authorization", "release.signoff", "release.tapeout"])
        #expect(descriptor.outputArtifactRoles.contains { $0.rawValue == "release-authorization-decision" })
    }

    @Test("electrical corpus tool reports observations without trust authority")
    func electricalCorpusToolReportsObservationsWithoutTrustAuthority() async throws {
        let descriptor = SignoffToolDescriptors.nativeElectricalCorpus()
        let capability = try #require(descriptor.capabilities.first)

        #expect(capability.operationID == "observe-electrical-signoff-corpus")
        #expect(capability.operationID.contains("qualify") == false)
        #expect(capability.operationID.contains("release") == false)
    }
}
