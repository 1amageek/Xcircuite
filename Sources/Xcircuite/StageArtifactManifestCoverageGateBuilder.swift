import DesignFlowKernel
import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import XcircuitePackage

struct StageArtifactManifestCoverageGateBuilder: Sendable {
    private let pathBoundary = ProjectPathBoundary()

    func drcGate(
        manifestURL: URL?,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> FlowGateResult {
        manifestGate(
            gateID: "drc-artifacts",
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        ) { data in
            let manifest = try JSONDecoder().decode(DRCArtifactManifest.self, from: data)
            return manifest.outputs.map { record in
                ManifestOutputRecord(
                    id: record.id,
                    kind: record.kind.rawValue,
                    path: record.path,
                    byteCount: record.byteCount.map(Int64.init),
                    sha256: record.sha256
                )
            }
        }
    }

    func lvsGate(
        manifestURL: URL?,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> FlowGateResult {
        let coverageGate = manifestGate(
            gateID: "lvs-artifacts",
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        ) { data in
            let manifest = try JSONDecoder().decode(LVSArtifactManifest.self, from: data)
            return manifest.outputs.map { record in
                ManifestOutputRecord(
                    id: record.id,
                    kind: record.kind.rawValue,
                    path: record.path,
                    byteCount: record.byteCount.map(Int64.init),
                    sha256: record.sha256
                )
            }
        }
        guard let manifestURL,
              pathBoundary.contains(manifestURL, projectRoot: projectRoot) else {
            return coverageGate
        }

        let manifest: LVSArtifactManifest
        do {
            manifest = try JSONDecoder().decode(
                LVSArtifactManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            return coverageGate
        }

        let diagnostics = coverageGate.diagnostics + lvsV2Diagnostics(
            manifest: manifest,
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        )
        return FlowGateResult(
            gateID: coverageGate.gateID,
            status: diagnostics.isEmpty ? .passed : .failed,
            diagnostics: diagnostics
        )
    }

    func pexGate(
        manifestURL: URL,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> FlowGateResult {
        manifestGate(
            gateID: "pex-flow-artifacts",
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        ) { data in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(PEXArtifactManifest.self, from: data)
            return manifest.artifacts
                .filter { $0.status == .available }
                .map { record in
                    ManifestOutputRecord(
                        id: record.id,
                        kind: record.kind.rawValue,
                        path: record.relativePath.value,
                        byteCount: record.byteCount.map(Int64.init),
                        sha256: record.sha256
                    )
                }
        }
    }

    private func manifestGate(
        gateID: String,
        manifestURL: URL?,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL,
        decodeOutputs: (Data) throws -> [ManifestOutputRecord]
    ) -> FlowGateResult {
        guard let manifestURL else {
            return failedGate(
                gateID: gateID,
                code: "ARTIFACT_MANIFEST_MISSING",
                message: "Stage did not provide an artifact manifest URL."
            )
        }
        guard pathBoundary.contains(manifestURL, projectRoot: projectRoot) else {
            return failedGate(
                gateID: gateID,
                code: "ARTIFACT_MANIFEST_INVALID_PATH",
                message: "Stage artifact manifest path escapes the project root."
            )
        }

        let outputs: [ManifestOutputRecord]
        do {
            outputs = try decodeOutputs(Data(contentsOf: manifestURL))
        } catch {
            return failedGate(
                gateID: gateID,
                code: "ARTIFACT_MANIFEST_UNREADABLE",
                message: "Stage artifact manifest could not be decoded: \(error.localizedDescription)"
            )
        }

        let artifactsByPath = Dictionary(grouping: artifacts, by: \.path)
        let duplicateArtifactDiagnostics = duplicateArtifactPathDiagnostics(artifactsByPath: artifactsByPath)
        let outputDiagnostics = outputs.compactMap { output -> FlowDiagnostic? in
            guard let expectedPath = projectRelativePath(
                for: output,
                manifestURL: manifestURL,
                projectRoot: projectRoot
            ) else {
                return FlowDiagnostic(
                    severity: .error,
                    code: "ARTIFACT_MANIFEST_INVALID_PATH",
                    message: "Artifact manifest output path escapes the project. id=\(output.id) path=\(output.path)"
                )
            }
            guard let artifact = artifactsByPath[expectedPath]?.first else {
                return FlowDiagnostic(
                    severity: .error,
                    code: "ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED",
                    message: "Artifact manifest output is not indexed in FlowStageResult.artifacts. id=\(output.id) kind=\(output.kind) path=\(expectedPath)"
                )
            }
            if let byteCount = output.byteCount, artifact.byteCount != byteCount {
                return FlowDiagnostic(
                    severity: .error,
                    code: "ARTIFACT_MANIFEST_BYTE_COUNT_MISMATCH",
                    message: "Artifact byte count differs from the engine manifest. id=\(output.id) path=\(expectedPath) manifestByteCount=\(byteCount) flowByteCount=\(artifact.byteCount.map(String.init) ?? "missing")"
                )
            }
            if let sha256 = output.sha256, artifact.sha256 != sha256 {
                return FlowDiagnostic(
                    severity: .error,
                    code: "ARTIFACT_MANIFEST_SHA256_MISMATCH",
                    message: "Artifact SHA-256 differs from the engine manifest. id=\(output.id) path=\(expectedPath) manifestSHA256=\(sha256) flowSHA256=\(artifact.sha256 ?? "missing")"
                )
            }
            return nil
        }
        let diagnostics = duplicateArtifactDiagnostics + outputDiagnostics

        return FlowGateResult(
            gateID: gateID,
            status: diagnostics.isEmpty ? .passed : .failed,
            diagnostics: diagnostics
        )
    }

    private func failedGate(
        gateID: String,
        code: String,
        message: String
    ) -> FlowGateResult {
        FlowGateResult(
            gateID: gateID,
            status: .failed,
            diagnostics: [
                FlowDiagnostic(severity: .error, code: code, message: message),
            ]
        )
    }

    private func duplicateArtifactPathDiagnostics(
        artifactsByPath: [String: [XcircuiteFileReference]]
    ) -> [FlowDiagnostic] {
        artifactsByPath.keys.sorted().compactMap { path in
            guard let artifacts = artifactsByPath[path], artifacts.count > 1 else {
                return nil
            }
            let artifactIDs = artifacts
                .map { $0.artifactID ?? $0.kind.rawValue }
                .sorted()
                .joined(separator: ",")
            return FlowDiagnostic(
                severity: .error,
                code: "ARTIFACT_MANIFEST_DUPLICATE_FLOW_ARTIFACT_PATH",
                message: "FlowStageResult.artifacts contains duplicate artifact paths. path=\(path) artifactIDs=\(artifactIDs)"
            )
        }
    }

    private func projectRelativePath(
        for output: ManifestOutputRecord,
        manifestURL: URL,
        projectRoot: URL
    ) -> String? {
        let outputURL: URL
        if output.path.hasPrefix("/") {
            outputURL = URL(filePath: output.path)
        } else {
            outputURL = manifestURL.deletingLastPathComponent().appending(path: output.path)
        }

        return pathBoundary.relativePathIfContained(for: outputURL, projectRoot: projectRoot)
    }

    private func lvsV2Diagnostics(
        manifest: LVSArtifactManifest,
        manifestURL: URL,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> [FlowDiagnostic] {
        var diagnostics: [FlowDiagnostic] = []
        guard manifest.schemaVersion == LVSArtifactManifest.currentSchemaVersion else {
            return [lvsDiagnostic(
                code: "LVS_ARTIFACT_MANIFEST_SCHEMA_UNSUPPORTED",
                message: "LVS artifact coverage requires manifest schemaVersion \(LVSArtifactManifest.currentSchemaVersion); found \(manifest.schemaVersion)."
            )]
        }

        diagnostics.append(contentsOf: lvsRequiredOutputDiagnostics(
            manifest: manifest,
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        ))
        diagnostics.append(contentsOf: lvsContractDiagnostics(manifest: manifest))
        diagnostics.append(contentsOf: lvsSummaryLineageDiagnostics(
            manifest: manifest,
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        ))
        diagnostics.append(contentsOf: lvsOptionalArtifactLineageDiagnostics(
            manifest: manifest,
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        ))
        return diagnostics
    }

    private func lvsRequiredOutputDiagnostics(
        manifest: LVSArtifactManifest,
        manifestURL: URL,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> [FlowDiagnostic] {
        let requirements: [(id: String, kind: LVSArtifactRecord.Kind, flowArtifactID: String?)] = [
            ("report", .report, nil),
            ("manifest", .manifest, nil),
            ("lvs-correspondence", .correspondence, "lvs-correspondence"),
        ]
        var diagnostics: [FlowDiagnostic] = []
        for requirement in requirements {
            let matches = manifest.outputs.filter {
                $0.id == requirement.id && $0.kind == requirement.kind
            }
            guard matches.count == 1, let output = matches.first else {
                diagnostics.append(lvsDiagnostic(
                    code: "LVS_ARTIFACT_MANIFEST_REQUIRED_OUTPUT_INVALID",
                    message: "LVS manifest v2 requires exactly one output id=\(requirement.id) kind=\(requirement.kind.rawValue); found \(matches.count)."
                ))
                continue
            }
            guard let artifact = indexedArtifact(
                for: output,
                manifestURL: manifestURL,
                artifacts: artifacts,
                projectRoot: projectRoot
            ) else {
                continue
            }
            if let flowArtifactID = requirement.flowArtifactID,
               artifact.artifactID != flowArtifactID {
                diagnostics.append(lvsDiagnostic(
                    code: "LVS_ARTIFACT_STABLE_ID_MISMATCH",
                    message: "LVS output \(requirement.id) must be indexed with stable artifactID \(flowArtifactID); found \(artifact.artifactID ?? "missing")."
                ))
            }
            if requirement.kind != .manifest {
                if (output.byteCount ?? 0) <= 0 {
                    diagnostics.append(lvsDiagnostic(
                        code: "LVS_ARTIFACT_MANIFEST_BYTE_COUNT_MISSING",
                        message: "LVS manifest v2 output \(requirement.id) must retain a positive byte count."
                    ))
                }
                if (output.sha256 ?? "").isEmpty {
                    diagnostics.append(lvsDiagnostic(
                        code: "LVS_ARTIFACT_MANIFEST_SHA256_MISSING",
                        message: "LVS manifest v2 output \(requirement.id) must retain a SHA-256 digest."
                    ))
                }
            }
        }
        return diagnostics
    }

    private func lvsContractDiagnostics(
        manifest: LVSArtifactManifest
    ) -> [FlowDiagnostic] {
        var diagnostics: [FlowDiagnostic] = []
        let executionStatus = manifest.executionStatus
        let verdict = manifest.verdict
        let readiness = manifest.readiness
        let blockingReasons = manifest.blockingReasons
        let blocked = executionStatus != .completed || verdict == .blocked || readiness == .blocked
        if blocked {
            if verdict != .blocked || readiness != .blocked || blockingReasons.isEmpty {
                diagnostics.append(lvsDiagnostic(
                    code: "LVS_ARTIFACT_MANIFEST_READINESS_INVALID",
                    message: "A non-completed or blocked LVS result must retain blocked verdict/readiness and at least one blocking reason."
                ))
            }
        } else if !blockingReasons.isEmpty {
            diagnostics.append(lvsDiagnostic(
                code: "LVS_ARTIFACT_MANIFEST_READINESS_INVALID",
                message: "A ready LVS result cannot retain blocking reasons."
            ))
        }
        return diagnostics
    }

    private func lvsSummaryLineageDiagnostics(
        manifest: LVSArtifactManifest,
        manifestURL: URL,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> [FlowDiagnostic] {
        let summaryArtifacts = artifacts.filter { $0.artifactID == "lvs-summary" }
        guard summaryArtifacts.count == 1, let summaryArtifact = summaryArtifacts.first else {
            return [lvsDiagnostic(
                code: "LVS_SUMMARY_ARTIFACT_REQUIRED",
                message: "LVS manifest v2 requires exactly one indexed lvs-summary artifact; found \(summaryArtifacts.count)."
            )]
        }
        guard let summaryURL = containedArtifactURL(
            for: summaryArtifact,
            projectRoot: projectRoot
        ) else {
            return [lvsDiagnostic(
                code: "LVS_SUMMARY_ARTIFACT_INVALID_PATH",
                message: "The indexed LVS summary path escapes the project root."
            )]
        }

        let summary: LVSRunSummaryReport
        do {
            summary = try JSONDecoder().decode(
                LVSRunSummaryReport.self,
                from: Data(contentsOf: summaryURL)
            )
        } catch {
            return [lvsDiagnostic(
                code: "LVS_SUMMARY_ARTIFACT_UNREADABLE",
                message: "The indexed LVS summary could not be decoded: \(error.localizedDescription)"
            )]
        }

        var diagnostics: [FlowDiagnostic] = []
        if summary.schemaVersion != LVSRunSummaryReport.currentSchemaVersion {
            diagnostics.append(lvsDiagnostic(
                code: "LVS_SUMMARY_SCHEMA_UNSUPPORTED",
                message: "LVS artifact coverage requires summary schemaVersion \(LVSRunSummaryReport.currentSchemaVersion); found \(summary.schemaVersion)."
            ))
        }
        let executionStatus = manifest.executionStatus
        let verdict = manifest.verdict
        let readiness = manifest.readiness
        let blockingReasons = manifest.blockingReasons
        if summary.summary.executionStatus != executionStatus
            || summary.summary.verdict != verdict
            || summary.summary.readiness != readiness
            || summary.summary.blockingReasons != blockingReasons {
            diagnostics.append(lvsDiagnostic(
                code: "LVS_SUMMARY_READINESS_LINEAGE_MISMATCH",
                message: "LVS summary execution contract does not match the engine manifest."
            ))
        }
        let reportOutput = manifest.outputs.first { $0.id == "report" && $0.kind == .report }
        if !url(summary.reportURL, matches: reportOutput, manifestURL: manifestURL, projectRoot: projectRoot) {
            diagnostics.append(lvsDiagnostic(
                code: "LVS_SUMMARY_REPORT_LINEAGE_MISMATCH",
                message: "LVS summary reportURL does not resolve to the manifest report output."
            ))
        }
        let manifestOutput = manifest.outputs.first { $0.id == "manifest" && $0.kind == .manifest }
        if !url(summary.manifestURL, matches: manifestOutput, manifestURL: manifestURL, projectRoot: projectRoot) {
            diagnostics.append(lvsDiagnostic(
                code: "LVS_SUMMARY_MANIFEST_LINEAGE_MISMATCH",
                message: "LVS summary manifestURL does not resolve to the manifest output."
            ))
        }

        let lineageArtifacts = requiredLVSLineageArtifacts(
            manifest: manifest,
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        ) + [summaryArtifact]
        let runIDs = Set(lineageArtifacts.compactMap(\.producedByRunID))
        if lineageArtifacts.contains(where: { $0.producedByRunID == nil }) || runIDs.count != 1 {
            diagnostics.append(lvsDiagnostic(
                code: "LVS_ARTIFACT_RUN_LINEAGE_INVALID",
                message: "LVS summary, report, manifest, and correspondence must retain one common producedByRunID."
            ))
        }
        return diagnostics
    }

    private func lvsOptionalArtifactLineageDiagnostics(
        manifest: LVSArtifactManifest,
        manifestURL: URL,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> [FlowDiagnostic] {
        let manifestOutputs = manifest.outputs.filter { output in
            isOptionalLVSArtifactIdentifier(output.id)
        }
        let flowArtifacts = artifacts.filter { artifact in
            artifact.kind == .netlist
                || artifact.artifactID.map { isOptionalLVSArtifactIdentifier($0) } == true
        }
        let requiredArtifacts = requiredLVSLineageArtifacts(
            manifest: manifest,
            manifestURL: manifestURL,
            artifacts: artifacts,
            projectRoot: projectRoot
        )
        let summaryArtifacts = artifacts.filter { $0.artifactID == "lvs-summary" }
        let expectedRunIDs = Set((requiredArtifacts + summaryArtifacts).compactMap(\.producedByRunID))
        let expectedRunID = expectedRunIDs.count == 1 ? expectedRunIDs.first : nil
        var diagnostics: [FlowDiagnostic] = []
        for output in manifestOutputs {
            if (output.byteCount ?? 0) <= 0 {
                diagnostics.append(lvsDiagnostic(
                    code: "LVS_OPTIONAL_ARTIFACT_BYTE_COUNT_MISSING",
                    message: "Optional LVS output \(output.id) must retain a positive byte count."
                ))
            }
            if (output.sha256 ?? "").isEmpty {
                diagnostics.append(lvsDiagnostic(
                    code: "LVS_OPTIONAL_ARTIFACT_SHA256_MISSING",
                    message: "Optional LVS output \(output.id) must retain a SHA-256 digest."
                ))
            }
            if let artifact = indexedArtifact(
                for: output,
                manifestURL: manifestURL,
                artifacts: artifacts,
                projectRoot: projectRoot
            ) {
                diagnostics.append(contentsOf: optionalRunLineageDiagnostics(
                    artifact: artifact,
                    expectedRunID: expectedRunID
                ))
            }
        }
        for artifact in flowArtifacts {
            guard manifestOutputs.contains(where: { output in
                indexedArtifact(
                    for: output,
                    manifestURL: manifestURL,
                    artifacts: artifacts,
                    projectRoot: projectRoot
                )?.path == artifact.path
            }) else {
                diagnostics.append(lvsDiagnostic(
                    code: "LVS_OPTIONAL_ARTIFACT_MANIFEST_LINEAGE_MISSING",
                    message: "Indexed LVS artifact \(artifact.artifactID ?? artifact.path) is not retained by the engine manifest."
                ))
                continue
            }
        }
        return diagnostics
    }

    private func optionalRunLineageDiagnostics(
        artifact: XcircuiteFileReference,
        expectedRunID: String?
    ) -> [FlowDiagnostic] {
        guard let runID = artifact.producedByRunID else {
            return [lvsDiagnostic(
                code: "LVS_OPTIONAL_ARTIFACT_RUN_LINEAGE_MISSING",
                message: "Indexed LVS artifact \(artifact.artifactID ?? artifact.path) is missing producedByRunID."
            )]
        }
        guard runID == expectedRunID else {
            return [lvsDiagnostic(
                code: "LVS_OPTIONAL_ARTIFACT_RUN_LINEAGE_MISMATCH",
                message: "Indexed LVS artifact \(artifact.artifactID ?? artifact.path) does not share the summary/report/manifest/correspondence producedByRunID."
            )]
        }
        return []
    }

    private func isOptionalLVSArtifactIdentifier(_ identifier: String) -> Bool {
        let normalized = identifier.lowercased()
        return normalized.contains("extraction")
            || normalized.contains("extracted-layout")
            || normalized.contains("transform-ledger")
            || normalized.contains("transformation-ledger")
    }

    private func requiredLVSLineageArtifacts(
        manifest: LVSArtifactManifest,
        manifestURL: URL,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> [XcircuiteFileReference] {
        ["report", "manifest", "lvs-correspondence"].compactMap { id in
            guard let output = manifest.outputs.first(where: { $0.id == id }) else {
                return nil
            }
            return indexedArtifact(
                for: output,
                manifestURL: manifestURL,
                artifacts: artifacts,
                projectRoot: projectRoot
            )
        }
    }

    private func indexedArtifact(
        for output: LVSArtifactRecord,
        manifestURL: URL,
        artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> XcircuiteFileReference? {
        let record = ManifestOutputRecord(
            id: output.id,
            kind: output.kind.rawValue,
            path: output.path,
            byteCount: output.byteCount.map(Int64.init),
            sha256: output.sha256
        )
        guard let path = projectRelativePath(
            for: record,
            manifestURL: manifestURL,
            projectRoot: projectRoot
        ) else {
            return nil
        }
        return artifacts.first { $0.path == path }
    }

    private func containedArtifactURL(
        for artifact: XcircuiteFileReference,
        projectRoot: URL
    ) -> URL? {
        let url = artifact.path.hasPrefix("/")
            ? URL(filePath: artifact.path)
            : projectRoot.appending(path: artifact.path)
        return pathBoundary.contains(url, projectRoot: projectRoot) ? url : nil
    }

    private func url(
        _ url: URL?,
        matches output: LVSArtifactRecord?,
        manifestURL: URL,
        projectRoot: URL
    ) -> Bool {
        guard let url, let output else { return false }
        let record = ManifestOutputRecord(
            id: output.id,
            kind: output.kind.rawValue,
            path: output.path,
            byteCount: output.byteCount.map(Int64.init),
            sha256: output.sha256
        )
        guard let expectedPath = projectRelativePath(
            for: record,
            manifestURL: manifestURL,
            projectRoot: projectRoot
        ) else {
            return false
        }
        return pathBoundary.relativePathIfContained(for: url, projectRoot: projectRoot) == expectedPath
    }

    private func lvsDiagnostic(code: String, message: String) -> FlowDiagnostic {
        FlowDiagnostic(severity: .error, code: code, message: message)
    }
}

private struct ManifestOutputRecord: Sendable, Hashable {
    var id: String
    var kind: String
    var path: String
    var byteCount: Int64?
    var sha256: String?
}
