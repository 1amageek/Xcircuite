import CircuiteFoundation
import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import Foundation
import QualificationEngine
import ReleaseCore
import SignoffToolSupport
import ToolQualification

public struct ElectricalSignoffQualificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let requestInput: XcircuiteFlowInputReference
    public let oracleInput: XcircuiteFlowInputReference?
    public let oracleProcessConfiguration: ElectricalSignoffOracleProcessConfiguration?
    public let qualificationScope: ToolQualificationScope
    private let runner: ElectricalSignoffQualificationRunner
    private let oracleProcessRunner: any ElectricalSignoffOracleProcessRunning

    public init(
        stageID: String = "electrical-signoff.qualification",
        toolID: String = "native-electrical-signoff-qualification",
        requestInput: XcircuiteFlowInputReference,
        oracleInput: XcircuiteFlowInputReference? = nil,
        oracleProcessConfiguration: ElectricalSignoffOracleProcessConfiguration? = nil,
        qualificationScope: ToolQualificationScope,
        runner: ElectricalSignoffQualificationRunner,
        oracleProcessRunner: any ElectricalSignoffOracleProcessRunning = TimedElectricalSignoffOracleProcessRunner()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.oracleInput = oracleInput
        self.oracleProcessConfiguration = oracleProcessConfiguration
        self.qualificationScope = qualificationScope
        self.runner = runner
        self.oracleProcessRunner = oracleProcessRunner
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage, context: context)
            let specURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let specInputReference = try inputReference(
                requestInput,
                artifactID: "electrical-signoff-qualification-spec-input",
                context: context
            )
            let specData = try Data(contentsOf: specURL)
            let spec = try JSONDecoder().decode(ElectricalSignoffQualificationSpec.self, from: specData)
            guard spec.cases.allSatisfy({ $0.request.runID == context.runID }) else {
                return failureResult(
                    stageID: stage.stageID,
                    code: "ELECTRICAL_SIGNOFF_QUALIFICATION_RUN_ID_MISMATCH",
                    message: "Every qualification case request must use the flow run ID."
                )
            }
            let oraclePreparation = try await prepareOracle(
                specURL: specURL,
                context: context
            )
            let oracleReference = try oracleInput.map { input in
                try inputReference(
                    input,
                    artifactID: "electrical-signoff-oracle-observations",
                    context: context
                )
            } ?? oraclePreparation?.observationReference
            let effectiveRunner: ElectricalSignoffQualificationRunner
            if let oracleURL = oraclePreparation?.observationURL {
                let oracle = try LocalElectricalSignoffQualificationOracle(contentsOf: oracleURL)
                effectiveRunner = ElectricalSignoffQualificationRunner(
                    engine: runner.engine,
                    oracle: oracle,
                    implementationID: runner.implementationID
                )
            } else {
                effectiveRunner = runner
            }
            let report = try await effectiveRunner.run(spec: spec)
            try context.checkCancellation()
            if report.qualificationLevel >= .oracleChecked, oracleReference == nil {
                throw ElectricalSignoffQualificationFlowError.missingOracleArtifact
            }
            let artifactRoot = ".xcircuite/runs/\(context.runID)/qualification"
            let specPath = "\(artifactRoot)/electrical-signoff-spec.json"
            let reportPath = "\(artifactRoot)/electrical-signoff-report.json"
            let specOutputURL = try context.storage.url(
                forProjectRelativePath: specPath,
                inProjectAt: context.projectRoot
            )
            let reportURL = try context.storage.url(
                forProjectRelativePath: reportPath,
                inProjectAt: context.projectRoot
            )
            try context.storage.ensureDirectory(at: reportURL.deletingLastPathComponent())
            try context.storage.writeJSON(spec, to: specOutputURL, forProjectAt: context.projectRoot)
            let specReference = try foundationReference(
                forProjectRelativePath: specPath,
                artifactID: "electrical-signoff-qualification-spec",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )
            try context.storage.writeJSON(report, to: reportURL, forProjectAt: context.projectRoot)
            let reportReference = try foundationReference(
                forProjectRelativePath: reportPath,
                artifactID: "electrical-signoff-qualification-report",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )

            let inputManifest = ElectricalSignoffInputArtifactManifest(
                runID: context.runID,
                stageID: stage.stageID,
                inputArtifacts: [specInputReference] + (oracleReference.map { [$0] } ?? [])
            )
            try inputManifest.validate()
            let inputManifestPath = "\(artifactRoot)/electrical-signoff-inputs.json"
            let inputManifestURL = try context.storage.url(
                forProjectRelativePath: inputManifestPath,
                inProjectAt: context.projectRoot
            )
            try context.storage.writeJSON(inputManifest, to: inputManifestURL, forProjectAt: context.projectRoot)
            let inputManifestReference = try foundationReference(
                forProjectRelativePath: inputManifestPath,
                artifactID: "electrical-signoff-input-manifest",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )

            let evidence = report.toolEvidence(
                reportPath: reportPath,
                reportSHA256: reportReference.sha256,
                scope: qualificationScope,
                checkedAt: report.generatedAt
            )
            let evidencePath = "\(artifactRoot)/electrical-signoff-tool-evidence.json"
            let evidenceURL = try context.storage.url(
                forProjectRelativePath: evidencePath,
                inProjectAt: context.projectRoot
            )
            try context.storage.writeJSON(evidence, to: evidenceURL, forProjectAt: context.projectRoot)
            let evidenceReference = try foundationReference(
                forProjectRelativePath: evidencePath,
                artifactID: "electrical-signoff-tool-evidence",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )

            let retainedArtifacts = try persistRetainedQualification(
                report: report,
                spec: spec,
                specReference: specReference,
                reportReference: reportReference,
                evidenceReference: evidenceReference,
                oracleReference: oracleReference,
                oracleExecutionArtifacts: oraclePreparation?.executionArtifacts ?? [],
                inputManifestReference: inputManifestReference,
                artifactRoot: artifactRoot,
                context: context
            )
            let artifacts = (oraclePreparation?.executionArtifacts ?? [])
                + [inputManifestReference, specReference, reportReference, evidenceReference]
                + (oracleReference.map { [$0] } ?? [])
                + retainedArtifacts
            let gate = FlowGateResult(
                gateID: "qualification",
                status: report.passed ? .passed : .failed,
                diagnostics: report.failureCodes.map { code in
                    FlowDiagnostic(
                        severity: .error,
                        code: "ELECTRICAL_SIGNOFF_QUALIFICATION_\(code.uppercased().replacingOccurrences(of: "-", with: "_"))",
                        message: "Electrical signoff qualification failed: \(code)."
                    )
                }
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: report.passed ? .succeeded : .failed,
                diagnostics: gate.diagnostics,
                gates: [gate],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            var oracleEvidence = [ArtifactReference]()
            var oracleEvidenceError: String?
            do {
                oracleEvidence = try externalOracleEvidenceReferences(context: context)
            } catch {
                oracleEvidenceError = error.localizedDescription
            }
            let message = [error.localizedDescription, oracleEvidenceError.map { "Oracle evidence retention also failed: \($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
            let code: String
            if let flowError = error as? ElectricalSignoffQualificationFlowError {
                code = flowError.failureCode
            } else {
                code = "ELECTRICAL_SIGNOFF_QUALIFICATION_EXECUTION_ERROR"
            }
            return failureResult(
                stageID: stage.stageID,
                code: code,
                message: message,
                artifacts: oracleEvidence
            )
        }
    }

    private func validate(stage: FlowStageDefinition, context: FlowExecutionContext) throws {
        guard stage.stageID == stageID else {
            throw ElectricalSignoffQualificationFlowError.stageMismatch
        }
        guard context.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ElectricalSignoffQualificationFlowError.invalidRunID
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
        guard qualificationScope.isComplete else {
            throw ElectricalSignoffQualificationFlowError.incompleteScope
        }
        if oracleInput != nil, oracleProcessConfiguration != nil {
            throw ElectricalSignoffQualificationFlowError.conflictingOracleSources
        }
        try oracleProcessConfiguration?.validate()
    }

    private func persistRetainedQualification(
        report: ElectricalSignoffQualificationReport,
        spec: ElectricalSignoffQualificationSpec,
        specReference: ArtifactReference,
        reportReference: ArtifactReference,
        evidenceReference: ArtifactReference,
        oracleReference: ArtifactReference?,
        oracleExecutionArtifacts: [ArtifactReference],
        inputManifestReference: ArtifactReference,
        artifactRoot: String,
        context: FlowExecutionContext
    ) throws -> [ArtifactReference] {
        let nativeLane = ReleaseQualificationLane(
            laneID: "electrical-signoff-native-corpus",
            domain: "electrical-signoff",
            kind: .nativeCorpus,
            corpusSpecPath: specReference.path,
            reportPath: reportReference.path,
            evidenceExportPath: evidenceReference.path
        )
        var lanes = [nativeLane]
        if report.qualificationLevel >= .oracleChecked {
            let oracleID = report.caseResults.compactMap(\.oracle?.oracleID).sorted().first
            lanes.append(ReleaseQualificationLane(
                laneID: "electrical-signoff-independent-oracle",
                domain: "electrical-signoff",
                kind: .externalOracle,
                corpusSpecPath: specReference.path,
                reportPath: reportReference.path,
                evidenceExportPath: evidenceReference.path,
                oracleBackendID: oracleID
            ))
        }
        var requiredArtifacts = [
            inputManifestReference.path,
            specReference.path,
            reportReference.path,
            evidenceReference.path,
        ]
        if let oracleReference {
            requiredArtifacts.append(oracleReference.path)
        }
        requiredArtifacts.append(contentsOf: oracleExecutionArtifacts.map(\.path))
        let suite = RetainedCorpusSuite(
            suiteID: "\(spec.corpusID):\(spec.corpusVersion)",
            lanes: lanes,
            createdAt: iso8601String(from: report.generatedAt),
            sourceDashboardPath: reportReference.path,
            requirements: RetainedCorpusSuite.Requirements(
                domainIDs: ["electrical-signoff"],
                requireExternalOracles: report.qualificationLevel >= .oracleChecked,
                requiredArtifacts: requiredArtifacts
            )
        )
        let domainResult = RetainedCorpusReport.DomainResult(
            domain: "electrical-signoff",
            status: report.passed ? "passed" : "failed",
            qualified: report.passed,
            caseCount: report.caseCount,
            coverageTagCount: Set(report.caseResults.map { $0.axis.rawValue }).count,
            coveredRequiredCoverageTagCount: Set(report.caseResults.map { $0.axis.rawValue }).count,
            passRate: report.caseCount == 0 ? 0 : Double(report.matchedCaseCount) / Double(report.caseCount),
            oracleAgreementRate: report.oracleCaseCount == 0 ? nil : Double(report.oracleAgreementCount) / Double(report.oracleCaseCount),
            durationBudgetPassRate: 1,
            report: RetainedCorpusReport.ArtifactIdentity(path: reportReference.path, sha256: reportReference.sha256, byteCount: Int64(reportReference.byteCount), status: "verified"),
            toolEvidence: RetainedCorpusReport.ToolEvidenceObservation(evidenceID: "electrical-signoff:\(spec.corpusID):\(spec.corpusVersion)", checkedAt: iso8601String(from: report.generatedAt), failureCodes: report.failureCodes),
            toolEvidenceExport: RetainedCorpusReport.ArtifactIdentity(path: evidenceReference.path, sha256: evidenceReference.sha256, byteCount: Int64(evidenceReference.byteCount), status: "verified")
        )
        var externalResults: [RetainedCorpusReport.ExternalOracleResult] = []
        if report.qualificationLevel >= .oracleChecked {
            externalResults.append(RetainedCorpusReport.ExternalOracleResult(
                domain: "electrical-signoff",
                oracleBackendID: report.caseResults.compactMap(\.oracle?.oracleID).sorted().first,
                status: report.passed ? "passed" : "failed",
                qualified: report.passed,
                caseCount: report.caseCount,
                coverageTagCount: domainResult.coverageTagCount,
                coveredRequiredCoverageTagCount: domainResult.coveredRequiredCoverageTagCount,
                passRate: domainResult.passRate,
                oracleAgreementRate: domainResult.oracleAgreementRate,
                durationBudgetPassRate: domainResult.durationBudgetPassRate,
                report: domainResult.report,
                toolEvidence: domainResult.toolEvidence,
                toolEvidenceExport: domainResult.toolEvidenceExport
            ))
        }
        let retainedReport = RetainedCorpusReport(
            status: report.passed ? "passed" : "failed",
            createdAt: iso8601String(from: report.generatedAt),
            domainResults: [domainResult],
            externalOracleResults: externalResults
        )

        let suitePath = "\(artifactRoot)/electrical-signoff-suite.json"
        let reportPath = "\(artifactRoot)/electrical-signoff-retained-report.json"
        let suiteURL = try context.storage.url(forProjectRelativePath: suitePath, inProjectAt: context.projectRoot)
        let retainedReportURL = try context.storage.url(forProjectRelativePath: reportPath, inProjectAt: context.projectRoot)
        try context.storage.writeJSON(suite, to: suiteURL, forProjectAt: context.projectRoot)
        try context.storage.writeJSON(retainedReport, to: retainedReportURL, forProjectAt: context.projectRoot)
        let suiteReference = try foundationReference(
            forProjectRelativePath: suitePath,
            artifactID: "electrical-signoff-retained-suite",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
        let retainedReportReference = try foundationReference(
            forProjectRelativePath: reportPath,
            artifactID: "electrical-signoff-retained-report",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
        return [suiteReference, retainedReportReference]
    }

    private func inputReference(
        _ input: XcircuiteFlowInputReference,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        switch input {
        case .artifact(let suppliedReference):
            _ = try input.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            return ArtifactReference(
                id: try ArtifactID(rawValue: artifactID),
                locator: ArtifactLocator(
                    location: suppliedReference.locator.location,
                    role: .input,
                    kind: ArtifactKind.report,
                    format: ArtifactFormat.json
                ),
                digest: suppliedReference.digest,
                byteCount: suppliedReference.byteCount,
                producer: suppliedReference.producer
            )
        case .path, .stageArtifact, .stageRawArtifact:
            let url = try input.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let path = try projectRelativePath(for: url, projectRoot: context.projectRoot)
            return try foundationReference(
                forProjectRelativePath: path,
                artifactID: artifactID,
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                verifiedByRunID: context.runID
            )
        }
    }

    private func foundationReference(
        forProjectRelativePath path: String,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String? = nil,
        verifiedByRunID: String? = nil
    ) throws -> ArtifactReference {
        _ = producedByRunID
        _ = verifiedByRunID
        return try StageArtifactReferenceBuilder().reference(
            for: projectRoot.appending(path: path),
            projectRoot: projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: format
        )
    }

    private func prepareOracle(
        specURL: URL,
        context: FlowExecutionContext
    ) async throws -> OraclePreparation? {
        guard let configuration = oracleProcessConfiguration else {
            return nil
        }
        let artifactRoot = ".xcircuite/runs/\(context.runID)/qualification/oracle"
        let outputPath = "\(artifactRoot)/observations.json"
        let stdoutPath = "\(artifactRoot)/stdout.txt"
        let stderrPath = "\(artifactRoot)/stderr.txt"
        let executionPath = "\(artifactRoot)/execution.json"
        let outputURL = try context.storage.url(
            forProjectRelativePath: outputPath,
            inProjectAt: context.projectRoot
        )
        let stdoutURL = try context.storage.url(
            forProjectRelativePath: stdoutPath,
            inProjectAt: context.projectRoot
        )
        let stderrURL = try context.storage.url(
            forProjectRelativePath: stderrPath,
            inProjectAt: context.projectRoot
        )
        let executionURL = try context.storage.url(
            forProjectRelativePath: executionPath,
            inProjectAt: context.projectRoot
        )
        try context.storage.ensureDirectory(at: outputURL.deletingLastPathComponent())
        let workingDirectory = configuration.resolvedWorkingDirectory(projectRoot: context.projectRoot)
        let arguments = configuration.expandedArguments(
            specPath: specURL.path(percentEncoded: false),
            outputPath: outputURL.path(percentEncoded: false),
            projectRoot: context.projectRoot,
            runID: context.runID
        )
        let startedAt = Date()
        let processResult: TimedProcessResult
        do {
            processResult = try await oracleProcessRunner.run(
                executablePath: configuration.executablePath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: configuration.timeoutSeconds,
                cancellationCheck: {
                    try context.checkCancellation()
                    return false
                }
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            try context.storage.writeText("", to: stdoutURL)
            try context.storage.writeText(error.localizedDescription, to: stderrURL)
            let execution = ElectricalSignoffOracleProcessExecution(
                runID: context.runID,
                executablePath: configuration.executablePath,
                arguments: arguments,
                workingDirectoryPath: workingDirectory.path(percentEncoded: false),
                specPath: specURL.path(percentEncoded: false),
                outputPath: outputPath,
                standardOutputPath: stdoutPath,
                standardErrorPath: stderrPath,
                status: "failed",
                exitCode: nil,
                startedAt: startedAt,
                completedAt: Date(),
                message: error.localizedDescription
            )
            try context.storage.writeJSON(execution, to: executionURL, forProjectAt: context.projectRoot)
            throw ElectricalSignoffQualificationFlowError.externalOracleProcessFailed(
                error.localizedDescription
            )
        }

        try context.storage.writeText(processResult.standardOutput, to: stdoutURL)
        try context.storage.writeText(processResult.standardError, to: stderrURL)
        let processSucceeded = processResult.exitCode == 0
        let execution = ElectricalSignoffOracleProcessExecution(
            runID: context.runID,
            executablePath: configuration.executablePath,
            arguments: arguments,
            workingDirectoryPath: workingDirectory.path(percentEncoded: false),
            specPath: specURL.path(percentEncoded: false),
            outputPath: outputPath,
            standardOutputPath: stdoutPath,
            standardErrorPath: stderrPath,
            status: processSucceeded ? "completed" : "failed",
            exitCode: processResult.exitCode,
            startedAt: startedAt,
            completedAt: Date(),
            message: processSucceeded ? nil : "External oracle process exited with code \(processResult.exitCode)."
        )
        try context.storage.writeJSON(execution, to: executionURL, forProjectAt: context.projectRoot)
        guard processSucceeded else {
            throw ElectricalSignoffQualificationFlowError.externalOracleProcessFailed(
                "External oracle process exited with code \(processResult.exitCode)."
            )
        }
        guard FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw ElectricalSignoffQualificationFlowError.externalOracleOutputMissing(outputPath)
        }
        let observationReference = try foundationReference(
            forProjectRelativePath: outputPath,
            artifactID: "electrical-signoff-oracle-observations",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
        let executionArtifacts = try [
            foundationReference(
                forProjectRelativePath: stdoutPath,
                artifactID: "electrical-signoff-oracle-stdout",
                kind: .report,
                format: .text,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            ),
            foundationReference(
                forProjectRelativePath: stderrPath,
                artifactID: "electrical-signoff-oracle-stderr",
                kind: .report,
                format: .text,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            ),
            foundationReference(
                forProjectRelativePath: executionPath,
                artifactID: "electrical-signoff-oracle-execution",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            ),
        ]
        return OraclePreparation(
            observationURL: outputURL,
            observationReference: observationReference,
            executionArtifacts: executionArtifacts
        )
    }

    private func projectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        let root = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path == root || path.hasPrefix("\(root)/") else {
            throw ElectricalSignoffQualificationFlowError.oracleOutsideProject(path)
        }
        let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else {
            throw ElectricalSignoffQualificationFlowError.oracleOutsideProject(path)
        }
        return relative
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func externalOracleEvidenceReferences(context: FlowExecutionContext) throws -> [ArtifactReference] {
        guard oracleProcessConfiguration != nil else { return [] }
        let artifactRoot = ".xcircuite/runs/\(context.runID)/qualification/oracle"
        let descriptors: [(String, String, ArtifactFormat)] = [
            ("stdout.txt", "electrical-signoff-oracle-stdout", .text),
            ("stderr.txt", "electrical-signoff-oracle-stderr", .text),
            ("execution.json", "electrical-signoff-oracle-execution", .json),
        ]
        var references: [ArtifactReference] = []
        for (fileName, artifactID, format) in descriptors {
            let relativePath = "\(artifactRoot)/\(fileName)"
            let url = try context.storage.url(
                forProjectRelativePath: relativePath,
                inProjectAt: context.projectRoot
            )
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            references.append(try foundationReference(
                forProjectRelativePath: relativePath,
                artifactID: artifactID,
                kind: .report,
                format: format,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            ))
        }
        return references
    }

    private func failureResult(
        stageID: String,
        code: String,
        message: String,
        artifacts: [ArtifactReference] = []
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "qualification", status: .failed, diagnostics: [diagnostic])],
            artifacts: artifacts
        )
    }

    private struct OraclePreparation: Sendable {
        let observationURL: URL
        let observationReference: ArtifactReference
        let executionArtifacts: [ArtifactReference]
    }
}

