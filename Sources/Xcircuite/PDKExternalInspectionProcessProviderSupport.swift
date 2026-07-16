import CircuiteFoundation
import Foundation
import PDKKit
import PDKStandardViews
import SignoffToolSupport

struct PDKExternalInspectionProcessRun: Sendable {
    var resultData: Data?
    var artifacts: [ArtifactReference]
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

        let projectRoot = URL(filePath: projectRootPath).standardizedFileURL
        let artifactDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
            .appending(path: "external-pdk")
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
        let startedAt = Date()
        let processOutcome = await run(
            executablePath: configuration.executablePath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            runID: runID,
            projectRoot: projectRoot
        )
        let completedAt = Date()

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
        let record = PDKExternalInspectionExecutionRecord(
            runID: runID,
            stageID: stageID,
            executablePath: configuration.executablePath,
            arguments: arguments,
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
            diagnostics: processOutcome.failure.map { [$0.localizedDescription] } ?? []
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(to: executionURL, options: [.atomic])
        } catch {
            throw PDKExternalInspectionProcessError.artifactPreparationFailed(
                path: executionURL.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }

        let artifacts: [ArtifactReference]
        do {
            artifacts = [
                try foundationReference(
                    for: requestURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-request",
                    role: .input,
                    kind: .request,
                    format: .json
                ),
                try foundationReference(
                    for: resultURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-result",
                    role: .output,
                    kind: .report,
                    format: .json
                ),
                try foundationReference(
                    for: standardOutputURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-stdout",
                    role: .output,
                    kind: .log,
                    format: .text
                ),
                try foundationReference(
                    for: standardErrorURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-stderr",
                    role: .output,
                    kind: .log,
                    format: .text
                ),
                try foundationReference(
                    for: executionURL,
                    projectRoot: projectRoot,
                    artifactID: "pdk-external-execution",
                    role: .output,
                    kind: .evidence,
                    format: .json
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
            exitCode: processOutcome.exitCode,
            failure: processOutcome.failure
        )
    }

    func appendArtifacts(
        to data: Data,
        artifacts: [ArtifactReference],
        as resultType: PDKRuleDeckInspectionResult.Type
    ) throws -> Data {
        _ = resultType
        var result = try JSONDecoder().decode(PDKRuleDeckInspectionResult.self, from: data)
        let existing = Set(result.artifacts)
        result.artifacts.append(contentsOf: artifacts.filter { !existing.contains($0) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }

    func appendArtifacts(
        to data: Data,
        artifacts: [ArtifactReference],
        as resultType: PDKStandardViewInspectionResult.Type
    ) throws -> Data {
        _ = resultType
        var result = try JSONDecoder().decode(PDKStandardViewInspectionResult.self, from: data)
        let existing = Set(result.artifacts)
        result.artifacts.append(contentsOf: artifacts.filter { !existing.contains($0) })
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
        format: ArtifactFormat
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
            producer: measured.producer
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
                return Data("{\"processFailure\":\"\(failure.localizedDescription)\"}".utf8)
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
