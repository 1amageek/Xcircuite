import DesignFlowKernel
import CircuiteFoundation
import Foundation
import PDKCore
import PDKDiscovery
import PDKStandardViews
import PDKValidation
import DesignFlowKernel

protocol PDKStageExecutionResult: Sendable {
    var status: PDKExecutionStatus { get }
    var diagnostics: [DesignDiagnostic] { get }
}

extension PDKDiscoveryResult: PDKStageExecutionResult {}
extension PDKValidationExecutionResult: PDKStageExecutionResult {}
extension PDKCorpusValidationExecutionResult: PDKStageExecutionResult {}
extension PDKQualificationExecutionResult: PDKStageExecutionResult {}
extension PDKOracleComparisonResult: PDKStageExecutionResult {}
extension PDKRuleDeckInspectionResult: PDKStageExecutionResult {}
extension PDKManifestViewInspectionResult: PDKStageExecutionResult {}

struct PDKStageExecutionSupport: Sendable {
    private let artifactBuilder: StageArtifactReferenceBuilder

    init(artifactBuilder: StageArtifactReferenceBuilder = StageArtifactReferenceBuilder()) {
        self.artifactBuilder = artifactBuilder
    }

    func persistResult<Result: Encodable>(
        _ result: Result,
        stageID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let stageDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: stageDirectory)
        let outputURL = stageDirectory.appending(path: "pdk-result.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: outputURL, options: .atomic)
        return try artifactBuilder.reference(
            for: outputURL,
            projectRoot: context.projectRoot,
            artifactID: "pdk-result",
            kind: .report,
            format: .json
        )
    }

    func inputReference(
        for url: URL,
        context: FlowExecutionContext,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            role: .input,
            kind: kind,
            format: format
        )
    }

    func inputLocator(
        for url: URL,
        context: FlowExecutionContext,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactLocator {
        try inputReference(
            for: url,
            context: context,
            artifactID: artifactID,
            kind: kind,
            format: format
        ).locator
    }

    func stageResult<Result: PDKStageExecutionResult>(
        result: Result,
        stageID: String,
        artifact: ArtifactReference
    ) -> FlowStageResult {
        let diagnostics = result.diagnostics.map(flowDiagnostic)
        let gateStatus = gateStatus(for: result.status)
        let stageStatus: FlowStageStatus
        switch result.status {
        case .completed:
            stageStatus = .succeeded
        case .blocked:
            stageStatus = .blocked
        case .failed, .cancelled:
            stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: diagnostics,
            gates: [FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: diagnostics)],
            artifacts: [artifact]
        )
    }

    func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: stageID, status: .failed, diagnostics: [diagnostic])]
        )
    }

    func validate(stage: FlowStageDefinition, stageID: String, toolID: String) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func flowDiagnostic(_ diagnostic: DesignDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.code.rawValue,
            message: diagnostic.summary
        )
    }

    private func flowSeverity(_ severity: DiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .information: .info
        case .warning: .warning
        case .error: .error
        }
    }

    private func gateStatus(
        for status: PDKExecutionStatus
    ) -> FlowGateStatus {
        switch status {
        case .completed: .passed
        case .failed: .failed
        case .blocked: .blocked
        case .cancelled: .incomplete
        }
    }
}
