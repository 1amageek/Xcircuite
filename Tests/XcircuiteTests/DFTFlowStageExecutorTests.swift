import CircuiteFoundation
import DesignFlowKernel
import DFTCore
import Foundation
import LogicIR
import PDKCore
import Testing
import TimingCore
import ToolQualification
@testable import Xcircuite

@Suite("DFT flow stage executors")
struct DFTFlowStageExecutorTests {
    @Test("scan insertion executes through the canonical flow context")
    func executesScanStage() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
        let runID = "dft-scan-run"
        let sourceSnapshot = try LogicDesignSnapshotCodec.finalized(makeGateSnapshot())
        let designData = try LogicDesignSnapshotCodec.encode(sourceSnapshot)
        let designArtifact = try writeArtifact(
            root: root,
            path: "design.json",
            artifactID: "design",
            data: designData,
            kind: .netlist,
            role: .input
        )
        let libraryManifest = makeCellLibraryManifest()
        let libraryData = try DFTCellLibraryManifestCodec.encode(libraryManifest)
        let libraryArtifact = try writeArtifact(
            root: root,
            path: "cell-library.json",
            artifactID: "cell-library",
            data: libraryData,
            kind: .technology,
            role: .input
        )
        let request = try makeRequest(
            root: root,
            runID: runID,
            designArtifact: designArtifact,
            designDigest: try LogicDesignSnapshotCodec.digest(sourceSnapshot),
            cellLibraryReference: DFTCellLibraryReference(
                artifact: libraryArtifact,
                processID: libraryManifest.processID,
                version: libraryManifest.version,
                manifestDigest: try DFTCellLibraryManifestCodec.digest(libraryManifest)
            ),
            pdkDigest: libraryManifest.pdkDigest
        )
        try DFTArtifactJSONEncoder().encode(request).write(
            to: root.appending(path: "dft-request.json"),
            options: .atomic
        )

