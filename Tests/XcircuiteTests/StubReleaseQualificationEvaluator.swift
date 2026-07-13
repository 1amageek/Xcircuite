import Foundation
import QualificationEngine
import ToolQualification
import DesignFlowKernel
import CircuiteFoundation

struct StubReleaseQualificationEvaluator: ReleaseQualificationEvaluating {
    func execute(
        _ request: ReleaseQualificationRequest
    ) async throws -> ReleaseQualificationResult {
        let now = Date()
        let payload = ReleaseQualificationPayload(
            qualified: true,
            processProfileID: request.processProfileID,
            qualificationLevel: .corpusChecked,
            qualificationScope: nil,
            qualificationDigest: String(repeating: "a", count: 64),
            promotionStatus: .corpusChecked
        )
        return ReleaseQualificationResult(
            schemaVersion: 1,
            runID: request.runID,
            status: .completed,
            metadata: try ExecutionProvenance(
                producer: try ProducerIdentity(
                    kind: .engine,
                    identifier: "stub-release-qualification",
                    version: "1.0.0"
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: payload
        )
    }
}
