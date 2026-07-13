import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicDesign
import DesignFlowKernel

struct LogicDesignFlowStageSupport: Sendable {
    let artifactBuilder: StageArtifactReferenceBuilder

    init(artifactBuilder: StageArtifactReferenceBuilder = StageArtifactReferenceBuilder()) {
        self.artifactBuilder = artifactBuilder
    }

    func validate(stage: FlowStageDefinition, stageID: String, toolID: String) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    func writeEnvelope<Payload: Sendable & Hashable & Codable>(
        _ envelope: XcircuiteEngineResultEnvelope<Payload>,
        stageID: String,
        context: FlowExecutionContext,
        fileName: String
    ) throws -> XcircuiteFileReference {
        let directory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: fileName)
        try context.packageStore.writeJSON(
            envelope,
            to: url,
            forProjectAt: context.projectRoot
        )
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "\(stageID)-result",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    func writeResult<Value: Encodable>(
        _ result: Value,
        stageID: String,
        context: FlowExecutionContext,
        fileName: String
    ) throws -> XcircuiteFileReference {
        let directory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: fileName)
        try context.packageStore.writeJSON(result, to: url, forProjectAt: context.projectRoot)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "\(stageID)-result",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    func stageResult(
        resultArtifact: XcircuiteFileReference,
        status: LogicExecutionStatus,
        diagnostics: [LogicDiagnostic],
        stageID: String,
        artifacts: [XcircuiteFileReference],
        context: FlowExecutionContext
    ) -> FlowStageResult {
        let flowDiagnostics = diagnostics.map { diagnostic in
            let severity: FlowDiagnosticSeverity
            switch diagnostic.severity {
            case .information: severity = .info
            case .warning: severity = .warning
            case .error: severity = .error
            }
            return FlowDiagnostic(
                severity: severity,
                code: diagnostic.code,
                message: diagnostic.message
            )
        }
        let allArtifacts = artifacts + [resultArtifact]
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: allArtifacts,
            projectRoot: context.projectRoot
        )
        let domainStageStatus: FlowStageStatus
        let gateStatus: FlowGateStatus
        switch status {
        case .completed:
            domainStageStatus = integrityGate.status == .passed ? .succeeded : .failed
            gateStatus = integrityGate.status == .passed ? .passed : .failed
        case .blocked:
            domainStageStatus = .blocked
            gateStatus = .blocked
        case .failed:
            domainStageStatus = .failed
            gateStatus = .failed
        case .cancelled:
            domainStageStatus = .blocked
            gateStatus = .incomplete
        }
        return FlowStageResult(
            stageID: stageID,
            status: domainStageStatus,
            diagnostics: flowDiagnostics + integrityGate.diagnostics,
            gates: [
                FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: flowDiagnostics),
                integrityGate,
            ],
            artifacts: allArtifacts
        )
    }

    func stageResult(
        resultArtifact: XcircuiteFileReference,
        envelopeStatus: XcircuiteEngineExecutionStatus,
        diagnostics: [XcircuiteEngineDiagnostic],
        stageID: String,
        artifacts: [XcircuiteFileReference],
        context: FlowExecutionContext
    ) -> FlowStageResult {
        let flowDiagnostics = diagnostics.map(flowDiagnostic)
        let allArtifacts = artifacts + [resultArtifact]
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: allArtifacts,
            projectRoot: context.projectRoot
        )
        let stageStatus: FlowStageStatus
        let gateStatus: FlowGateStatus
        switch envelopeStatus {
        case .completed:
            stageStatus = integrityGate.status == .passed ? .succeeded : .failed
            gateStatus = integrityGate.status == .passed ? .passed : .failed
        case .blocked:
            stageStatus = .blocked
            gateStatus = .blocked
        case .failed:
            stageStatus = .failed
            gateStatus = .failed
        case .cancelled:
            stageStatus = .blocked
            gateStatus = .incomplete
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: flowDiagnostics + integrityGate.diagnostics,
            gates: [
                FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: flowDiagnostics),
                integrityGate,
            ],
            artifacts: allArtifacts
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

    private func flowDiagnostic(_ diagnostic: XcircuiteEngineDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: FlowDiagnosticSeverity(rawValue: diagnostic.severity.rawValue) ?? .error,
            code: diagnostic.code,
            message: diagnostic.message
        )
    }
}
