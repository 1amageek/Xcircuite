import DFTCore
import Foundation
import ToolQualification
import XcircuitePackage

public protocol DFTProcessQualificationEvidenceValidating: Sendable {
    func validate(
        _ evidence: ToolProcessQualificationEvidence,
        request: DFTRequest,
        result: XcircuiteEngineResultEnvelope<DFTPayload>,
        at date: Date
    ) throws
}
