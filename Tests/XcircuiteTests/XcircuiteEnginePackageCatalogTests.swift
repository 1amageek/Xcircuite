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

    @Test("electrical package catalogs process qualification ownership")
    func catalogsElectricalProcessQualification() throws {
        let descriptor = try #require(
            XcircuiteEnginePackageCatalog.descriptors.first { $0.packageID == "ElectricalSignoffEngine" }
        )
        #expect(descriptor.stageIDs.contains("electrical-signoff.process-qualification"))
        #expect(descriptor.inputArtifactRoles.contains("electrical-process-approval"))
        #expect(descriptor.outputArtifactRoles.contains("electrical-process-qualification-evidence"))
    }
}
