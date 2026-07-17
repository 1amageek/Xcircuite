import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicEvidence
import LogicSimulation
import LogicSynthesis
import PDKCore
import RTLVerificationCore
import Testing
import TimingCore
import ToolQualification
@testable import Xcircuite

@Suite("LogicEngine flow stage executors")
struct LogicEngineFlowStageExecutorTests {
    @Test("evidence validation blocks release without process evidence", .timeLimit(.minutes(1)))
    func evidenceValidationRequiresProcessEvidence() async throws {
        let root = try makeRoot(name: "logic-evidence-validation-stage")
        defer { removeRoot(root) }
        let report = LogicEvidenceReport(
            suiteID: "validation-suite",
            implementationID: "native-logic-engine",
            implementationVersion: "1",
            state: .oracleCorrelated,
            evaluations: [LogicEvidenceCaseEvaluation(
                caseID: "case",
                observedStatus: .completed,
                observedDiagnosticCodes: [],
                observedArtifactIDs: ["logic-report"],
                mismatches: []
            )],
            blockers: ["process_qualification_required"],
            oracleCorrelation: LogicEvidenceOracleCorrelationReport(
                suiteID: "validation-suite",
                nativeImplementationID: "native-logic-engine",
                oracleImplementationID: "reference-oracle",
                matchedCaseIDs: ["case"]
            )
        )
        let reportReference = try writeJSON(
            report,
            name: "logic-evidence-validation-report.json",
            root: root,
            kind: .report
        )
        let context = try await makeContext(root: root, runID: "logic-evidence-validation-stage")
        let result = try await LogicEvidenceValidationFlowStageExecutor(
            reportInput: .path(reportReference.locator.location.value)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.evidence-validation", displayName: "Logic evidence validation"),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(
            result.diagnostics.contains { $0.code == "LOGIC_EVIDENCE_VALIDATION_PROCESS_REQUIRED" },
            "Diagnostics: \(result.diagnostics)"
        )
        #expect(result.artifacts.contains { $0.artifactID == "logic-evidence-validation-result" })
    }