        let result = try await DFTFlowStageExecutor(
            stageID: "dft.scan",
            requestInput: .path("dft-request.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.scan", displayName: "DFT scan insertion"),
            context: try await makeContext(root: root, runID: runID)
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.contains { $0.gateID == "dft" && $0.status == .passed })
        #expect(Set(result.artifacts.map(\.artifactID)) == [
            "dft-transformed-design",
            "dft-design-diff",
            "dft-result",
        ])
        #expect(FileManager.default.fileExists(atPath: root
            .appending(path: "dft/runs/\(runID)/transformed-design.json")
            .path))
    }

    @Test("DFT executor specs round-trip with current fields")
    func stageSpecsRoundTrip() async throws {
        let scan = XcircuiteFlowStageExecutorSpec.dftExecution(
            .init(stageID: "dft.scan", requestPath: "dft-request.json")
        )
        let qualification = XcircuiteFlowStageExecutorSpec.dftQualification(
            .init(
                corpusInput: .path("dft-corpus.json"),
                observationsInput: .path("dft-observations.json"),
                processQualificationEvidenceBuildInput: .path("dft-process-evidence-request.json")
            )
        )

        for spec in [scan, qualification] {
            let decoded = try JSONDecoder().decode(
                XcircuiteFlowStageExecutorSpec.self,
                from: JSONEncoder().encode(spec)
            )
            #expect(decoded == spec)
        }

        let runtimeSpec = XcircuiteFlowRuntimeSpec(executors: [scan, qualification])
        #expect(runtimeSpec.schemaVersion == XcircuiteFlowRuntimeSpec.currentSchemaVersion)
        let obsoleteData = try JSONEncoder().encode(
            XcircuiteFlowRuntimeSpec(schemaVersion: 1, executors: [])
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: obsoleteData)
        }
    }

    @Test("qualification stage builds current ToolQualification process evidence")
    func executesQualificationStage() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
        let runID = "dft-qualification-run"
        let now = Date()
        let buildRequest = try makeProcessQualificationBuildRequest(
            root: root,
            processID: "fixture-process",
            toolID: "qualified-scan",
            implementationID: "qualified-scan",
            now: now
        )
        try JSONEncoder().encode(buildRequest).write(
            to: root.appending(path: "dft-process-evidence-request.json"),
            options: .atomic
        )
        let requestDigest = String(repeating: "a", count: 64)
        let expectation = DFTOracleCaseExpectation(expectedStatus: .completed)
        let expectationData = try JSONEncoder().encode(expectation)
        let oracleArtifact = try writeArtifact(
            root: root,
            path: "oracle/expectation.json",
            artifactID: "oracle-case",
            data: expectationData,
            kind: .evidence,
            role: .input
        )
        let corpus = DFTOracleCorpus(
            corpusID: "fixture-corpus",
            revision: "fixture-revision",
            processID: "fixture-process",
            pdkDigest: buildRequest.scope.pdkDigest ?? "",
            cases: [
                DFTOracleCorpusCase(
                    caseID: "scan-case",
                    operation: .scanInsertion,
                    requestDigest: requestDigest,
                    expectation: expectation,
                    oracleArtifact: oracleArtifact
                ),
            ]
        )
        let observation = DFTOracleCaseObservation(
            caseID: "scan-case",
            operation: .scanInsertion,
            requestDigest: requestDigest,
            result: DFTResult(
                schemaVersion: DFTRequest.currentSchemaVersion,
                runID: "native-case-run",
                status: .completed,
                provenance: try ExecutionProvenance(
                    producer: ProducerIdentity(
                        kind: .engine,
                        identifier: "qualified-scan",
                        version: "1.0.0"
                    ),
                    startedAt: now.addingTimeInterval(-2),
                    completedAt: now.addingTimeInterval(-1)
                ),
                payload: DFTPayload(transformedDesign: nil, faultCoverage: nil)
            )
        )
        try JSONEncoder().encode(corpus).write(
            to: root.appending(path: "dft-corpus.json"),
            options: .atomic
        )
        try JSONEncoder().encode([observation]).write(
            to: root.appending(path: "dft-observations.json"),
            options: .atomic
        )

        let result = try await DFTQualificationFlowStageExecutor(
            corpusInput: .path("dft-corpus.json"),
            observationsInput: .path("dft-observations.json"),
            processQualificationEvidenceBuildInput: .path("dft-process-evidence-request.json")
        ).execute(
            stage: FlowStageDefinition(
                stageID: "dft.qualification",
                displayName: "DFT qualification"
            ),
            context: try await makeContext(root: root, runID: runID)
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.contains {
            $0.gateID == "dft-oracle-correlation" && $0.status == .passed
        })
        #expect(result.artifacts.contains { $0.id.rawValue == "dft-evidence-provenance" })
        #expect(result.artifacts.contains {
            $0.id.rawValue == "dft-process-qualification-evidence"
        })
    }

    private func makeProcessQualificationBuildRequest(
        root: URL,
        processID: String,
        toolID: String,
        implementationID: String,
        now: Date
    ) throws -> ToolProcessQualificationEvidenceBuildRequest {
        let toolProducer = try ProducerIdentity(
            kind: .tool,
            identifier: implementationID,
            version: "1.0.0"
        )
        let oracleProducer = try ProducerIdentity(
            kind: .tool,
            identifier: "independent-dft-oracle",
            version: "2.0.0"
        )
        let tool = try writeQualificationArtifact(
            root: root,
            name: "tool",
            producer: toolProducer
        )
        let processProfile = try writeQualificationArtifact(root: root, name: "process-profile")
        let pdk = try writeQualificationArtifact(root: root, name: "pdk")
        let ruleDeck = try writeQualificationArtifact(root: root, name: "rule-deck")
        let oracleTool = try writeQualificationArtifact(
            root: root,
            name: "oracle-tool",
            producer: oracleProducer
        )
        let identity = ToolProcessQualificationArtifacts(
            toolExecutable: tool,
            processProfile: processProfile,
            pdk: pdk,
            ruleDeck: ruleDeck,
            oracleExecutable: oracleTool
        )
        let scope = ToolQualificationScope(
            implementationID: implementationID,
            toolVersion: "1.0.0",
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "dft-v1",
            processProfileID: processID,
            processProfileDigest: processProfile.digest.hexadecimalValue,
            deckDigest: ruleDeck.digest.hexadecimalValue,
            pdkID: "fixture-pdk",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: "independent-dft-oracle",
                version: "2.0.0",
                binaryDigest: oracleTool.digest.hexadecimalValue
            )
        )
        let input = try writeQualificationArtifact(root: root, name: "input")
        let output = try writeQualificationArtifact(root: root, name: "output")
        let issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "dft-qualification-runner",
            version: "1.0.0"
        )
        let checkedAt = now.addingTimeInterval(-30)
        let passingCase = ToolQualificationCaseOutcome(
            caseID: "dft-case",
            coverageTags: ["scan"],
            comparisons: [
                ToolQualificationMetricComparison(
                    metricID: "result",
                    observed: 1,
                    expected: 1
                ),
            ]
        )
        let corpus = try writeQualificationArtifact(
            root: root,
            name: "corpus-result",
            data: ToolCorpusQualificationResult(
                resultID: "dft-corpus-result",
                qualificationID: "dft-process-qualification",
                toolID: toolID,
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                cases: [passingCase],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
        )
        let oracle = try writeQualificationArtifact(
            root: root,
            name: "oracle-result",
            data: ToolOracleQualificationResult(
                resultID: "dft-oracle-result",
                qualificationID: "dft-process-qualification",
                primaryToolID: implementationID,
                oracleToolID: "independent-dft-oracle",
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                primaryOutputArtifacts: [output],
                oracleOutputArtifacts: [output],
                cases: [
                    ToolOracleCaseComparison(
                        caseID: "dft-case",
                        primary: passingCase,
                        oracle: passingCase,
                        agreementComparisons: [
                            ToolQualificationMetricComparison(
                                metricID: "agreement",
                                observed: 0,
                                expected: 0
                            ),
                        ]
                    ),
                ],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
        )
        let health = try writeQualificationArtifact(
            root: root,
            name: "health-result",
            data: ToolHealthQualificationResult(
                resultID: "dft-health-result",
                qualificationID: "dft-process-qualification",
                toolID: toolID,
                scope: scope,
                issuer: issuer,
                inputArtifacts: [input],
                outputArtifacts: [output],
                checkedAt: checkedAt
            ).canonicalData(),
            producer: issuer
        )
        return ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "dft-process-qualification",
            toolID: toolID,
            scope: scope,
            identityArtifacts: identity,
            corpusResultArtifacts: [corpus],
            oracleResultArtifacts: [oracle],
            healthResultArtifacts: [health],
            inputArtifacts: [input],
            outputArtifacts: [output],
            qualifiedAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(3_600)
        )
    }

    private func makeRequest(
        root: URL,
        runID: String,
        designArtifact: ArtifactReference,
        designDigest: String,
        cellLibraryReference: DFTCellLibraryReference? = nil,
        pdkArtifact: ArtifactReference? = nil,
        pdkDigest: String? = nil
    ) throws -> DFTRequest {
        let constraints = try writeArtifact(
            root: root,
            path: "constraints.sdc",
            artifactID: "constraints",
            data: Data("create_clock -name scan_clk -period 10 scan_clk".utf8),
            kind: .constraint,
            format: .sdc,
            role: .input
        )
        let pdk = try pdkArtifact ?? writeArtifact(
            root: root,
            path: "pdk.json",
            artifactID: "pdk",
            data: Data("{\"process\":\"fixture-process\"}".utf8),
            kind: .technology,
            role: .input
        )
        var inputs = [designArtifact]
        if let cellLibraryReference {
            inputs.append(cellLibraryReference.artifact)
        }
        return DFTRequest(
            runID: runID,
            inputs: inputs,
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: "top",
                designDigest: designDigest
            ),
            constraints: DFTConstraintReference(
                artifact: constraints,
                modeIDs: ["test"]
            ),
            pdk: PDKReference(
                manifest: pdk,
                processID: "fixture-process",
                version: "1",
                digest: pdkDigest ?? pdk.digest.hexadecimalValue
            ),
            cellLibrary: cellLibraryReference,
            operation: .scanInsertion,
            scanArchitecture: DFTScanArchitecture(
                name: "core-scan",
                clocks: [
                    DFTScanClock(
                        id: "clk",
                        signalName: "scan_clk",
                        periodNanoseconds: 10
                    ),
                ],
                domains: [
                    DFTScanDomain(
                        id: "core",
                        clockID: "clk",
                        chainCount: 1,
                        estimatedElementCount: 2
                    ),
                ],
                scanEnableSignal: "scan_en",
                testModeSignal: "test_mode"
            ),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )
    }

    private func makeContext(
        root: URL,
        runID: String,
        approval: FlowApprovalRecord? = nil
    ) async throws -> FlowExecutionContext {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.prepareRun(runID: runID, requireNew: false)
        do {
            let existing = try await store.loadRunLedger(runID: runID)
            if let approval, !existing.approvals.contains(approval) {
                _ = try await FlowRunLedgerCoordinator(persistence: store).update(runID: runID) {
                    $0.approvals.removeAll { $0.stageID == approval.stageID }
                    $0.approvals.append(approval)
                }
            }
        } catch FlowRunLedgerPersistenceError.resumeTargetNotFound {
            let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
            let manifest = try FlowRunManifest(
                runID: runID,
                status: .created,
                actor: FlowRunActor(kind: .system, identifier: "test"),
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try await store.saveRunLedger(
                FlowRunLedger(
                    runID: runID,
                    runManifest: manifest,
                    stages: [],
                    approvals: approval.map { [$0] } ?? []
                )
            )
        }
        return FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: "dft-flow-stage-tests"),
            runID: runID,
            infrastructure: store,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func writeArtifact(
        root: URL,
        path: String,
        artifactID: String,
        data: Data,
        kind: ArtifactKind,
        format: ArtifactFormat = .json,
        role: ArtifactRole = .output,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        let referenced = try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: role,
                kind: kind,
                format: format
            ),
            relativeTo: root,
            producer: producer
        )
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: referenced.locator,
            digest: referenced.digest,
            byteCount: referenced.byteCount,
            producer: referenced.producer
        )
    }

    private func writeQualificationArtifact(
        root: URL,
        name: String,
        data: Data? = nil,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        try writeArtifact(
            root: root,
            path: "qualification/\(name).json",
            artifactID: "qualification-\(name)",
            data: data ?? Data("artifact:\(name)".utf8),
            kind: .evidence,
            producer: producer
        )
    }

    private func makeGateSnapshot() -> LogicDesignSnapshot {
        let cells = (0..<2).map { index in
            GateCell(
                id: "cell-\(index)",
                type: "DFF",
                instanceName: "u_ff\(index)",
                pins: [
                    GatePin(id: "pin-\(index)-d", name: "D", direction: .input, netID: "d-\(index)"),
                    GatePin(id: "pin-\(index)-q", name: "Q", direction: .output, netID: "q-\(index)"),
                    GatePin(id: "pin-\(index)-clk", name: "CLK", direction: .input, netID: "clk"),
                ]
            )
        }
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: GateDesign(
                topModuleName: "top",
                modules: [
                    GateModule(
                        id: "module-top",
                        name: "top",
                        ports: [RTLPort(id: "port-clk", name: "clk", direction: .input)],
                        cells: cells,
                        nets: [
                            GateNet(id: "d-0", name: "d0"),
                            GateNet(id: "d-1", name: "d1"),
                            GateNet(id: "q-0", name: "q0"),
                            GateNet(id: "q-1", name: "q1"),
                            GateNet(id: "clk", name: "scan_clk"),
                        ]
                    ),
                ]
            )
        )
    }

    private func makeCellLibraryManifest() -> DFTCellLibraryManifest {
        DFTCellLibraryManifest(
            processID: "fixture-process",
            version: "1",
            pdkDigest: String(repeating: "e", count: 64),
            bindings: [
                DFTCellLibraryBinding(
                    bindingID: "dff-to-sdff",
                    functionalCellType: "DFF",
                    scanCellType: "SDFF",
                    dataPinName: "D",
                    outputPinName: "Q",
                    clockPinNames: ["CLK"],
                    scanInPinName: "SI",
                    scanEnablePinName: "SE",
                    testModePinName: "TM"
                ),
            ],
            evidenceProvenance: DFTEvidenceProvenance(
                status: .corpusObserved,
                corpusRevision: "fixture-m2",
                notes: ["Fixture binding for native scan insertion testing."]
            )
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dft-flow-executor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error.localizedDescription)")
        }
    }
}
