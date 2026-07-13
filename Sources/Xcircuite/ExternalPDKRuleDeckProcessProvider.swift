import Foundation
import CircuiteFoundation
import PDKKit

public struct ExternalPDKRuleDeckProcessProvider: PDKExternalRuleDeckResultProviding {
    private let support: PDKExternalInspectionProcessProviderSupport

    public init(
        configuration: PDKExternalInspectionProcessConfiguration,
        stageID: String = PDKKitAPI.ruleDeckInspectionStageID,
        runner: any PDKExternalInspectionProcessRunning = TimedPDKExternalInspectionProcessRunner()
    ) {
        self.support = PDKExternalInspectionProcessProviderSupport(
            configuration: configuration,
            stageID: stageID,
            runner: runner
        )
    }

    public func resultData(
        for request: PDKRuleDeckInspectionRequest
    ) async throws -> Data {
        let run = try await support.execute(
            request: request,
            runID: request.runID,
            assetID: request.assetID,
            projectRootPath: request.projectRootPath
        )
        if let failure = run.failure {
            return try failureResult(
                request: request,
                artifacts: run.artifacts,
                finding: PDKValidationFinding(
                    severity: .error,
                    code: "pdk.external.process-execution-failed",
                    message: failure.localizedDescription,
                    entity: request.assetID,
                    suggestedActions: ["inspect_external_process_artifacts", "repair_external_process"]
                )
            )
        }
        do {
            return try support.appendArtifacts(
                to: run.resultData ?? Data(),
                artifacts: run.artifacts,
                as: PDKRuleDeckInspectionResult.self
            )
        } catch {
            return try failureResult(
                request: request,
                artifacts: run.artifacts,
                finding: PDKValidationFinding(
                    severity: .error,
                    code: "pdk.external.process-result-invalid",
                    message: "External process result could not be decoded: " + error.localizedDescription,
                    entity: request.assetID,
                    suggestedActions: ["inspect_external_process_artifacts", "repair_external_result"]
                )
            )
        }
    }

    private func failureResult(
        request: PDKRuleDeckInspectionRequest,
        artifacts: [ArtifactReference],
        finding: PDKValidationFinding
    ) throws -> Data {
        let result = PDKRuleDeckInspectionResult(
            schemaVersion: PDKRuleDeckInspectionRequest.currentSchemaVersion,
            runID: request.runID,
            status: .failed,
            diagnostics: [PDKStandardViewDiagnosticMapper.map(finding)],
            artifacts: artifacts.map(\.locator),
            metadata: PDKExecutionMetadata(
                engineID: "PDKRuleDeckInspection",
                implementationID: "ExternalPDKRuleDeckProcessProvider",
                implementationVersion: "1",
                startedAt: Date(),
                completedAt: Date()
            ),
            payload: PDKRuleDeckInspectionPayload(
                isValid: false,
                assetID: request.assetID,
                pdkDigest: request.pdk.digest,
                findings: [finding],
                limitations: [
                    "The external process did not produce an accepted rule-deck result.",
                    "Process execution and tool qualification remain separate evidence gates."
                ]
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }
}
