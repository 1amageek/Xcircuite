import DesignFlowKernel
import Foundation
import PEXEngine
import ToolQualification
import Xcircuite

/// Generates a minimal valid `XcircuiteFlowRunSpec` + `XcircuiteFlowRuntimeSpec`
/// pair without claiming qualification that has not been performed. Stage
/// IDs are sequential (`001-…`), and every generated tool starts at the
/// honest `unknown` trust level with no fabricated qualification evidence.
/// `make()` validates coverage on the constructed pair before returning —
/// an invalid scaffold is a typed error, never a file.
struct XcircuiteFlowRunScaffolder: Sendable {

    enum StageKind: String, CaseIterable, Sendable {
        case coreSpiceSimulation
        case mockPEX
        case postLayoutComparison

        var slug: String {
            switch self {
            case .coreSpiceSimulation:
                "core-spice-simulation"
            case .mockPEX:
                "mock-pex"
            case .postLayoutComparison:
                "post-layout-comparison"
            }
        }

        var displayName: String {
            switch self {
            case .coreSpiceSimulation:
                "CoreSpice simulation"
            case .mockPEX:
                "Mock PEX extraction"
            case .postLayoutComparison:
                "Post-layout waveform comparison"
            }
        }
    }

    struct Scaffold: Sendable {
        let runSpec: XcircuiteFlowRunSpec
        let runtimeSpec: XcircuiteFlowRuntimeSpec
        let stageIDs: [String]
        let placeholderPaths: [String]
    }

    static let defaultStageKinds: [StageKind] = [
        .coreSpiceSimulation,
        .mockPEX,
        .postLayoutComparison,
    ]

    // Placeholder project-relative input paths the caller must replace.
    static let placeholderNetlistPath = "pre-layout.cir"
    static let placeholderLayoutPath = "layout.gds"
    static let placeholderPEXTechnologyPath = "pex-technology.json"
    static let placeholderPreLayoutWaveformPath = "pre-layout-waveform.csv"
    static let placeholderPostLayoutWaveformPath = "post-layout-waveform.csv"
    static let placeholderTopCell = "TOP"

    let runID: String
    let stageKinds: [StageKind]

    init(runID: String, stageKinds: [StageKind]) {
        self.runID = runID
        self.stageKinds = stageKinds
    }

    func make() throws -> Scaffold {
        var stages: [FlowStageDefinition] = []
        var executors: [XcircuiteFlowStageExecutorSpec] = []
        var placeholderPaths: [String] = []

        for (index, kind) in stageKinds.enumerated() {
            let stageID = String(format: "%03d-%@", index + 1, kind.slug)
            stages.append(FlowStageDefinition(
                stageID: stageID,
                displayName: kind.displayName,
                requiredTool: requiredTool(for: kind),
                requiresApproval: false
            ))
            executors.append(try executor(for: kind, stageID: stageID))
            placeholderPaths.append(contentsOf: placeholders(for: kind))
        }

        let runSpec = XcircuiteFlowRunSpec(
            runID: runID,
            intent: "Scaffolded flow run \(runID): replace the placeholder input paths, then validate and run.",
            stages: stages
        )
        let runtimeSpec = XcircuiteFlowRuntimeSpec(executors: executors)

        // Construct-time gate: the pair must already satisfy the same
        // coverage validation `xcircuite-flow validate` applies.
        try runtimeSpec.validateCoverage(for: runSpec)

        return Scaffold(
            runSpec: runSpec,
            runtimeSpec: runtimeSpec,
            stageIDs: stages.map(\.stageID),
            placeholderPaths: stableUniquePaths(placeholderPaths)
        )
    }

    // MARK: - Run-spec stage requirements

    private func requiredTool(for kind: StageKind) -> ToolTrustRequirement {
        switch kind {
        case .coreSpiceSimulation:
            ToolTrustRequirement(
                kind: .simulation,
                operationID: "run-simulation",
                minimumLevel: .unknown,
                requiredInputFormats: [.spice],
                requiredOutputFormats: [.csv, .json],
                requiredEvidenceKinds: [],
                requiredQualifiedEvidenceKinds: [],
                requirePassingHealthCheck: false
            )
        case .mockPEX:
            // The runtime's mock contract: a mock executor cannot declare a
            // qualified tool, so the stage requirement stays at `unknown`
            // and demands no qualified evidence.
            ToolTrustRequirement(
                kind: .pex,
                operationID: "run-pex",
                minimumLevel: .unknown,
                requiredInputFormats: [.gdsii, .spice, .json],
                requiredOutputFormats: [.spef, .json],
                requiredEvidenceKinds: [],
                requiredQualifiedEvidenceKinds: [],
                requirePassingHealthCheck: false
            )
        case .postLayoutComparison:
            ToolTrustRequirement(
                kind: .simulation,
                operationID: "compare-waveforms",
                minimumLevel: .unknown,
                requiredInputFormats: [.csv],
                requiredOutputFormats: [.json],
                requiredEvidenceKinds: [],
                requiredQualifiedEvidenceKinds: [],
                requirePassingHealthCheck: false
            )
        }
    }

    // MARK: - Runtime executors

    private func executor(
        for kind: StageKind,
        stageID: String
    ) throws -> XcircuiteFlowStageExecutorSpec {
        switch kind {
        case .coreSpiceSimulation:
            return .coreSpiceSimulation(XcircuiteFlowStageExecutorSpec.CoreSpiceSimulation(
                stageID: stageID,
                netlistPath: Self.placeholderNetlistPath,
                expectations: [
                    SimulationMeasurementExpectation(
                        name: "placeholder_measure",
                        target: 1.0,
                        tolerance: 0.1
                    ),
                ],
                tool: XcircuiteFlowToolSpec()
            ))
        case .mockPEX:
            return .mockPEX(XcircuiteFlowStageExecutorSpec.MockPEX(
                stageID: stageID,
                layoutPath: Self.placeholderLayoutPath,
                layoutFormat: .gds,
                sourceNetlistPath: Self.placeholderNetlistPath,
                sourceNetlistFormat: .spice,
                topCell: Self.placeholderTopCell,
                corners: [PEXCorner(id: "tt_25c_1v0")],
                technology: .jsonFile(path: Self.placeholderPEXTechnologyPath),
                tool: XcircuiteFlowToolSpec(
                    qualificationLevel: .unknown,
                    healthStatus: .notChecked
                )
            ))
        case .postLayoutComparison:
            return .postLayoutComparison(XcircuiteFlowStageExecutorSpec.PostLayoutComparison(
                stageID: stageID,
                preLayoutWaveformPath: Self.placeholderPreLayoutWaveformPath,
                postLayoutWaveformPath: Self.placeholderPostLayoutWaveformPath,
                options: PostLayoutComparisonOptions(
                    maxAbsoluteDelta: 0.2,
                    maxRelativeDelta: 1.0,
                    relativeDeltaDenominatorFloor: 0.05
                ),
                tool: XcircuiteFlowToolSpec()
            ))
        }
    }

    private func placeholders(for kind: StageKind) -> [String] {
        switch kind {
        case .coreSpiceSimulation:
            [Self.placeholderNetlistPath]
        case .mockPEX:
            [
                Self.placeholderLayoutPath,
                Self.placeholderNetlistPath,
                Self.placeholderPEXTechnologyPath,
            ]
        case .postLayoutComparison:
            [
                Self.placeholderPreLayoutWaveformPath,
                Self.placeholderPostLayoutWaveformPath,
            ]
        }
    }

    private func stableUniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for path in paths where !seen.contains(path) {
            seen.insert(path)
            unique.append(path)
        }
        return unique
    }
}
