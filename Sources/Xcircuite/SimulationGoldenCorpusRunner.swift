import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct SimulationGoldenCorpusRunner: Sendable {
    private let engine: any SimulationExecuting
    private let comparisonService: SimulationGoldenComparisonService
    private let identifierValidator: FlowIdentifierValidator

    public init(
        engine: any SimulationExecuting = CoreSpiceSimulationEngine(),
        comparisonService: SimulationGoldenComparisonService = SimulationGoldenComparisonService(),
        identifierValidator: FlowIdentifierValidator = FlowIdentifierValidator()
    ) {
        self.engine = engine
        self.comparisonService = comparisonService
        self.identifierValidator = identifierValidator
    }

    public func run(
        suite: SimulationGoldenCorpusSuiteSpec,
        projectRoot: URL,
        artifactDirectory: URL? = nil
    ) async throws -> SimulationGoldenCorpusReport {
        try validate(suite: suite)
        if let artifactDirectory {
            try FileManager.default.createDirectory(
                at: artifactDirectory,
                withIntermediateDirectories: true
            )
        }

        var caseResults: [SimulationGoldenCorpusReport.CaseResult] = []
        for corpusCase in suite.cases {
            let result = try await runCase(
                corpusCase,
                projectRoot: projectRoot,
                artifactDirectory: artifactDirectory
            )
            caseResults.append(result)
        }

        let coverageTags = stableUnique(caseResults.flatMap(\.coverageTags)).sorted()
        let passedCount = caseResults.filter { $0.status == "passed" }.count
        let summary = SimulationGoldenCorpusReport.Summary(
            caseCount: caseResults.count,
            passedCaseCount: passedCount,
            failedCaseCount: caseResults.count - passedCount,
            coverageTagCount: coverageTags.count
        )
        return SimulationGoldenCorpusReport(
            suiteID: suite.suiteID,
            status: passedCount == caseResults.count ? "passed" : "failed",
            summary: summary,
            coverageTags: coverageTags,
            cases: caseResults
        )
    }

    private func runCase(
        _ corpusCase: SimulationGoldenCorpusCaseSpec,
        projectRoot: URL,
        artifactDirectory: URL?
    ) async throws -> SimulationGoldenCorpusReport.CaseResult {
        do {
            let netlistURL = try resolvePath(corpusCase.netlistPath, projectRoot: projectRoot)
            let goldenURL = try resolvePath(corpusCase.goldenWaveformPath, projectRoot: projectRoot)
            let netlistSource = try String(contentsOf: netlistURL, encoding: .utf8)
            let goldenCSV = try String(contentsOf: goldenURL, encoding: .utf8)
            let outcome = try await engine.run(
                netlistSource: netlistSource,
                fileName: netlistURL.lastPathComponent
            )
            let comparison = try comparisonService.compare(
                goldenCSV: goldenCSV,
                candidateCSV: outcome.waveformCSV,
                options: corpusCase.options
            )
            let comparisonDiagnostics = comparison.diagnostics + comparison.gateViolations
            let caseDirectory = try artifactDirectory.map {
                try caseArtifactDirectory(
                    caseID: corpusCase.caseID,
                    artifactDirectory: $0
                )
            }
            if let caseDirectory {
                try FileManager.default.createDirectory(
                    at: caseDirectory,
                    withIntermediateDirectories: true
                )
            }
            let candidateArtifact = try caseDirectory.map {
                try writeTextArtifact(
                    outcome.waveformCSV,
                    to: $0.appending(path: "candidate-waveform.csv"),
                    artifactID: "\(corpusCase.caseID)-candidate-waveform",
                    kind: .waveform,
                    format: .csv
                )
            }
            let comparisonArtifact = try caseDirectory.map {
                try writeJSONArtifact(
                    comparison,
                    to: $0.appending(path: "simulation-golden-comparison.json"),
                    artifactID: "\(corpusCase.caseID)-simulation-golden-comparison",
                    kind: .report,
                    format: .json
                )
            }
            let status = comparison.gateStatus == corpusCase.expectedGateStatus
                && diagnosticsSatisfy(
                    corpusCase.expectedDiagnosticSubstrings,
                    diagnostics: comparisonDiagnostics
                )
                ? "passed"
                : "failed"
            return SimulationGoldenCorpusReport.CaseResult(
                caseID: corpusCase.caseID,
                status: status,
                expectedGateStatus: corpusCase.expectedGateStatus,
                observedGateStatus: comparison.gateStatus,
                analysisLabel: outcome.analysisLabel,
                coverageTags: corpusCase.coverageTags.sorted(),
                comparison: comparison,
                candidateWaveformArtifact: candidateArtifact,
                comparisonArtifact: comparisonArtifact,
                diagnostics: status == "passed"
                    ? comparisonDiagnostics
                    : comparisonDiagnostics + [
                        "Expected gate status \(corpusCase.expectedGateStatus), observed \(comparison.gateStatus).",
                    ]
            )
        } catch {
            let infrastructureFailure = isInfrastructureError(error)
            let diagnostics = diagnostics(
                from: error,
                infrastructureFailure: infrastructureFailure
            )
            let expectedFailure = corpusCase.expectedGateStatus == "failed"
                && !infrastructureFailure
                && diagnosticsSatisfy(
                    corpusCase.expectedDiagnosticSubstrings,
                    diagnostics: diagnostics
                )
            return SimulationGoldenCorpusReport.CaseResult(
                caseID: corpusCase.caseID,
                status: expectedFailure ? "passed" : "failed",
                expectedGateStatus: corpusCase.expectedGateStatus,
                observedGateStatus: "failed",
                analysisLabel: nil,
                coverageTags: corpusCase.coverageTags.sorted(),
                comparison: nil,
                candidateWaveformArtifact: nil,
                comparisonArtifact: nil,
                diagnostics: diagnostics
            )
        }
    }

    private func validate(suite: SimulationGoldenCorpusSuiteSpec) throws {
        guard suite.schemaVersion == 1 else {
            throw SimulationGoldenCorpusRunnerError.unsupportedSchemaVersion(suite.schemaVersion)
        }
        guard !suite.cases.isEmpty else {
            throw SimulationGoldenCorpusRunnerError.emptySuite
        }
        try validateIdentifier(suite.suiteID, kind: "suiteID")
        var seen: Set<String> = []
        for corpusCase in suite.cases {
            try validateIdentifier(corpusCase.caseID, kind: "caseID")
            guard !seen.contains(corpusCase.caseID) else {
                throw SimulationGoldenCorpusRunnerError.duplicateCaseID(corpusCase.caseID)
            }
            seen.insert(corpusCase.caseID)
            try validateProjectRelativePath(corpusCase.netlistPath)
            try validateProjectRelativePath(corpusCase.goldenWaveformPath)
            try validateExpectedGateStatus(corpusCase.expectedGateStatus, caseID: corpusCase.caseID)
            try validateExpectedFailureDiagnostics(corpusCase)
            for coverageTag in corpusCase.coverageTags {
                try validateIdentifier(coverageTag, kind: "coverageTag")
            }
        }
    }

    private func resolvePath(_ path: String, projectRoot: URL) throws -> URL {
        try validateProjectRelativePath(path)
        let root = projectRoot.standardizedFileURL
        let resolved = root.appendingPathComponent(path).standardizedFileURL
        let rootPath = normalizedPath(root)
        let resolvedPath = normalizedPath(resolved)
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
            throw SimulationGoldenCorpusRunnerError.pathEscapesProjectRoot(path)
        }
        return resolved
    }

    private func caseArtifactDirectory(
        caseID: String,
        artifactDirectory: URL
    ) throws -> URL {
        let root = artifactDirectory.standardizedFileURL
        let directory = root.appending(path: caseID).standardizedFileURL
        let rootPath = normalizedPath(root)
        let directoryPath = normalizedPath(directory)
        guard directoryPath != rootPath,
              directoryPath.hasPrefix(rootPath + "/") else {
            throw SimulationGoldenCorpusRunnerError.artifactDirectoryEscapesRoot(
                caseID: caseID,
                path: directoryPath,
                artifactRoot: rootPath
            )
        }
        return directory
    }

    private func validateIdentifier(_ value: String, kind: String) throws {
        do {
            try identifierValidator.validate(value, kind: .artifactID)
        } catch {
            throw SimulationGoldenCorpusRunnerError.invalidIdentifier(
                kind: kind,
                value: value
            )
        }
    }

    private func validateProjectRelativePath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~") else {
            throw SimulationGoldenCorpusRunnerError.invalidProjectRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw SimulationGoldenCorpusRunnerError.pathEscapesProjectRoot(path)
        }
    }

    private func validateExpectedGateStatus(_ status: String, caseID: String) throws {
        guard status == "passed" || status == "failed" else {
            throw SimulationGoldenCorpusRunnerError.invalidExpectedGateStatus(
                caseID: caseID,
                status: status
            )
        }
    }

    private func validateExpectedFailureDiagnostics(_ corpusCase: SimulationGoldenCorpusCaseSpec) throws {
        guard corpusCase.expectedGateStatus == "failed" else {
            return
        }
        guard !corpusCase.expectedDiagnosticSubstrings.isEmpty else {
            throw SimulationGoldenCorpusRunnerError.expectedFailureRequiresDiagnostics(
                caseID: corpusCase.caseID
            )
        }
    }

    private func normalizedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else {
            return path
        }
        return String(path.dropLast())
    }

    private func writeTextArtifact(
        _ text: String,
        to url: URL,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try artifactReference(for: url, artifactID: artifactID, kind: kind, format: format)
    }

    private func writeJSONArtifact<T: Encodable>(
        _ value: T,
        to url: URL,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
        return try artifactReference(for: url, artifactID: artifactID, kind: kind, format: format)
    }

    private func artifactReference(
        for url: URL,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        let data = try Data(contentsOf: url)
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(fileURL: url),
                role: .output,
                kind: kind,
                format: format
            ),
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count)
        )
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func diagnosticsSatisfy(
        _ expectedSubstrings: [String],
        diagnostics: [String]
    ) -> Bool {
        expectedSubstrings.allSatisfy { expected in
            diagnostics.contains { $0.contains(expected) }
        }
    }

    private func diagnostics(from error: any Error, infrastructureFailure: Bool) -> [String] {
        var values = stableUnique([
            error.localizedDescription,
            String(describing: error),
            String(reflecting: error),
        ]).filter { !$0.isEmpty }
        if infrastructureFailure {
            values.append("Simulation golden corpus infrastructure error prevented expected-failure acceptance.")
        }
        return stableUnique(values)
    }

    private func isInfrastructureError(_ error: any Error) -> Bool {
        if error is SimulationGoldenCorpusRunnerError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain || nsError.domain == NSPOSIXErrorDomain
    }
}
