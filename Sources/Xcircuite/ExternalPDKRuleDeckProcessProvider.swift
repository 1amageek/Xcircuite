import Foundation
import CircuiteFoundation
import PDKCore
import PDKKit
import PDKStandardViews
import PDKValidation

public struct ExternalPDKRuleDeckProcessProvider: PDKExternalRuleDeckResultProviding {
    private let support: PDKExternalInspectionProcessProviderSupport

    public init(
        configuration: PDKExternalInspectionProcessConfiguration,
        stageID: String = PDKOperation.ruleDeckInspection.rawValue,
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
                provenance: run.provenance,
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
                provenance: run.provenance,
                as: PDKRuleDeckInspectionResult.self
            )
        } catch {
            return try failureResult(
                request: request,
                artifacts: run.artifacts,
                provenance: run.provenance,
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
        provenance: ExecutionProvenance,
        finding: PDKValidationFinding
    ) throws -> Data {
        let result = PDKRuleDeckInspectionResult(
            schemaVersion: PDKRuleDeckInspectionRequest.currentSchemaVersion,
            runID: request.runID,
            status: .failed,
            diagnostics: [PDKStandardViewDiagnosticMapper.map(finding)],
            artifacts: artifacts,
            provenance: provenance,
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
