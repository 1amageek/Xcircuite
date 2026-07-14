import DesignFlowKernel
import CircuiteFoundation
import DRCEngine
import Foundation
import LayoutIO
import LayoutTech
import LVSEngine
import PEXEngine
import Testing
import ToolQualification
@testable import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

/// Converts a legacy fixture reference at test boundaries while the workspace
/// stores are migrated. Production APIs consume `ArtifactReference` directly.
func foundationReference(
    _ reference: XcircuiteFileReference,
    role: ArtifactRole = .input
) throws -> ArtifactReference {
    let kindRawValue: String = switch reference.kind {
    case .powerIntent: "power-intent"
    case .timingLibrary: "timing-library"
    case .testPattern: "test-pattern"
    case .ruleDeck: "rule-deck"
    case .designDiff: "design-diff"
    case .parasitic: "parasitics"
    default: reference.kind.rawValue
    }
    let formatRawValue: String = switch reference.format {
    case .systemVerilog: "system-verilog"
    default: reference.format.rawValue.lowercased()
    }
    let location: ArtifactLocation
    if reference.path.hasPrefix("/") {
        location = try ArtifactLocation(fileURL: URL(filePath: reference.path))
    } else {
        location = try ArtifactLocation(workspaceRelativePath: reference.path)
    }
    return ArtifactReference(
        id: try reference.artifactID.map { try ArtifactID(rawValue: $0) },
        locator: ArtifactLocator(
            location: location,
            role: role,
            kind: try ArtifactKind(rawValue: kindRawValue),
            format: try ArtifactFormat(rawValue: formatRawValue)
        ),
        digest: try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: reference.sha256 ?? String(repeating: "0", count: 64)
        ),
        byteCount: UInt64(max(reference.byteCount ?? 0, 0))
    )
}

