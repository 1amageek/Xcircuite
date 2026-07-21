import Foundation

struct ReleaseOperatingCornerQualificationValidator: Sendable {
    func validate(
        requiredCornerIDs: [String],
        qualifiedCornerIDs: [String],
        producer: ReleaseSignoffEvidenceProducer
    ) throws {
        let required = Set(requiredCornerIDs)
        guard !required.isEmpty else {
            throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                "\(producer.rawValue) release evidence must declare operating corners"
            )
        }
        let qualified = Set(qualifiedCornerIDs)
        guard required.isSubset(of: qualified) else {
            let missing = required.subtracting(qualified).sorted().joined(separator: ", ")
            throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                "\(producer.rawValue) qualification is missing operating corners: \(missing)"
            )
        }
    }
}
