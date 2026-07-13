import Foundation
import QualificationEngine
import ToolQualification
import XcircuitePackage

struct StubReleaseQualificationEvaluator: ReleaseQualificationEvaluating {
    func execute(
        _ request: ReleaseQualificationRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ReleaseQualificationPayload> {
        let now = Date()
        let payload = ReleaseQualificationPayload(
            qualified: true,
            processProfileID: request.processProfileID,
            qualificationLevel: .corpusChecked,
            qualificationScope: nil,
            qualificationDigest: String(repeating: "a", count: 64),
            promotionStatus: .corpusChecked
        )
        return XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: request.runID,
            status: .completed,
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "release-qualification",
                implementationID: "stub-release-qualification",
                implementationVersion: "1.0.0",
                startedAt: now,
                completedAt: now
            ),
            payload: payload
        )
    }
}
