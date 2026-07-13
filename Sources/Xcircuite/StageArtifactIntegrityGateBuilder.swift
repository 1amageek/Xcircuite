import Foundation
import CircuiteFoundation
import DesignFlowKernel

struct StageArtifactIntegrityGateBuilder: Sendable {
    private let verifier: XcircuiteFileReferenceVerifier
    private let foundationVerifier: LocalArtifactVerifier

    init(
        verifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier(),
        foundationVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.verifier = verifier
        self.foundationVerifier = foundationVerifier
    }

    func gate(
        for artifacts: [ArtifactReference],
        projectRoot: URL
    ) -> FlowGateResult {
        let diagnostics = artifacts.compactMap { artifact -> FlowDiagnostic? in
            let integrity = foundationVerifier.verify(artifact, relativeTo: projectRoot)
            guard !integrity.isVerified else {
                return nil
            }
            return diagnostic(for: artifact, integrity: integrity)
        }

        return FlowGateResult(
            gateID: "artifact-integrity",
            status: diagnostics.isEmpty ? .passed : .failed,
            diagnostics: diagnostics
        )
    }

    func gate(
        for artifacts: [XcircuiteFileReference],
        projectRoot: URL
    ) -> FlowGateResult {
        let diagnostics = artifacts.compactMap { artifact -> FlowDiagnostic? in
            let integrity = verifier.verify(artifact, projectRoot: projectRoot)
            guard integrity.status != .verified else {
                return nil
            }
            return diagnostic(for: artifact, integrity: integrity)
        }

        return FlowGateResult(
            gateID: "artifact-integrity",
            status: diagnostics.isEmpty ? .passed : .failed,
            diagnostics: diagnostics
        )
    }

    private func diagnostic(
        for artifact: ArtifactReference,
        integrity: ArtifactIntegrity
    ) -> FlowDiagnostic {
        let details = integrity.issues.map { issue -> String in
            switch issue.code {
            case .byteCountMismatch:
                return "byteCount expected=\(issue.expectedByteCount.map(String.init) ?? "unknown") actual=\(issue.actualByteCount.map(String.init) ?? "unknown")"
            case .digestMismatch:
                return "digest expected=\(issue.expectedDigest?.hexadecimalValue ?? "unknown") actual=\(issue.actualDigest?.hexadecimalValue ?? "unknown")"
            default:
                return issue.detail ?? issue.code.rawValue
            }
        }.joined(separator: "; ")
        return FlowDiagnostic(
            severity: .error,
            code: foundationDiagnosticCode(for: integrity),
            message: "Artifact integrity verification failed. artifactID=\(artifact.id.rawValue) path=\(artifact.path) \(details)"
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

    private func diagnostic(
        for artifact: XcircuiteFileReference,
        integrity: XcircuiteFileReferenceIntegrity
    ) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .error,
            code: diagnosticCode(for: integrity.status),
            message: diagnosticMessage(for: artifact, integrity: integrity)
        )
    }

    private func diagnosticCode(for status: XcircuiteFileReferenceIntegrityStatus) -> String {
        switch status {
        case .verified:
            "ARTIFACT_INTEGRITY_VERIFIED"
        case .missingArtifact:
            "ARTIFACT_INTEGRITY_MISSING_ARTIFACT"
        case .missingDigest:
            "ARTIFACT_INTEGRITY_MISSING_DIGEST"
        case .missingByteCount:
            "ARTIFACT_INTEGRITY_MISSING_BYTE_COUNT"
        case .invalidDigest:
            "ARTIFACT_INTEGRITY_INVALID_DIGEST"
        case .invalidByteCount:
            "ARTIFACT_INTEGRITY_INVALID_BYTE_COUNT"
        case .byteCountMismatch:
            "ARTIFACT_INTEGRITY_BYTE_COUNT_MISMATCH"
        case .sha256Mismatch:
            "ARTIFACT_INTEGRITY_SHA256_MISMATCH"
        case .invalidPath:
            "ARTIFACT_INTEGRITY_INVALID_PATH"
        case .unreadableArtifact:
            "ARTIFACT_INTEGRITY_UNREADABLE_ARTIFACT"
        }
    }

    private func diagnosticMessage(
        for artifact: XcircuiteFileReference,
        integrity: XcircuiteFileReferenceIntegrity
    ) -> String {
        var parts = [
            "Artifact integrity verification failed.",
            "artifactID=\(artifact.artifactID ?? artifact.path)",
            "path=\(artifact.path)",
            "status=\(integrity.status.rawValue)",
            integrity.message,
        ]

        if let expectedByteCount = integrity.expectedByteCount {
            parts.append("expectedByteCount=\(expectedByteCount)")
        }
        if let actualByteCount = integrity.actualByteCount {
            parts.append("actualByteCount=\(actualByteCount)")
        }
        if let expectedSHA256 = integrity.expectedSHA256 {
            parts.append("expectedSHA256=\(expectedSHA256)")
        }
        if let actualSHA256 = integrity.actualSHA256 {
            parts.append("actualSHA256=\(actualSHA256)")
        }
        return parts.joined(separator: " ")
    }
}
