import CircuiteFoundation
import Foundation
import PDKKit
import PDKStandardViews
import SignoffToolSupport

struct PDKExternalInspectionProcessRun: Sendable {
    var resultData: Data?
    var artifacts: [ArtifactReference]
    var provenance: ExecutionProvenance
    var exitCode: Int32?
    var failure: PDKExternalInspectionProcessError?
}

struct PDKExternalInspectionProcessProviderSupport: Sendable {
    let configuration: PDKExternalInspectionProcessConfiguration
    let stageID: String
    let runner: any PDKExternalInspectionProcessRunning

    init(
        configuration: PDKExternalInspectionProcessConfiguration,
        stageID: String,
        runner: any PDKExternalInspectionProcessRunning
    ) {
        self.configuration = configuration
        self.stageID = stageID
        self.runner = runner
    }

    func execute<Request: Encodable>(
        request: Request,
        runID: String,
        assetID: String,
        projectRootPath: String?
    ) async throws -> PDKExternalInspectionProcessRun {
        try configuration.validate()
        do {
            _ = try ArtifactID(rawValue: stageID)
        } catch {
            throw PDKExternalInspectionProcessError.invalidStageID(stageID)
        }
        do {
            _ = try ArtifactID(rawValue: runID)
        } catch {
            throw PDKExternalInspectionProcessError.invalidRunID(runID)
        }
        do {
            _ = try ArtifactID(rawValue: assetID)
        } catch {
            throw PDKExternalInspectionProcessError.invalidAssetID(assetID)
        }
        guard let projectRootPath, !projectRootPath.isEmpty else {
            throw PDKExternalInspectionProcessError.missingProjectRoot
        }

        let projectRoot = URL(filePath: projectRootPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let requestedArtifactDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
            .appending(path: "external-pdk")
        let artifactDirectory = requestedArtifactDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard artifactDirectory.path.hasPrefix(projectRoot.path + "/") else {
            throw PDKExternalInspectionProcessError.artifactPreparationFailed(
                path: requestedArtifactDirectory.path(percentEncoded: false),
                reason: "Artifact directory escapes the project root through a symbolic link."
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: artifactDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PDKExternalInspectionProcessError.artifactPreparationFailed(
                path: artifactDirectory.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }

        let requestURL = artifactDirectory.appending(path: "request.json")
        let resultURL = artifactDirectory.appending(path: "result.json")
        let standardOutputURL = artifactDirectory.appending(path: "stdout.txt")
        let standardErrorURL = artifactDirectory.appending(path: "stderr.txt")
        let executionURL = artifactDirectory.appending(path: "execution.json")
        let requestData: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            requestData = try encoder.encode(request)
            try requestData.write(to: requestURL, options: [.atomic])
            if FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: resultURL)
            }
        } catch {
            throw PDKExternalInspectionProcessError.artifactPreparationFailed(
                path: requestURL.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }

        let workingDirectory: URL
        if let configuredPath = configuration.workingDirectoryPath {
            if configuredPath.hasPrefix("/") {
                workingDirectory = URL(filePath: configuredPath).standardizedFileURL
            } else {
                workingDirectory = projectRoot.appending(path: configuredPath).standardizedFileURL
            }
        } else {
            workingDirectory = projectRoot
        }
        let arguments = expandedArguments(
            configuration.arguments,
            requestPath: requestURL,
            resultPath: resultURL,
            projectRoot: projectRoot,
            runID: runID,
            assetID: assetID
        )
        let recordedArguments = try configuration.recordedArguments(from: arguments)
        let executableURL = URL(filePath: configuration.executablePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let digester = SHA256ContentDigester()
        let executableDigestBeforeRun: ContentDigest
        do {
            executableDigestBeforeRun = try digester.digest(fileAt: executableURL, using: .sha256)
        } catch {
            throw PDKExternalInspectionProcessError.executableMeasurementFailed(
                path: executableURL.path,
                reason: error.localizedDescription
            )
        }
        let startedAt = Date()
        var processOutcome = await run(
            executablePath: executableURL.path,
            arguments: arguments,
            workingDirectory: workingDirectory,
            runID: runID,
            projectRoot: projectRoot
        )
        let completedAt = Date()
        do {
            let executableDigestAfterRun = try digester.digest(fileAt: executableURL, using: .sha256)
            if executableDigestAfterRun != executableDigestBeforeRun {
                processOutcome.failure = .processFailed(
                    "The external executable changed during inspection."
                )
            }
        } catch {
            processOutcome.failure = .processFailed(
                "The external executable could not be reverified after inspection: \(error.localizedDescription)"
            )
        }

        let standardOutputData = Data(processOutcome.standardOutput.utf8)
        let standardErrorData = Data(processOutcome.standardError.utf8)
        let resultData = try resultData(
            resultURL: resultURL,
            standardOutput: processOutcome.standardOutput,
            failure: processOutcome.failure
        )
        do {
            try standardOutputData.write(to: standardOutputURL, options: [.atomic])
            try standardErrorData.write(to: standardErrorURL, options: [.atomic])
            try resultData.write(to: resultURL, options: [.atomic])
        } catch {
            throw PDKExternalInspectionProcessError.artifactPreparationFailed(
                path: artifactDirectory.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }

        let status: String
        if let failure = processOutcome.failure {
            status = switch failure {
            case .cancelled: "cancelled"
            case .timedOut: "timed-out"
            default: "failed"
            }
        } else if processOutcome.exitCode == 0 {
            status = "completed"
        } else {
            status = "failed"
        }
        let artifacts: [ArtifactReference]
        let provenance: ExecutionProvenance
        do {
            let requestReference = try foundationReference(
                for: requestURL,
                projectRoot: projectRoot,
                artifactID: "pdk-external-request",
                role: .input,
                kind: .request,
                format: .json
            )
            provenance = try PDKExternalInspectionExecutionProvenance.make(
                executablePath: executableURL.path,
                arguments: recordedArguments,
                workingDirectory: workingDirectory,
                requestReference: requestReference,
                startedAt: startedAt,
                completedAt: completedAt,
                executableDigest: executableDigestBeforeRun
            )
            let record = PDKExternalInspectionExecutionRecord(
                runID: runID,
                stageID: stageID,
                executablePath: executableURL.path,
                arguments: recordedArguments,
                workingDirectoryPath: workingDirectory.path(percentEncoded: false),
                timeoutSeconds: configuration.timeoutSeconds,
                requestPath: requestURL.path(percentEncoded: false),
                resultPath: resultURL.path(percentEncoded: false),
                standardOutputPath: standardOutputURL.path(percentEncoded: false),
                standardErrorPath: standardErrorURL.path(percentEncoded: false),
                exitCode: processOutcome.exitCode,
                status: status,
                startedAt: startedAt,
                completedAt: completedAt,
                provenance: provenance,
                diagnostics: processOutcome.failure.map { [$0.localizedDescription] } ?? []
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(to: executionURL, options: [.atomic])

            artifacts = [
                requestReference,
                try foundationReference(
                    for: resultURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-result",
                    role: .output,
                    kind: .report,
                    format: .json,
                    producer: provenance.producer
                ),
                try foundationReference(
                    for: standardOutputURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-stdout",
                    role: .output,
                    kind: .log,
                    format: .text,
                    producer: provenance.producer
                ),
                try foundationReference(
                    for: standardErrorURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-stderr",
                    role: .output,
                    kind: .log,
                    format: .text,
                    producer: provenance.producer
                ),
                try foundationReference(
                    for: executionURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-execution",
                    role: .output,
                    kind: .evidence,
                    format: .json,
                    producer: provenance.producer
                ),
            ]
        } catch {
            throw PDKExternalInspectionProcessError.artifactPreparationFailed(
                path: artifactDirectory.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }

        return PDKExternalInspectionProcessRun(
            resultData: resultData,
            artifacts: artifacts,
            provenance: provenance,
            exitCode: processOutcome.exitCode,
            failure: processOutcome.failure
        )
    }

    func appendArtifacts(
        to data: Data,
        artifacts: [ArtifactReference],
        provenance: ExecutionProvenance,
        as resultType: PDKRuleDeckInspectionResult.Type
    ) throws -> Data {
        _ = resultType
        var result = try JSONDecoder().decode(PDKRuleDeckInspectionResult.self, from: data)
        let existing = Set(result.artifacts)
        result.artifacts.append(contentsOf: artifacts.filter { !existing.contains($0) })
        result.provenance = provenance
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }

    func appendArtifacts(
        to data: Data,
        artifacts: [ArtifactReference],
        provenance: ExecutionProvenance,
        as resultType: PDKStandardViewInspectionResult.Type
    ) throws -> Data {
        _ = resultType
        var result = try JSONDecoder().decode(PDKStandardViewInspectionResult.self, from: data)
        let existing = Set(result.artifacts)
        result.artifacts.append(contentsOf: artifacts.filter { !existing.contains($0) })
        result.provenance = provenance
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }

    private func foundationReference(
        for url: URL,
        projectRoot: URL,
        artifactID: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            throw PDKExternalInspectionProcessError.artifactPreparationFailed(
                path: candidate.path,
                reason: "Artifact path escapes project root."
            )
        }
        let relativePath = String(candidate.path.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: relativePath),
            role: role,
            kind: kind,
            format: format
        )
        let measured = try LocalArtifactReferencer().reference(locator, relativeTo: root)
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: measured.locator,
            digest: measured.digest,
            byteCount: measured.byteCount,
            producer: producer ?? measured.producer
        )
    }

    private func resultData(
        resultURL: URL,
        standardOutput: String,
        failure: PDKExternalInspectionProcessError?
    ) throws -> Data {
        if FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)) {
            do {
                return try Data(contentsOf: resultURL)
            } catch {
                throw PDKExternalInspectionProcessError.resultReadFailed(
                    path: resultURL.path(percentEncoded: false),
                    reason: error.localizedDescription
                )
            }
        }
        let outputData = Data(standardOutput.utf8)
        guard !outputData.isEmpty else {
            if let failure {
                return try JSONEncoder().encode([
                    "processFailure": failure.localizedDescription,
                ])
            }
            throw PDKExternalInspectionProcessError.resultMissing(
                path: resultURL.path(percentEncoded: false)
            )
        }
        return outputData
    }

