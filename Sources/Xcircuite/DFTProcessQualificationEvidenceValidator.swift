import DFTCore
import Foundation
import ToolQualification
import XcircuitePackage

public struct DFTProcessQualificationEvidenceValidator: DFTProcessQualificationEvidenceValidating {
    public init() {}

    public func validate(
        _ evidence: ToolProcessQualificationEvidence,
        request: DFTRequest,
        result: XcircuiteEngineResultEnvelope<DFTPayload>,
        at date: Date
    ) throws {
        guard evidence.isStructurallyValid else {
            throw DFTProcessQualificationEvidenceValidationError.structurallyInvalid
        }

        var reasons: [String] = []
        if evidence.status != .qualified {
            reasons.append("status-\(evidence.status.rawValue)")
        }
        if !evidence.scope.isCompleteForPDK {
            reasons.append("pdk-scope-incomplete")
        }
        if !evidence.independenceVerified {
            reasons.append("independence-unverified")
        }
        if !evidence.blockers.isEmpty {
            reasons.append(contentsOf: evidence.blockers.map { "blocker-\($0)" })
        }
        if !evidence.isFresh(at: date) {
            reasons.append("evidence-expired-or-not-yet-valid")
        }
        guard evidence.isQualified(at: date, requirePDKScope: true) else {
            throw DFTProcessQualificationEvidenceValidationError.notQualified(
                reasons: Array(Set(reasons)).sorted()
            )
        }

        guard evidence.toolID == result.metadata.engineID else {
            throw DFTProcessQualificationEvidenceValidationError.toolMismatch(
                expected: result.metadata.engineID,
                actual: evidence.toolID
            )
        }
        guard evidence.scope.implementationID == result.metadata.implementationID else {
            throw DFTProcessQualificationEvidenceValidationError.implementationMismatch(
                expected: result.metadata.implementationID,
                actual: evidence.scope.implementationID
            )
        }
        guard evidence.scope.processProfileID == request.pdk.processID else {
            throw DFTProcessQualificationEvidenceValidationError.processMismatch(
                expected: request.pdk.processID,
                actual: evidence.scope.processProfileID
            )
        }
        guard evidence.scope.pdkDigest?.caseInsensitiveCompare(request.pdk.digest) == .orderedSame else {
            throw DFTProcessQualificationEvidenceValidationError.pdkMismatch(
                expected: request.pdk.digest,
                actual: evidence.scope.pdkDigest ?? ""
            )
        }
    }
}
