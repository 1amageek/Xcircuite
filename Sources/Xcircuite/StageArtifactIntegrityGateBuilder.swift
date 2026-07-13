import Foundation
import CircuiteFoundation
import DesignFlowKernel

struct StageArtifactIntegrityGateBuilder: Sendable {
    private let foundationVerifier: LocalArtifactVerifier

    init(
        foundationVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.foundationVerifier = foundationVerifier
    }

    func gate(
        for artifacts: [ArtifactReference],
        projectRoot: URL
    ) -> FlowGateResult {
        let diagnostics = diagnostics(for: artifacts, projectRoot: projectRoot).map(flowDiagnostic)

        return FlowGateResult(
            gateID: "artifact-integrity",
            status: diagnostics.isEmpty ? .passed : .failed,
            diagnostics: diagnostics
        )
    }

    func diagnostics(
        for artifacts: [ArtifactReference],
        projectRoot: URL
    ) -> [DesignDiagnostic] {
        artifacts.compactMap { artifact -> DesignDiagnostic? in
            let integrity = foundationVerifier.verify(artifact, relativeTo: projectRoot)
            guard !integrity.isVerified else {
                return nil
            }
            let details = integrity.issues.map { issue -> String in
                switch issue.code {
                case .byteCountMismatch:
                    let expected = issue.expectedByteCount.map(String.init) ?? "unknown"
                    let actual = issue.actualByteCount.map(String.init) ?? "unknown"
                    return "byteCount expected=\(expected) actual=\(actual)"
                case .digestMismatch:
                    let expected = issue.expectedDigest?.hexadecimalValue ?? "unknown"
                    let actual = issue.actualDigest?.hexadecimalValue ?? "unknown"
                    return "digest expected=\(expected) actual=\(actual)"
                default:
                    return issue.detail ?? issue.code.rawValue
                }
            }.joined(separator: "; ")
            return DesignDiagnostic(
                code: .trusted(foundationDiagnosticCode(for: integrity)),
                severity: .error,
                summary: "Artifact integrity verification failed.",
                detail: "artifactID=\(artifact.id.rawValue) path=\(artifact.path) \(details)",
                artifactID: artifact.id
            )
        }
    }

    private func flowDiagnostic(_ diagnostic: DesignDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .error,
            code: diagnostic.code.rawValue,
            message: [diagnostic.summary, diagnostic.detail].compactMap { $0 }.joined(separator: " ")
        )
    }

    private func foundationDiagnosticCode(for integrity: ArtifactIntegrity) -> String {
        guard let issue = integrity.issues.first else {
            return "ARTIFACT_INTEGRITY_VERIFIED"
        }
        return switch issue.code {
        case .missingFile: "ARTIFACT_INTEGRITY_MISSING_ARTIFACT"
        case .notRegularFile: "ARTIFACT_INTEGRITY_NOT_REGULAR_FILE"
        case .byteCountMismatch: "ARTIFACT_INTEGRITY_BYTE_COUNT_MISMATCH"
        case .digestMismatch: "ARTIFACT_INTEGRITY_SHA256_MISMATCH"
        case .invalidLocation: "ARTIFACT_INTEGRITY_INVALID_PATH"
        case .unreadableFile: "ARTIFACT_INTEGRITY_UNREADABLE_ARTIFACT"
        case .unsupportedDigestAlgorithm: "ARTIFACT_INTEGRITY_UNSUPPORTED_DIGEST"
        }
    }

}