extension XcircuiteFlowRuntimeTests {
    struct NoopDRCEngine: DRCExecuting {
        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            DRCExecutionResult(
                request: request,
                result: DRCResult(
                    backendID: "noop",
                    toolName: "NoopDRC",
                    success: true,
                    completed: true,
                    logPath: ""
                )
            )
        }
    }

    struct FlakyDRCEngine: DRCExecuting {
        let state: FlakyDRCEngineState

        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            try await state.run(request)
        }
    }

    struct AlwaysFailingDRCEngine: DRCExecuting {
        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            throw DRCError.backendUnavailable("Persistent native DRC startup failure.")
        }
    }

    actor FlakyDRCEngineState {
        var runCount = 0

        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            runCount += 1
            if runCount == 1 {
                throw DRCError.backendUnavailable("Transient native DRC startup failure.")
            }
            return try await DefaultDRCEngine(backend: nil).run(request)
        }

        func executionCount() -> Int {
            runCount
        }
    }

    struct EvidenceAttachmentOutput: Decodable {
        var status: String
        var stageID: String
        var evidenceID: String
        var evidenceKind: String
        var outputPath: String?
    }

    struct ValidationOutput: Decodable {
        var status: String
        var validated: [String]
        var runSpecPath: String?
        var runtimeConfigPath: String?
        var runStageCount: Int?
        var runtimeExecutorCount: Int?
    }

    struct StandardMaskLVSCase: Sendable, Hashable {
        var name: String
        var displayName: String
        var artifactID: String
        var exportFormat: LayoutFileFormat
        var artifactFormat: XcircuiteFileFormat
        var lvsFormat: LVSLayoutFormat
        var fileSuffix: String
    }

    struct WaveformArtifactExecutor: FlowStageExecutor {
        let stageID: String
        let toolID: String = "waveform-fixture"
        var artifactID: String
        var fileName: String
        var csv: String

        func execute(
            stage: FlowStageDefinition,
            context: FlowExecutionContext
        ) async throws -> FlowStageResult {
            guard stage.stageID == stageID else {
                throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
            }
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "raw")
            try context.storage.ensureDirectory(at: rawDirectory)
            let waveformURL = rawDirectory.appending(path: fileName)
            try context.storage.writeText(csv, to: waveformURL)
            let reference = try context.storage.fileReference(
                forProjectRelativePath: ".xcircuite/runs/\(context.runID)/stages/\(stage.stageID)/raw/\(fileName)",
                artifactID: artifactID,
                kind: .waveform,
                format: .csv,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: .succeeded,
                gates: [
                    FlowGateResult(gateID: "waveform-artifact", status: .passed),
                ],
                artifacts: [try foundationReference(reference)]
            )
        }
    }

    func drcRequirement(
        requiredLayoutFormat: ArtifactFormat = .json,
        requiredQualifiedEvidenceKinds: [ToolEvidenceKind] = []
    ) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .drc,
            operationID: "run-drc",
            minimumLevel: .corpusChecked,
            requiredInputFormats: [requiredLayoutFormat],
            requiredOutputFormats: [.json],
            requiredQualifiedEvidenceKinds: requiredQualifiedEvidenceKinds
        )
    }

    func layoutCommandRequirement(
        requiredStandardOutputFormat: ArtifactFormat? = nil
    ) -> ToolTrustRequirement {
        var outputFormats: [ArtifactFormat] = [.json]
        if let requiredStandardOutputFormat, !outputFormats.contains(requiredStandardOutputFormat) {
            outputFormats.append(requiredStandardOutputFormat)
        }
        return ToolTrustRequirement(
            kind: .layout,
            operationID: "edit-layout",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [.json],
            requiredOutputFormats: outputFormats
        )
    }

    func lvsRequirement(requiredLayoutFormat: ArtifactFormat = .gdsii) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .lvs,
            operationID: "run-lvs",
            minimumLevel: .corpusChecked,
            requiredInputFormats: [requiredLayoutFormat, .spice],
            requiredOutputFormats: [.json]
        )
    }

    func pexRequirement(requiredLayoutFormat: ArtifactFormat = .gdsii) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .pex,
            operationID: "run-pex",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [requiredLayoutFormat, .spice, .json],
            requiredOutputFormats: [.spef, .json]
        )
    }

    func mockPEXContractRequirement(requiredLayoutFormat: ArtifactFormat = .gdsii) -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .pex,
            operationID: "run-pex",
            minimumLevel: .unknown,
            requiredInputFormats: [requiredLayoutFormat, .spice, .json],
            requiredOutputFormats: [.spef, .json]
        )
    }

    func mockPEXContractToolSpec() -> XcircuiteFlowToolSpec {
        XcircuiteFlowToolSpec(
            qualificationLevel: .unknown,
            healthStatus: .passed
        )
    }

    func simulationRequirement() -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .simulation,
            operationID: "run-simulation",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [.spice],
            requiredOutputFormats: [.csv, .json]
        )
    }

    func comparisonRequirement() -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .simulation,
            operationID: "compare-waveforms",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [.csv],
            requiredOutputFormats: [.json]
        )
    }

    func standardMaskLVSCases() -> [StandardMaskLVSCase] {
        [
            StandardMaskLVSCase(
                name: "gds",
                displayName: "GDSII",
                artifactID: "layout-gds",
                exportFormat: .gds,
                artifactFormat: .gdsii,
                lvsFormat: .gds,
                fileSuffix: ".gds"
            ),
            StandardMaskLVSCase(
                name: "oasis",
                displayName: "OASIS",
                artifactID: "layout-oasis",
                exportFormat: .oasis,
                artifactFormat: .oasis,
                lvsFormat: .oasis,
                fileSuffix: ".oas"
            ),
            StandardMaskLVSCase(
                name: "cif",
                displayName: "CIF",
                artifactID: "layout-cif",
                exportFormat: .cif,
                artifactFormat: .raw,
                lvsFormat: .cif,
                fileSuffix: ".cif"
            ),
            StandardMaskLVSCase(
                name: "dxf",
                displayName: "DXF",
                artifactID: "layout-dxf",
                exportFormat: .dxf,
                artifactFormat: .raw,
                lvsFormat: .dxf,
                fileSuffix: ".dxf"
            ),
        ]
    }

    func makePEXTechnology() -> TechnologyIR {
        TechnologyIR(
            processName: "test_process",
            stack: [
                TechnologyLayer(
                    name: "M1",
                    order: 0,
                    thickness: 0.1,
                    material: "copper",
                    resistivity: 1.7e-8
                ),
            ],
            logicalToPhysicalLayerMap: [:],
            vias: [],
            defaultExtractionRules: .default,
            backendHints: [:]
        )
    }

    func cleanLayout() -> NativeDRCLayout {
        NativeDRCLayout(
            technologyID: "generic",
            topCell: "TOP",
            rectangles: [
                NativeDRCRectangle(id: "m1_a", layer: "met1", xMin: 0, yMin: 0, xMax: 1, yMax: 1),
                NativeDRCRectangle(id: "m1_b", layer: "met1", xMin: 2, yMin: 0, xMax: 3, yMax: 1),
            ],
            rules: [
                NativeDRCRule(id: "met1.width", kind: .minimumWidth, layer: "met1", value: 0.5),
                NativeDRCRule(id: "met1.space", kind: .minimumSpacing, layer: "met1", value: 0.5),
            ]
        )
    }

    func writeLayout(_ layout: NativeDRCLayout, root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "layout.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try data.write(to: url)
        return url
    }

    func writeNetlist(_ text: String, name: String, root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeStandardLayoutTechnology(root: URL) throws {
        let url = root.appending(path: "tech/process.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LayoutTechDatabase.standard())
        try data.write(to: url, options: [.atomic])
    }

    func writePEXTechnology(root: URL) throws {
        let url = root.appending(path: "tech/pex.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(makePEXTechnology())
        try data.write(to: url, options: [.atomic])
    }

    func writeTechnologyCatalog(
        root: URL,
        catalogPath: String = "tech/catalog.json",
        technologyCatalogID: String = "test-catalog",
        pdkID: String = "test-pdk",
        profileIDs: [String]? = ["local-signoff"],
        requiredFiles: [XcircuiteFlowTechnologyCatalogRequiredFile]
    ) throws {
        let url = root.appending(path: catalogPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let catalog = XcircuiteFlowTechnologyCatalog(
            entries: [
                XcircuiteFlowTechnologyCatalogEntry(
                    technologyCatalogID: technologyCatalogID,
                    pdkID: pdkID,
                    profileIDs: profileIDs,
                    requiredFiles: requiredFiles
                ),
            ]
        )
        try writeJSON(catalog, to: url)
    }

    func writeLayoutCommandRequest(root: URL) throws {
        let request = """
        {
          "artifactManifestPath" : "ignored/manifest.json",
          "commands" : [
            {
              "createCell" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "makeTop" : true,
                "name" : "top"
              },
              "kind" : "createCell"
            },
            {
              "addNet" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "name" : "out",
                "netID" : "20000000-0000-0000-0000-000000000002"
              },
              "kind" : "addNet"
            },
            {
              "addRect" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "layer" : {
                  "name" : "M1",
                  "purpose" : "drawing"
                },
                "netID" : "20000000-0000-0000-0000-000000000002",
                "origin" : {
                  "x" : 0,
                  "y" : 0
                },
                "properties" : {
                  "role" : "wire"
                },
                "shapeID" : "20000000-0000-0000-0000-000000000003",
                "size" : {
                  "height" : 2,
                  "width" : 10
                }
              },
              "kind" : "addRect"
            }
          ],
          "documentID" : "20000000-0000-0000-0000-000000000000",
          "documentName" : "flow-layout",
          "outputDocumentPath" : "ignored/layout.json",
          "resultPath" : "ignored/result.json",
          "schemaVersion" : 1
        }
        """
        let url = root.appending(path: "layout-command-request.json")
        try request.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeLayoutCommandRequestWithVia(root: URL) throws {
        let request = """
        {
          "artifactManifestPath" : "ignored/manifest.json",
          "commands" : [
            {
              "createCell" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "makeTop" : true,
                "name" : "top"
              },
              "kind" : "createCell"
            },
            {
              "addNet" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "name" : "out",
                "netID" : "20000000-0000-0000-0000-000000000002"
              },
              "kind" : "addNet"
            },
            {
              "addRect" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "layer" : {
                  "name" : "M1",
                  "purpose" : "drawing"
                },
                "netID" : "20000000-0000-0000-0000-000000000002",
                "origin" : {
                  "x" : 0,
                  "y" : 0
                },
                "properties" : {
                },
                "shapeID" : "20000000-0000-0000-0000-000000000003",
                "size" : {
                  "height" : 2,
                  "width" : 2
                }
              },
              "kind" : "addRect"
            },
            {
              "addRect" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "layer" : {
                  "name" : "M2",
                  "purpose" : "drawing"
                },
                "netID" : "20000000-0000-0000-0000-000000000002",
                "origin" : {
                  "x" : 0,
                  "y" : 0
                },
                "properties" : {
                },
                "shapeID" : "20000000-0000-0000-0000-000000000004",
                "size" : {
                  "height" : 2,
                  "width" : 2
                }
              },
              "kind" : "addRect"
            },
            {
              "addVia" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "netID" : "20000000-0000-0000-0000-000000000002",
                "position" : {
                  "x" : 1,
                  "y" : 1
                },
                "viaDefinitionID" : "VIA1",
                "viaID" : "20000000-0000-0000-0000-000000000005"
              },
              "kind" : "addVia"
            }
          ],
          "documentID" : "20000000-0000-0000-0000-000000000000",
          "documentName" : "flow-layout-with-via",
          "outputDocumentPath" : "ignored/layout.json",
          "resultPath" : "ignored/result.json",
          "schemaVersion" : 1
        }
        """
        let url = root.appending(path: "layout-command-request.json")
        try request.write(to: url, atomically: true, encoding: .utf8)
    }

    func matchingLVSNetlist() -> String {
        """
        .subckt TOP in out vdd vss
        M1 out in vdd vdd pmos
        M2 out in vss vss nmos
        .ends TOP
        """
    }

    func runtimeSpecWithProfile(
        _ profile: XcircuiteFlowToolchainProfile
    ) -> XcircuiteFlowRuntimeSpec {
        XcircuiteFlowRuntimeSpec(
            toolchainProfile: profile,
            executors: [
                .coreSpiceSimulation(
                    XcircuiteFlowStageExecutorSpec.CoreSpiceSimulation(
                        stageID: "010-sim",
                        netlistPath: "circuits/top.spice"
                    )
                ),
            ]
        )
    }

    func writeRuntimeSpec(_ spec: XcircuiteFlowRuntimeSpec, root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "runtime.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(spec)
        try data.write(to: url)
        return url
    }

    func writeRunSpec(_ spec: XcircuiteFlowRunSpec, root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "run.json")
        try writeJSON(spec, to: url)
        return url
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    func readToolchainManifest(in root: URL, runID: String) throws -> FlowToolchainManifest {
        try XcircuiteWorkspaceStore().readJSON(
            FlowToolchainManifest.self,
            from: root.appending(path: ".xcircuite/runs/\(runID)/toolchain.json")
        )
    }

    func fixtureURL(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/FlowRuntime/\(name)")
    }

    func workspaceRoot() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteFlowRuntimeTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func copyProgressStressArtifactIfRequested(root: URL, runID: String) throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LSI_PROGRESS_STRESS_ARTIFACT_OUT"],
              !outputPath.isEmpty else {
            return
        }
        let source = root.appending(path: ".xcircuite/runs/\(runID)/progress.jsonl")
        let destination = URL(filePath: outputPath)
        let destinationPath = destination.path(percentEncoded: false)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationPath) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}

actor ProgressEventSink {
    private var state: [FlowRunProgressEvent] = []

    func append(_ event: FlowRunProgressEvent) {
        state.append(event)
    }

    func events() -> [FlowRunProgressEvent] {
        state
    }
}