    private func expandedArguments(
        _ arguments: [String],
        requestPath: URL,
        resultPath: URL,
        projectRoot: URL,
        runID: String,
        assetID: String
    ) -> [String] {
        let replacements: [(String, String)] = [
            ("{{requestPath}}", requestPath.path(percentEncoded: false)),
            ("{{resultPath}}", resultPath.path(percentEncoded: false)),
            ("{{projectRoot}}", projectRoot.path(percentEncoded: false)),
            ("{{runID}}", runID),
            ("{{assetID}}", assetID),
        ]
        return arguments.map { argument in
            replacements.reduce(argument) { value, replacement in
                value.replacingOccurrences(of: replacement.0, with: replacement.1)
            }
        }
    }

    private func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: URL,
        runID: String,
        projectRoot: URL
    ) async -> ProcessOutcome {
        do {
            let result = try await runner.run(
                executablePath: executablePath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: configuration.timeoutSeconds,
                cancellationCheck: FlowExecutionCancellationProbe.make(
                    runID: runID,
                    projectRoot: projectRoot
                )
            )
            let failure: PDKExternalInspectionProcessError?
            if result.exitCode == 0 {
                failure = nil
            } else {
                failure = .nonZeroExit(result.exitCode)
            }
            return ProcessOutcome(
                exitCode: result.exitCode,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                failure: failure
            )
        } catch let error as TimedProcessError {
            let streams = processStreams(from: error)
            return ProcessOutcome(
                exitCode: nil,
                standardOutput: streams.standardOutput,
                standardError: streams.standardError,
                failure: processError(from: error)
            )
        } catch {
            return ProcessOutcome(
                exitCode: nil,
                standardOutput: "",
                standardError: "",
                failure: .processFailed(error.localizedDescription)
            )
        }
    }

    private func processError(from error: TimedProcessError) -> PDKExternalInspectionProcessError {
        switch error {
        case .invalidConfiguration(let message), .launchFailed(_, let message),
             .cancellationCheckFailed(_, let message, _, _):
            .processFailed(message)
        case .cancelled:
            .cancelled
        case .timedOut(_, let timeout, _, _):
            .timedOut(timeout)
        }
    }

    private func processStreams(
        from error: TimedProcessError
    ) -> (standardOutput: String, standardError: String) {
        switch error {
        case .invalidConfiguration, .launchFailed:
            ("", "")
        case .cancellationCheckFailed(_, _, let standardOutput, let standardError),
             .cancelled(_, let standardOutput, let standardError),
             .timedOut(_, _, let standardOutput, let standardError):
            (standardOutput, standardError)
        }
    }

    private struct ProcessOutcome: Sendable {
        var exitCode: Int32?
        var standardOutput: String
        var standardError: String
        var failure: PDKExternalInspectionProcessError?
    }
}
