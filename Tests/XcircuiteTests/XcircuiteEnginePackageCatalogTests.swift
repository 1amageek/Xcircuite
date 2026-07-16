import Testing
@testable import Xcircuite

@Suite("Engine package catalog")
struct XcircuiteEnginePackageCatalogTests {
    @Test("catalog covers every scaffold package")
    func coversEveryScaffoldPackage() {
        #expect(XcircuiteEnginePackageCatalog.descriptors.count == 9)
    }

    @Test("stage identifiers are globally unique")
    func stageIdentifiersAreUnique() {
        let stageIDs = XcircuiteEnginePackageCatalog.descriptors.flatMap(\.stageIDs)
        #expect(Set(stageIDs).count == stageIDs.count)
    }

    @Test("electrical package catalogs observation without qualification authority")
    func catalogsElectricalObservationBoundary() async throws {
        let descriptor = try #require(
            XcircuiteEnginePackageCatalog.descriptors.first { $0.packageID == "ElectricalSignoffEngine" }
        )
        #expect(descriptor.stageIDs.contains("electrical-signoff.corpus"))
        #expect(descriptor.stageIDs.contains { $0.contains("qualification") } == false)
        #expect(descriptor.stageIDs.contains { $0.contains("release") } == false)
        #expect(descriptor.inputArtifactRoles.contains("electrical-process-approval") == false)
        #expect(descriptor.outputArtifactRoles.contains("electrical-process-qualification-evidence") == false)
    }
}
