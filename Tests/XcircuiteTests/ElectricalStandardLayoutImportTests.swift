import DesignFlowKernel
import ElectricalSignoffCore
import Foundation
import LayoutCore
import LayoutIO
import LayoutTech
import PhysicalDesignCore
import Testing
import ToolQualification
import DesignFlowKernel
@testable import Xcircuite

@Suite("Electrical standard layout import")
struct ElectricalStandardLayoutImportTests {
    @Test("checked-in DEF and LEF fixtures produce a canonical snapshot", .timeLimit(.minutes(1)))
    func importsCheckedInStandardFixtures() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-standard-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixtureRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/ElectricalSignoff/StandardLayout")
        try FileManager.default.copyItem(
            at: fixtureRoot.appending(path: "layout.def"),
            to: root.appending(path: "layout.def")
        )
        try FileManager.default.copyItem(
            at: fixtureRoot.appending(path: "technology.lef"),
            to: root.appending(path: "technology.lef")
        )
        try FileManager.default.copyItem(
            at: fixtureRoot.appending(path: "layer-map.json"),
            to: root.appending(path: "layer-map.json")
        )

        let executor = ElectricalStandardLayoutImportFlowStageExecutor(
            layoutInput: .path("layout.def"),
            layoutFormat: .def,
            technologyInput: .path("technology.lef"),
            technologyFormat: .lef,
            technologyLayerMappingInput: .path("layer-map.json"),
            topCellName: "top"
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(
                stageID: "electrical-signoff.standard-layout-import",
                displayName: "Standard layout import"
            ),
            context: FlowExecutionContext(
                projectRoot: root,
                runID: "electrical-standard-fixture-run",
                runDirectory: root.appending(path: "run"),
                workspaceStore: XcircuiteWorkspaceStore(),
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .succeeded, "\(result.diagnostics)")
        let manifestReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-standard-layout-input-manifest"
        })
        let manifestURL = try XcircuiteWorkspaceStore().url(
            forProjectRelativePath: manifestReference.path,
            inProjectAt: root
        )
        let manifest = try JSONDecoder().decode(
            ElectricalSignoffInputArtifactManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        try manifest.validate()
        #expect(manifest.inputArtifacts.count == 3)
        #expect(manifest.inputArtifacts.contains { $0.format == .def && $0.sha256.count == 64 })
        #expect(manifest.inputArtifacts.contains { $0.format == .lef && $0.sha256.count == 64 })
        #expect(manifest.inputArtifacts.contains { $0.path == "layer-map.json" && $0.format == .json })

        let snapshotReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-standard-physical-snapshot"
        })
        let snapshotURL = try XcircuiteWorkspaceStore().url(
            forProjectRelativePath: snapshotReference.path,
            inProjectAt: root
        )
        let snapshot = try PhysicalDesignJSONCodec().decode(
            PhysicalDesignSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        #expect(snapshot.topCell == "top")
        #expect(snapshot.routes.count == 1)
        #expect(snapshot.routes.first?.netID == "VDD")
    }

    @Test("LEF technology without an explicit layer map is blocked", .timeLimit(.minutes(1)))
    func blocksLEFWithoutLayerMapping() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-standard-lef-blocked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixtureRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/ElectricalSignoff/StandardLayout")
        try FileManager.default.copyItem(
            at: fixtureRoot.appending(path: "layout.def"),
            to: root.appending(path: "layout.def")
        )
        try FileManager.default.copyItem(
            at: fixtureRoot.appending(path: "technology.lef"),
            to: root.appending(path: "technology.lef")
        )

        let executor = ElectricalStandardLayoutImportFlowStageExecutor(
            layoutInput: .path("layout.def"),
            layoutFormat: .def,
            technologyInput: .path("technology.lef"),
            technologyFormat: .lef,
            topCellName: "top"
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(
                stageID: "electrical-signoff.standard-layout-import",
                displayName: "Standard layout import"
            ),
            context: FlowExecutionContext(
                projectRoot: root,
                runID: "electrical-standard-lef-blocked-run",
                runDirectory: root.appending(path: "run"),
                workspaceStore: XcircuiteWorkspaceStore(),
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.first?.code == "ELECTRICAL_STANDARD_LAYOUT_IMPORT_BLOCKED")
        #expect(result.diagnostics.first?.message.contains("GDS layer mapping") == true)
    }

    @Test("DEF routed connectivity becomes a digest-bearing physical snapshot", .timeLimit(.minutes(1)))
    func importsDEFConnectivity() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-standard-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.routedDEF.write(to: root.appending(path: "layout.def"), atomically: true, encoding: .utf8)
        let runID = "electrical-standard-layout-run"
        let executor = ElectricalStandardLayoutImportFlowStageExecutor(
            layoutInput: .path("layout.def"),
            layoutFormat: .def,
            topCellName: "top",
            technology: .standard()
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(
                stageID: "electrical-signoff.standard-layout-import",
                displayName: "Standard layout import"
            ),
            context: FlowExecutionContext(
                projectRoot: root,
                runID: runID,
                runDirectory: root.appending(path: "run"),
                workspaceStore: XcircuiteWorkspaceStore(),
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .succeeded)
        let manifestReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-standard-layout-input-manifest"
        })
        let manifestURL = try XcircuiteWorkspaceStore().url(
            forProjectRelativePath: manifestReference.path,
            inProjectAt: root
        )
        let manifest = try JSONDecoder().decode(
            ElectricalSignoffInputArtifactManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        try manifest.validate()
        #expect(manifest.inputArtifacts.count == 1)
        let reference = try #require(result.artifacts.first { $0.artifactID == "electrical-standard-physical-snapshot" })
        #expect(reference.sha256.count == 64)
        #expect(reference.byteCount > 0)
        let url = try XcircuiteWorkspaceStore().url(forProjectRelativePath: reference.path, inProjectAt: root)
        let snapshot = try PhysicalDesignJSONCodec().decode(PhysicalDesignSnapshot.self, from: Data(contentsOf: url))
        #expect(snapshot.topCell == "top")
        #expect(snapshot.nets.map { $0.id } == ["VDD"])
        #expect(snapshot.routes.count == 1)
        #expect(snapshot.routes.first?.netID == "VDD")
        #expect(snapshot.routes.first?.segments.first?.layer == 1)
    }

    @Test("layout geometry without electrical connectivity is blocked", .timeLimit(.minutes(1)))
    func blocksUnconnectedGeometry() throws {
        let top = LayoutCell(
            name: "TOP",
            shapes: [LayoutShape(
                layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                geometry: .rect(LayoutRect(
                    origin: .zero,
                    size: LayoutSize(width: 1, height: 1)
                ))
            )]
        )
        let document = LayoutDocument(name: "unconnected", cells: [top], topCellID: top.id)

        #expect(throws: ElectricalStandardLayoutImportError.self) {
            try ElectricalStandardLayoutSnapshotBuilder().build(
                document: document,
                technology: .standard(),
                sourceFormat: "gds"
            )
        }
    }

    @Test("GDSII and OASIS geometry can be paired with explicit DEF connectivity", .timeLimit(.minutes(1)))
    func importsGeometryWithExplicitConnectivity() async throws {
        for (format, extensionName) in [(LayoutFileFormat.gds, "gds"), (LayoutFileFormat.oasis, "oas")] {
            let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-standard-\(extensionName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let geometryTop = LayoutCell(
                name: "top",
                shapes: [
                    LayoutShape(
                        layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                        geometry: .rect(
                            LayoutRect(
                                origin: .zero,
                                size: LayoutSize(width: 1, height: 1)
                            )
                        )
                    )
                ]
            )
            let geometryDocument = LayoutDocument(
                name: "geometry",
                cells: [geometryTop],
                topCellID: geometryTop.id
            )
            let geometryURL = root.appending(path: "layout.\(extensionName)")
            try MaskDataFormatConverter(tech: .standard()).exportDocument(
                geometryDocument,
                to: geometryURL,
                format: format
            )
            try Self.routedDEF.write(
                to: root.appending(path: "connectivity.def"),
                atomically: true,
                encoding: .utf8
            )

            let executor = ElectricalStandardLayoutImportFlowStageExecutor(
                layoutInput: .path("layout.\(extensionName)"),
                layoutFormat: format,
                connectivityInput: .path("connectivity.def"),
                connectivityFormat: .def,
                topCellName: "top",
                technology: .standard()
            )
            let result = try await executor.execute(
                stage: FlowStageDefinition(
                    stageID: "electrical-signoff.standard-layout-import",
                    displayName: "Standard layout import"
                ),
                context: FlowExecutionContext(
                    projectRoot: root,
                    runID: "electrical-standard-\(extensionName)-run",
                    runDirectory: root.appending(path: "run"),
                    workspaceStore: XcircuiteWorkspaceStore(),
                    toolRegistry: ToolRegistry(),
                    healthResults: [:]
                )
            )

            #expect(result.status == .succeeded)
            let manifestReference = try #require(result.artifacts.first {
                $0.artifactID == "electrical-standard-layout-input-manifest"
            })
            let manifestURL = try XcircuiteWorkspaceStore().url(
                forProjectRelativePath: manifestReference.path,
                inProjectAt: root
            )
            let manifest = try JSONDecoder().decode(
                ElectricalSignoffInputArtifactManifest.self,
                from: Data(contentsOf: manifestURL)
            )
            try manifest.validate()
            #expect(manifest.inputArtifacts.count == 2)
            #expect(result.artifacts.contains { $0.artifactID == "electrical-standard-physical-snapshot" })
        }
    }

    private static let routedDEF = """
    VERSION 5.8 ;
    DESIGN top ;
    UNITS DISTANCE MICRONS 1000 ;
    NETS 1 ;
      - VDD ( PIN VDD ) + USE POWER + ROUTED M1 ( 100 200 ) ( 900 200 ) ;
    END NETS
    END DESIGN
    """
}
