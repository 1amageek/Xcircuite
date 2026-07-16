import CircuiteFoundation
import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffEvidence
import Foundation
import SignoffToolSupport

public struct ElectricalSignoffCorpusFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let requestInput: XcircuiteFlowInputReference
    public let oracleInput: XcircuiteFlowInputReference?
    public let oracleProcessConfiguration: ElectricalSignoffOracleProcessConfiguration?
    private let runner: ElectricalSignoffCorpusRunner
    private let oracleProcessRunner: any ElectricalSignoffOracleProcessRunning

    public init(
        stageID: String = "electrical-signoff.corpus",
        toolID: String = "native-electrical-signoff-corpus",
        requestInput: XcircuiteFlowInputReference,
        oracleInput: XcircuiteFlowInputReference? = nil,
        oracleProcessConfiguration: ElectricalSignoffOracleProcessConfiguration? = nil,
        runner: ElectricalSignoffCorpusRunner,
        oracleProcessRunner: any ElectricalSignoffOracleProcessRunning = TimedElectricalSignoffOracleProcessRunner()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.oracleInput = oracleInput
        self.oracleProcessConfiguration = oracleProcessConfiguration
        self.runner = runner
        self.oracleProcessRunner = oracleProcessRunner
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage, context: context)
            let specURL = try requestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let specInputReference = try inputReference(
                requestInput,
                artifactID: "electrical-signoff-corpus-spec-input",
                context: context
            )
            let specData = try Data(contentsOf: specURL)
            let spec = try JSONDecoder().decode(ElectricalSignoffCorpusSpec.self, from: specData)
            guard spec.cases.allSatisfy({ $0.request.runID == context.runID }) else {
                return failureResult(
                    stageID: stage.stageID,
                    code: "ELECTRICAL_SIGNOFF_CORPUS_RUN_ID_MISMATCH",
                    message: "Every corpus case request must use the flow run ID."
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
            let effectiveRunner: ElectricalSignoffCorpusRunner
            if let oracleURL = oraclePreparation?.observationURL {
                let oracle = try LocalElectricalSignoffOracle(contentsOf: oracleURL)
                effectiveRunner = ElectricalSignoffCorpusRunner(
                    engine: runner.engine,
                    oracle: oracle,
                    implementationID: runner.implementationID
                )
            } else {
                effectiveRunner = runner
            }
            let report = try await effectiveRunner.run(spec: spec)
            try await context.checkCancellation()
            if report.observationMaturity == .oracleCorrelated, oracleReference == nil {
                throw ElectricalSignoffCorpusFlowError.missingOracleArtifact
            }
            let artifactRoot = ".xcircuite/runs/\(context.runID)/electrical-signoff-corpus"
            let specPath = "\(artifactRoot)/electrical-signoff-spec.json"
            let reportPath = "\(artifactRoot)/electrical-signoff-report.json"
            let specReference = try await persistJSON(
                spec,
                path: specPath,
                artifactID: "electrical-signoff-corpus-spec",
                kind: .report,
                context: context
            )
            let reportReference = try await persistJSON(
                report,
                path: reportPath,
                artifactID: "electrical-signoff-corpus-report",
                kind: .report,
                context: context
            )

            let inputManifest = ElectricalSignoffInputArtifactManifest(
                runID: context.runID,
                stageID: stage.stageID,
                inputArtifacts: [specInputReference] + (oracleReference.map { [$0] } ?? [])
            )
            try inputManifest.validate()
            let inputManifestPath = "\(artifactRoot)/electrical-signoff-inputs.json"
            let inputManifestReference = try await persistJSON(
                inputManifest,
                path: inputManifestPath,
                artifactID: "electrical-signoff-input-manifest",
                kind: .report,
                context: context
            )

            let artifacts = (oraclePreparation?.executionArtifacts ?? [])
                + [inputManifestReference, specReference, reportReference]
                + (oracleReference.map { [$0] } ?? [])
            let gate = FlowGateResult(
                gateID: "corpus-observations",
                status: report.passed ? .passed : .failed,
                diagnostics: report.failureCodes.map { code in
                    FlowDiagnostic(
                        severity: .error,
                        code: "ELECTRICAL_SIGNOFF_CORPUS_\(code.uppercased().replacingOccurrences(of: "-", with: "_"))",
                        message: "Electrical signoff corpus observation failed: \(code)."
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
                oracleEvidence = try await externalOracleEvidenceReferences(context: context)
            } catch {
                oracleEvidenceError = error.localizedDescription
            }
            let message = [error.localizedDescription, oracleEvidenceError.map { "Oracle evidence retention also failed: \($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
            let code: String
            if let flowError = error as? ElectricalSignoffCorpusFlowError {
                code = flowError.failureCode
            } else {
                code = "ELECTRICAL_SIGNOFF_CORPUS_EXECUTION_ERROR"
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
            throw ElectricalSignoffCorpusFlowError.stageMismatch
        }
        guard context.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ElectricalSignoffCorpusFlowError.invalidRunID
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
        if oracleInput != nil, oracleProcessConfiguration != nil {
            throw ElectricalSignoffCorpusFlowError.conflictingOracleSources
        }
        try oracleProcessConfiguration?.validate()
    }

    private func inputReference(
        _ input: XcircuiteFlowInputReference,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        switch input {
        case .artifact(let suppliedReference):
            _ = try input.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
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
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let path = try projectRelativePath(for: url, projectRoot: try context.xcircuiteProjectRoot())
            return try foundationReference(
                forProjectRelativePath: path,
                artifactID: artifactID,
                kind: .report,
                format: .json,
                projectRoot: try context.xcircuiteProjectRoot()
            )
        }
    }

    private func foundationReference(
        forProjectRelativePath path: String,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        projectRoot: URL
    ) throws -> ArtifactReference {
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
        let artifactRoot = ".xcircuite/runs/\(context.runID)/electrical-signoff-corpus/oracle"
        let outputPath = "\(artifactRoot)/observations.json"
        let stdoutPath = "\(artifactRoot)/stdout.txt"
        let stderrPath = "\(artifactRoot)/stderr.txt"
        let executionPath = "\(artifactRoot)/execution.json"
        let outputURL = try artifactURL(path: outputPath, context: context)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let workingDirectory = configuration.resolvedWorkingDirectory(projectRoot: try context.xcircuiteProjectRoot())
        let arguments = configuration.expandedArguments(
            specPath: specURL.path(percentEncoded: false),
            outputPath: outputURL.path(percentEncoded: false),
            projectRoot: try context.xcircuiteProjectRoot(),
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
                    try await context.checkCancellation()
                    return false
                }
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
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
            _ = try await persistData(Data(), path: stdoutPath, artifactID: "electrical-signoff-oracle-stdout", format: .text, context: context)
            _ = try await persistData(Data(error.localizedDescription.utf8), path: stderrPath, artifactID: "electrical-signoff-oracle-stderr", format: .text, context: context)
            _ = try await persistJSON(execution, path: executionPath, artifactID: "electrical-signoff-oracle-execution", kind: .report, context: context)
            throw ElectricalSignoffCorpusFlowError.externalOracleProcessFailed(
                error.localizedDescription
            )
        }

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
        let stdoutReference = try await persistData(Data(processResult.standardOutput.utf8), path: stdoutPath, artifactID: "electrical-signoff-oracle-stdout", format: .text, context: context)
        let stderrReference = try await persistData(Data(processResult.standardError.utf8), path: stderrPath, artifactID: "electrical-signoff-oracle-stderr", format: .text, context: context)
        let executionReference = try await persistJSON(execution, path: executionPath, artifactID: "electrical-signoff-oracle-execution", kind: .report, context: context)
        guard processSucceeded else {
            throw ElectricalSignoffCorpusFlowError.externalOracleProcessFailed(
                "External oracle process exited with code \(processResult.exitCode)."
            )
        }
        guard FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw ElectricalSignoffCorpusFlowError.externalOracleOutputMissing(outputPath)
        }
        let observationReference = try await persistData(
            Data(contentsOf: outputURL, options: [.mappedIfSafe]),
            path: outputPath,
            artifactID: "electrical-signoff-oracle-observations",
            format: .json,
            context: context
        )
        let executionArtifacts = [stdoutReference, stderrReference, executionReference]
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
            throw ElectricalSignoffCorpusFlowError.oracleOutsideProject(path)
        }
        let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else {
            throw ElectricalSignoffCorpusFlowError.oracleOutsideProject(path)
        }
        return relative
    }

    private func artifactURL(
        path: String,
        context: FlowExecutionContext
    ) throws -> URL {
        let url = try context.xcircuiteProjectRoot().appending(path: path).standardizedFileURL
        guard ProjectPathBoundary().contains(url, projectRoot: try context.xcircuiteProjectRoot()) else {
            throw ElectricalSignoffCorpusFlowError.oracleOutsideProject(
                url.path(percentEncoded: false)
            )
        }
        return url
    }

    private func persistJSON<Value: Encodable>(
        _ value: Value,
        path: String,
        artifactID: String,
        kind: ArtifactKind,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await context.infrastructure.persistArtifact(
            content: encoder.encode(value),
            id: ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: .json
            ),
            runID: context.runID,
            mode: .replaceable
        )
    }

    private func persistData(
        _ data: Data,
        path: String,
        artifactID: String,
        format: ArtifactFormat,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        try await context.infrastructure.persistArtifact(
            content: data,
            id: ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: format
            ),
            runID: context.runID,
            mode: .replaceable
        )
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func externalOracleEvidenceReferences(context: FlowExecutionContext) async throws -> [ArtifactReference] {
        guard oracleProcessConfiguration != nil else { return [] }
        let artifactRoot = ".xcircuite/runs/\(context.runID)/electrical-signoff-corpus/oracle"
        let descriptors: [(String, String, ArtifactFormat)] = [
            ("stdout.txt", "electrical-signoff-oracle-stdout", .text),
            ("stderr.txt", "electrical-signoff-oracle-stderr", .text),
            ("execution.json", "electrical-signoff-oracle-execution", .json),
        ]
        var references: [ArtifactReference] = []
        for (fileName, artifactID, format) in descriptors {
            let relativePath = "\(artifactRoot)/\(fileName)"
            let url = try artifactURL(path: relativePath, context: context)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            references.append(try await persistData(
                Data(contentsOf: url, options: [.mappedIfSafe]),
                path: relativePath,
                artifactID: artifactID,
                format: format,
                context: context
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
            gates: [FlowGateResult(gateID: "corpus-observations", status: .failed, diagnostics: [diagnostic])],
            artifacts: artifacts
        )
    }

    private struct OraclePreparation: Sendable {
        let observationURL: URL
        let observationReference: ArtifactReference
        let executionArtifacts: [ArtifactReference]
    }
}

private enum ElectricalSignoffCorpusFlowError: Error, LocalizedError {
    case stageMismatch
    case invalidRunID
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
        case .stageMismatch, .invalidRunID, .missingOracleArtifact:
            return "ELECTRICAL_SIGNOFF_CORPUS_EXECUTION_ERROR"
        }
    }

    var errorDescription: String? {
        switch self {
        case .stageMismatch:
            return "The configured electrical signoff corpus stage does not match the requested stage."
        case .invalidRunID:
            return "The flow run ID is required for electrical signoff corpus execution."
        case .missingOracleArtifact:
            return "Independent oracle correlation requires the immutable oracle observation artifact to be retained."
        case .conflictingOracleSources:
            return "Electrical signoff corpus execution must use either an oracle observation artifact or an external oracle process, not both."
        case let .externalOracleProcessFailed(message):
            return "The external electrical oracle process failed: \(message)"
        case let .externalOracleOutputMissing(path):
            return "The external electrical oracle did not produce its observation artifact: \(path)."
        case let .oracleOutsideProject(path):
            return "The oracle observation artifact is outside the project root: \(path)."
        }
    }
}
