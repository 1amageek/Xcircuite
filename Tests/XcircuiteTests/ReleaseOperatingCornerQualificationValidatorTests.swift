import Testing
@testable import Xcircuite

@Suite("Release operating-corner qualification")
struct ReleaseOperatingCornerQualificationValidatorTests {
    @Test("accepts only complete requested-corner coverage")
    func acceptsCompleteCoverage() throws {
        try ReleaseOperatingCornerQualificationValidator().validate(
            requiredCornerIDs: ["tt", "ss", "ff"],
            qualifiedCornerIDs: ["ff", "ss", "tt", "fs"],
            producer: .parasiticExtraction
        )
    }

    @Test("rejects missing corner qualification")
    func rejectsMissingCoverage() {
        #expect(throws: ReleaseSignoffEvidenceAssemblyError.self) {
            try ReleaseOperatingCornerQualificationValidator().validate(
                requiredCornerIDs: ["tt", "ss", "ff"],
                qualifiedCornerIDs: ["tt", "ff"],
                producer: .staticTiming
            )
        }
    }

    @Test("rejects an implicit default corner")
    func rejectsImplicitCorner() {
        #expect(throws: ReleaseSignoffEvidenceAssemblyError.self) {
            try ReleaseOperatingCornerQualificationValidator().validate(
                requiredCornerIDs: [],
                qualifiedCornerIDs: ["tt"],
                producer: .electricalSignoff
            )
        }
    }
}
