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
}
