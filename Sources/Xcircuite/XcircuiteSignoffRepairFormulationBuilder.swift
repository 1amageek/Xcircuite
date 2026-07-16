import DRCEngine
import CircuiteFoundation
import Foundation
import LVSEngine
import DesignFlowKernel

public struct XcircuiteSignoffRepairFormulationBuilder: Sendable {
    private struct LoadedReports {
        var drc: DRCRepairHintReport?
        var drcPath: String?
        var drcReference: ArtifactReference?
        var lvs: LVSRepairHintReport?
        var lvsPath: String?
        var lvsReference: ArtifactReference?
    }

    private struct DraftAction {
        var goal: XcircuiteRepairPlanFormulation.Goal
        var action: XcircuiteRepairPlanFormulation.Action
        var risk: XcircuitePlanningRiskClassification?
    }

    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let compiler: XcircuiteRepairPlanFormulationCompiler
    private let artifactVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        compiler: XcircuiteRepairPlanFormulationCompiler? = nil,
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.compiler = compiler ?? XcircuiteRepairPlanFormulationCompiler(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        )
        self.artifactVerifier = artifactVerifier
    }

    public func compile(
        request: XcircuiteSignoffRepairFormulationRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSignoffRepairFormulationResult {
        let loadedReports = try await loadReports(request: request, projectRoot: projectRoot)
        let actionDomainArtifact = try await artifactStore.persistActionDomainSnapshot(
            runID: request.runID,
            projectRoot: projectRoot
        )
        let formulation = try makeFormulation(
            request: request,
            loadedReports: loadedReports,
            actionDomainArtifact: actionDomainArtifact
        )
        let compilation = try await compiler.compile(
            request: XcircuiteRepairPlanFormulationCompilationRequest(
                runID: request.runID,
                formulation: formulation,
                problemID: request.problemID
            ),
            projectRoot: projectRoot
        )
        return XcircuiteSignoffRepairFormulationResult(
            status: compilation.status,
            runID: request.runID,
            formulationID: formulation.formulationID,
            problemID: compilation.problemID,
            sourceReports: sourceReports(from: loadedReports),
            compilation: compilation
        )
    }

    public func makeFormulation(
        request: XcircuiteSignoffRepairFormulationRequest,
        projectRoot: URL
    ) async throws -> XcircuiteRepairPlanFormulation {
        let loadedReports = try await loadReports(request: request, projectRoot: projectRoot)
        let actionDomainArtifact = try await artifactStore.persistActionDomainSnapshot(
            runID: request.runID,
            projectRoot: projectRoot
        )
        return try makeFormulation(
            request: request,
            loadedReports: loadedReports,
            actionDomainArtifact: actionDomainArtifact
        )
    }

    private func loadReports(
        request: XcircuiteSignoffRepairFormulationRequest,
        projectRoot: URL
    ) async throws -> LoadedReports {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        guard request.drcRepairHintPath != nil || request.lvsRepairHintPath != nil else {
            throw XcircuiteSignoffRepairFormulationError.missingRepairHintSource
        }
        let manifest = try await loadRunManifest(runID: request.runID)
        let drc: (report: DRCRepairHintReport, reference: ArtifactReference)?
        if let drcPath = request.drcRepairHintPath {
            drc = try await loadVerifiedReport(
                DRCRepairHintReport.self,
                sourceKind: "drc",
                path: drcPath,
                expectedArtifactID: "drc-repair-hints",
                runID: request.runID,
                manifest: manifest,
                projectRoot: projectRoot
            )
        } else {
            drc = nil
        }
        let lvs: (report: LVSRepairHintReport, reference: ArtifactReference)?
        if let lvsPath = request.lvsRepairHintPath {
            lvs = try await loadVerifiedReport(
                LVSRepairHintReport.self,
                sourceKind: "lvs",
                path: lvsPath,
                expectedArtifactID: "lvs-repair-hints",
                runID: request.runID,
                manifest: manifest,
                projectRoot: projectRoot
            )
        } else {
            lvs = nil
        }
        return LoadedReports(
            drc: drc?.report,
            drcPath: request.drcRepairHintPath,
            drcReference: drc?.reference,
            lvs: lvs?.report,
            lvsPath: request.lvsRepairHintPath,
            lvsReference: lvs?.reference
        )
    }

    private func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        return try await workspaceStore.loadRunManifest(runID: runID)
    }

    private func loadVerifiedReport<T: Decodable & Sendable>(
        _ type: T.Type,
        sourceKind: String,
        path: String,
        expectedArtifactID: String,
        runID: String,
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> (report: T, reference: ArtifactReference) {
        do {
            let location = try ArtifactLocation(workspaceRelativePath: path)
            _ = try location.resolvedFileURL(relativeTo: projectRoot)
        } catch {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: error.localizedDescription
            )
        }

        let matches = manifest.artifacts.filter { $0.path == path }
        guard !matches.isEmpty else {
            throw XcircuiteSignoffRepairFormulationError.unregisteredRepairHintReport(
                sourceKind: sourceKind,
                path: path
            )
        }
        guard matches.count == 1 else {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: "run manifest contains \(matches.count) artifacts for the same repair hint path."
            )
        }

        let reference = matches[0]
        guard reference.artifactID == expectedArtifactID else {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: "artifactID does not match expected \(expectedArtifactID)."
            )
        }
        guard reference.kind == .report, reference.format == .json else {
            throw XcircuiteSignoffRepairFormulationError.invalidRepairHintArtifact(
                sourceKind: sourceKind,
                path: path,
                reason: "repair hint reports must be JSON report artifacts."
            )
        }
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteSignoffRepairFormulationError.repairHintArtifactIntegrityFailed(
                sourceKind: sourceKind,
                path: path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }

        let data: Data
        do {
            data = try await workspaceStore.verifiedData(for: reference)
        } catch {
            throw XcircuiteSignoffRepairFormulationError.reportReadFailed(
                path: path,
                message: error.localizedDescription
            )
        }
        do {
            return (report: try JSONDecoder().decode(type, from: data), reference: reference)
        } catch {
            throw XcircuiteSignoffRepairFormulationError.reportReadFailed(
                path: path,
                message: error.localizedDescription
            )
        }
    }

    private func makeFormulation(
        request: XcircuiteSignoffRepairFormulationRequest,
        loadedReports: LoadedReports,
        actionDomainArtifact: ArtifactReference
    ) throws -> XcircuiteRepairPlanFormulation {
        let drcRepairDrafts: [DraftAction] = loadedReports.drc.map {
            drcDrafts(report: $0, sourcePath: loadedReports.drcPath)
        } ?? []
        let lvsRepairDrafts: [DraftAction] = loadedReports.lvs.map {
            lvsDrafts(report: $0, sourcePath: loadedReports.lvsPath)
        } ?? []
        let drafts: [DraftAction] = drcRepairDrafts + lvsRepairDrafts
        guard !drafts.isEmpty else {
            throw XcircuiteSignoffRepairFormulationError.noActionableHints
        }

        let risks = drafts.compactMap(\.risk)
        let hasApprovalRisk = risks.contains { !$0.requiredApprovals.isEmpty }
        return XcircuiteRepairPlanFormulation(
            formulationID: request.formulationID ?? "signoff-repair-formulation-\(request.runID)",
            runID: request.runID,
            intentID: request.intentID ?? "repair-signoff-diagnostics-\(request.runID)",
            intent: request.intent ?? defaultIntent(loadedReports: loadedReports),
            sourceRefs: sourceRefs(from: loadedReports),
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "action-domain-snapshot",
                    kind: "action-domain-snapshot",
                    path: actionDomainArtifact.path,
                    artifactID: actionDomainArtifact.artifactID
                ),
            ],
            assumptions: assumptions(from: loadedReports),
            riskClassifications: risks,
            goals: drafts.map(\.goal),
            constraints: constraints(
                hasApprovalRisk: hasApprovalRisk,
                sourceRefIDs: sourceRefIDs(from: loadedReports)
            ),
            actionDomainRefs: unique(drafts.map(\.action.domainID)),
            actions: drafts.map(\.action),
            costModel: costModel(),
            verificationGates: verificationGates(from: drafts),
            resumeContract: resumeContract(sourcePaths: [loadedReports.drcPath, loadedReports.lvsPath].compactMap { $0 }),
            metadata: metadata(from: loadedReports)
        )
    }

    private func sourceRefs(from loadedReports: LoadedReports) -> [XcircuitePlanningReference] {
        var refs: [XcircuitePlanningReference] = []
        if let report = loadedReports.drc, let path = loadedReports.drcPath {
            refs.append(XcircuitePlanningReference(
                refID: "drc-repair-hints",
                kind: "drc-repair-hint-report",
                path: path,
                artifactID: "drc-repair-hints",
                metadata: sourceMetadata(
                    sourceKind: "drc",
                    backendID: report.backendID,
                    topCell: report.topCell,
                    status: report.status,
                    activeDiagnosticCount: report.activeDiagnosticCount,
                    hintCount: report.hintCount,
                    unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                    reference: loadedReports.drcReference
                )
            ))
        }
        if let report = loadedReports.lvs, let path = loadedReports.lvsPath {
            refs.append(XcircuitePlanningReference(
                refID: "lvs-repair-hints",
                kind: "lvs-repair-hint-report",
                path: path,
                artifactID: "lvs-repair-hints",
                metadata: sourceMetadata(
                    sourceKind: "lvs",
                    backendID: report.backendID,
                    topCell: report.topCell,
                    status: report.status,
                    activeDiagnosticCount: report.activeDiagnosticCount,
                    hintCount: report.hintCount,
                    unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                    reference: loadedReports.lvsReference
                )
            ))
        }
        return refs
    }

    private func sourceReports(
        from loadedReports: LoadedReports
    ) -> [XcircuiteSignoffRepairFormulationResult.SourceReport] {
        var reports: [XcircuiteSignoffRepairFormulationResult.SourceReport] = []
        if let report = loadedReports.drc, let path = loadedReports.drcPath {
            reports.append(XcircuiteSignoffRepairFormulationResult.SourceReport(
                sourceKind: "drc",
                path: path,
                backendID: report.backendID,
                topCell: report.topCell,
                status: report.status,
                activeDiagnosticCount: report.activeDiagnosticCount,
                hintCount: report.hintCount,
                unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                artifactID: loadedReports.drcReference?.artifactID,
                sha256: loadedReports.drcReference?.sha256,
                byteCount: loadedReports.drcReference.flatMap { Int64(exactly: $0.byteCount) },
                integrityStatus: FlowArtifactVerificationStatus.verified.rawValue
            ))
        }
        if let report = loadedReports.lvs, let path = loadedReports.lvsPath {
            reports.append(XcircuiteSignoffRepairFormulationResult.SourceReport(
                sourceKind: "lvs",
                path: path,
                backendID: report.backendID,
                topCell: report.topCell,
                status: report.status,
                activeDiagnosticCount: report.activeDiagnosticCount,
                hintCount: report.hintCount,
                unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
                artifactID: loadedReports.lvsReference?.artifactID,
                sha256: loadedReports.lvsReference?.sha256,
                byteCount: loadedReports.lvsReference.flatMap { Int64(exactly: $0.byteCount) },
                integrityStatus: FlowArtifactVerificationStatus.verified.rawValue
            ))
        }
        return reports
    }

    private func drcDrafts(
        report: DRCRepairHintReport,
        sourcePath: String?
    ) -> [DraftAction] {
        report.hints.enumerated().map { pair in
            let index = pair.offset
            let hint = pair.element
            let goalID = "drc-goal-\(index)"
            let actionID = "drc-action-\(index)"
            let target = "drc-\(symbolicAtomToken(hint.kind ?? hint.ruleID ?? "violation"))-cleared"
            let goal = XcircuiteRepairPlanFormulation.Goal(
                goalID: goalID,
                kind: "repair",
                domain: "drc",
                priority: "error",
                sourceRefIDs: ["drc-repair-hints"],
                target: target,
                currentValue: hint.measured.map { .scalar($0) },
                requiredValue: hint.required.map { .scalar($0) },
                unit: hint.stringParameters["unit"],
                description: "Clear active DRC diagnostic \(hint.hintID) for \(hint.ruleID ?? hint.kind ?? "unknown-rule").",
                symbolicGoalAtoms: [target],
                evidence: drcEvidence(hint: hint, sourcePath: sourcePath),
                suggestedActions: [hint.operationID]
            )
            let action = XcircuiteRepairPlanFormulation.Action(
                actionID: actionID,
                domainID: domainID(for: hint.operationID),
                operationID: hint.operationID,
                maturity: "implemented",
                reason: hint.rationale,
                sourceGoalIDs: [goalID],
                requiredInputRefs: ["drc-repair-hints"],
                verificationGates: hint.verificationGates,
                parameterHints: drcParameterHints(hint: hint, sourcePath: sourcePath)
            )
            return DraftAction(
                goal: goal,
                action: action,
                risk: drcRisk(hint: hint, goalID: goalID, actionID: actionID)
            )
        }
    }

    private func lvsDrafts(
        report: LVSRepairHintReport,
        sourcePath: String?
    ) -> [DraftAction] {
        report.hints.enumerated().map { pair in
            let index = pair.offset
            let hint = pair.element
            let goalID = "lvs-goal-\(index)"
            let actionID = "lvs-action-\(index)"
            let target = "lvs-\(symbolicAtomToken(hint.category ?? hint.ruleID ?? "mismatch"))-resolved"
            let goal = XcircuiteRepairPlanFormulation.Goal(
                goalID: goalID,
                kind: "repair",
                domain: "lvs",
                priority: "error",
                sourceRefIDs: ["lvs-repair-hints"],
                target: target,
                currentValue: lvsCurrentValue(hint),
                requiredValue: lvsRequiredValue(hint),
                description: "Resolve active LVS diagnostic \(hint.hintID) for \(hint.ruleID ?? hint.category ?? "unknown-rule").",
                symbolicGoalAtoms: [target],
                evidence: lvsEvidence(hint: hint, sourcePath: sourcePath),
                suggestedActions: [hint.operationID]
            )
            let action = XcircuiteRepairPlanFormulation.Action(
                actionID: actionID,
                domainID: domainID(for: hint.operationID),
                operationID: hint.operationID,
                maturity: "implemented",
                reason: hint.rationale,
                sourceGoalIDs: [goalID],
                requiredInputRefs: ["lvs-repair-hints"],
                verificationGates: normalizedLVSGates(hint.verificationGates, operationID: hint.operationID),
                parameterHints: lvsParameterHints(hint: hint, sourcePath: sourcePath)
            )
            return DraftAction(
                goal: goal,
                action: action,
                risk: lvsRisk(hint: hint, goalID: goalID, actionID: actionID)
            )
        }
    }

    private func sourceMetadata(
        sourceKind: String,
        backendID: String,
        topCell: String,
        status: String,
        activeDiagnosticCount: Int,
        hintCount: Int,
        unsupportedDiagnosticCount: Int,
        reference: ArtifactReference?
    ) -> [String: PlanningParameterValue] {
        var metadata: [String: PlanningParameterValue] = [
            "sourceKind": .text(sourceKind),
            "backendID": .text(backendID),
            "topCell": .text(topCell),
            "status": .text(status),
            "activeDiagnosticCount": .scalar(Double(activeDiagnosticCount)),
            "hintCount": .scalar(Double(hintCount)),
            "unsupportedDiagnosticCount": .scalar(Double(unsupportedDiagnosticCount)),
        ]
        if let reference {
            metadata["artifactID"] = .text(reference.artifactID)
            metadata["artifactPath"] = .text(reference.path)
            metadata["artifactSHA256"] = .text(reference.sha256)
            metadata["artifactByteCount"] = .scalar(Double(reference.byteCount))
            metadata["artifactIntegrityStatus"] = .text(FlowArtifactVerificationStatus.verified.rawValue)
        }
        return metadata
    }

    private func drcEvidence(
        hint: DRCRepairHint,
        sourcePath: String?
    ) -> [String: PlanningParameterValue] {
        var evidence = drcParameterHints(hint: hint, sourcePath: sourcePath)
        evidence["sourceEngineOperation"] = .text("drc.export-repair-hints")
        evidence["sourceDiagnosticIndex"] = .scalar(Double(hint.sourceDiagnosticIndex))
        evidence["repairHintID"] = .text(hint.hintID)
        evidence["repairHintConfidence"] = .text(hint.confidence)
        return evidence
    }

    private func drcParameterHints(
        hint: DRCRepairHint,
        sourcePath: String?
    ) -> [String: PlanningParameterValue] {
        var values = jsonValues(strings: hint.stringParameters, numbers: hint.numericParameters)
        values["sourceKind"] = .text("drc")
        values["sourceRepairHintPath"] = sourcePath.map { .text($0) }
        values["repairHintID"] = .text(hint.hintID)
        values["operationID"] = .text(hint.operationID)
        values["confidence"] = .text(hint.confidence)
        values["targetShapeIDs"] = jsonArray(hint.targetShapeIDs)
        values["relatedViaIDs"] = jsonArray(hint.relatedViaIDs)
        values["relatedNetIDs"] = jsonArray(hint.relatedNetIDs)
        if let measured = hint.measured {
            values["measured"] = .scalar(measured)
        }
        if let required = hint.required {
            values["required"] = .scalar(required)
        }
        if let region = hint.region {
            values["region"] = .region(
                PlanningRegion(x: region.x, y: region.y, width: region.width, height: region.height)
            )
        }
        return values
    }

    private func lvsEvidence(
        hint: LVSRepairHint,
        sourcePath: String?
    ) -> [String: PlanningParameterValue] {
        var evidence = lvsParameterHints(hint: hint, sourcePath: sourcePath)
        evidence["sourceEngineOperation"] = .text("lvs.export-repair-hints")
        evidence["sourceDiagnosticIndex"] = .scalar(Double(hint.sourceDiagnosticIndex))
        evidence["repairHintID"] = .text(hint.hintID)
        evidence["repairHintConfidence"] = .text(hint.confidence)
        return evidence
    }

    private func lvsParameterHints(
        hint: LVSRepairHint,
        sourcePath: String?
    ) -> [String: PlanningParameterValue] {
        var values = jsonValues(strings: hint.stringParameters, numbers: [:])
        values["sourceKind"] = .text("lvs")
        values["sourceRepairHintPath"] = sourcePath.map { .text($0) }
        values["repairHintID"] = .text(hint.hintID)
        values["operationID"] = .text(hint.operationID)
        values["confidence"] = .text(hint.confidence)
        values["layoutPorts"] = jsonArray(hint.layoutPorts)
        values["schematicPorts"] = jsonArray(hint.schematicPorts)
        if let layoutCount = hint.layoutCount {
            values["layoutCount"] = .scalar(Double(layoutCount))
        }
        if let schematicCount = hint.schematicCount {
            values["schematicCount"] = .scalar(Double(schematicCount))
        }
        return values
    }

    private func lvsCurrentValue(_ hint: LVSRepairHint) -> PlanningParameterValue? {
        if let value = hint.layoutValue {
            return .text(value)
        }
        if let count = hint.layoutCount {
            return .scalar(Double(count))
        }
        if !hint.layoutPorts.isEmpty {
            return jsonArray(hint.layoutPorts)
        }
        return nil
    }

    private func lvsRequiredValue(_ hint: LVSRepairHint) -> PlanningParameterValue? {
        if let value = hint.schematicValue {
            return .text(value)
        }
        if let count = hint.schematicCount {
            return .scalar(Double(count))
        }
        if !hint.schematicPorts.isEmpty {
            return jsonArray(hint.schematicPorts)
        }
        return nil
    }

    private func assumptions(from loadedReports: LoadedReports) -> [XcircuitePlanningAssumption] {
        [
            XcircuitePlanningAssumption(
                assumptionID: "signoff-repair-hints-are-engine-derived",
                source: "xcircuite.formulate-signoff-repair-planning-problem",
                statement: "DRC and LVS repair formulations are derived from engine-owned typed repair hint reports.",
                status: "resolved",
                confidence: 1,
                sourceRefIDs: sourceRefIDs(from: loadedReports),
                requiredBeforeExecution: false,
                evidence: metadata(from: loadedReports)
            ),
        ]
    }

    private func drcRisk(
        hint: DRCRepairHint,
        goalID: String,
        actionID: String
    ) -> XcircuitePlanningRiskClassification? {
        guard hint.confidence == "low"
            || hint.operationID == "layout.delete-shape"
            || hint.operationID == "layout.split-shape"
            || hint.operationID == "layout.add-via" else {
            return nil
        }
        let severity = hint.confidence == "low" ? "high" : "medium"
        return XcircuitePlanningRiskClassification(
            riskID: "\(actionID)-layout-risk",
            category: "layout-signoff-regression",
            severity: severity,
            scope: "layout-edit",
            description: "DRC repair hint \(hint.hintID) may change connectivity or create secondary signoff violations.",
            affectedObjectiveIDs: [goalID],
            affectedActionIDs: [actionID],
            requiredApprovals: severity == "high" ? ["layout-review"] : [],
            mitigationActions: ["run-native-drc", "run-native-lvs"],
            evidence: [
                "repairHintID": .text(hint.hintID),
                "operationID": .text(hint.operationID),
                "confidence": .text(hint.confidence),
            ]
        )
    }

    private func lvsRisk(
        hint: LVSRepairHint,
        goalID: String,
        actionID: String
    ) -> XcircuitePlanningRiskClassification? {
        if hint.operationID == "lvs.policy-repair" {
            return XcircuitePlanningRiskClassification(
                riskID: "\(actionID)-policy-risk",
                category: "lvs-policy-mutation",
                severity: "high",
                scope: "lvs-policy",
                description: "LVS policy repair hint \(hint.hintID) changes equivalence policy and requires human approval.",
                affectedObjectiveIDs: [goalID],
                affectedActionIDs: [actionID],
                requiredApprovals: ["lvs-policy-review"],
                mitigationActions: ["run-native-lvs", "review-policy-diff"],
                evidence: [
                    "repairHintID": .text(hint.hintID),
                    "operationID": .text(hint.operationID),
                    "confidence": .text(hint.confidence),
                ]
            )
        }
        if hint.confidence == "low" {
            return XcircuitePlanningRiskClassification(
                riskID: "\(actionID)-layout-risk",
                category: "lvs-layout-edit-regression",
                severity: "high",
                scope: "layout-edit",
                description: "Low-confidence LVS repair hint \(hint.hintID) may not preserve intended connectivity.",
                affectedObjectiveIDs: [goalID],
                affectedActionIDs: [actionID],
                requiredApprovals: ["layout-review"],
                mitigationActions: ["run-native-lvs", "run-native-drc"],
                evidence: [
                    "repairHintID": .text(hint.hintID),
                    "operationID": .text(hint.operationID),
                    "confidence": .text(hint.confidence),
                ]
            )
        }
        return nil
    }

    private func constraints(
        hasApprovalRisk: Bool,
        sourceRefIDs: [String]
    ) -> [XcircuitePlanningConstraint] {
        var constraints = [
            XcircuitePlanningConstraint(
                constraintID: "post-repair-signoff-required",
                kind: "verification",
                severity: "error",
                description: "Any selected signoff repair must be verified by the native DRC/LVS gates declared on the action.",
                sourceRefIDs: sourceRefIDs,
                evidence: [
                    "coveredSourceRefIDs": .textList(sourceRefIDs),
                ]
            ),
        ]
        if hasApprovalRisk {
            constraints.append(XcircuitePlanningConstraint(
                constraintID: "human-approval-required-for-risk",
                kind: "human-approval",
                severity: "error",
                description: "High-risk layout or LVS policy repair actions require explicit human approval before execution.",
                sourceRefIDs: sourceRefIDs,
                evidence: [
                    "coveredSourceRefIDs": .textList(sourceRefIDs),
                ]
            ))
        }
        return constraints
    }

    private func verificationGates(from drafts: [DraftAction]) -> [XcircuitePlanningVerificationGate] {
        unique(drafts.flatMap(\.action.verificationGates)).map { gateID in
            XcircuitePlanningVerificationGate(
                gateID: gateID,
                required: true,
                description: "Required by signoff repair formulation action gate \(gateID)."
            )
        }
    }

    private func costModel() -> XcircuitePlanningCostModel {
        XcircuitePlanningCostModel(
            strategy: "signoff-repair-formulation-confidence-first",
            terms: [
                XcircuitePlanningCostTerm(
                    termID: "repair.action-count",
                    weight: 1,
                    direction: "minimize",
                    description: "Prefer fewer signoff repair actions before re-running verification."
                ),
                XcircuitePlanningCostTerm(
                    termID: "repair.risk",
                    weight: 3,
                    direction: "minimize",
                    description: "Prefer higher-confidence repair hints and avoid approval-gated mutations when alternatives exist."
                ),
            ]
        )
    }

    private func resumeContract(sourcePaths: [String]) -> XcircuitePlanningResumeContract {
        XcircuitePlanningResumeContract(
            mode: "signoff-repair-formulation",
            requiredArtifacts: unique(
                sourcePaths
                    + [
                        XcircuitePlanningArtifactStore.repairPlanFormulationRelativePath,
                        XcircuitePlanningArtifactStore.problemRelativePath,
                        XcircuitePlanningArtifactStore.actionDomainRelativePath,
                    ]
            ),
            blockedStates: ["repair-hints-missing", "formulation-validation-failed", "candidate-rejected"]
        )
    }

    private func defaultIntent(loadedReports: LoadedReports) -> String {
        let kinds = sourceRefIDs(from: loadedReports).joined(separator: " and ")
        return "Repair active \(kinds) signoff diagnostics using engine-derived repair hints, then verify with native signoff gates."
    }

    private func metadata(from loadedReports: LoadedReports) -> [String: PlanningParameterValue] {
        let sourceReports = sourceReports(from: loadedReports)
        return [
            "sourceReportCount": .scalar(Double(sourceReports.count)),
            "totalActiveDiagnosticCount": .scalar(Double(sourceReports.map(\.activeDiagnosticCount).reduce(0, +))),
            "totalRepairHintCount": .scalar(Double(sourceReports.map(\.hintCount).reduce(0, +))),
            "totalUnsupportedDiagnosticCount": .scalar(Double(sourceReports.map(\.unsupportedDiagnosticCount).reduce(0, +))),
        ]
    }

    private func sourceRefIDs(from loadedReports: LoadedReports) -> [String] {
        var ids: [String] = []
        if loadedReports.drc != nil {
            ids.append("drc-repair-hints")
        }
        if loadedReports.lvs != nil {
            ids.append("lvs-repair-hints")
        }
        return ids
    }

    private func domainID(for operationID: String) -> String {
        operationID.hasPrefix("layout.") ? "layout-edit" : "lvs-signoff"
    }

    private func normalizedLVSGates(_ gates: [String], operationID: String) -> [String] {
        var result = gates
        if operationID == "lvs.policy-repair" && !result.contains("approval-gate") {
            result.append("approval-gate")
        }
        return result
    }

    private func jsonValues(
        strings: [String: String],
        numbers: [String: Double]
    ) -> [String: PlanningParameterValue] {
        var values = strings.mapValues { PlanningParameterValue.text($0) }
        for (key, value) in numbers {
            values[key] = .scalar(value)
        }
        return values
    }

    private func jsonArray(_ values: [String]) -> PlanningParameterValue {
        .textList(values)
    }

    private func symbolicAtomToken(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let mapped = value.lowercased().map { character -> Character in
            allowed.contains(character) ? character : "-"
        }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "diagnostic" : collapsed
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
