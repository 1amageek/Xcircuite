import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteNumericRepairLoopRunner: Sendable {
    private struct PolicySelection: Sendable, Hashable {
        var candidateStrategy: String
        var trace: XcircuiteNumericRepairLoopPolicyTrace
    }

    private let packageStore: XcircuitePackageStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let candidateGenerator: XcircuiteParameterCandidateGenerator
    private let planSynthesizer: XcircuiteParameterCandidatePlanSynthesizer
    private let planExecutor: XcircuiteCandidatePlanExecutor
    private let planVerifier: XcircuiteCandidatePlanVerifier
    private let improvementArtifactGenerator: XcircuiteImprovementPlanningArtifactGenerator
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        candidateGenerator: XcircuiteParameterCandidateGenerator = XcircuiteParameterCandidateGenerator(),
        planSynthesizer: XcircuiteParameterCandidatePlanSynthesizer = XcircuiteParameterCandidatePlanSynthesizer(),
        planExecutor: XcircuiteCandidatePlanExecutor = XcircuiteCandidatePlanExecutor(),
        planVerifier: XcircuiteCandidatePlanVerifier = XcircuiteCandidatePlanVerifier(),
        improvementArtifactGenerator: XcircuiteImprovementPlanningArtifactGenerator = XcircuiteImprovementPlanningArtifactGenerator(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.candidateGenerator = candidateGenerator
        self.planSynthesizer = planSynthesizer
        self.planExecutor = planExecutor
        self.planVerifier = planVerifier
        self.improvementArtifactGenerator = improvementArtifactGenerator
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func runNumericRepairLoop(
        request: XcircuiteNumericRepairLoopRequest,
        projectRoot: URL
    ) async throws -> XcircuiteNumericRepairLoopResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        guard request.maxCandidates > 0 else {
            throw XcircuiteNumericRepairLoopError.invalidMaxCandidates(request.maxCandidates)
        }
        guard request.maxIterations > 0 else {
            throw XcircuiteNumericRepairLoopError.invalidMaxIterations(request.maxIterations)
        }
        let calibrationPolicy = try normalizedCalibrationPolicy(request.calibrationPolicy)

        var iterations: [XcircuiteNumericRepairLoopIteration] = []
        var problemID: String?

        for iterationIndex in 1...request.maxIterations {
            let policySelection = try selectPolicy(
                iterationIndex: iterationIndex,
                calibrationPolicy: calibrationPolicy,
                request: request,
                problemID: problemID,
                iterations: iterations,
                projectRoot: projectRoot
            )
            let candidateStrategy = policySelection.candidateStrategy
            let generation = try candidateGenerator.generateParameterCandidates(
                request: XcircuiteParameterCandidateGenerationRequest(
                    runID: request.runID,
                    problemArtifactID: request.problemArtifactID,
                    problemPath: request.problemPath,
                    metricThresholdProfileArtifactID: policySelection.trace.metricThresholdProfileArtifact.map { $0.id.rawValue },
                    metricThresholdProfilePath: policySelection.trace.metricThresholdProfileArtifact.map { $0.locator.location.value },
                    costCalibrationArtifactID: policySelection.trace.costCalibrationArtifact.map { $0.id.rawValue },
                    costCalibrationPath: policySelection.trace.costCalibrationArtifact.map { $0.locator.location.value },
                    paretoCandidatesArtifactID: policySelection.trace.paretoCandidatesArtifact.map { $0.id.rawValue },
                    paretoCandidatesPath: policySelection.trace.paretoCandidatesArtifact.map { $0.locator.location.value },
                    strategy: candidateStrategy,
                    maxCandidates: request.maxCandidates
                ),
                projectRoot: projectRoot
            )
            problemID = generation.problemID

            guard generation.status == "generated",
                  generation.parameterCandidatesArtifact != nil else {
                let archived = try archiveIterationArtifacts(
                    iterationIndex: iterationIndex,
                    runID: request.runID,
                    refs: [
                        ("parameter-candidates", generation.parameterCandidatesArtifact),
                        ("search-trace", generation.searchTraceArtifact),
                    ],
                    projectRoot: projectRoot
                )
                iterations.append(XcircuiteNumericRepairLoopIteration(
                    iterationIndex: iterationIndex,
                    status: "blocked",
                    candidateGenerationStrategy: candidateStrategy,
                    synthesisStrategy: request.synthesisStrategy,
                    verificationMode: request.verificationMode,
                    candidateGenerationStatus: generation.status,
                    policyTrace: policySelection.trace,
                    parameterCandidatesArtifact: generation.parameterCandidatesArtifact,
                    searchTraceArtifact: generation.searchTraceArtifact,
                    archivedArtifactRefs: archived,
                    diagnostics: loopDiagnostics(from: generation.diagnostics, iterationIndex: iterationIndex),
                    nextActions: ["inspect-parameter-candidate-search-trace"]
                ))
                break
            }

            let synthesis: XcircuiteParameterCandidatePlanSynthesisResult
            do {
                synthesis = try planSynthesizer.synthesizeCandidatePlan(
                    request: XcircuiteParameterCandidatePlanSynthesisRequest(
                        runID: request.runID,
                        problemArtifactID: request.problemArtifactID,
                        problemPath: request.problemPath,
                        parameterCandidatesArtifactID: generation.parameterCandidatesArtifact.map { $0.id.rawValue },
                        parameterCandidatesPath: generation.parameterCandidatesArtifact.map { $0.locator.location.value },
                        strategy: request.synthesisStrategy
                    ),
                    projectRoot: projectRoot
                )
            } catch let error as XcircuiteParameterCandidatePlanSynthesisError {
                let archived = try archiveIterationArtifacts(
                    iterationIndex: iterationIndex,
                    runID: request.runID,
                    refs: [
                        ("parameter-candidates", generation.parameterCandidatesArtifact),
                        ("search-trace", generation.searchTraceArtifact),
                    ],
                    projectRoot: projectRoot
                )
                iterations.append(XcircuiteNumericRepairLoopIteration(
                    iterationIndex: iterationIndex,
                    status: synthesisBlockedStatus(for: error),
                    candidateGenerationStrategy: candidateStrategy,
                    synthesisStrategy: request.synthesisStrategy,
                    verificationMode: request.verificationMode,
                    candidateGenerationStatus: generation.status,
                    policyTrace: policySelection.trace,
                    parameterCandidatesArtifact: generation.parameterCandidatesArtifact,
                    searchTraceArtifact: generation.searchTraceArtifact,
                    archivedArtifactRefs: archived,
                    diagnostics: [
                        XcircuiteNumericRepairLoopDiagnostic(
                            severity: "warning",
                            code: "candidate-plan-synthesis-blocked",
                            message: error.localizedDescription,
                            iterationIndex: iterationIndex
                        ),
                    ],
                    nextActions: ["inspect-parameter-candidate-selection-trace"]
                ))
                break
            }

            let execution = try await planExecutor.executeCandidatePlan(
                request: XcircuiteCandidatePlanExecutionRequest(
                    runID: request.runID,
                    candidatePlanArtifactID: synthesis.candidatePlanArtifact.id.rawValue,
                    candidatePlanPath: synthesis.candidatePlanArtifact.locator.location.value,
                    actor: request.actor
                ),
                projectRoot: projectRoot
            )
            let verification = try await planVerifier.verifyCandidatePlan(
                request: XcircuiteCandidatePlanVerificationRequest(
                    runID: request.runID,
                    candidatePlanArtifactID: synthesis.candidatePlanArtifact.id.rawValue,
                    candidatePlanPath: synthesis.candidatePlanArtifact.locator.location.value,
                    verificationMode: request.verificationMode
                ),
                projectRoot: projectRoot
            )
            let verificationDiagnostics = try planVerificationDiagnostics(
                from: verification.planVerificationArtifact,
                projectRoot: projectRoot,
                iterationIndex: iterationIndex
            )
            let archived = try archiveIterationArtifacts(
                iterationIndex: iterationIndex,
                runID: request.runID,
                refs: [
                    ("parameter-candidates", generation.parameterCandidatesArtifact),
                    ("search-trace", generation.searchTraceArtifact),
                    ("selection-trace", synthesis.selectionTraceArtifact),
                    ("candidate-plan", synthesis.candidatePlanArtifact),
                    ("plan-execution", execution.planExecutionArtifact),
                    ("design-diff", execution.designDiffArtifact),
                    ("plan-verification", verification.planVerificationArtifact),
                ],
                projectRoot: projectRoot
            )
            let iterationStatus = verification.accepted ? "accepted" : verification.status
            iterations.append(XcircuiteNumericRepairLoopIteration(
                iterationIndex: iterationIndex,
                status: iterationStatus,
                candidateGenerationStrategy: candidateStrategy,
                synthesisStrategy: request.synthesisStrategy,
                verificationMode: request.verificationMode,
                candidateGenerationStatus: generation.status,
                selectedCandidateID: synthesis.selectedCandidateID,
                selectedCandidateRank: synthesis.selectedCandidateRank,
                skippedRejectedCandidateIDs: synthesis.skippedRejectedCandidateIDs ?? [],
                planID: synthesis.planID,
                executionStatus: execution.status,
                verificationStatus: verification.status,
                accepted: verification.accepted,
                policyTrace: policySelection.trace,
                parameterCandidatesArtifact: generation.parameterCandidatesArtifact,
                searchTraceArtifact: generation.searchTraceArtifact,
                selectionTraceArtifact: synthesis.selectionTraceArtifact,
                candidatePlanArtifact: synthesis.candidatePlanArtifact,
                planExecutionArtifact: execution.planExecutionArtifact,
                designDiffArtifact: execution.designDiffArtifact,
                producedArtifacts: execution.producedArtifacts,
                planVerificationArtifact: verification.planVerificationArtifact,
                rejectedPlansArtifact: verification.rejectedPlansArtifact,
                archivedArtifactRefs: archived,
                diagnostics: verificationDiagnostics,
                nextActions: verification.nextActions
            ))
            if verification.accepted {
                break
            }
        }

        let result = makeResult(
            request: request,
            problemID: problemID,
            iterations: iterations
        )
        try validateResult(result, request: request)
        try artifactStore.persistNumericRepairLoop(result, runID: request.runID, projectRoot: projectRoot)
        return result
    }

    private func makeResult(
        request: XcircuiteNumericRepairLoopRequest,
        problemID: String?,
        iterations: [XcircuiteNumericRepairLoopIteration]
    ) -> XcircuiteNumericRepairLoopResult {
        let acceptedIteration = iterations.first(where: \.accepted)
        let limitReached = acceptedIteration == nil
            && iterations.count >= request.maxIterations
            && iterations.last?.status != "blocked"
            && iterations.last?.status != "exhausted"
        let status: String
        if acceptedIteration != nil {
            status = "accepted"
        } else if limitReached {
            status = "iteration-limit-reached"
        } else {
            status = iterations.last?.status ?? "blocked"
        }
        var nextActions = acceptedIteration == nil ? (iterations.last?.nextActions ?? []) : []
        if limitReached {
            nextActions.append("increase-max-iterations")
        }
        if acceptedIteration == nil {
            nextActions.append("inspect-numeric-repair-loop")
        }
        let loopArtifactPath = ".xcircuite/runs/\(request.runID)/\(XcircuitePlanningArtifactStore.numericRepairLoopRelativePath)"
        return XcircuiteNumericRepairLoopResult(
            status: status,
            runID: request.runID,
            problemID: problemID,
            loopArtifactPath: loopArtifactPath,
            maxIterations: request.maxIterations,
            iterationCount: iterations.count,
            accepted: acceptedIteration != nil,
            acceptedIterationIndex: acceptedIteration?.iterationIndex,
            selectedCandidateID: acceptedIteration?.selectedCandidateID ?? iterations.last?.selectedCandidateID,
            finalPlanID: acceptedIteration?.planID ?? iterations.last?.planID,
            calibrationPolicy: storedCalibrationPolicy(request.calibrationPolicy),
            policyTraces: iterations.compactMap(\.policyTrace),
            iterations: iterations,
            diagnostics: iterations.flatMap(\.diagnostics),
            nextActions: unique(nextActions)
        )
    }

    private func normalizedCalibrationPolicy(_ value: String?) throws -> String {
        let policy = storedCalibrationPolicy(value)
        switch policy {
        case "disabled":
            return "disabled"
        case "cp7-feedback":
            return "cp7-feedback"
        default:
            throw XcircuiteNumericRepairLoopError.invalidCalibrationPolicy(policy)
        }
    }

    private func storedCalibrationPolicy(_ value: String?) -> String {
        let policy = (value ?? "disabled").trimmingCharacters(in: .whitespacesAndNewlines)
        return policy.isEmpty ? "disabled" : policy
    }

    private func selectPolicy(
        iterationIndex: Int,
        calibrationPolicy: String,
        request: XcircuiteNumericRepairLoopRequest,
        problemID: String?,
        iterations: [XcircuiteNumericRepairLoopIteration],
        projectRoot: URL
    ) throws -> PolicySelection {
        let baseStrategy = iterations.isEmpty
            ? request.initialCandidateStrategy
            : request.feedbackCandidateStrategy

        guard !iterations.isEmpty else {
            return PolicySelection(
                candidateStrategy: baseStrategy,
                trace: XcircuiteNumericRepairLoopPolicyTrace(
                    iterationIndex: iterationIndex,
                    calibrationPolicy: calibrationPolicy,
                    baseCandidateStrategy: baseStrategy,
                    selectedCandidateStrategy: baseStrategy,
                    usesCalibrationArtifacts: false,
                    reasonCodes: ["initial-iteration"]
                )
            )
        }

        guard calibrationPolicy == "cp7-feedback" else {
            return PolicySelection(
                candidateStrategy: baseStrategy,
                trace: XcircuiteNumericRepairLoopPolicyTrace(
                    iterationIndex: iterationIndex,
                    calibrationPolicy: calibrationPolicy,
                    baseCandidateStrategy: baseStrategy,
                    selectedCandidateStrategy: baseStrategy,
                    usesCalibrationArtifacts: false,
                    sourceIterationIndexes: iterations.map(\.iterationIndex),
                    reasonCodes: ["feedback-strategy-without-cp7-calibration"]
                )
            )
        }

        let partialResult = makeResult(
            request: request,
            problemID: problemID,
            iterations: iterations
        )
        try artifactStore.persistNumericRepairLoop(
            partialResult,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let calibration = try improvementArtifactGenerator.generateImprovementPlanningArtifacts(
            request: XcircuiteImprovementPlanningArtifactGenerationRequest(
                runID: request.runID,
                problemArtifactID: request.problemArtifactID,
                problemPath: request.problemPath,
                numericRepairLoopArtifactID: XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
            ),
            projectRoot: projectRoot
        )
        let calibratedStrategy = "calibrated-feedback-aware-bounded-refinement"
        return PolicySelection(
            candidateStrategy: calibratedStrategy,
            trace: XcircuiteNumericRepairLoopPolicyTrace(
                iterationIndex: iterationIndex,
                calibrationPolicy: calibrationPolicy,
                baseCandidateStrategy: baseStrategy,
                selectedCandidateStrategy: calibratedStrategy,
                usesCalibrationArtifacts: true,
                sourceIterationIndexes: iterations.map(\.iterationIndex),
                metricThresholdProfileArtifact: calibration.thresholdProfileArtifact,
                costCalibrationArtifact: calibration.costCalibrationArtifact,
                paretoCandidatesArtifact: calibration.paretoCandidatesArtifact,
                improvementLoopArtifact: calibration.improvementLoopArtifact,
                reasonCodes: [
                    "previous-iterations-available",
                    "cp7-artifacts-generated",
                    "calibrated-feedback-aware-strategy-selected",
                ],
                diagnostics: calibration.diagnostics
            )
        )
    }

    private func synthesisBlockedStatus(
        for error: XcircuiteParameterCandidatePlanSynthesisError
    ) -> String {
        switch error {
        case .noEligibleCandidateAfterFeedback:
            return "exhausted"
        case .candidateNotFound:
            return "exhausted"
        default:
            return "blocked"
        }
    }

    private func planVerificationDiagnostics(
        from reference: ArtifactReference,
        projectRoot: URL,
        iterationIndex: Int
    ) throws -> [XcircuiteNumericRepairLoopDiagnostic] {
        let verification = try packageStore.readJSON(
            XcircuitePlanVerification.self,
            from: try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
        )
        return verification.diagnostics.map {
            XcircuiteNumericRepairLoopDiagnostic(
                severity: $0.severity,
                code: $0.code,
                message: $0.message,
                iterationIndex: iterationIndex
            )
        }
    }

    private func loopDiagnostics(
        from diagnostics: [XcircuiteParameterCandidateDiagnostic],
        iterationIndex: Int
    ) -> [XcircuiteNumericRepairLoopDiagnostic] {
        diagnostics.map {
            XcircuiteNumericRepairLoopDiagnostic(
                severity: $0.severity,
                code: $0.code,
                message: $0.message,
                iterationIndex: iterationIndex
            )
        }
    }

    private func archiveIterationArtifacts(
        iterationIndex: Int,
        runID: String,
        refs: [(String, ArtifactReference?)],
        projectRoot: URL
    ) throws -> [ArtifactReference] {
        var archived: [ArtifactReference] = []
        for (role, maybeRef) in refs {
            guard let sourceRef = maybeRef else {
                continue
            }
            let sourceIntegrity = LocalArtifactVerifier().verify(sourceRef, relativeTo: projectRoot)
            guard sourceIntegrity.isVerified else {
                throw XcircuiteNumericRepairLoopError.sourceArtifactIntegrityFailed(
                    artifactID: sourceRef.id.rawValue,
                    path: sourceRef.locator.location.value,
                    status: .unreadableArtifact,
                    message: sourceIntegrity.issues.map { String(describing: $0) }.joined(separator: "; ")
                )
            }
            let sourceURL = try sourceRef.locator.location.resolvedFileURL(relativeTo: projectRoot)
            let archiveRelativePath = ".xcircuite/runs/\(runID)/planning/numeric-repair-loop/iterations/\(iterationIndex)/\(role)-\(sourceURL.lastPathComponent)"
            let archiveURL = try packageStore.url(
                forProjectRelativePath: archiveRelativePath,
                inProjectAt: projectRoot
            )
            try packageStore.ensureDirectory(at: archiveURL.deletingLastPathComponent())
            if FileManager.default.fileExists(atPath: archiveURL.path(percentEncoded: false)) {
                throw XcircuiteNumericRepairLoopError.archiveArtifactAlreadyExists(path: archiveRelativePath)
            }
            let temporaryURL = archiveURL
                .deletingLastPathComponent()
                .appending(path: ".\(archiveURL.lastPathComponent).\(UUID().uuidString).tmp")
            do {
                try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
                try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
            } catch {
                try removeTemporaryArchiveFile(temporaryURL)
                throw error
            }
            let archivedLegacyRef = try packageStore.fileReference(
                forProjectRelativePath: archiveRelativePath,
                artifactID: "planning-numeric-repair-loop-iteration-\(iterationIndex)-\(role)",
                kind: legacyFileKind(for: sourceRef.locator.kind),
                format: legacyFileFormat(for: sourceRef.locator.format),
                inProjectAt: projectRoot,
                producedByRunID: runID
            )
            try packageStore.upsertRunArtifact(archivedLegacyRef, runID: runID, inProjectAt: projectRoot)
            archived.append(try requireFoundationArtifactReference(
                archivedLegacyRef,
                field: "numeric-repair-loop-iteration-\(iterationIndex)-\(role)"
            ))
        }
        return archived
    }

    private func legacyFileKind(for kind: ArtifactKind) -> XcircuiteFileKind {
        switch kind.rawValue {
        case "parasitics":
            return .parasitic
        case "power-intent":
            return .powerIntent
        case "timing.library":
            return .timingLibrary
        default:
            return XcircuiteFileKind(rawValue: kind.rawValue) ?? .other
        }
    }

    private func legacyFileFormat(for format: ArtifactFormat) -> XcircuiteFileFormat {
        switch format.rawValue {
        case "system-verilog":
            return .systemVerilog
        default:
            return XcircuiteFileFormat(rawValue: format.rawValue.uppercased()) ?? .unknown
        }
    }

    private func removeTemporaryArchiveFile(_ url: URL) throws {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw XcircuiteNumericRepairLoopError.archiveTemporaryCleanupFailed(
                path: path,
                message: error.localizedDescription
            )
        }
    }

    private func validateResult(
        _ result: XcircuiteNumericRepairLoopResult,
        request: XcircuiteNumericRepairLoopRequest
    ) throws {
        try requireInvariant(
            field: "runID",
            expected: request.runID,
            actual: result.runID
        )
        try requireInvariant(
            field: "maxIterations",
            expected: "\(request.maxIterations)",
            actual: "\(result.maxIterations)"
        )
        try requireInvariant(
            field: "iterationCount",
            expected: "\(result.iterations.count)",
            actual: "\(result.iterationCount)"
        )
        try requireInvariant(
            field: "loopArtifactPath",
            expected: ".xcircuite/runs/\(request.runID)/\(XcircuitePlanningArtifactStore.numericRepairLoopRelativePath)",
            actual: result.loopArtifactPath
        )

        var seenIterationIndexes: Set<Int> = []
        for (offset, iteration) in result.iterations.enumerated() {
            let expectedIndex = offset + 1
            guard seenIterationIndexes.insert(iteration.iterationIndex).inserted else {
                throw XcircuiteNumericRepairLoopError.duplicateIterationIndex(iteration.iterationIndex)
            }
            guard iteration.iterationIndex == expectedIndex else {
                throw XcircuiteNumericRepairLoopError.nonSequentialIterationIndex(
                    expected: expectedIndex,
                    actual: iteration.iterationIndex
                )
            }
            if let policyTrace = iteration.policyTrace {
                try requireInvariant(
                    field: "iteration[\(iteration.iterationIndex)].policyTrace.iterationIndex",
                    expected: "\(iteration.iterationIndex)",
                    actual: "\(policyTrace.iterationIndex)"
                )
            }
            for diagnostic in iteration.diagnostics {
                try requireInvariant(
                    field: "iteration[\(iteration.iterationIndex)].diagnostic.iterationIndex",
                    expected: "\(iteration.iterationIndex)",
                    actual: diagnostic.iterationIndex.map { "\($0)" }
                )
            }
        }

        let acceptedIteration = result.iterations.first(where: \.accepted)
        try requireInvariant(
            field: "accepted",
            expected: "\(acceptedIteration != nil)",
            actual: "\(result.accepted)"
        )
        try requireInvariant(
            field: "acceptedIterationIndex",
            expected: acceptedIteration.map { "\($0.iterationIndex)" },
            actual: result.acceptedIterationIndex.map { "\($0)" }
        )
        try requireInvariant(
            field: "selectedCandidateID",
            expected: acceptedIteration?.selectedCandidateID ?? result.iterations.last?.selectedCandidateID,
            actual: result.selectedCandidateID
        )
        try requireInvariant(
            field: "finalPlanID",
            expected: acceptedIteration?.planID ?? result.iterations.last?.planID,
            actual: result.finalPlanID
        )

        if let policyTraces = result.policyTraces {
            try requireInvariant(
                field: "policyTraces.count",
                expected: "\(result.iterations.compactMap(\.policyTrace).count)",
                actual: "\(policyTraces.count)"
            )
        }
    }

    private func requireInvariant(
        field: String,
        expected: String?,
        actual: String?
    ) throws {
        guard expected == actual else {
            throw XcircuiteNumericRepairLoopError.resultInvariantViolation(
                field: field,
                expected: expected ?? "nil",
                actual: actual ?? "nil"
            )
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
