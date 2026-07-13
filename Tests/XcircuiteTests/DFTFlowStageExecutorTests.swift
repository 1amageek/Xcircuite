import DFTCore
import DesignFlowKernel
import Foundation
import LogicIR
import PDKCore
import Testing
import ToolQualification
import TimingCore
import XcircuitePackage
@testable import Xcircuite

@Suite("DFT flow stage adapter")
struct DFTFlowStageExecutorTests {
    @Test("headless adapter executes scan insertion and verifies artifacts")
    func executesScanStage() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
        let runID = "dft-adapter-run"
        let sourceSnapshot = try LogicDesignSnapshotCodec.finalized(makeGateSnapshot())
        let designData = try LogicDesignSnapshotCodec.encode(sourceSnapshot)
        let designDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let designPath = root.appending(path: "design.json")
        try designData.write(to: designPath, options: .atomic)
        let designArtifact = XcircuiteFileReference(
            artifactID: "design",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: designData),
            byteCount: Int64(designData.count)
        )
        let libraryManifest = makeCellLibraryManifest()
        let libraryData = try DFTCellLibraryManifestCodec.encode(libraryManifest)
        let libraryPath = root.appending(path: "cell-library.json")
        try libraryData.write(to: libraryPath, options: .atomic)
        let libraryArtifact = XcircuiteFileReference(
            artifactID: "cell-library",
            path: "cell-library.json",
            kind: .technology,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: libraryData),
            byteCount: Int64(libraryData.count)
        )
        let libraryReference = DFTCellLibraryReference(
            artifact: libraryArtifact,
            processID: libraryManifest.processID,
            version: libraryManifest.version,
            manifestDigest: try DFTCellLibraryManifestCodec.digest(libraryManifest)
        )
        let request = makeRequest(
            runID: runID,
            designArtifact: designArtifact,
            designDigest: designDigest,
            cellLibraryReference: libraryReference
        )
        let requestURL = root.appending(path: "dft-request.json")
        let requestData = try DFTArtifactJSONEncoder().encode(request)
        try requestData.write(to: requestURL, options: .atomic)
        let context = makeContext(root: root, runID: runID)

        let result = try await DFTFlowStageExecutor(
            stageID: "dft.scan",
            requestInput: .path("dft-request.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.scan", displayName: "DFT scan insertion"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.contains { $0.gateID == "dft" && $0.status == .passed })
        #expect(result.artifacts.count == 3)
        #expect(FileManager.default.fileExists(atPath: root
            .appending(path: "dft/runs/\(runID)/transformed-design.json")
            .path))
    }

    @Test("DFT stage specs round-trip")
    func stageSpecRoundTrip() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.scan",
                requestPath: "dft-request.json"
            )
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowStageExecutorSpec.self, from: data)

        #expect(decoded == spec)
    }

    @Test("DFT release stage spec round-trips its review inputs")
    func releaseStageSpecRoundTrip() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.release",
                requestPath: "dft-request.json",
                releaseResultPath: "dft-result.json",
                releaseDownstreamEvidencePath: "dft-downstream.json",
                releaseApprovalPath: "dft-approval.json"
            )
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowStageExecutorSpec.self, from: data)

        #expect(decoded == spec)
    }

    @Test("DFT qualification stage spec round-trips its oracle inputs")
    func qualificationStageSpecRoundTrip() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.qualification",
                requestPath: "dft-request.json",
                qualificationCorpusPath: "dft-corpus.json",
                qualificationObservationsPath: "dft-observations.json",
                qualificationEvidencePath: "dft-qualification-evidence.json"
            )
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowStageExecutorSpec.self, from: data)

        #expect(decoded == spec)
    }

    @Test("DFT qualification stage correlates retained artifacts and records provenance")
    func executesQualificationStage() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
        let runID = "dft-qualification-run"
        let pdkDigest = String(repeating: "e", count: 64)
        let requestDigest = String(repeating: "a", count: 64)
        let expectation = DFTOracleCaseExpectation(expectedStatus: .completed)
        let expectationData = try JSONEncoder().encode(expectation)
        let oracleDirectory = root.appending(path: "oracle")
        try FileManager.default.createDirectory(
            at: oracleDirectory,
            withIntermediateDirectories: true
        )
        let oracleURL = oracleDirectory.appending(path: "expectation.json")
        try expectationData.write(to: oracleURL, options: .atomic)
        let oracleArtifact = XcircuiteFileReference(
            artifactID: "oracle-case",
            path: "oracle/expectation.json",
            kind: .report,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: expectationData),
            byteCount: Int64(expectationData.count)
        )
        let corpus = DFTOracleCorpus(
            corpusID: "fixture-corpus",
            revision: "fixture-revision",
            processID: "fixture-process",
            pdkDigest: pdkDigest,
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
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "fixture-native",
            implementationID: "fixture-native",
            implementationVersion: "1",
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2)
        )
        let nativeResult = XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: "native-case-run",
            status: .completed,
            metadata: metadata,
            payload: DFTPayload(
                transformedDesign: nil,
                faultCoverage: nil
            )
        )
        let observations = [
            DFTOracleCaseObservation(
                caseID: "scan-case",
                operation: .scanInsertion,
                requestDigest: requestDigest,
                result: nativeResult
            ),
        ]
        let corpusURL = root.appending(path: "dft-corpus.json")
        let observationsURL = root.appending(path: "dft-observations.json")
        try JSONEncoder().encode(corpus).write(to: corpusURL, options: .atomic)
        try JSONEncoder().encode(observations).write(to: observationsURL, options: .atomic)

        let correlation = try await DFTOracleCorrelationEngine(
            artifactLoader: FileSystemDFTOracleArtifactLoader(rootURL: root)
        ).correlate(corpus: corpus, observations: observations)
        let evidence = try correlation.makeQualificationEvidence(
            evidenceID: "fixture-qualification",
            engineID: "fixture-native",
            implementationID: "fixture-native",
            approvedBy: "reviewer"
        )
        let evidenceURL = root.appending(path: "dft-qualification-evidence.json")
        try JSONEncoder().encode(evidence).write(to: evidenceURL, options: .atomic)

        let result = try await DFTQualificationFlowStageExecutor(
            corpusInput: .path("dft-corpus.json"),
            observationsInput: .path("dft-observations.json"),
            qualificationEvidenceInput: .path("dft-qualification-evidence.json")
        ).execute(
            stage: FlowStageDefinition(
                stageID: "dft.qualification",
                displayName: "DFT qualification"
            ),
            context: makeContext(root: root, runID: runID)
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.contains {
            $0.gateID == "dft-qualification" && $0.status == .passed
        })
        #expect(FileManager.default.fileExists(atPath: root
            .appending(path: ".xcircuite/runs/\(runID)/stages/dft.qualification/raw/dft-qualification-provenance.json")
            .path))
    }

    private func makeRequest(
        runID: String,
        designArtifact: XcircuiteFileReference = XcircuiteFileReference(
            artifactID: "design",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 10
        ),
        designDigest: String = String(repeating: "b", count: 64),
        cellLibraryReference: DFTCellLibraryReference
    ) -> DFTRequest {
        let design = designArtifact
        return DFTRequest(
            runID: runID,
            inputs: [design, cellLibraryReference.artifact],
            design: LogicDesignReference(
                artifact: design,
                topDesignName: "top",
                designDigest: designDigest
            ),
            constraints: TimingConstraintReference(
                artifact: XcircuiteFileReference(
                    artifactID: "constraints",
                    path: "constraints.sdc",
                    kind: .constraint,
                    format: .sdc,
                    sha256: String(repeating: "c", count: 64),
                    byteCount: 1
                ),
                modeIDs: ["test"]
            ),
            pdk: PDKReference(
                manifest: XcircuiteFileReference(
                    artifactID: "pdk",
                    path: "pdk.json",
                    kind: .technology,
                    format: .json,
                    sha256: String(repeating: "d", count: 64),
                    byteCount: 1
                ),
                processID: "fixture-process",
                version: "1",
                digest: String(repeating: "e", count: 64)
            ),
            cellLibrary: cellLibraryReference,
            operation: .scanInsertion,
            scanArchitecture: DFTScanArchitecture(
                name: "core-scan",
                clocks: [DFTScanClock(id: "clk", signalName: "scan_clk", periodNanoseconds: 10)],
                domains: [DFTScanDomain(id: "core", clockID: "clk", chainCount: 1, estimatedElementCount: 2)],
                scanEnableSignal: "scan_en",
                testModeSignal: "test_mode"
            ),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
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
        let nets = [
            GateNet(id: "d-0", name: "d0"),
            GateNet(id: "d-1", name: "d1"),
            GateNet(id: "q-0", name: "q0"),
            GateNet(id: "q-1", name: "q1"),
            GateNet(id: "clk", name: "scan_clk"),
        ]
        let gate = GateDesign(
            topModuleName: "top",
            modules: [
                GateModule(
                    id: "module-top",
                    name: "top",
                    ports: [RTLPort(id: "port-clk", name: "clk", direction: .input)],
                    cells: cells,
                    nets: nets
                )
            ]
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: gate
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
                )
            ],
            qualification: DFTQualificationProvenance(
                status: .corpusChecked,
                corpusRevision: "fixture-m2",
                notes: ["fixture binding only; no foundry qualification"]
            )
        )
    }

    private func makeContext(root: URL, runID: String) -> FlowExecutionContext {
        let runDirectory = root
            .appending(path: XcircuitePackage.directoryName)
            .appending(path: "runs")
            .appending(path: runID)
        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        } catch {
            Issue.record("Failed to create run directory: \(error)")
        }
        return FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: runDirectory,
            packageStore: XcircuitePackageStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dft-flow-adapter-\(UUID().uuidString)")
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
