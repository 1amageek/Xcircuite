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
        manifestGate(
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
}

private struct ManifestOutputRecord: Sendable, Hashable {
    var id: String
    var kind: String
    var path: String
    var byteCount: Int64?
    var sha256: String?
}
