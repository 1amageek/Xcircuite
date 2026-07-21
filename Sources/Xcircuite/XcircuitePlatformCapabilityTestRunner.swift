import CircuiteFoundation
import Foundation
import SignoffToolSupport

public struct XcircuitePlatformCapabilityTestRunner: Sendable {
    private let processRunner: any TimedProcessRunning

    public init() {
        self.processRunner = TimedProcessRunner(timeoutSeconds: 120)
    }

    init(processRunner: any TimedProcessRunning) {
        self.processRunner = processRunner
    }

    public func run(
        declaration: XcircuitePlatformCapabilityTestEvidence,
        evidenceRoot: URL
    ) async throws -> XcircuitePlatformCapabilityTestRun {
        let evidenceID: ArtifactID
        do {
            evidenceID = try ArtifactID(rawValue: declaration.evidenceID)
        } catch {
            throw XcircuitePlatformCapabilityTestRunnerError.invalidEvidenceID(
                declaration.evidenceID
            )
        }
        try declaration.invocation.validate()
        guard declaration.resultArtifact == nil,
              declaration.retainedArtifacts.isEmpty,
              declaration.provenance == nil,
              declaration.exitStatus == nil else {
            throw XcircuitePlatformCapabilityTestRunnerError.declarationContainsExecutionResults
        }

        let canonicalRoot = evidenceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let packageDirectory = canonicalRoot
            .appending(path: declaration.packagePath, directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard packageDirectory.path == canonicalRoot.path
                || packageDirectory.path.hasPrefix(canonicalRoot.path + "/") else {
            throw XcircuitePlatformCapabilityTestRunnerError.packageDirectoryEscapesRoot(
                declaration.packagePath
            )
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: packageDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw XcircuitePlatformCapabilityTestRunnerError.packageDirectoryUnavailable(
                declaration.packagePath
            )
        }

        let xcodebuildURL = URL(filePath: declaration.invocation.xcodebuildPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let xcodebuildDigest = try measuredXcodebuildDigest(at: xcodebuildURL)
        let xcodebuildVersion = try await measuredXcodebuildVersion(at: xcodebuildURL)
        let xcodebuildIdentity = try ProducerIdentity(
            kind: .tool,
            identifier: xcodebuildURL.lastPathComponent,
            version: xcodebuildVersion,
            build: xcodebuildDigest.hexadecimalValue
        )
        let environment = try executionEnvironment(
            xcodebuildIdentity: xcodebuildIdentity,
            xcodebuildDigest: xcodebuildDigest
        )
        var executedDeclaration = declaration
        executedDeclaration.invocation.xcodebuildPath = xcodebuildURL.path
        try executedDeclaration.invocation.validate()

        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = Array(executedDeclaration.command.dropFirst())
        process.currentDirectoryURL = packageDirectory
        let result = await runProcess(process)
        let completedAt = Date()
        guard try measuredXcodebuildDigest(at: xcodebuildURL) == xcodebuildDigest else {
            throw XcircuitePlatformCapabilityTestRunnerError
                .xcodebuildExecutableChangedDuringExecution(xcodebuildURL.path)
        }
        guard try await measuredXcodebuildVersion(at: xcodebuildURL) == xcodebuildVersion else {
            throw XcircuitePlatformCapabilityTestRunnerError
                .xcodebuildExecutableChangedDuringExecution(xcodebuildURL.path)
        }

        let relativeDirectory = ".xcircuite/validation/platform-capability/\(evidenceID.rawValue)/\(UUID().uuidString.lowercased())"
        let requestedOutputDirectory = canonicalRoot.appending(
            path: relativeDirectory,
            directoryHint: .isDirectory
        )
        let outputDirectory = requestedOutputDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard outputDirectory.path.hasPrefix(canonicalRoot.path + "/"),
              !FileManager.default.fileExists(atPath: outputDirectory.path) else {
            throw XcircuitePlatformCapabilityTestRunnerError.persistenceFailure(
                "The fresh evidence output directory is unavailable or escapes the evidence root."
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw XcircuitePlatformCapabilityTestRunnerError.persistenceFailure(
                error.localizedDescription
            )
        }

        let producer = try XcircuiteRuntimeProducerIdentity.current()
        let transcriptData = Data(
            ("STDOUT\n" + result.standardOutput + "\nSTDERR\n" + result.standardError).utf8
        )
        let transcriptPath = "\(relativeDirectory)/xcodebuild.log"
        let transcriptURL = canonicalRoot.appending(path: transcriptPath)
        do {
            try transcriptData.write(to: transcriptURL, options: .atomic)
        } catch {
            throw XcircuitePlatformCapabilityTestRunnerError.persistenceFailure(
                error.localizedDescription
            )
        }
        let digester = SHA256ContentDigester()
        let transcriptReference = ArtifactReference(
            id: ArtifactID(stableKey: "\(evidenceID.rawValue):xcodebuild-transcript"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: transcriptPath),
                role: .output,
                kind: .log,
                format: .text
            ),
            digest: try digester.digest(data: transcriptData, using: .sha256),
            byteCount: UInt64(transcriptData.count),
            producer: producer
        )
        let record = XcircuitePlatformCapabilityTestExecutionRecord(
            evidenceID: executedDeclaration.evidenceID,
            testFilter: executedDeclaration.testFilter,
            command: executedDeclaration.command,
            startedAt: startedAt,
            completedAt: completedAt,
            exitStatus: result.exitCode,
            transcriptArtifact: transcriptReference
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let recordData = try encoder.encode(record)
        let recordPath = "\(relativeDirectory)/execution.json"
        let recordURL = canonicalRoot.appending(path: recordPath)
        do {
            try recordData.write(to: recordURL, options: .atomic)
        } catch {
            throw XcircuitePlatformCapabilityTestRunnerError.persistenceFailure(
                error.localizedDescription
            )
        }
        let recordReference = ArtifactReference(
            id: ArtifactID(stableKey: "\(evidenceID.rawValue):execution-record"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: recordPath),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try digester.digest(data: recordData, using: .sha256),
            byteCount: UInt64(recordData.count),
            producer: producer
        )
        let invocation = try ExecutionInvocation.externalProcess(
            executable: "/usr/bin/perl",
            arguments: Array(executedDeclaration.command.dropFirst()),
            workingDirectory: executedDeclaration.packagePath
        )
        var evidence = executedDeclaration
        evidence.resultArtifact = recordReference
        evidence.retainedArtifacts = [transcriptReference]
        evidence.provenance = try ExecutionProvenance(
            producer: producer,
            supportingTools: [xcodebuildIdentity],
            invocation: invocation,
            environment: environment,
            startedAt: startedAt,
            completedAt: completedAt
        )
        evidence.exitStatus = result.exitCode
        let evidenceDigest = try digester.digest(
            data: encoder.encode(evidence),
            using: .sha256
        )

        return XcircuitePlatformCapabilityTestRun(
            evidence: evidence,
            verification: XcircuitePlatformCapabilityTestEvidenceVerification(
                evidenceID: declaration.evidenceID,
                resultArtifactID: recordReference.id,
                resultDigest: recordReference.digest,
                evidenceDigest: evidenceDigest,
                exitStatus: result.exitCode
            )
        )
    }

    private func measuredXcodebuildDigest(at executableURL: URL) throws -> ContentDigest {
        do {
            return try SHA256ContentDigester().digest(
                fileAt: executableURL,
                using: .sha256
            )
        } catch {
            throw XcircuitePlatformCapabilityTestRunnerError.xcodebuildExecutableUnavailable(
                path: executableURL.path,
                reason: error.localizedDescription
            )
        }
    }

    private func measuredXcodebuildVersion(at executableURL: URL) async throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-version"]
        let outcome = await runProcess(process)
        let lines = (outcome.standardOutput + "\n" + outcome.standardError)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard outcome.exitCode == 0, !lines.isEmpty else {
            throw XcircuitePlatformCapabilityTestRunnerError.xcodebuildVersionProbeFailed(
                path: executableURL.path,
                exitStatus: outcome.exitCode
            )
        }
        return lines.joined(separator: " | ")
    }

    private func executionEnvironment(
        xcodebuildIdentity: ProducerIdentity,
        xcodebuildDigest: ContentDigest
    ) throws -> ExecutionEnvironmentFingerprint {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        throw XcircuitePlatformCapabilityTestRunnerError.invalidCommand
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let platform = "macOS-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let toolchain = "\(xcodebuildIdentity.identifier)-\(xcodebuildIdentity.version)"
        let manifest = ExecutionEnvironmentManifest(
            platform: platform,
            architecture: architecture,
            toolchain: toolchain,
            xcodebuildDigest: xcodebuildDigest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try ExecutionEnvironmentFingerprint(
            platform: platform,
            architecture: architecture,
            toolchain: toolchain,
            environmentDigest: try SHA256ContentDigester().digest(
                data: encoder.encode(manifest),
                using: .sha256
            )
        )
    }

    private func runProcess(_ process: Process) async -> TestProcessOutcome {
        do {
            let result = try await processRunner.run(
                process: process,
                cancellationCheck: nil
            )
            return TestProcessOutcome(
                exitCode: result.exitCode,
                standardOutput: result.standardOutput,
                standardError: result.standardError
            )
        } catch let error as TimedProcessError {
            switch error {
            case .invalidConfiguration(let message), .launchFailed(_, let message):
                return TestProcessOutcome(
                    exitCode: 127,
                    standardOutput: "",
                    standardError: message
                )
            case .cancellationCheckFailed(_, let message, let output, let errorOutput):
                return TestProcessOutcome(
                    exitCode: 125,
                    standardOutput: output,
                    standardError: errorOutput + "\n" + message
                )
            case .cancelled(_, let output, let errorOutput):
                return TestProcessOutcome(
                    exitCode: 130,
                    standardOutput: output,
                    standardError: errorOutput
                )
            case .timedOut(_, _, let output, let errorOutput):
                return TestProcessOutcome(
                    exitCode: 124,
                    standardOutput: output,
                    standardError: errorOutput
                )
            }
        } catch {
            return TestProcessOutcome(
                exitCode: 125,
                standardOutput: "",
                standardError: error.localizedDescription
            )
        }
    }

    private struct TestProcessOutcome: Sendable {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String
    }

    private struct ExecutionEnvironmentManifest: Encodable {
        let platform: String
        let architecture: String
        let toolchain: String
        let xcodebuildDigest: ContentDigest
    }

}
