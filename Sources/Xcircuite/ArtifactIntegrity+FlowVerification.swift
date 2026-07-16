import CircuiteFoundation
import DesignFlowKernel

extension ArtifactIntegrity {
    var flowVerificationStatus: FlowArtifactVerificationStatus {
        switch issues.first?.code {
        case .missingFile:
            .missingArtifact
        case .notRegularFile, .unreadableFile:
            .unreadableArtifact
        case .byteCountMismatch:
            .byteCountMismatch
        case .digestMismatch:
            .sha256Mismatch
        case .invalidLocation:
            .invalidPath
        case .unsupportedDigestAlgorithm:
            .invalidDigest
        case nil:
            .verified
        }
    }

    var diagnosticMessage: String {
        issues.map { issue in
            issue.detail ?? issue.location ?? issue.code.rawValue
        }.joined(separator: "; ")
    }
}
