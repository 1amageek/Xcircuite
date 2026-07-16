import DFTCore
import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct DFTReleaseDownstreamEvidenceBundleFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let sources: [DFTReleaseDownstreamEvidenceSource]
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String = "dft.release-evidence",
        toolID: String = "dft-release-evidence",
        sources: [DFTReleaseDownstreamEvidenceSource]
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.sources = sources
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)
            let evidence = try sources.map { source in
                guard !source.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DFTReleaseDownstreamEvidenceBundleError.invalidRole
                }
                let url = try source.input.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                let artifact = try artifactBuilder.reference(
                    for: url,
                    projectRoot: context.projectRoot,
                    artifactID: "dft-downstream-\(source.domain.rawValue)",
                    kind: .report,
                    format: format(for: url)
                )
                return DFTReleaseDownstreamEvidence(
                    domain: source.domain,
                    role: source.role,
                    artifact: artifact
                )
            }
            let bundleArtifact = try await context.persistJSONArtifact(
                evidence,
                artifactID: "dft-downstream-evidence-bundle",
                stageID: stageID,
                fileName: "dft-downstream-evidence.json",
                kind: .release,
                mode: .immutable
            )
            let sourceArtifacts = evidence.map(\.artifact)
            return FlowStageResult(
                stageID: stage.stageID,
                status: .succeeded,
                diagnostics: [],
                gates: [
                    FlowGateResult(
                        gateID: "dft-release-evidence",
                        status: .passed,
                        diagnostics: []
                    )
                ],
                artifacts: sourceArtifacts + [bundleArtifact]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as DFTReleaseDownstreamEvidenceBundleError {
            return blockedResult(stageID: stage.stageID, code: "DFT_RELEASE_EVIDENCE_BUNDLE_INVALID", message: error.localizedDescription)
        } catch {
            return blockedResult(stageID: stage.stageID, code: "DFT_RELEASE_EVIDENCE_BUNDLE_FAILED", message: error.localizedDescription)
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw DFTReleaseDownstreamEvidenceBundleError.stageMismatch(
                expected: stageID,
                actual: stage.stageID
            )
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
        guard !sources.isEmpty else {
            throw DFTReleaseDownstreamEvidenceBundleError.invalidInput("at least one downstream evidence source is required")
        }
        var domains = Set<DFTReleaseDownstreamEvidence.Domain>()
        for source in sources {
            guard domains.insert(source.domain).inserted else {
                throw DFTReleaseDownstreamEvidenceBundleError.duplicateDomain(source.domain.rawValue)
            }
        }
        for domain in [
            DFTReleaseDownstreamEvidence.Domain.equivalence,
            .drc,
            .lvs,
            .pex,
        ] where !domains.contains(domain) {
            throw DFTReleaseDownstreamEvidenceBundleError.missingDomain(domain.rawValue)
        }
    }

    private func format(for url: URL) -> ArtifactFormat {
        switch url.pathExtension.lowercased() {
        case "json":
            return .json
        case "gds":
            return .gdsii
        case "oas", "oasis":
            return .oasis
        case "lef":
            return .lef
        case "def":
            return .def
        case "spef":
            return .spef
        case "dspf":
            return .dspf
        case "sdc":
            return .sdc
        case "stil":
            return .stil
        case "wgl":
            return .wgl
        default:
            return .raw
        }
    }

    private func blockedResult(
        stageID: String,
        code: String,
        message: String
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "dft-release-evidence", status: .blocked, diagnostics: [diagnostic])]
        )
    }
}
