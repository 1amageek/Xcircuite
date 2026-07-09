import Foundation
import XcircuitePackage

public struct OpAmpDesignArtifactStore: Sendable {
    private let packageStore: XcircuitePackageStore

    public init(packageStore: XcircuitePackageStore = XcircuitePackageStore()) {
        self.packageStore = packageStore
    }

    @discardableResult
    public func persistSpec(
        _ spec: OpAmpSpec,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try writeJSONArtifact(
            spec,
            runID: runID,
            projectRoot: projectRoot,
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
    ) throws -> XcircuiteFileReference {
        try writeJSONArtifact(
            candidates,
            runID: runID,
            projectRoot: projectRoot,
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
    ) throws -> [XcircuiteFileReference] {
        let sizingReference = try writeJSONArtifact(
            result,
            runID: runID,
            projectRoot: projectRoot,
            relativePath: "opamp/sizing-result.json",
            artifactID: "opamp-sizing-result",
            kind: .report
        )
        let netlistReference = try writeTextArtifact(
            result.netlist,
            runID: runID,
            projectRoot: projectRoot,
            relativePath: "opamp/opamp.cir",
            artifactID: "opamp-netlist",
            kind: .netlist,
            format: .spice
        )
        let layoutReference = try writeJSONArtifact(
            result.layoutConstraintPlan,
            runID: runID,
            projectRoot: projectRoot,
            relativePath: "opamp/layout-constraints.json",
            artifactID: "opamp-layout-constraints",
            kind: .report
        )
        var references = [sizingReference, netlistReference, layoutReference]
        if let simulationDeckSet = result.simulationDeckSet {
            references.append(try writeJSONArtifact(
                simulationDeckSet,
                runID: runID,
                projectRoot: projectRoot,
                relativePath: "opamp/simulation-decks.json",
                artifactID: "opamp-simulation-deck-set",
                kind: .report
            ))
            for deck in simulationDeckSet.decks {
                references.append(try writeTextArtifact(
                    deck.netlist,
                    runID: runID,
                    projectRoot: projectRoot,
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
    ) throws -> XcircuiteFileReference {
        try writeJSONArtifact(
            report,
            runID: runID,
            projectRoot: projectRoot,
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
    ) throws -> XcircuiteFileReference {
        try writeJSONArtifact(
            report,
            runID: runID,
            projectRoot: projectRoot,
            relativePath: "opamp/simulation-deck-validation.json",
            artifactID: "opamp-simulation-deck-validation",
            kind: .report
        )
    }

    @discardableResult
    public func persistPostLayoutComparison(
        _ report: OpAmpPostLayoutComparisonReport,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try writeJSONArtifact(
            report,
            runID: runID,
            projectRoot: projectRoot,
            relativePath: "opamp/post-layout-comparison.json",
            artifactID: "opamp-post-layout-comparison",
            kind: .report
        )
    }

    private func writeJSONArtifact<T: Encodable>(
        _ value: T,
        runID: String,
        projectRoot: URL,
        relativePath: String,
        artifactID: String,
        kind: XcircuiteFileKind
    ) throws -> XcircuiteFileReference {
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)"
        let url = projectRoot.appending(path: projectRelativePath)
        try packageStore.ensureRunDirectory(for: runID, inProjectAt: projectRoot)
        try packageStore.ensureDirectory(at: url.deletingLastPathComponent())
        try packageStore.writeJSON(value, to: url, forProjectAt: projectRoot)
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: artifactID,
            kind: kind,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    private func writeTextArtifact(
        _ text: String,
        runID: String,
        projectRoot: URL,
        relativePath: String,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(relativePath)"
        let url = projectRoot.appending(path: projectRelativePath)
        try packageStore.ensureRunDirectory(for: runID, inProjectAt: projectRoot)
        try packageStore.ensureDirectory(at: url.deletingLastPathComponent())
        try packageStore.writeText(text, to: url)
        let reference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }
}
