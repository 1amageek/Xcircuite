import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore

public struct ReleaseSignoffEvidenceAssemblyFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let assembler: any ReleaseSignoffEvidenceAssembling

    public init(
        stageID: String = "release.evidence-assembly",
        toolID: String = "xcircuite.release-evidence-assembler",
        requestInput: XcircuiteFlowInputReference,
        assembler: any ReleaseSignoffEvidenceAssembling = DefaultReleaseSignoffEvidenceAssembler()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.assembler = assembler
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            guard stage.stageID == stageID else {
                throw XcircuiteRuntimeError.stageMismatch(
                    expected: stageID,
                    actual: stage.stageID
                )
            }
            try FlowIdentifierValidator().validate(stageID, kind: .stageID)
            try FlowIdentifierValidator().validate(toolID, kind: .toolID)
            let projectRoot = try context.xcircuiteProjectRoot()
            let requestArtifact = try requestInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: try context.xcircuiteRunDirectory(),
                artifactID: "release-signoff-evidence-assembly-request",
                kind: .request,
                format: .json
            )
            let requestURL = try requestArtifact.locator.location.resolvedFileURL(
                relativeTo: projectRoot
            )
            let requestData = try Data(contentsOf: requestURL)
            let retainedRequest = try await context.persistArtifact(
                requestData,
                artifactID: "release-signoff-evidence-assembly-request",
                stageID: stageID,
                fileName: "request.json",
                role: .input,
                kind: .request,
                format: .json,
                mode: .immutable
            )
            let request = try JSONDecoder().decode(
                ReleaseSignoffEvidenceAssemblyRequest.self,
                from: requestData
            )
            guard request.runID == context.runID else {
                return blocked(
                    code: "RELEASE_EVIDENCE_RUN_ID_MISMATCH",
                    message: "Release evidence assembly request does not match the flow run."
                )
            }
            let records = try await assembler.assemble(
                request,
                reading: context.infrastructure
            )
            try await context.checkCancellation()
            let producer = try ProducerIdentity(
                kind: .engine,
                identifier: toolID,
                version: "1.0.0"
            )
            let recordsArtifact = try await context.persistJSONArtifact(
                records,
                artifactID: "release-signoff-evidence-records",
                stageID: stageID,
                fileName: "release-signoff-evidence-records.json",
                kind: .release,
                producer: producer,
                mode: .immutable
            )
            let diagnostics = records.compactMap(diagnostic)
            let gateStatus: FlowGateStatus
            let stageStatus: FlowStageStatus
            if records.contains(where: { $0.disposition == .blocked }) {
                gateStatus = .blocked
                stageStatus = .blocked
            } else if records.contains(where: { $0.disposition == .failed }) {
                gateStatus = .failed
                stageStatus = .failed
            } else {
                gateStatus = .passed
                stageStatus = .succeeded
            }
            let sourceArtifacts = request.sources.flatMap(\.allArtifacts)
            let artifacts = uniqueArtifacts(
                [retainedRequest, recordsArtifact, request.designArtifact, request.pdkArtifact]
                    + sourceArtifacts
            )
            let integrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: projectRoot
            )
            let finalStatus = integrityGate.status == .passed ? stageStatus : .failed
            let finalGate = integrityGate.status == .passed ? gateStatus : .failed
            return FlowStageResult(
                stageID: stageID,
                status: finalStatus,
                diagnostics: diagnostics + integrityGate.diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "release-evidence-assembly",
                        status: finalGate,
                        diagnostics: diagnostics
                    ),
                    integrityGate,
                ],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as ReleaseSignoffEvidenceAssemblyError {
            return blocked(
                code: "RELEASE_EVIDENCE_ASSEMBLY_BLOCKED",
                message: error.localizedDescription
            )
        } catch {
            return failed(
                code: "RELEASE_EVIDENCE_ASSEMBLY_FAILED",
                message: error.localizedDescription
            )
        }
    }

    private func diagnostic(
        _ record: ReleaseSignoffEvidenceReference
    ) -> FlowDiagnostic? {
        guard record.disposition != .passed else {
            return nil
        }
        return FlowDiagnostic(
            severity: .error,
            code: record.disposition == .blocked
                ? "RELEASE_EVIDENCE_SOURCE_BLOCKED"
                : "RELEASE_EVIDENCE_SOURCE_FAILED",
            message: "\(record.axis.rawValue): \(record.reason ?? "producer did not pass")"
        )
    }

    private func blocked(code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [
                FlowGateResult(
                    gateID: "release-evidence-assembly",
                    status: .blocked,
                    diagnostics: [diagnostic]
                ),
            ]
        )
    }

    private func failed(code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [
                FlowGateResult(
                    gateID: "release-evidence-assembly",
                    status: .failed,
                    diagnostics: [diagnostic]
                ),
            ]
        )
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }
}