private enum ElectricalSignoffQualificationFlowError: Error, LocalizedError {
    case stageMismatch
    case invalidRunID
    case incompleteScope
    case missingOracleArtifact
    case conflictingOracleSources
    case externalOracleProcessFailed(String)
    case externalOracleOutputMissing(String)
    case oracleOutsideProject(String)

    var failureCode: String {
        switch self {
        case .externalOracleProcessFailed:
            return "ELECTRICAL_SIGNOFF_EXTERNAL_ORACLE_PROCESS_FAILED"
        case .externalOracleOutputMissing:
            return "ELECTRICAL_SIGNOFF_EXTERNAL_ORACLE_OUTPUT_MISSING"
        case .conflictingOracleSources:
            return "ELECTRICAL_SIGNOFF_ORACLE_SOURCE_CONFLICT"
        case .oracleOutsideProject:
            return "ELECTRICAL_SIGNOFF_ORACLE_OUTSIDE_PROJECT"
        case .stageMismatch, .invalidRunID, .incompleteScope, .missingOracleArtifact:
            return "ELECTRICAL_SIGNOFF_QUALIFICATION_EXECUTION_ERROR"
        }
    }

    var errorDescription: String? {
        switch self {
        case .stageMismatch:
            return "The configured electrical signoff qualification stage does not match the requested stage."
        case .invalidRunID:
            return "The flow run ID is required for electrical signoff qualification."
        case .incompleteScope:
            return "A complete ToolQualification scope is required for electrical signoff qualification."
        case .missingOracleArtifact:
            return "Independent oracle qualification requires the immutable oracle observation artifact to be retained."
        case .conflictingOracleSources:
            return "Electrical signoff qualification must use either an oracle observation artifact or an external oracle process, not both."
        case let .externalOracleProcessFailed(message):
            return "The external electrical oracle process failed: \(message)"
        case let .externalOracleOutputMissing(path):
            return "The external electrical oracle did not produce its observation artifact: \(path)."
        case let .oracleOutsideProject(path):
            return "The oracle observation artifact is outside the project root: \(path)."
        }
    }
}
