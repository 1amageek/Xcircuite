import DesignFlowKernel
import CircuiteFoundation
import ElectricalSignoffEngine
import Foundation
import PhysicalDesignCore

public struct ElectricalSignoffRepairRevisionFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let request: XcircuiteElectricalRepairRevisionRequest
    private let physicalDesignExecutor: NativePhysicalDesignExecutor?

    public init(
        stageID: String = "electrical-signoff.repair-revision",
        toolID: String = "native-electrical-signoff-repair-revision",
        request: XcircuiteElectricalRepairRevisionRequest,
        physicalDesignExecutor: NativePhysicalDesignExecutor? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.request = request
        self.physicalDesignExecutor = physicalDesignExecutor
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage, context: context)
            let plan = try await loadPlan(context: context)
            let candidate = try selectCandidate(from: plan)
            try validateProvenance(plan: plan, candidate: candidate)
            let executor = physicalDesignExecutorWithProjectStore(context: context)
            let result = try await executor.execute(request.physicalDesignRequest)
            try await context.checkCancellation()
            let newDigest = result.payload.physicalDesign?.layoutDigest
            let lineage = XcircuiteElectricalRepairRevisionResult.DigestLineage(
                parentLayoutDigest: request.physicalDesignRequest.inputLayout?.layoutDigest ?? plan.layoutDigest ?? "",
                newLayoutDigest: newDigest,
                designDigest: request.physicalDesignRequest.design.designDigest,
                pdkDigest: request.physicalDesignRequest.pdk.digest
            )
            let persisted = XcircuiteElectricalRepairRevisionResult(
                runID: context.runID,
                selectedCandidateID: candidate.candidateID,
                repairPlanArtifact: request.repairPlanArtifact,
                physicalDesignResult: result,
                digestLineage: lineage
            )
            let wrapperReference = try await persist(persisted, context: context)
            var diagnostics = result.diagnostics.map { diagnostic in
                let severity: FlowDiagnosticSeverity
                switch diagnostic.severity {
                case .information: severity = .info
                case .warning: severity = .warning
                case .error: severity = .error
                }
                let detail = diagnostic.detail.map { value in " (\(value))" } ?? ""
                return FlowDiagnostic(
                    severity: severity,
                    code: diagnostic.code.rawValue,
                    message: diagnostic.summary + detail
                )
            }
            let committed = persisted.committedNewRevision
            if result.status == .completed && !committed {
                diagnostics.append(FlowDiagnostic(
                    severity: .error,
                    code: "ELECTRICAL_SIGNOFF_REPAIR_NO_NEW_REVISION",
                    message: XcircuiteElectricalRepairRevisionError.noImmutableRevision.localizedDescription
                ))
            }
            let gateStatus: FlowGateStatus
            let stageStatus: FlowStageStatus
            switch result.status {
            case .completed where committed:
                gateStatus = .passed
                stageStatus = .succeeded
            case .blocked:
                gateStatus = .blocked
                stageStatus = .blocked
            case .completed:
                gateStatus = .blocked
                stageStatus = .blocked
            case .failed, .cancelled:
                gateStatus = .failed
                stageStatus = .failed
            }
            let artifacts = unique(result.artifacts + [wrapperReference])
            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: diagnostics,
                gates: [FlowGateResult(gateID: "electrical-repair-revision", status: gateStatus, diagnostics: diagnostics)],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "ELECTRICAL_SIGNOFF_REPAIR_REVISION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func validate(stage: FlowStageDefinition, context: FlowExecutionContext) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteElectricalRepairRevisionError.invalidRequest("stage ID does not match the executor")
        }
        guard request.schemaVersion == XcircuiteElectricalRepairRevisionRequest.currentSchemaVersion else {
            throw XcircuiteElectricalRepairRevisionError.unsupportedSchemaVersion(request.schemaVersion)
        }
        guard request.runID == context.runID,
              request.physicalDesignRequest.runID == context.runID else {
            throw XcircuiteElectricalRepairRevisionError.invalidRequest("request and physical-design run IDs must match the flow run")
        }
        guard request.physicalDesignRequest.inputLayout != nil else {
            throw XcircuiteElectricalRepairRevisionError.invalidRequest("an immutable repair revision requires a canonical input layout reference")
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func loadPlan(context: FlowExecutionContext) async throws -> ElectricalSignoffRepairPlan {
        let integrity = await context.infrastructure.verifyArtifact(request.repairPlanArtifact)
        guard integrity.isVerified else {
            throw XcircuiteElectricalRepairRevisionError.sourceIntegrity(integrity.diagnosticMessage)
        }
        do {
            let content = try await context.infrastructure.loadArtifactContent(
                for: request.repairPlanArtifact
            )
            return try JSONDecoder().decode(
                ElectricalSignoffRepairPlan.self,
                from: content
            )
        } catch {
            throw XcircuiteElectricalRepairRevisionError.invalidPlan(error.localizedDescription)
        }
    }

    private func selectCandidate(
        from plan: ElectricalSignoffRepairPlan
    ) throws -> ElectricalSignoffRepairPlan.Candidate {
        guard plan.runID == request.runID else {
            throw XcircuiteElectricalRepairRevisionError.invalidPlan("repair plan run ID does not match the request")
        }
        guard let candidate = plan.candidates.first(where: { $0.candidateID == request.selectedCandidateID }) else {
            throw XcircuiteElectricalRepairRevisionError.candidateNotFound(request.selectedCandidateID)
        }
        guard !candidate.actions.isEmpty else {
            throw XcircuiteElectricalRepairRevisionError.invalidPlan("selected candidate has no actionable repair contract")
        }
        return candidate
    }

    private func validateProvenance(
        plan: ElectricalSignoffRepairPlan,
        candidate: ElectricalSignoffRepairPlan.Candidate
    ) throws {
        guard let inputLayout = request.physicalDesignRequest.inputLayout else {
            throw XcircuiteElectricalRepairRevisionError.invalidRequest("input layout is required")
        }
        guard let planLayoutDigest = plan.layoutDigest,
              planLayoutDigest == inputLayout.layoutDigest else {
            throw XcircuiteElectricalRepairRevisionError.invalidPlan("selected revision does not descend from the failed signoff layout digest")
        }
        if let planDesignDigest = plan.designDigest,
           planDesignDigest != request.physicalDesignRequest.design.designDigest {
            throw XcircuiteElectricalRepairRevisionError.invalidPlan("design digest does not match the failed signoff plan")
        }
        if let planPDKDigest = plan.pdkDigest,
           planPDKDigest != request.physicalDesignRequest.pdk.digest {
            throw XcircuiteElectricalRepairRevisionError.invalidPlan("PDK digest does not match the failed signoff plan")
        }
        guard !candidate.entity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteElectricalRepairRevisionError.invalidPlan("selected candidate has no target entity")
        }
    }

    private func physicalDesignExecutorWithProjectStore(
        context: FlowExecutionContext
    ) -> NativePhysicalDesignExecutor {
        if let physicalDesignExecutor {
            return physicalDesignExecutor
        }
        return NativePhysicalDesignExecutor(
            allowedStages: [.timingECO, .drcRepair, .antennaRepair, .redundantViaInsertion, .hotspotRepair],
            artifactStore: FileSystemPhysicalDesignArtifactStore(projectRoot: context.projectRoot),
            implementationID: "native-electrical-signoff-repair-revision",
            implementationVersion: "1.0.0"
        )
    }

    private func persist(
        _ result: XcircuiteElectricalRepairRevisionResult,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        try await context.persistJSONArtifact(
            result,
            artifactID: "electrical-signoff-repair-revision",
            stageID: stageID,
            fileName: "repair-revision.json",
            kind: ArtifactKind.designDiff,
            mode: .replaceable
        )
    }

    private func unique(_ references: [ArtifactReference]) -> [ArtifactReference] {
        var paths = Set<String>()
        return references.filter { paths.insert($0.path).inserted }
    }

    private func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "electrical-repair-revision", status: .failed, diagnostics: [diagnostic])]
        )
    }
}
