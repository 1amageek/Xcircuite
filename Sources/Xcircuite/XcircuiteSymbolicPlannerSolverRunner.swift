import Foundation
import DesignFlowKernel
import SignoffToolSupport
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverRunner: XcircuiteSymbolicPlannerSolving {
    private let packageStore: XcircuitePackageStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let artifactReferenceResolver: XcircuiteSymbolicPlannerArtifactReferenceResolver

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.artifactReferenceResolver = XcircuiteSymbolicPlannerArtifactReferenceResolver(
            packageStore: packageStore,
            fileReferenceVerifier: fileReferenceVerifier
        )
    }

    public func solve(
        request: XcircuiteSymbolicPlannerSolverRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerSolverResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        guard request.timeoutSeconds.isFinite, request.timeoutSeconds > 0 else {
            throw XcircuiteSymbolicPlannerSolverError.invalidTimeout(request.timeoutSeconds)
        }

        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let domainArtifact = try artifactReference(
            explicitPath: request.domainPath,
            artifactID: request.domainArtifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerPDDLDomainArtifactID,
            missingReferenceError: .missingDomainReference,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            format: .text
        )
        let problemArtifact = try artifactReference(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerPDDLProblemArtifactID,
            missingReferenceError: .missingProblemReference,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            format: .text
        )
        let pddlExportArtifact = try optionalPDDLExportArtifact(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        )
        let domainURL = try packageStore.url(forProjectRelativePath: domainArtifact.path, inProjectAt: projectRoot)
        let problemURL = try packageStore.url(forProjectRelativePath: problemArtifact.path, inProjectAt: projectRoot)
        let pddlExportURL = try pddlExportArtifact.map { artifact in
            try packageStore.url(forProjectRelativePath: artifact.path, inProjectAt: projectRoot)
        }
        let workingDirectoryPath = request.workingDirectoryPath ?? defaultSolverWorkingDirectoryPath(runID: request.runID)
        let workingDirectoryURL = try packageStore.url(
            forProjectRelativePath: workingDirectoryPath,
            inProjectAt: projectRoot
        )
        try packageStore.ensureDirectory(at: workingDirectoryURL)

        let solverPlanOutputPath = solverPlanOutputPath(for: request)
        let solverPlanOutputURL = try solverPlanOutputPath.map {
            try packageStore.url(forProjectRelativePath: $0, inProjectAt: projectRoot)
        }
        if let solverPlanOutputURL, let solverPlanOutputPath {
            try validateSolverPlanOutput(
                path: solverPlanOutputPath,
                outputURL: solverPlanOutputURL,
                workingDirectoryPath: workingDirectoryPath,
                workingDirectoryURL: workingDirectoryURL,
                protectedArtifacts: protectedSolverInputArtifacts(
                    domainArtifact: domainArtifact,
                    domainURL: domainURL,
                    problemArtifact: problemArtifact,
                    problemURL: problemURL,
                    pddlExportArtifact: pddlExportArtifact,
                    pddlExportURL: pddlExportURL
                )
            )
            try packageStore.ensureDirectory(at: solverPlanOutputURL.deletingLastPathComponent())
        }
        let arguments = resolvedArguments(
            request.arguments,
            domainURL: domainURL,
            problemURL: problemURL,
            solverPlanOutputURL: solverPlanOutputURL
        )

        let process = Process()
        process.executableURL = URL(filePath: request.executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL

        let startedAt = Self.currentTimestamp()
        let processOutcome = await run(
            process: process,
            timeoutSeconds: request.timeoutSeconds,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let finishedAt = Self.currentTimestamp()
        var diagnostics = processOutcome.diagnostics
        var status = status(for: processOutcome)

        let solverPlan = try solverPlanText(
            standardOutput: processOutcome.standardOutput,
            solverPlanOutputURL: solverPlanOutputURL,
            diagnostics: &diagnostics
        )
        let solverPlanSource = solverPlan?.source
        let solverMetadata = XcircuiteSymbolicPlannerSolverMetadataParser().parse(
            standardOutput: processOutcome.standardOutput,
            standardError: processOutcome.standardError,
            solverPlanText: solverPlan?.text
        )
        var solverPlanArtifact: XcircuiteFileReference?
        var importResult: XcircuiteSymbolicPlannerPlanImportResult?
        var planReplayValidation: XcircuiteSymbolicPlannerPlanReplayValidation?
        var planReplayValidationArtifact: XcircuiteFileReference?

        if processOutcome.exitCode == 0,
           !processOutcome.didTimeout,
           !processOutcome.didCancel,
           let solverPlanText = solverPlan?.text {
            if request.importCandidatePlan {
                if pddlExportArtifact == nil {
                    diagnostics.append(
                        XcircuiteSymbolicPlannerSolverDiagnostic(
                            severity: "error",
                            code: "missing-pddl-export-for-import",
                            message: "Solver produced a plan, but no PDDL export mapping artifact was available for typed import."
                        )
                    )
                    status = "solved-without-import"
                } else {
                    let imported = try XcircuiteSymbolicPlannerPlanImporter(
                        packageStore: packageStore,
                        artifactStore: artifactStore
                    ).importSolverPlan(
                        request: XcircuiteSymbolicPlannerPlanImportRequest(
                            runID: request.runID,
                            pddlExportArtifactID: pddlExportArtifact?.artifactID,
                            pddlExportPath: pddlExportArtifact?.path,
                            solverPlanText: solverPlanText
                        ),
                        projectRoot: projectRoot
                    )
                    importResult = imported
                    solverPlanArtifact = imported.solverPlanArtifact
                    if let pddlExportArtifact {
                        let replay = try replayValidation(
                            importResult: imported,
                            pddlExportArtifact: pddlExportArtifact,
                            projectRoot: projectRoot
                        )
                        planReplayValidation = replay
                        planReplayValidationArtifact = try artifactStore.persistSymbolicPlannerPlanReplayValidation(
                            replay,
                            runID: request.runID,
                            projectRoot: projectRoot
                        )
                        diagnostics.append(contentsOf: replayDiagnostics(from: replay))
                    }
                    if imported.status == "imported" {
                        status = planReplayValidation?.status == "failed"
                            ? "solved-with-replay-diagnostics"
                            : "solved"
                    } else {
                        status = "solved-with-import-diagnostics"
                    }
                }
            } else {
                solverPlanArtifact = try artifactStore.persistSymbolicPlannerSolverPlan(
                    solverPlanText,
                    runID: request.runID,
                    projectRoot: projectRoot
                )
                status = "solved-without-import"
            }
        } else if solverPlan?.text == nil {
            if processOutcome.exitCode == 0, !processOutcome.didTimeout, !processOutcome.didCancel {
                status = "solver-plan-missing"
            } else if status == "solver-failed" {
                diagnostics.append(
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "solver-failed-without-plan",
                        message: "Symbolic planner process failed and did not produce a solver plan."
                    )
                )
            }
        }

        let report = XcircuiteSymbolicPlannerSolverExecutionReport(
            status: status,
            runID: request.runID,
            executablePath: request.executablePath,
            arguments: arguments,
            timeoutSeconds: request.timeoutSeconds,
            workingDirectoryPath: workingDirectoryPath,
            domainArtifact: domainArtifact,
            problemArtifact: problemArtifact,
            pddlExportArtifact: pddlExportArtifact,
            planReplayValidationArtifact: planReplayValidationArtifact,
            planReplayValidationStatus: planReplayValidation?.status,
            solverPlanOutputPath: solverPlanOutputPath,
            solverPlanSource: solverPlanSource,
            solverMetadata: solverMetadata,
            exitCode: processOutcome.exitCode,
            didTimeout: processOutcome.didTimeout,
            didCancel: processOutcome.didCancel,
            startedAt: startedAt,
            finishedAt: finishedAt,
            diagnostics: diagnostics
        )
        let solverArtifacts = try artifactStore.persistSymbolicPlannerSolverExecution(
            report: report,
            standardOutput: processOutcome.standardOutput,
            standardError: processOutcome.standardError,
            runID: request.runID,
            projectRoot: projectRoot
        )

        return XcircuiteSymbolicPlannerSolverResult(
            status: status,
            runID: request.runID,
            exitCode: processOutcome.exitCode,
            didTimeout: processOutcome.didTimeout,
            didCancel: processOutcome.didCancel,
            domainArtifact: domainArtifact,
            problemArtifact: problemArtifact,
            pddlExportArtifact: pddlExportArtifact,
            runArtifact: solverArtifacts.runArtifact,
            standardOutputArtifact: solverArtifacts.standardOutputArtifact,
            standardErrorArtifact: solverArtifacts.standardErrorArtifact,
            solverPlanArtifact: solverPlanArtifact,
            planReplayValidationArtifact: planReplayValidationArtifact,
            solverMetadata: solverMetadata,
            importResult: importResult,
            planReplayValidation: planReplayValidation,
            diagnostics: diagnostics
        )
    }

    private func replayValidation(
        importResult: XcircuiteSymbolicPlannerPlanImportResult,
        pddlExportArtifact: XcircuiteFileReference,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerPlanReplayValidation {
        let pddlExport = try packageStore.readJSON(
            XcircuiteSymbolicPlannerPDDLExport.self,
            from: packageStore.url(
                forProjectRelativePath: pddlExportArtifact.path,
                inProjectAt: projectRoot
            )
        )
        return XcircuiteSymbolicPlannerPlanReplayValidator().validate(
            candidatePlan: importResult.candidatePlan,
            pddlExport: pddlExport
        )
    }

    private func replayDiagnostics(
        from validation: XcircuiteSymbolicPlannerPlanReplayValidation
    ) -> [XcircuiteSymbolicPlannerSolverDiagnostic] {
        validation.diagnostics.map { diagnostic in
            XcircuiteSymbolicPlannerSolverDiagnostic(
                severity: diagnostic.severity,
                code: "plan-replay-\(diagnostic.code)",
                message: diagnostic.message
            )
        }
    }

    private func run(
        process: Process,
        timeoutSeconds: Double,
        runID: String,
        projectRoot: URL
    ) async -> ProcessOutcome {
        do {
            let result = try await TimedProcessRunner(timeoutSeconds: timeoutSeconds).run(
                process: process,
                cancellationCheck: FlowExecutionCancellationProbe.make(
                    runID: runID,
                    projectRoot: projectRoot
                )
            )
            return ProcessOutcome(
                exitCode: result.exitCode,
                didTimeout: false,
                didCancel: false,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                diagnostics: result.exitCode == 0 ? [] : [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "non-zero-exit",
                        message: "Symbolic planner exited with code \(result.exitCode)."
                    ),
                ]
            )
        } catch let error as TimedProcessError {
            return outcome(for: error)
        } catch {
            return ProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: "",
                standardError: "",
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "process-runner-error",
                        message: error.localizedDescription
                    ),
                ]
            )
        }
    }

    private func outcome(for error: TimedProcessError) -> ProcessOutcome {
        switch error {
        case .invalidConfiguration(let message):
            return ProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: "",
                standardError: "",
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "invalid-process-configuration",
                        message: message
                    ),
                ]
            )
        case .launchFailed(_, let message):
            return ProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: "",
                standardError: "",
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "launch-failed",
                        message: message
                    ),
                ]
            )
        case .cancellationCheckFailed(_, let message, let standardOutput, let standardError):
            return ProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: false,
                standardOutput: standardOutput,
                standardError: standardError,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "cancellation-check-failed",
                        message: message
                    ),
                ]
            )
        case .cancelled(_, let standardOutput, let standardError):
            return ProcessOutcome(
                exitCode: nil,
                didTimeout: false,
                didCancel: true,
                standardOutput: standardOutput,
                standardError: standardError,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "cancelled",
                        message: "Symbolic planner process was cancelled."
                    ),
                ]
            )
        case .timedOut(_, let timeoutSeconds, let standardOutput, let standardError):
            return ProcessOutcome(
                exitCode: nil,
                didTimeout: true,
                didCancel: false,
                standardOutput: standardOutput,
                standardError: standardError,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "timed-out",
                        message: "Symbolic planner process timed out after \(timeoutSeconds) seconds."
                    ),
                ]
            )
        }
    }

    private func status(for outcome: ProcessOutcome) -> String {
        if outcome.didTimeout {
            return "timed-out"
        }
        if outcome.didCancel {
            return "cancelled"
        }
        if outcome.exitCode == 0 {
            return "solved-without-import"
        }
        if outcome.diagnostics.contains(where: { $0.code == "launch-failed" }) {
            return "launch-failed"
        }
        return "solver-failed"
    }

    private func solverPlanText(
        standardOutput: String,
        solverPlanOutputURL: URL?,
        diagnostics: inout [XcircuiteSymbolicPlannerSolverDiagnostic]
    ) throws -> SolverPlanText? {
        if let solverPlanOutputURL,
           FileManager.default.fileExists(atPath: solverPlanOutputURL.path(percentEncoded: false)) {
            let text = try String(contentsOf: solverPlanOutputURL, encoding: .utf8)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return SolverPlanText(text: text, source: "solver-plan-output-path")
            }
        }
        if !standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SolverPlanText(text: standardOutput, source: "stdout")
        }
        diagnostics.append(
            XcircuiteSymbolicPlannerSolverDiagnostic(
                severity: "error",
                code: "missing-solver-plan-output",
                message: "Symbolic planner completed without a non-empty solver plan output file or stdout plan."
            )
        )
        return nil
    }

    private func validateSolverPlanOutput(
        path: String,
        outputURL: URL,
        workingDirectoryPath: String,
        workingDirectoryURL: URL,
        protectedArtifacts: [ProtectedSolverInputArtifact]
    ) throws {
        if let conflict = protectedArtifacts.first(where: { sameFileLocation($0.url, outputURL) }) {
            throw XcircuiteSymbolicPlannerSolverError.conflictingSolverPlanOutputPath(
                path: path,
                conflictingArtifactID: conflict.artifactID,
                conflictingPath: conflict.path
            )
        }
        guard isFile(outputURL, inside: workingDirectoryURL) else {
            throw XcircuiteSymbolicPlannerSolverError.solverPlanOutputOutsideWorkingDirectory(
                path: path,
                workingDirectoryPath: workingDirectoryPath
            )
        }
        if FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) {
            throw XcircuiteSymbolicPlannerSolverError.existingSolverPlanOutput(path: path)
        }
    }

    private func protectedSolverInputArtifacts(
        domainArtifact: XcircuiteFileReference,
        domainURL: URL,
        problemArtifact: XcircuiteFileReference,
        problemURL: URL,
        pddlExportArtifact: XcircuiteFileReference?,
        pddlExportURL: URL?
    ) -> [ProtectedSolverInputArtifact] {
        var artifacts = [
            ProtectedSolverInputArtifact(
                artifactID: domainArtifact.artifactID,
                path: domainArtifact.path,
                url: domainURL
            ),
            ProtectedSolverInputArtifact(
                artifactID: problemArtifact.artifactID,
                path: problemArtifact.path,
                url: problemURL
            ),
        ]
        if let pddlExportArtifact, let pddlExportURL {
            artifacts.append(
                ProtectedSolverInputArtifact(
                    artifactID: pddlExportArtifact.artifactID,
                    path: pddlExportArtifact.path,
                    url: pddlExportURL
                )
            )
        }
        return artifacts
    }

    private func sameFileLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path(percentEncoded: false) == rhs.standardizedFileURL.path(percentEncoded: false)
    }

    private func isFile(_ fileURL: URL, inside directoryURL: URL) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL.path(percentEncoded: false)
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : "\(directoryPath)/"
        return filePath.hasPrefix(prefix)
    }

    private func optionalPDDLExportArtifact(
        request: XcircuiteSymbolicPlannerSolverRequest,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> XcircuiteFileReference? {
        if request.importCandidatePlan || request.pddlExportPath != nil || request.pddlExportArtifactID != nil {
            return try artifactReference(
                explicitPath: request.pddlExportPath,
                artifactID: request.pddlExportArtifactID ?? XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID,
                missingReferenceError: .missingPDDLExportReference,
                manifest: manifest,
                runID: request.runID,
                projectRoot: projectRoot,
                format: .json
            )
        }
        return nil
    }

    private func artifactReference(
        explicitPath: String?,
        artifactID: String?,
        missingReferenceError: XcircuiteSymbolicPlannerSolverError,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL,
        format: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        if let explicitPath {
            return try artifactReferenceResolver.projectFileReference(
                path: explicitPath,
                artifactID: artifactID,
                field: "solverInputArtifact",
                expectedFormat: format,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        guard let artifactID else {
            throw missingReferenceError
        }
        return try artifactReferenceResolver.uniqueManifestArtifact(
            artifactID: artifactID,
            field: "solverInputArtifact",
            expectedFormat: format,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    private func resolvedArguments(
        _ arguments: [String],
        domainURL: URL,
        problemURL: URL,
        solverPlanOutputURL: URL?
    ) -> [String] {
        arguments.map { argument in
            argument
                .replacingOccurrences(
                    of: "{domain}",
                    with: domainURL.path(percentEncoded: false)
                )
                .replacingOccurrences(
                    of: "{problem}",
                    with: problemURL.path(percentEncoded: false)
                )
                .replacingOccurrences(
                    of: "{solverPlan}",
                    with: solverPlanOutputURL?.path(percentEncoded: false) ?? ""
                )
        }
    }

    private func solverPlanOutputPath(for request: XcircuiteSymbolicPlannerSolverRequest) -> String? {
        if let solverPlanOutputPath = request.solverPlanOutputPath {
            return solverPlanOutputPath
        }
        if request.arguments.contains(where: { $0.contains("{solverPlan}") }) {
            return defaultSolverPlanOutputPath(runID: request.runID)
        }
        return nil
    }

    private func defaultSolverWorkingDirectoryPath(runID: String) -> String {
        "\(XcircuitePackage.directoryName)/runs/\(runID)/planning/symbolic-planner/solver-work"
    }

    private func defaultSolverPlanOutputPath(runID: String) -> String {
        "\(defaultSolverWorkingDirectoryPath(runID: runID))/solver-plan.out"
    }

    private func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try artifactReferenceResolver.runManifest(runID: runID, projectRoot: projectRoot)
    }

    private static func currentTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private struct ProcessOutcome: Sendable, Hashable {
        var exitCode: Int32?
        var didTimeout: Bool
        var didCancel: Bool
        var standardOutput: String
        var standardError: String
        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]
    }

    private struct SolverPlanText: Sendable, Hashable {
        var text: String
        var source: String
    }

    private struct ProtectedSolverInputArtifact: Sendable, Hashable {
        var artifactID: String?
        var path: String
        var url: URL
    }
}
