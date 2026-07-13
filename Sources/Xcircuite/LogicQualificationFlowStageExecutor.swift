import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LogicEngineCore
import LogicQualification

public struct LogicQualificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let reportInput: XcircuiteFlowInputReference
    private let processEvidenceInput: XcircuiteFlowInputReference?
    private let releaseApprovalInput: XcircuiteFlowInputReference?
    private let support: LogicEngineStageExecutionSupport
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String = "logic.qualification",
        toolID: String = "logic-qualification",
        reportInput: XcircuiteFlowInputReference,
        processEvidenceInput: XcircuiteFlowInputReference? = nil,
        releaseApprovalInput: XcircuiteFlowInputReference? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.reportInput = reportInput
        self.processEvidenceInput = processEvidenceInput
        self.releaseApprovalInput = releaseApprovalInput
        self.support = LogicEngineStageExecutionSupport()
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let reportURL = try reportInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            var report = try JSONDecoder().decode(
                LogicQualificationReport.self,
                from: Data(contentsOf: reportURL)
            )
            try report.validate()
            var additionalArtifacts: [ArtifactReference] = [try reference(
                for: reportURL,
                artifactID: "logic-qualification-report",
                context: context
            )]
            if let processEvidenceInput {
                let processURL = try processEvidenceInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                let evidence = try JSONDecoder().decode(
                    LogicQualificationProcessEvidence.self,
                    from: Data(contentsOf: processURL)
                )
                report = try report.includingProcessQualification(evidence)
                additionalArtifacts.append(try reference(
                    for: processURL,
                    artifactID: "logic-process-qualification-evidence",
                    context: context
                ))
            }
            if let releaseApprovalInput {
                let approvalURL = try releaseApprovalInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                let approval = try JSONDecoder().decode(
                    LogicQualificationReleaseApproval.self,
                    from: Data(contentsOf: approvalURL)
                )
                report = try report.includingReleaseApproval(approval)
                additionalArtifacts.append(try reference(
                    for: approvalURL,
                    artifactID: "logic-release-approval",
                    context: context
                ))
            }
            try report.validate()
            let diagnostics = diagnostics(for: report)
            let resultArtifact = try support.persistResult(
                report,
                fileName: "logic-qualification-result.json",
                artifactID: "logic-qualification-result",
                stageID: stageID,
                context: context
            )
            let flowDiagnostics = diagnostics.map { diagnostic in
                FlowDiagnostic(
                    severity: .error,
                    code: diagnostic.code.rawValue,
                    message: diagnostic.summary
                )
            }
            let allArtifacts = additionalArtifacts + [resultArtifact]
            let integrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: allArtifacts,
                projectRoot: context.projectRoot
            )
            let stageStatus: FlowStageStatus = report.isReleaseEligible
                ? (integrityGate.status == .passed ? .succeeded : .failed)
                : .blocked
            let gateStatus: FlowGateStatus = report.isReleaseEligible
                ? (integrityGate.status == .passed ? .passed : .failed)
                : .blocked
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
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as LogicQualificationError {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_QUALIFICATION_ARTIFACT_INVALID",
                message: error.localizedDescription
            )
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_QUALIFICATION_ADAPTER_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func reference(
        for url: URL,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            role: .input,
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func diagnostics(
        for report: LogicQualificationReport
    ) -> [DesignDiagnostic] {
        guard !report.isReleaseEligible else {
            return []
        }
        let code: String
        switch report.state {
        case .unassessed:
            code = "LOGIC_QUALIFICATION_CORPUS_REQUIRED"
        case .corpusChecked:
            code = "LOGIC_QUALIFICATION_ORACLE_REQUIRED"
        case .oracleCorrelated:
            code = "LOGIC_QUALIFICATION_PROCESS_REQUIRED"
        case .processQualified:
            code = "LOGIC_QUALIFICATION_RELEASE_APPROVAL_REQUIRED"
        case .releaseEligible:
            code = "LOGIC_QUALIFICATION_RELEASE_GATE_INVALID"
        }
        let message = report.blockers.sorted().joined(separator: ", ")
        return [DesignDiagnostic(
            code: .trusted(code),
            severity: .error,
            summary: message.isEmpty ? "Logic qualification has not reached release eligibility." : message
        )]
    }
}
