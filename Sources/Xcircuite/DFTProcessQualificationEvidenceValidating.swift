import DFTCore
import Foundation
import ToolQualification

public protocol DFTProcessQualificationEvidenceValidating: Sendable {
    func validate(
        _ evidence: ToolProcessQualificationEvidence,
        request: DFTRequest,
        result: DFTResult,
        at date: Date
    ) throws
}
