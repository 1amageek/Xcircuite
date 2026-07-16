import Foundation
import CircuiteFoundation
import SignoffToolSupport
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverValidator: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let solverRunner: XcircuiteSymbolicPlannerSolving
    private let artifactReferenceResolver: XcircuiteSymbolicPlannerArtifactReferenceResolver

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        solverRunner: (any XcircuiteSymbolicPlannerSolving)? = nil,
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.solverRunner = solverRunner ?? XcircuiteSymbolicPlannerSolverRunner(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore,
            artifactVerifier: artifactVerifier
        )
        self.artifactReferenceResolver = XcircuiteSymbolicPlannerArtifactReferenceResolver(
            workspaceStore: workspaceStore,
            artifactVerifier: artifactVerifier
        )
    }

    public func validate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverValidationResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        try await validateValidationRequest(request)
        if let maximumSolverCost = request.maximumSolverCost,
           (!maximumSolverCost.isFinite || maximumSolverCost < 0) {
            throw XcircuiteSymbolicPlannerSolverError.invalidMaximumSolverCost(maximumSolverCost)
        }
        if request.requireProofValidation,
           (!request.proofCheckerTimeoutSeconds.isFinite || request.proofCheckerTimeoutSeconds <= 0) {
            throw XcircuiteSymbolicPlannerSolverError.invalidProofCheckerTimeout(request.proofCheckerTimeoutSeconds)
        }
        let solverResult = try await solverRunner.solve(
            request: XcircuiteSymbolicPlannerSolverRequest(
                runID: request.runID,
                executablePath: request.executablePath,
                arguments: request.arguments,
                timeoutSeconds: request.timeoutSeconds,
                domainArtifactID: request.domainArtifactID,
                domainPath: request.domainPath,
                problemArtifactID: request.problemArtifactID,
                problemPath: request.problemPath,
                pddlExportArtifactID: request.pddlExportArtifactID,
                pddlExportPath: request.pddlExportPath,
                workingDirectoryPath: request.workingDirectoryPath,
                solverPlanOutputPath: request.solverPlanOutputPath,
                importCandidatePlan: true
            ),
            projectRoot: projectRoot
        )

        var diagnostics = solverResult.diagnostics
        let observedActionIDs = solverResult.importResult?.candidatePlan.steps.map(\.actionID) ?? []
        let planCostEvaluation = try await planCostEvaluation(
            solverResult: solverResult,
            projectRoot: projectRoot
        )
        let planReplayValidation = try await planReplayValidation(
            solverResult: solverResult,
            projectRoot: projectRoot
        )
        let planReplayValidationArtifact: ArtifactReference?
        if let retainedArtifact = solverResult.planReplayValidationArtifact {
            planReplayValidationArtifact = retainedArtifact
        } else if let planReplayValidation {
            planReplayValidationArtifact = try await artifactStore.persistSymbolicPlannerPlanReplayValidation(
                planReplayValidation,
                runID: request.runID,
                projectRoot: projectRoot
            )
        } else {
            planReplayValidationArtifact = nil
        }
        let nativeCertificateResult = try await nativeCertificate(
            request: request,
            solverResult: solverResult,
            projectRoot: projectRoot
        )
        let proofValidationResult = try await proofValidation(
            request: request,
            solverResult: solverResult,
            projectRoot: projectRoot
        )
        appendActionDiagnostics(
            expectedActionIDs: request.expectedActionIDs,
            observedActionIDs: observedActionIDs,
            diagnostics: &diagnostics
        )
        appendSolverMetadataDiagnostics(
            request: request,
            solverMetadata: solverResult.solverMetadata,
            nativeCertificate: nativeCertificateResult.certificate,
            planCostEvaluation: planCostEvaluation,
            diagnostics: &diagnostics
        )
        diagnostics.append(contentsOf: nativeCertificateResult.diagnostics)
        appendPlanReplayDiagnostics(
            planReplayValidation: planReplayValidation,
            diagnostics: &diagnostics
        )
        diagnostics.append(contentsOf: proofValidationResult.diagnostics)
        appendProofValidationDiagnostics(
            proofValidation: proofValidationResult.validation,
            diagnostics: &diagnostics
        )

        var planVerificationArtifact: ArtifactReference?
        var goalCoverageStatus: String?
        var missingGoalAtoms: [String] = []
        if solverResult.importResult != nil {
            let verifierResult = try await XcircuiteCandidatePlanVerifier(
                workspaceStore: workspaceStore,
                artifactStore: artifactStore
            ).verifyCandidatePlan(
                request: XcircuiteCandidatePlanVerificationRequest(runID: request.runID),
                projectRoot: projectRoot
            )
            planVerificationArtifact = verifierResult.planVerificationArtifact
            let verification = try await workspaceStore.readJSON(
                XcircuitePlanVerification.self,
                from: planVerificationArtifact?.path
                    ?? verifierResult.planVerificationArtifact.path
            )
            goalCoverageStatus = verification.goalCoverageStatus
            missingGoalAtoms = verification.missingGoalAtoms
            if request.requireGoalCoverage, verification.goalCoverageStatus != "covered" {
                diagnostics.append(
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "goal-coverage-not-validated",
                        message: "Validated symbolic planner solver output must cover objective goal atoms."
                    )
                )
            }
            appendNativeCertificateDiagnostics(
                request: request,
                nativeCertificate: nativeCertificateResult.certificate,
                observedActionIDs: observedActionIDs,
                goalCoverageStatus: verification.goalCoverageStatus,
                planCostEvaluation: planCostEvaluation,
                diagnostics: &diagnostics
            )
        } else {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "candidate-plan-not-imported",
                    message: "Solver validation requires a typed candidate plan imported from the solver output."
                )
            )
        }
        if solverResult.importResult == nil {
            appendNativeCertificateDiagnostics(
                request: request,
                nativeCertificate: nativeCertificateResult.certificate,
                observedActionIDs: observedActionIDs,
                goalCoverageStatus: nil,
                planCostEvaluation: planCostEvaluation,
                diagnostics: &diagnostics
            )
        }

        let status = diagnostics.contains(where: { $0.severity == "error" }) ? "failed" : "passed"
        let result = makeResult(
            status: status,
            request: request,
            solverResult: solverResult,
            observedActionIDs: observedActionIDs,
            goalCoverageStatus: goalCoverageStatus,
            missingGoalAtoms: missingGoalAtoms,
            planCostEvaluation: planCostEvaluation,
            planReplayValidation: planReplayValidation,
            nativeCertificate: nativeCertificateResult.certificate,
            proofValidation: proofValidationResult.validation,
            planReplayValidationArtifact: planReplayValidationArtifact,
            nativeCertificateArtifact: nativeCertificateResult.artifact,
            proofValidationArtifact: proofValidationResult.artifact,
            planVerificationArtifact: planVerificationArtifact,
            validationArtifact: nil,
            diagnostics: diagnostics
        )
        let validationArtifact = try await artifactStore.persistSymbolicPlannerSolverValidation(
            result,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return result.attachingValidationArtifact(
            validationArtifact
        )
    }

    private func validateValidationRequest(
        _ request: XcircuiteSymbolicPlannerSolverValidationRequest
    ) async throws {
        let validator = FlowIdentifierValidator()
        try validateIdentifier(request.toolID, field: "toolID", kind: .toolID, validator: validator)
        try validateIdentifier(request.policyID, field: "policyID", kind: .artifactID, validator: validator)
        for expectedActionID in request.expectedActionIDs {
            try validateIdentifier(
                expectedActionID,
                field: "expectedActionIDs",
                kind: .artifactID,
                validator: validator
            )
        }
        try validateIdentifier(request.domainArtifactID, field: "domainArtifactID", validator: validator)
        try validateIdentifier(request.problemArtifactID, field: "problemArtifactID", validator: validator)
        try validateIdentifier(request.pddlExportArtifactID, field: "pddlExportArtifactID", validator: validator)
        try validateIdentifier(request.certificateArtifactID, field: "certificateArtifactID", validator: validator)
        try validateIdentifier(request.proofArtifactID, field: "proofArtifactID", validator: validator)

        try await validateProjectPath(request.domainPath, field: "domainPath")
        try await validateProjectPath(request.problemPath, field: "problemPath")
        try await validateProjectPath(request.pddlExportPath, field: "pddlExportPath")
        try await validateProjectPath(request.workingDirectoryPath, field: "workingDirectoryPath")
        try await validateProjectPath(request.solverPlanOutputPath, field: "solverPlanOutputPath")
        try await validateProjectPath(request.certificatePath, field: "certificatePath")
        try await validateProjectPath(request.proofPath, field: "proofPath")
        try await validateProjectPath(
            request.proofCheckerWorkingDirectoryPath,
            field: "proofCheckerWorkingDirectoryPath"
        )

        try validateExecutablePath(request.executablePath, field: "executablePath")
        if let proofCheckerExecutablePath = request.proofCheckerExecutablePath {
            try validateExecutablePath(proofCheckerExecutablePath, field: "proofCheckerExecutablePath")
        }
    }

    private func validateIdentifier(
        _ value: String?,
        field: String,
        kind: FlowIdentifierKind = .artifactID,
        validator: FlowIdentifierValidator
    ) throws {
        guard let value else { return }
        do {
            try validator.validate(value, kind: kind)
        } catch {
            throw XcircuiteSymbolicPlannerSolverError.invalidSolverValidationReference(
                field: field,
                value: value
            )
        }
    }

    private func validateProjectPath(
        _ value: String?,
        field: String
    ) async throws {
        guard let value else { return }
        do {
            _ = try await workspaceStore.url(for: value)
        } catch {
            throw XcircuiteSymbolicPlannerSolverError.invalidSolverValidationPath(
                field: field,
                value: value
            )
        }
    }

    private func validateExecutablePath(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteSymbolicPlannerSolverError.invalidSolverValidationExecutablePath(
                field: field,
                value: value
            )
        }
    }

    private func appendActionDiagnostics(
        expectedActionIDs: [String],
        observedActionIDs: [String],
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard !expectedActionIDs.isEmpty else { return }
        let observed = Set(observedActionIDs)
        let missing = expectedActionIDs.filter { !observed.contains($0) }
        if !missing.isEmpty {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "expected-actions-missing",
                    message: "Solver output did not include expected candidate actions: \(missing.joined(separator: ","))."
                )
            )
        }
    }

    private func planCostEvaluation(
        solverResult: XcircuiteSymbolicPlannerSolverResult,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerPlanCostEvaluation? {
        guard let importResult = solverResult.importResult else {
            return nil
        }
        let pddlExportArtifact = try await artifactReferenceResolver.verifiedArtifactReference(
            importResult.pddlExportArtifact,
            field: "pddlExportArtifact",
            expectedFormat: .json,
            runID: solverResult.runID,
            projectRoot: projectRoot
        )
        let pddlExport = try await workspaceStore.readJSON(
            XcircuiteSymbolicPlannerPDDLExport.self,
            from: pddlExportArtifact.path
        )
        return XcircuiteSymbolicPlannerPlanCostEvaluator()
            .evaluate(candidatePlan: importResult.candidatePlan, pddlExport: pddlExport)
    }

    private func planReplayValidation(
        solverResult: XcircuiteSymbolicPlannerSolverResult,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerPlanReplayValidation? {
        if let planReplayValidation = solverResult.planReplayValidation {
            return planReplayValidation
        }
        guard let importResult = solverResult.importResult else {
            return nil
        }
        let pddlExportArtifact = try await artifactReferenceResolver.verifiedArtifactReference(
            importResult.pddlExportArtifact,
            field: "pddlExportArtifact",
            expectedFormat: .json,
            runID: solverResult.runID,
            projectRoot: projectRoot
        )
        let pddlExport = try await workspaceStore.readJSON(
            XcircuiteSymbolicPlannerPDDLExport.self,
            from: pddlExportArtifact.path
        )
        return XcircuiteSymbolicPlannerPlanReplayValidator().validate(
            candidatePlan: importResult.candidatePlan,
            pddlExport: pddlExport
        )
    }

    private func appendSolverMetadataDiagnostics(
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        solverMetadata: XcircuiteSymbolicPlannerSolverMetadata?,
        nativeCertificate: XcircuiteSymbolicPlannerSolverCertificateParseResult?,
        planCostEvaluation: XcircuiteSymbolicPlannerPlanCostEvaluation?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        let optimalityStatus = nativeCertificate?.certificate?.optimalityStatus
            ?? solverMetadata?.optimalityStatus
        if request.requireOptimality, optimalityStatus != "optimal" {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "optimality-not-validated",
                    message: "Validated symbolic planner solver output must include an optimality claim."
                )
            )
        }

        if let claimedPlanLength = solverMetadata?.planLength,
           let evaluatedPlanLength = planCostEvaluation?.planLength,
           claimedPlanLength != evaluatedPlanLength {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "solver-plan-length-claim-mismatch",
                    message: "Solver plan length claim \(claimedPlanLength) does not match imported candidate plan length \(evaluatedPlanLength)."
                )
            )
        }

        if let claimedPlanCost = solverMetadata?.planCost,
           let evaluatedPlanCost = planCostEvaluation?.evaluatedCost,
           !approximatelyEqual(claimedPlanCost, evaluatedPlanCost) {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "solver-cost-claim-mismatch",
                    message: "Solver plan cost claim \(claimedPlanCost) does not match independently evaluated plan cost \(evaluatedPlanCost)."
                )
            )
        }

        guard let maximumSolverCost = request.maximumSolverCost else {
            return
        }
        guard maximumSolverCost.isFinite, maximumSolverCost >= 0 else {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "invalid-solver-cost-bound",
                    message: "Solver validation maximum cost must be finite and non-negative."
                )
            )
            return
        }
        guard let planCost = planCostEvaluation?.evaluatedCost else {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "solver-cost-missing",
                    message: "Validated symbolic planner solver output must import a candidate plan so LSI can evaluate cost when a maximum cost is configured."
                )
            )
            return
        }
        if planCost > maximumSolverCost {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "solver-cost-exceeds-bound",
                    message: "Solver plan cost \(planCost) exceeds configured maximum cost \(maximumSolverCost)."
                )
            )
        }
    }

    private func appendPlanReplayDiagnostics(
        planReplayValidation: XcircuiteSymbolicPlannerPlanReplayValidation?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard let planReplayValidation else {
            return
        }
        let existingCodes = Set(diagnostics.map(\.code))
        for replayDiagnostic in planReplayValidation.diagnostics {
            let diagnosticCode = "plan-replay-\(replayDiagnostic.code)"
            if existingCodes.contains(diagnosticCode) {
                continue
            }
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: replayDiagnostic.severity,
                    code: diagnosticCode,
                    message: replayDiagnostic.message
                )
            )
        }
    }

    private func nativeCertificate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        solverResult: XcircuiteSymbolicPlannerSolverResult,
        projectRoot: URL
    ) async throws -> NativeCertificateRunResult {
        let shouldParse = request.requireNativeCertificate
            || request.certificateArtifactID != nil
            || request.certificatePath != nil
        guard shouldParse else {
            return NativeCertificateRunResult(certificate: nil, artifact: nil, diagnostics: [])
        }
        let manifest = try await loadRunManifest(runID: request.runID)
        guard let sourceArtifact = try await certificateArtifact(
            request: request,
            solverResult: solverResult,
            manifest: manifest,
            projectRoot: projectRoot
        ) else {
            return NativeCertificateRunResult(
                certificate: nil,
                artifact: nil,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "native-certificate-missing",
                        message: "Native solver certificate parsing requires a certificate artifact or project-relative certificate path."
                    ),
                ]
            )
        }
        let certificateURL = try await workspaceStore.url(for: sourceArtifact.path)
        let certificateText = try String(contentsOf: certificateURL, encoding: .utf8)
        let parsed = XcircuiteSymbolicPlannerSolverCertificateParser().parse(
            text: certificateText,
            requestedFormat: request.certificateFormat
        )
        let parseResult = XcircuiteSymbolicPlannerSolverCertificateParseResult(
            status: parsed.status,
            runID: request.runID,
            toolID: request.toolID,
            requestedFormat: request.certificateFormat,
            detectedFormat: parsed.detectedFormat,
            sourceArtifact: sourceArtifact,
            certificate: parsed.certificate,
            diagnostics: parsed.diagnostics
        )
        let artifact = try await artifactStore.persistSymbolicPlannerSolverCertificate(
            parseResult,
            runID: request.runID,
            projectRoot: projectRoot
        )
        var diagnostics = parsed.diagnostics
        if request.requireNativeCertificate, parsed.status != "parsed" {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "native-certificate-not-validated",
                    message: "Native solver certificate was required but could not be parsed into trusted claims."
                )
            )
        }
        if solverResult.exitCode != 0, parsed.status == "parsed" {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "warning",
                    code: "native-certificate-from-failed-solver-process",
                    message: "Native solver certificate was parsed, but the solver process did not complete successfully."
                )
            )
        }
        return NativeCertificateRunResult(
            certificate: parseResult,
            artifact: artifact,
            diagnostics: diagnostics
        )
    }

    private func certificateArtifact(
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        solverResult: XcircuiteSymbolicPlannerSolverResult,
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> ArtifactReference? {
        let artifactID = request.certificateArtifactID
            ?? XcircuitePlanningArtifactStore.symbolicPlannerSolverCertificateArtifactID
        if let certificatePath = request.certificatePath {
            let certificateURL = try await workspaceStore.url(for: certificatePath)
            guard FileManager.default.fileExists(atPath: certificateURL.path(percentEncoded: false)) else {
                return nil
            }
            return try await artifactReferenceResolver.projectFileReference(
                path: certificatePath,
                artifactID: artifactID,
                field: "nativeCertificateArtifact",
                expectedFormat: .text,
                runID: request.runID,
                projectRoot: projectRoot
            )
        }
        if request.certificateArtifactID == nil {
            return try verifiedFoundationArtifactReference(
                solverResult.standardOutputArtifact,
                field: "nativeCertificateStandardOutputArtifact",
                expectedFormat: .text,
                projectRoot: projectRoot
            )
        }
        return try await artifactReferenceResolver.uniqueManifestArtifact(
            artifactID: artifactID,
            field: "nativeCertificateArtifact",
            expectedFormat: .text,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
    }

    private func appendNativeCertificateDiagnostics(
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        nativeCertificate: XcircuiteSymbolicPlannerSolverCertificateParseResult?,
        observedActionIDs: [String],
        goalCoverageStatus: String?,
        planCostEvaluation: XcircuiteSymbolicPlannerPlanCostEvaluation?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard let certificate = nativeCertificate?.certificate else {
            if request.requireNativeCertificate, !diagnostics.contains(where: { $0.code == "native-certificate-missing" }) {
                diagnostics.append(
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "native-certificate-missing",
                        message: "Native solver certificate is required by policy but no parsed certificate is available."
                    )
                )
            }
            return
        }

        appendCertificatePlanLengthDiagnostics(
            certificate: certificate,
            planCostEvaluation: planCostEvaluation,
            diagnostics: &diagnostics
        )
        appendCertificateCostDiagnostics(
            certificate: certificate,
            planCostEvaluation: planCostEvaluation,
            diagnostics: &diagnostics
        )
        appendCertificateActionDiagnostics(
            certificate: certificate,
            observedActionIDs: observedActionIDs,
            diagnostics: &diagnostics
        )
        appendCertificateGoalCoverageDiagnostics(
            certificate: certificate,
            goalCoverageStatus: goalCoverageStatus,
            diagnostics: &diagnostics
        )
    }

    private func appendCertificatePlanLengthDiagnostics(
        certificate: XcircuiteSymbolicPlannerSolverCertificate,
        planCostEvaluation: XcircuiteSymbolicPlannerPlanCostEvaluation?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard let certifiedPlanLength = certificate.planLength,
              let evaluatedPlanLength = planCostEvaluation?.planLength,
              certifiedPlanLength != evaluatedPlanLength,
              !diagnostics.contains(where: { $0.code == "native-certificate-plan-length-mismatch" }) else {
            return
        }
        diagnostics.append(
            XcircuiteSymbolicPlannerSolverDiagnostic(
                severity: "error",
                code: "native-certificate-plan-length-mismatch",
                message: "Native solver certificate plan length \(certifiedPlanLength) does not match imported candidate plan length \(evaluatedPlanLength)."
            )
        )
    }

    private func appendCertificateCostDiagnostics(
        certificate: XcircuiteSymbolicPlannerSolverCertificate,
        planCostEvaluation: XcircuiteSymbolicPlannerPlanCostEvaluation?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard let certifiedCost = certificate.planCost,
              let evaluatedCost = planCostEvaluation?.evaluatedCost,
              !approximatelyEqual(certifiedCost, evaluatedCost),
              !diagnostics.contains(where: { $0.code == "native-certificate-cost-mismatch" }) else {
            return
        }
        diagnostics.append(
            XcircuiteSymbolicPlannerSolverDiagnostic(
                severity: "error",
                code: "native-certificate-cost-mismatch",
                message: "Native solver certificate cost \(certifiedCost) does not match independently evaluated plan cost \(evaluatedCost)."
            )
        )
    }

    private func appendCertificateActionDiagnostics(
        certificate: XcircuiteSymbolicPlannerSolverCertificate,
        observedActionIDs: [String],
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard !certificate.observedActionIDs.isEmpty else {
            return
        }
        let observed = Set(observedActionIDs)
        let missing = certificate.observedActionIDs.filter { !observed.contains($0) }
        guard !missing.isEmpty,
              !diagnostics.contains(where: { $0.code == "native-certificate-action-mismatch" }) else {
            return
        }
        diagnostics.append(
            XcircuiteSymbolicPlannerSolverDiagnostic(
                severity: "error",
                code: "native-certificate-action-mismatch",
                message: "Native solver certificate references actions not present in imported candidate plan: \(missing.joined(separator: ","))."
            )
        )
    }

    private func appendCertificateGoalCoverageDiagnostics(
        certificate: XcircuiteSymbolicPlannerSolverCertificate,
        goalCoverageStatus: String?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard let certifiedGoalCoverageStatus = certificate.goalCoverageStatus,
              let goalCoverageStatus,
              certifiedGoalCoverageStatus != goalCoverageStatus,
              !diagnostics.contains(where: { $0.code == "native-certificate-goal-coverage-mismatch" }) else {
            return
        }
        diagnostics.append(
            XcircuiteSymbolicPlannerSolverDiagnostic(
                severity: "error",
                code: "native-certificate-goal-coverage-mismatch",
                message: "Native solver certificate goal coverage \(certifiedGoalCoverageStatus) does not match plan verification goal coverage \(goalCoverageStatus)."
            )
        )
    }

    private func proofValidation(
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        solverResult: XcircuiteSymbolicPlannerSolverResult,
        projectRoot: URL
    ) async throws -> ProofValidationRunResult {
        let shouldValidate = request.requireProofValidation
            || request.proofCheckerExecutablePath != nil
            || request.proofArtifactID != nil
            || request.proofPath != nil
        guard shouldValidate else {
            return ProofValidationRunResult(validation: nil, artifact: nil, diagnostics: [])
        }
        guard let proofCheckerExecutablePath = request.proofCheckerExecutablePath else {
            return ProofValidationRunResult(
                validation: nil,
                artifact: nil,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "proof-validation-not-configured",
                        message: "Proof validation requires a proof checker executable path."
                    ),
                ]
            )
        }
        guard request.proofCheckerTimeoutSeconds.isFinite,
              request.proofCheckerTimeoutSeconds > 0 else {
            throw XcircuiteSymbolicPlannerSolverError.invalidProofCheckerTimeout(request.proofCheckerTimeoutSeconds)
        }

        let manifest = try await loadRunManifest(runID: request.runID)
        guard let proofArtifact = try await proofArtifact(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        ) else {
            return ProofValidationRunResult(
                validation: nil,
                artifact: nil,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "proof-artifact-missing",
                        message: "Proof validation requires a solver proof artifact or project-relative proof path."
                    ),
                ]
            )
        }

        let domainArtifact = try verifiedFoundationArtifactReference(
            solverResult.domainArtifact,
            field: "proofValidationDomainArtifact",
            expectedFormat: .text,
            projectRoot: projectRoot
        )
        let problemArtifact = try verifiedFoundationArtifactReference(
            solverResult.problemArtifact,
            field: "proofValidationProblemArtifact",
            expectedFormat: .text,
            projectRoot: projectRoot
        )
        let pddlExportArtifact: ArtifactReference?
        if let reference = solverResult.pddlExportArtifact {
            pddlExportArtifact = try verifiedFoundationArtifactReference(
                reference,
                field: "proofValidationPDDLExportArtifact",
                expectedFormat: .json,
                projectRoot: projectRoot
            )
        } else {
            pddlExportArtifact = nil
        }
        let solverPlanArtifact: ArtifactReference?
        if let reference = solverResult.solverPlanArtifact {
            solverPlanArtifact = try verifiedFoundationArtifactReference(
                reference,
                field: "proofValidationSolverPlanArtifact",
                expectedFormat: .text,
                projectRoot: projectRoot
            )
        } else {
            solverPlanArtifact = nil
        }
        let proofURL = try await workspaceStore.url(for: proofArtifact.path)
        let domainURL = try await workspaceStore.url(for: domainArtifact.path)
        let problemURL = try await workspaceStore.url(for: problemArtifact.path)
        let pddlExportURL: URL?
        if let pddlExportArtifact {
            pddlExportURL = try await workspaceStore.url(for: pddlExportArtifact.path)
        } else {
            pddlExportURL = nil
        }
        let solverPlanURL: URL?
        if let solverPlanArtifact {
            solverPlanURL = try await workspaceStore.url(for: solverPlanArtifact.path)
        } else {
            solverPlanURL = nil
        }
        let workingDirectoryPath = request.proofCheckerWorkingDirectoryPath
            ?? defaultProofCheckerWorkingDirectoryPath(runID: request.runID)
        let workingDirectoryURL = try await workspaceStore.url(for: workingDirectoryPath)
        try await workspaceStore.ensureWorkspaceDirectory(at: workingDirectoryPath)

        let proofCheckerArguments = resolvedProofCheckerArguments(
            request.proofCheckerArguments.isEmpty ? ["{proof}"] : request.proofCheckerArguments,
            proofURL: proofURL,
            domainURL: domainURL,
            problemURL: problemURL,
            pddlExportURL: pddlExportURL,
            solverPlanURL: solverPlanURL
        )
        let process = Process()
        process.executableURL = URL(filePath: proofCheckerExecutablePath)
        process.arguments = proofCheckerArguments
        process.currentDirectoryURL = workingDirectoryURL

        let startedAt = Self.currentTimestamp()
        let outcome = await runProofChecker(process: process, timeoutSeconds: request.proofCheckerTimeoutSeconds)
        let finishedAt = Self.currentTimestamp()
        let status = proofValidationStatus(for: outcome)
        var validation = XcircuiteSymbolicPlannerProofValidation(
            status: status,
            runID: request.runID,
            toolID: request.toolID,
            proofArtifact: proofArtifact,
            domainArtifact: domainArtifact,
            problemArtifact: problemArtifact,
            pddlExportArtifact: pddlExportArtifact,
            solverPlanArtifact: solverPlanArtifact,
            proofCheckerExecutablePath: proofCheckerExecutablePath,
            proofCheckerArguments: proofCheckerArguments,
            proofCheckerTimeoutSeconds: request.proofCheckerTimeoutSeconds,
            workingDirectoryPath: workingDirectoryPath,
            exitCode: outcome.exitCode,
            didTimeout: outcome.didTimeout,
            didCancel: outcome.didCancel,
            startedAt: startedAt,
            finishedAt: finishedAt,
            diagnostics: outcome.diagnostics
        )
        let artifactSet = try await artifactStore.persistSymbolicPlannerProofValidation(
            validation,
            standardOutput: outcome.standardOutput,
            standardError: outcome.standardError,
            runID: request.runID,
            projectRoot: projectRoot
        )
        validation.standardOutputArtifact = artifactSet.standardOutputArtifact
        validation.standardErrorArtifact = artifactSet.standardErrorArtifact

        return ProofValidationRunResult(
            validation: validation,
            artifact: artifactSet.validationArtifact,
            diagnostics: []
        )
    }

    private func proofArtifact(
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> ArtifactReference? {
        let artifactID = request.proofArtifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID
        if let proofPath = request.proofPath {
            let proofURL = try await workspaceStore.url(for: proofPath)
            guard FileManager.default.fileExists(atPath: proofURL.path(percentEncoded: false)) else {
                return nil
            }
            let manifestMatches = manifest.artifacts.filter { $0.artifactID == artifactID }
            guard manifestMatches.count <= 1 else {
                throw XcircuiteSymbolicPlannerSolverError.duplicateArtifactReference(
                    runID: request.runID,
                    artifactID: artifactID,
                    count: manifestMatches.count
                )
            }
            if let manifestReference = manifestMatches.first {
                guard manifestReference.path == proofPath else {
                    throw XcircuiteSymbolicPlannerSolverError.artifactReferenceMismatch(
                        field: "proofArtifact",
                        artifactID: artifactID,
                        path: proofPath,
                        manifestPath: manifestReference.path
                    )
                }
                return try await artifactReferenceResolver.uniqueManifestArtifact(
                    artifactID: artifactID,
                    field: "proofArtifact",
                    expectedFormat: .text,
                    manifest: manifest,
                    runID: request.runID,
                    projectRoot: projectRoot
                )
            }
            let reference = try await artifactReferenceResolver.projectFileReference(
                path: proofPath,
                artifactID: artifactID,
                field: "proofArtifact",
                expectedFormat: .text,
                runID: request.runID,
                projectRoot: projectRoot
            )
            let retained = try await workspaceStore.persistArtifact(
                content: Data(contentsOf: proofURL, options: [.mappedIfSafe]),
                id: reference.id,
                locator: reference.locator,
                runID: request.runID,
                mode: .immutable
            )
            return retained
        }
        return try await artifactReferenceResolver.uniqueManifestArtifact(
            artifactID: artifactID,
            field: "proofArtifact",
            expectedFormat: .text,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
    }

    private func appendProofValidationDiagnostics(
        proofValidation: XcircuiteSymbolicPlannerProofValidation?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) {
        guard let proofValidation else {
            return
        }
        let existingCodes = Set(diagnostics.map(\.code))
        for proofDiagnostic in proofValidation.diagnostics {
            let diagnosticCode = "proof-validation-\(proofDiagnostic.code)"
            if existingCodes.contains(diagnosticCode) {
                continue
            }
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: proofDiagnostic.severity,
                    code: diagnosticCode,
                    message: proofDiagnostic.message
                )
            )
        }
    }

    private func resolvedProofCheckerArguments(
        _ arguments: [String],
        proofURL: URL,
        domainURL: URL,
        problemURL: URL,
        pddlExportURL: URL?,
        solverPlanURL: URL?
    ) -> [String] {
        arguments.map { argument in
            argument
                .replacingOccurrences(
                    of: "{proof}",
                    with: proofURL.path(percentEncoded: false)
                )
                .replacingOccurrences(
                    of: "{domain}",
                    with: domainURL.path(percentEncoded: false)
                )
                .replacingOccurrences(
                    of: "{problem}",
                    with: problemURL.path(percentEncoded: false)
                )
                .replacingOccurrences(
                    of: "{pddlExport}",
                    with: pddlExportURL?.path(percentEncoded: false) ?? ""
                )
                .replacingOccurrences(
                    of: "{solverPlan}",
                    with: solverPlanURL?.path(percentEncoded: false) ?? ""
                )
        }
    }

    private func runProofChecker(process: Process, timeoutSeconds: Double) async -> ProofProcessOutcome {
        do {
            let result = try await TimedProcessRunner(timeoutSeconds: timeoutSeconds).run(process: process)
            return ProofProcessOutcome(
                exitCode: result.exitCode,
                didTimeout: false,
                didCancel: false,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                diagnostics: result.exitCode == 0 ? [] : [
                    XcircuiteSymbolicPlannerProofValidationDiagnostic(
                        severity: "error",
                        code: "proof-checker-non-zero-exit",
                        message: "Symbolic planner proof checker exited with code \(result.exitCode)."
                    ),
                ]
            )
        } catch let error as TimedProcessError {
            return proofOutcome(for: error)
        } catch {
            return ProofProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: "",
                standardError: "",
                diagnostics: [
                    XcircuiteSymbolicPlannerProofValidationDiagnostic(
                        severity: "error",
                        code: "proof-checker-process-runner-error",
                        message: error.localizedDescription
                    ),
                ]
            )
        }
    }

    private func proofOutcome(for error: TimedProcessError) -> ProofProcessOutcome {
        switch error {
        case .invalidConfiguration(let message):
            return ProofProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: "",
                standardError: "",
                diagnostics: [
                    XcircuiteSymbolicPlannerProofValidationDiagnostic(
                        severity: "error",
                        code: "proof-checker-invalid-process-configuration",
                        message: message
                    ),
                ]
            )
        case .launchFailed(_, let message):
            return ProofProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: "",
                standardError: "",
                diagnostics: [
                    XcircuiteSymbolicPlannerProofValidationDiagnostic(
                        severity: "error",
                        code: "proof-checker-launch-failed",
                        message: message
                    ),
                ]
            )
        case .cancellationCheckFailed(_, let message, let standardOutput, let standardError):
            return ProofProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: standardOutput,
                standardError: standardError,
                diagnostics: [
                    XcircuiteSymbolicPlannerProofValidationDiagnostic(
                        severity: "error",
                        code: "proof-checker-cancellation-check-failed",
                        message: message
                    ),
                ]
            )
        case .cancelled(_, let standardOutput, let standardError):
            return ProofProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: true,
                standardOutput: standardOutput,
                standardError: standardError,
                diagnostics: [
                    XcircuiteSymbolicPlannerProofValidationDiagnostic(
                        severity: "error",
                        code: "proof-checker-cancelled",
                        message: "Symbolic planner proof checker process was cancelled."
                    ),
                ]
            )
        case .timedOut(_, let timeoutSeconds, let standardOutput, let standardError):
            return ProofProcessOutcome(
                exitCode: nil,
                didTimeout: true,
                didCancel: false,
                standardOutput: standardOutput,
                standardError: standardError,
                diagnostics: [
                    XcircuiteSymbolicPlannerProofValidationDiagnostic(
                        severity: "error",
                        code: "proof-checker-timed-out",
                        message: "Symbolic planner proof checker process timed out after \(timeoutSeconds) seconds."
                    ),
                ]
            )
        }
    }

    private func proofValidationStatus(for outcome: ProofProcessOutcome) -> String {
        if outcome.didTimeout {
            return "timed-out"
        }
        if outcome.didCancel {
            return "cancelled"
        }
        if outcome.exitCode == 0, !outcome.diagnostics.contains(where: { $0.severity == "error" }) {
            return "validated"
        }
        return "failed"
    }

    private func defaultProofCheckerWorkingDirectoryPath(runID: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/planning/symbolic-planner/proof-checker-work"
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_001
    }

    private func makeResult(
        status: String,
        request: XcircuiteSymbolicPlannerSolverValidationRequest,
        solverResult: XcircuiteSymbolicPlannerSolverResult,
        observedActionIDs: [String],
        goalCoverageStatus: String?,
        missingGoalAtoms: [String],
        planCostEvaluation: XcircuiteSymbolicPlannerPlanCostEvaluation?,
        planReplayValidation: XcircuiteSymbolicPlannerPlanReplayValidation?,
        nativeCertificate: XcircuiteSymbolicPlannerSolverCertificateParseResult?,
        proofValidation: XcircuiteSymbolicPlannerProofValidation?,
        planReplayValidationArtifact: ArtifactReference?,
        nativeCertificateArtifact: ArtifactReference?,
        proofValidationArtifact: ArtifactReference?,
        planVerificationArtifact: ArtifactReference?,
        validationArtifact: ArtifactReference?,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) -> XcircuiteSymbolicPlannerSolverValidationResult {
        let solverMetadata = solverResult.solverMetadata
        return XcircuiteSymbolicPlannerSolverValidationResult(
            status: status,
            runID: request.runID,
            toolID: request.toolID,
            policyID: request.policyID,
            expectedActionIDs: request.expectedActionIDs,
            observedActionIDs: observedActionIDs,
            requireGoalCoverage: request.requireGoalCoverage,
            requireOptimality: request.requireOptimality,
            maximumSolverCost: request.maximumSolverCost,
            requireNativeCertificate: request.requireNativeCertificate,
            requireProofValidation: request.requireProofValidation,
            goalCoverageStatus: goalCoverageStatus,
            missingGoalAtoms: missingGoalAtoms,
            nativeCertificate: nativeCertificate,
            solverMetadata: solverMetadata,
            planCostEvaluation: planCostEvaluation,
            planReplayValidation: planReplayValidation,
            proofValidation: proofValidation,
            solverResult: solverResult,
            planReplayValidationArtifact: planReplayValidationArtifact,
            proofValidationArtifact: proofValidationArtifact,
            nativeCertificateArtifact: nativeCertificateArtifact,
            planVerificationArtifact: planVerificationArtifact,
            validationArtifact: validationArtifact,
            diagnostics: diagnostics
        )
    }

    private func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        try await artifactReferenceResolver.runManifest(runID: runID)
    }

    private func verifiedFoundationArtifactReference(
        _ reference: ArtifactReference,
        field: String,
        expectedFormat: ArtifactFormat,
        projectRoot: URL
    ) throws -> ArtifactReference {
        guard reference.locator.kind == .other else {
            throw XcircuiteSymbolicPlannerSolverError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "expected artifact kind \(ArtifactKind.other.rawValue), got \(reference.locator.kind.rawValue)"
            )
        }
        guard reference.locator.format == expectedFormat else {
            throw XcircuiteSymbolicPlannerSolverError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "expected format \(expectedFormat.rawValue), got \(reference.locator.format.rawValue)"
            )
        }
        let integrity = LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            let reason = integrity.issues.map { issue in
                issue.detail ?? issue.location ?? issue.code.rawValue
            }.joined(separator: "; ")
            throw XcircuiteSymbolicPlannerSolverError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "artifact integrity verification failed: \(reason)"
            )
        }
        return reference
    }

    private static func currentTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private struct ProofValidationRunResult: Sendable, Hashable {
        var validation: XcircuiteSymbolicPlannerProofValidation?
        var artifact: ArtifactReference?
        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    }

    private struct NativeCertificateRunResult: Sendable, Hashable {
        var certificate: XcircuiteSymbolicPlannerSolverCertificateParseResult?
        var artifact: ArtifactReference?
        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    }

    private struct ProofProcessOutcome: Sendable, Hashable {
        var exitCode: Int32?
        var didTimeout: Bool
        var didCancel: Bool
        var standardOutput: String
        var standardError: String
        var diagnostics: [XcircuiteSymbolicPlannerProofValidationDiagnostic]
    }
}
