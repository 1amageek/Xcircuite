import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct OpAmpDesignArtifactStore: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore

    public init(workspaceStore: XcircuiteWorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    @discardableResult
    public func persistSpec(
        _ spec: OpAmpSpec,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            spec,
            runID: runID,
            relativePath: "opamp/spec.json",
            artifactID: "opamp-spec",
            kind: .report
        )
    }

    @discardableResult
    public func persistTopologyCandidates(
        _ candidates: [OpAmpTopologyCandidate],
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            candidates,
            runID: runID,
            relativePath: "opamp/topology-candidates.json",
            artifactID: "opamp-topology-candidates",
            kind: .report
        )
    }

    @discardableResult
    public func persistSizingResult(
        _ result: OpAmpSizingResult,
        runID: String,
        projectRoot: URL
    ) async throws -> [ArtifactReference] {
        let sizingReference = try await writeJSONArtifact(
            result,
            runID: runID,
            relativePath: "opamp/sizing-result.json",
            artifactID: "opamp-sizing-result",
            kind: .report
        )
        let netlistReference = try await writeTextArtifact(
            result.netlist,
            runID: runID,
            relativePath: "opamp/opamp.cir",
            artifactID: "opamp-netlist",
            kind: .netlist,
            format: .spice
        )
        let layoutReference = try await writeJSONArtifact(
            result.layoutConstraintPlan,
            runID: runID,
            relativePath: "opamp/layout-constraints.json",
            artifactID: "opamp-layout-constraints",
            kind: .report
        )
        var references = [sizingReference, netlistReference, layoutReference]
        if let simulationDeckSet = result.simulationDeckSet {
            references.append(try await writeJSONArtifact(
                simulationDeckSet,
                runID: runID,
                relativePath: "opamp/simulation-decks.json",
                artifactID: "opamp-simulation-deck-set",
                kind: .report
            ))
            for deck in simulationDeckSet.decks {
                references.append(try await writeTextArtifact(
                    deck.netlist,
                    runID: runID,
                    relativePath: "opamp/simulation/\(deck.deckID).cir",
                    artifactID: "opamp-simulation-\(deck.deckID)-netlist",
                    kind: .netlist,
                    format: .spice
                ))
            }
        }
        return references
    }

    @discardableResult
    public func persistEvaluationReport(
        _ report: OpAmpEvaluationReport,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            report,
            runID: runID,
            relativePath: "opamp/evaluation-report.json",
            artifactID: "opamp-evaluation-report",
            kind: .report
        )
    }

    @discardableResult
    public func persistSimulationDeckValidationReport(
        _ report: OpAmpSimulationDeckValidationReport,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            report,
            runID: runID,
            relativePath: "opamp/simulation-deck-validation.json",
            artifactID: "opamp-simulation-deck-validation",
            kind: .report
        )
    }

    @discardableResult
    public func persistSimulationDeckExecutionReport(
        _ report: OpAmpSimulationDeckExecutionReport,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            report,
            runID: runID,
            relativePath: "opamp/simulation-execution-report.json",
            artifactID: "opamp-simulation-execution-report",
            kind: .report
        )
    }

    @discardableResult
    public func persistSimulationDeckWaveform(
        _ waveformCSV: String,
        deckID: String,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        let safeDeckID = deckID.replacingOccurrences(of: "/", with: "_")
        return try await writeTextArtifact(
            waveformCSV,
            runID: runID,
            relativePath: "opamp/simulation/\(safeDeckID)-waveform.csv",
            artifactID: "opamp-simulation-\(safeDeckID)-waveform",
            kind: .waveform,
            format: .csv
        )
    }

    @discardableResult
    public func persistWaveformMetricExtraction(
        _ extraction: OpAmpSimulationMetricExtraction,
        analysisKind: OpAmpWaveformAnalysisKind,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            extraction,
            runID: runID,
            relativePath: "opamp/waveform-metric-extraction-\(analysisKind.rawValue).json",
            artifactID: "opamp-waveform-metric-extraction-\(analysisKind.rawValue)",
            kind: .measurement
        )
    }

    @discardableResult
    public func persistMergedMetricExtraction(
        _ extraction: OpAmpSimulationMetricExtraction,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            extraction,
            runID: runID,
            relativePath: "opamp/metric-extraction.json",
            artifactID: "opamp-metric-extraction",
            kind: .measurement
        )
    }

    @discardableResult
    public func persistPostLayoutComparison(
        _ report: OpAmpPostLayoutComparisonReport,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        try await writeJSONArtifact(
            report,
            runID: runID,
            relativePath: "opamp/post-layout-comparison.json",
            artifactID: "opamp-post-layout-comparison",
            kind: .report
        )
    }

    private func writeJSONArtifact<T: Encodable>(
        _ value: T,
        runID: String,
        relativePath: String,
        artifactID: String,
        kind: ArtifactKind
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let content = try encoder.encode(value)
        return try await workspaceStore.persistArtifact(
            content: content,
            id: ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/\(relativePath)"
                ),
                role: .output,
                kind: kind,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
    }

    private func writeTextArtifact(
        _ text: String,
        runID: String,
        relativePath: String,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) async throws -> ArtifactReference {
        return try await workspaceStore.persistArtifact(
            content: Data(text.utf8),
            id: ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/\(relativePath)"
                ),
                role: .output,
                kind: kind,
                format: format
            ),
            runID: runID,
            mode: .replaceable
        )
    }
}
