import DesignFlowKernel
import Foundation
import LogicQualification
import DesignFlowKernel

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
            var additionalArtifacts: [XcircuiteFileReference] = [try reference(
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
            let now = Date()
            let status: XcircuiteEngineExecutionStatus = report.isReleaseEligible
                ? .completed
                : .blocked
            let diagnostics = diagnostics(for: report)
            let envelope = XcircuiteEngineResultEnvelope(
                schemaVersion: 1,
                runID: context.runID,
                status: status,
                diagnostics: diagnostics,
                artifacts: additionalArtifacts,
                metadata: XcircuiteEngineExecutionMetadata(
                    engineID: "logic-qualification",
                    implementationID: report.implementationID,
                    implementationVersion: report.implementationVersion,
                    startedAt: now,
                    completedAt: now
                ),
                payload: report
            )
            let resultArtifact = try support.persistEnvelope(
                envelope,
                fileName: "logic-qualification-result.json",
                artifactID: "logic-qualification-result",
                stageID: stageID,
                context: context
            )
            return try support.result(
                envelope: envelope,
                resultArtifact: resultArtifact,
                stageID: stageID,
                gateID: stageID,
                context: context,
                additionalArtifacts: []
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
    ) throws -> XcircuiteFileReference {
        try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    private func diagnostics(
        for report: LogicQualificationReport
    ) -> [XcircuiteEngineDiagnostic] {
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
        return [XcircuiteEngineDiagnostic(
            severity: .error,
            code: code,
            message: message.isEmpty ? "Logic qualification has not reached release eligibility." : message,
            suggestedActions: ["attach_required_qualification_artifact"]
        )]
    }
}
