import DesignFlowKernel
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
    ) throws -> XcircuiteFileReference {
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
            format: .json,
            producedByRunID: context.runID
        )
    }

    func inputReference(
        for url: URL,
        context: FlowExecutionContext,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: format,
            producedByRunID: context.runID
        )
    }

    func inputLocator(
        for url: URL,
        context: FlowExecutionContext,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> ArtifactLocator {
        let reference = try inputReference(
            for: url,
            context: context,
            artifactID: artifactID,
            kind: kind,
            format: format
        )
        let location: ArtifactLocation
        if reference.path.hasPrefix("/") {
            location = try ArtifactLocation(fileURL: URL(filePath: reference.path))
        } else {
            location = try ArtifactLocation(workspaceRelativePath: reference.path)
        }
        return ArtifactLocator(
            location: location,
            role: .input,
            kind: try ArtifactKind(rawValue: reference.kind.rawValue),
            format: try ArtifactFormat(rawValue: reference.format.rawValue)
        )
    }

    func foundationInputReference(
        for url: URL,
        context: FlowExecutionContext,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> ArtifactReference {
        let legacy = try inputReference(
            for: url,
            context: context,
            artifactID: artifactID,
            kind: kind,
            format: format
        )
        guard let hexadecimalValue = legacy.sha256,
              let byteCount = legacy.byteCount,
              byteCount >= 0 else {
            throw XcircuiteRuntimeError.invalidInputReference(
                "PDK input artifact digest metadata is incomplete."
            )
        }
        let artifactIDValue: ArtifactID?
        if let rawValue = legacy.artifactID {
            artifactIDValue = try ArtifactID(rawValue: rawValue)
        } else {
            artifactIDValue = nil
        }
        let location: ArtifactLocation
        if legacy.path.hasPrefix("/") {
            location = try ArtifactLocation(fileURL: URL(filePath: legacy.path))
        } else {
            location = try ArtifactLocation(workspaceRelativePath: legacy.path)
        }
        return try ArtifactReference(
            id: artifactIDValue,
            locator: ArtifactLocator(
                location: location,
                role: .input,
                kind: try ArtifactKind(rawValue: legacy.kind.rawValue),
                format: try ArtifactFormat(rawValue: legacy.format.rawValue)
            ),
            digest: ContentDigest(algorithm: .sha256, hexadecimalValue: hexadecimalValue),
            byteCount: UInt64(byteCount)
        )
    }

    func stageResult<Result: PDKStageExecutionResult>(
        result: Result,
        stageID: String,
        artifact: XcircuiteFileReference
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
