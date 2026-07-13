import DesignFlowKernel
import ElectricalSignoffEngine
import Foundation
import PhysicalDesignCore
import XcircuitePackage

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
            try context.checkCancellation()
            try validate(stage: stage, context: context)
            let plan = try loadPlan(context: context)
            let candidate = try selectCandidate(from: plan)
            try validateProvenance(plan: plan, candidate: candidate)
            let executor = physicalDesignExecutorWithProjectStore(context: context)
            let result = try await executor.execute(request.physicalDesignRequest)
            try context.checkCancellation()
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
            let wrapperReference = try persist(persisted, context: context)
            var diagnostics = result.diagnostics.map { diagnostic in
                FlowDiagnostic(
                    severity: flowSeverity(for: diagnostic.severity),
                    code: diagnostic.code,
                    message: diagnostic.message
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
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func loadPlan(context: FlowExecutionContext) throws -> ElectricalSignoffRepairPlan {
        let integrity = XcircuiteFileReferenceVerifier().verify(
            request.repairPlanArtifact,
            projectRoot: context.projectRoot
        )
        guard integrity.status == .verified else {
            throw XcircuiteElectricalRepairRevisionError.sourceIntegrity(integrity.message)
        }
        let url = try XcircuitePackage(projectRoot: context.projectRoot)
            .url(forProjectRelativePath: request.repairPlanArtifact.path)
        do {
            return try JSONDecoder().decode(
                ElectricalSignoffRepairPlan.self,
                from: Data(contentsOf: url)
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
    ) throws -> XcircuiteFileReference {
        let relativePath = ".xcircuite/runs/\(context.runID)/electrical-signoff/repair-revision.json"
        let url = try context.packageStore.url(forProjectRelativePath: relativePath, inProjectAt: context.projectRoot)
        try context.packageStore.ensureDirectory(at: url.deletingLastPathComponent())
        try context.packageStore.writeJSON(result, to: url, forProjectAt: context.projectRoot)
        return try context.packageStore.fileReference(
            forProjectRelativePath: relativePath,
            artifactID: "electrical-signoff-repair-revision",
            kind: .designDiff,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
    }

    private func flowSeverity(for severity: XcircuiteEngineDiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private func unique(_ references: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
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
