import DesignFlowKernel
import Foundation
import XcircuitePackage

struct StageArtifactIntegrityGateBuilder: Sendable {
    private let verifier: XcircuiteFileReferenceVerifier

    init(verifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()) {
        self.verifier = verifier
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