    @Test("evidence validation rejects a forged release report", .timeLimit(.minutes(1)))
    func evidenceValidationRejectsForgedReleaseReport() async throws {
        let root = try makeRoot(name: "logic-evidence-validation-forged-report")
        defer { removeRoot(root) }
        let report = LogicEvidenceReport(
            suiteID: "validation-suite",
            implementationID: "native-logic-engine",
            implementationVersion: "1",
            state: .oracleCorrelated,
            evaluations: [LogicEvidenceCaseEvaluation(
                caseID: "case",
                observedStatus: .completed,
                observedDiagnosticCodes: [],
                observedArtifactIDs: ["logic-report"],
                mismatches: []
            )]
        )
        let reportReference = try writeJSON(
            report,
            name: "forged-logic-evidence-validation-report.json",
            root: root,
            kind: .report
        )
        let context = try await makeContext(root: root, runID: "logic-evidence-validation-forged-report")
        let result = try await LogicEvidenceValidationFlowStageExecutor(
            reportInput: .path(reportReference.locator.location.value)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.evidence-validation", displayName: "Logic evidence validation"),
            context: context
        )

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code == "LOGIC_EVIDENCE_VALIDATION_ARTIFACT_INVALID" })
    }

    @Test("lowering stage converts a canonical RTL snapshot into an execution artifact", .timeLimit(.minutes(1)))
    func loweringStageExecutor() async throws {
        let root = try makeRoot(name: "logic-lowering-stage")
        defer { removeRoot(root) }
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(
                topModuleName: "flow_top",
                modules: [RTLModule(
                    id: "module-top",
                    name: "flow_top",
                    ports: [
                        RTLPort(id: "a", name: "a", direction: .input),
                        RTLPort(id: "y", name: "y", direction: .output),
                    ],
                    assignments: [RTLAssignment(
                        id: "assignment-y",
                        target: .identifier("y"),
                        value: .identifier("a")
                    )]
                )]
            )
        ))
        let snapshotReference = try writeJSON(snapshot, name: "rtl-snapshot.json", root: root, kind: .rtl)
        let snapshotRevision: ContentDigest?
        if let digest = snapshot.designDigest {
            snapshotRevision = try ContentDigest(algorithm: .sha256, hexadecimalValue: digest)
        } else {
            snapshotRevision = nil
        }
        let request = LogicLoweringRequest(
            runID: "logic-lowering-stage",
            inputs: [snapshotReference],
            design: LogicDesignArtifact(
                artifact: snapshotReference,
                topDesignName: "flow_top",
                designRevision: snapshotRevision
            )
        )
        let requestPath = try writeRequest(request, name: "lowering-request.json", root: root)
        let context = try await makeContext(root: root, runID: request.runID)
        let result = try await LogicLoweringFlowStageExecutor(
            requestInput: .path(requestPath)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.lower", displayName: "Logic lowering"),
            context: context
        )

        #expect(result.status == .succeeded, "Diagnostics: \(result.diagnostics)")
        #expect(result.artifacts.contains { $0.artifactID == "logic-execution-design" })
        #expect(result.artifacts.contains { $0.artifactID == "logic-lowering-result" })
    }

    @Test("simulation stage executes the native engine and persists artifacts", .timeLimit(.minutes(1)))
    func simulationStageExecutor() async throws {
        let root = try makeRoot(name: "logic-simulation-stage")
        defer { removeRoot(root) }
        let designReference = try writeDesign(to: root)
        let stimulusReference = try writeStimulus(to: root)
        let request = LogicSimulationRequest(
            runID: "logic-simulation-stage",
            inputs: [designReference.artifact, stimulusReference],
            design: designReference,
            stimulus: stimulusReference
        )
        let requestPath = try writeRequest(request, name: "simulation-request.json", root: root)
        let context = try await makeContext(root: root, runID: request.runID)
        let result = try await LogicSimulationFlowStageExecutor(
            requestInput: .path(requestPath)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.simulate", displayName: "Logic simulation"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.contains { $0.status == .passed })
        #expect(result.artifacts.contains { $0.artifactID == "logic-waveform" })
        #expect(result.artifacts.contains { $0.artifactID == "logic-simulation-result" })
    }

    @Test("simulation stage preserves signed arithmetic semantics", .timeLimit(.minutes(1)))
    func signedSimulationStageExecutor() async throws {
        let root = try makeRoot(name: "logic-signed-simulation-stage")
        defer { removeRoot(root) }
        let document = LogicDesignDocument(
            topDesignName: "signed_flow_top",
            ports: [
                LogicPort(name: "a", direction: .input, width: 4),
                LogicPort(name: "b", direction: .input, width: 2),
                LogicPort(name: "sum", direction: .output, width: 4),
            ],
            signals: [
                LogicSignal(name: "a", width: 4, isSigned: true),
                LogicSignal(name: "b", width: 2, isSigned: true),
                LogicSignal(name: "sum", width: 4, isSigned: true),
            ],
            nodes: [LogicNode(
                id: "signed-add",
                kind: .add,
                inputs: ["a", "b"],
                outputs: ["sum"],
                parameters: ["signed": "true"]
            )]
        )
        let designReference = try writeJSON(document, name: "signed-design.json", root: root, kind: .netlist)
        let design = LogicDesignArtifact(
            artifact: designReference,
            topDesignName: document.topDesignName,
            designRevision: designReference.digest
        )
        let stimulus = LogicStimulusDocument(
            events: [LogicStimulusEvent(time: 0, assignments: [
                "a": try LogicVector(string: "1100"),
                "b": try LogicVector(string: "01"),
            ])],
            assertions: [LogicAssertion(
                id: "signed-sum",
                time: 0,
                signal: "sum",
                expected: try LogicVector(string: "1101")
            )]
        )
        let stimulusReference = try writeJSON(stimulus, name: "signed-stimulus.json", root: root, kind: .testPattern)
        let request = LogicSimulationRequest(
            runID: "logic-signed-simulation-stage",
            inputs: [designReference, stimulusReference],
            design: design,
            stimulus: stimulusReference
        )
        let requestPath = try writeRequest(request, name: "signed-simulation-request.json", root: root)
        let context = try await makeContext(root: root, runID: request.runID)
        let result = try await LogicSimulationFlowStageExecutor(
            requestInput: .path(requestPath)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.simulate", displayName: "Logic simulation"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.artifacts.contains { $0.artifactID == "logic-waveform" })
        #expect(result.artifacts.contains { $0.artifactID == "logic-simulation-result" })
    }

    @Test("synthesis stage preserves equivalence-required provenance", .timeLimit(.minutes(1)))
    func synthesisStageExecutor() async throws {
        let root = try makeRoot(name: "logic-synthesis-stage")
        defer { removeRoot(root) }
        let designReference = try writeDesign(to: root)
        let library = try writeTextJSON(
            "{\"schemaVersion\":1,\"libraryName\":\"flow-stage\",\"cells\":[{\"name\":\"AND2_X1\",\"kind\":\"and\",\"inputCount\":2,\"area\":1.0,\"power\":0.1,\"driveStrength\":1}]}",
            name: "logic-cells.json",
            root: root,
            kind: .timingLibrary
        )
        let constraints = try writeTextJSON(
            "{\"schemaVersion\":1,\"maximumArea\":2.0}",
            name: "logic-constraints.json",
            root: root,
            kind: .constraint
        )
        let pdk = try writeTextJSON(
            "{\"processID\":\"fixture\",\"version\":\"1\"}",
            name: "pdk.json",
            root: root,
            kind: .technology
        )
        let pdkDigest = pdk.digest.hexadecimalValue
        let request = LogicSynthesisRequest(
            runID: "logic-synthesis-stage",
            inputs: [designReference.artifact, library, constraints, pdk],
            design: designReference,
            libraries: [TimingLibraryReference(artifact: library, cornerIDs: ["typical"])],
            constraints: constraints,
            pdk: PDKReference(manifest: pdk, processID: "fixture", version: "1", digest: pdkDigest)
        )
        let requestPath = try writeRequest(request, name: "synthesis-request.json", root: root)
        let context = try await makeContext(root: root, runID: request.runID)
        let result = try await LogicSynthesisFlowStageExecutor(
            requestInput: .path(requestPath)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.synthesize", displayName: "Logic synthesis"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.artifacts.contains { $0.artifactID == "mapped-design" })
        #expect(result.artifacts.contains { $0.artifactID == "logic-synthesis-provenance" })
        #expect(result.artifacts.contains { $0.artifactID == "logic-equivalence-request" })
        #expect(result.artifacts.contains { $0.artifactID == "logic-synthesis-result" })
    }

    @Test("equivalence stage proves mapped synthesis and emits acceptance evidence", .timeLimit(.minutes(1)))
    func equivalenceStageExecutor() async throws {
        let root = try makeRoot(name: "logic-equivalence-stage")
        defer { removeRoot(root) }
        let designReference = try writeDesign(to: root)
        let library = try writeTextJSON(
            "{\"schemaVersion\":1,\"libraryName\":\"flow-stage\",\"cells\":[{\"name\":\"AND2_X1\",\"kind\":\"and\",\"inputCount\":2,\"area\":1.0,\"power\":0.1,\"driveStrength\":1}]}",
            name: "equivalence-cells.json",
            root: root,
            kind: .timingLibrary
        )
        let constraints = try writeTextJSON(
            "{\"schemaVersion\":1,\"maximumArea\":2.0}",
            name: "equivalence-constraints.json",
            root: root,
            kind: .constraint
        )
        let pdk = try writeTextJSON(
            "{\"processID\":\"fixture\",\"version\":\"1\"}",
            name: "equivalence-pdk.json",
            root: root,
            kind: .technology
        )
        let pdkDigest = pdk.digest.hexadecimalValue
        let synthesisRequest = LogicSynthesisRequest(
            runID: "logic-equivalence-stage",
            inputs: [designReference.artifact, library, constraints, pdk],
            design: designReference,
            libraries: [TimingLibraryReference(artifact: library, cornerIDs: ["typical"])],
            constraints: constraints,
            pdk: PDKReference(manifest: pdk, processID: "fixture", version: "1", digest: pdkDigest)
        )
        let synthesisRequestPath = try writeRequest(
            synthesisRequest,
            name: "equivalence-synthesis-request.json",
            root: root
        )
        let context = try await makeContext(root: root, runID: synthesisRequest.runID)
        let synthesisResult = try await LogicSynthesisFlowStageExecutor(
            requestInput: .path(synthesisRequestPath)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.synthesize", displayName: "Logic synthesis"),
            context: context
        )
        let equivalenceRequestReference = try #require(
            synthesisResult.artifacts.first { $0.artifactID == "logic-equivalence-request" }
        )

        let equivalenceResult = try await LogicEquivalenceFlowStageExecutor(
            requestInput: .path(equivalenceRequestReference.locator.location.value)
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.equivalence", displayName: "Logic equivalence"),
            context: context
        )

        #expect(equivalenceResult.status == .succeeded)
        #expect(equivalenceResult.gates.contains { $0.gateID == "logic.equivalence" && $0.status == .passed })
        #expect(equivalenceResult.artifacts.contains { $0.artifactID == "rtl-verification-report" })
        #expect(equivalenceResult.artifacts.contains { $0.artifactID == "logic-equivalence-evidence" })
        #expect(equivalenceResult.artifacts.contains { $0.artifactID == "logic-synthesis-acceptance" })
        #expect(equivalenceResult.artifacts.contains { $0.artifactID == "logic-equivalence-review" })
        #expect(equivalenceResult.artifacts.contains { $0.artifactID == "logic-equivalence-audit" })

        let resumedResult = try await LogicEquivalenceFlowStageExecutor(
            requestInput: .path(equivalenceRequestReference.locator.location.value),
            engine: UnexpectedRTLVerificationExecution()
        ).execute(
            stage: FlowStageDefinition(stageID: "logic.equivalence", displayName: "Logic equivalence"),
            context: context
        )

        #expect(resumedResult.status == .succeeded)
        #expect(resumedResult.gates.contains { $0.gateID == "logic.equivalence" && $0.status == .passed })
        #expect(resumedResult.artifacts.contains { $0.artifactID == "logic-equivalence-audit" })
    }

    private func writeDesign(to root: URL) throws -> LogicDesignArtifact {
        let document = LogicDesignDocument(
            topDesignName: "flow_top",
            ports: [
                LogicPort(name: "a", direction: .input),
                LogicPort(name: "b", direction: .input),
                LogicPort(name: "y", direction: .output),
            ],
            signals: [LogicSignal(name: "a"), LogicSignal(name: "b"), LogicSignal(name: "y")],
            nodes: [LogicNode(id: "and0", kind: .and, inputs: ["a", "b"], outputs: ["y"])]
        )
        let reference = try writeJSON(document, name: "design.json", root: root, kind: .netlist)
        return LogicDesignArtifact(
            artifact: reference,
            topDesignName: document.topDesignName,
            designRevision: reference.digest
        )
    }

    private func writeStimulus(to root: URL) throws -> ArtifactReference {
        let stimulus = LogicStimulusDocument(
            events: [LogicStimulusEvent(
                time: 0,
                assignments: [
                    "a": try LogicVector(string: "1"),
                    "b": try LogicVector(string: "1"),
                ]
            )],
            assertions: [LogicAssertion(
                id: "y",
                time: 0,
                signal: "y",
                expected: try LogicVector(string: "1")
            )]
        )
        return try writeJSON(stimulus, name: "stimulus.json", root: root, kind: .testPattern)
    }

    private func writeRequest<T: Encodable>(_ request: T, name: String, root: URL) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(request)
        try data.write(to: root.appending(path: name), options: .atomic)
        return name
    }

    private func writeJSON<T: Encodable>(
        _ value: T,
        name: String,
        root: URL,
        kind: ArtifactKind
    ) throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: root.appending(path: name), options: .atomic)
        let locator = try ArtifactLocator(
            location: ArtifactLocation(workspaceRelativePath: name),
            role: .input,
            kind: kind,
            format: .json
        )
        return ArtifactReference(
            id: try ArtifactID(rawValue: name.replacingOccurrences(of: ".json", with: "")),
            locator: locator,
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
    }

    private func writeTextJSON(
        _ text: String,
        name: String,
        root: URL,
        kind: ArtifactKind
    ) throws -> ArtifactReference {
        try Data(text.utf8).write(to: root.appending(path: name), options: .atomic)
        let data = Data(text.utf8)
        let locator = try ArtifactLocator(
            location: ArtifactLocation(workspaceRelativePath: name),
            role: .input,
            kind: kind,
            format: .json
        )
        return ArtifactReference(
            id: try ArtifactID(rawValue: name.replacingOccurrences(of: ".json", with: "")),
            locator: locator,
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
    }

    private func makeContext(root: URL, runID: String) async throws -> FlowExecutionContext {
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()
        _ = try await prepareTestRun(runID: runID, store: workspaceStore)
        let manifest = try await workspaceStore.loadManifest()
        return FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: workspaceStore,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}

private struct UnexpectedRTLVerificationExecution: RTLVerificationExecuting {
    func execute(
        _ request: RTLVerificationRequest
    ) async throws -> RTLVerificationResult {
        throw LogicExecutionError.invalidArtifact(
            "The equivalence engine must not execute while resuming a valid persisted result."
        )
    }
}
