import CircuiteFoundation
import DFTCore
import ElectricalSignoffCore
import Foundation
import LayoutIO
import LogicIR
import PDKCore
import PDKStandardViews
import PEXEngine
import PhysicalDesignCore
import RTLVerificationCore
import Testing
@testable import Xcircuite

@Suite("Flow runtime executor schema coverage")
struct XcircuiteFlowRuntimeExecutorCoverageTests {
    @Test("schema v7 decodes, validates, and constructs every executor kind")
    func schemaConstructsEveryExecutorKind() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "runtime-executor-coverage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove executor coverage fixture: \(error.localizedDescription)")
            }
        }

        let executors = try makeExecutorSpecs(projectRoot: root)
        let original = XcircuiteFlowRuntimeSpec(executors: executors)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(original)
        let discriminators = try JSONDecoder().decode(RuntimeSpecKindProbe.self, from: data)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)

        #expect(decoded.schemaVersion == 7)
        #expect(decoded.executors.count == 35)
        #expect(discriminators.executors.count == 35)
        #expect(Set(discriminators.executors.map(\.kind)).count == 35)
        #expect(decoded == original)
        try decoded.validate(projectRoot: root)

        let expectedTypes = expectedExecutorTypeSuffixes()
        #expect(Set(expectedTypes.keys) == Set(decoded.executors.map(\.stageID)))
        for executorSpec in decoded.executors {
            let executor = try executorSpec.makeExecutor(projectRoot: root)
            #expect(executor.stageID == executorSpec.stageID)
            let expectedType = try #require(expectedTypes[executorSpec.stageID])
            #expect(
                String(reflecting: type(of: executor)).hasSuffix(expectedType),
                "\(executorSpec.stageID) must construct \(expectedType)"
            )
            #expect(!executorSpec.makeDescriptor().toolID.isEmpty)
        }

        let runtime = try await decoded.makeRuntime(projectRoot: root)
        for executorSpec in decoded.executors {
            #expect(runtime.toolRegistry.descriptor(
                toolID: executorSpec.makeDescriptor().toolID
            ) != nil)
        }
    }

    @Test("unknown executor discriminator fails with a typed error")
    func unknownExecutorKindIsTypedFailure() throws {
        let data = Data("""
        {"executors":[{"kind":"unregisteredExecutor","value":{}}],"schemaVersion":7}
        """.utf8)

        do {
            _ = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
            Issue.record("Unknown executor kind must not decode.")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .unknownExecutorKind("unregisteredExecutor"))
        } catch {
            Issue.record("Unexpected error type: \(String(reflecting: type(of: error)))")
        }
    }

    private func makeExecutorSpecs(
        projectRoot: URL
    ) throws -> [XcircuiteFlowStageExecutorSpec] {
        let artifacts = try makeRequestArtifacts()
        try writeFactoryRequests(artifacts: artifacts, projectRoot: projectRoot)
        let pdkDigest = String(repeating: "0", count: 64)
        let timingDesign = XcircuiteFlowInputReference.path("design/timing.json")
        let timingConstraints = XcircuiteFlowInputReference.path("constraints/top.sdc")
        let timingPDK = XcircuiteFlowInputReference.path("pdk/manifest.json")
        let timingParasitics = XcircuiteFlowInputReference.path("parasitics/top.spef")

        return [
            .logicElaboration(.init(
                stageID: "logic.elaborate",
                sourceInput: .path("rtl/top.sv"),
                topDesignName: "top"
            )),
            .logicLowering(.init(
                stageID: "logic.lower",
                requestInput: .path("requests/logic-lowering.json")
            )),
            .logicSimulation(.init(
                stageID: "logic.simulate",
                requestInput: .path("requests/logic-simulation.json")
            )),
            .powerIntent(.init(
                stageID: "logic.power-intent",
                sourceInput: .path("power/top.upf"),
                designInput: .path("design/logic.json"),
                pdkInput: .path("pdk/manifest.json"),
                topDesignName: "top"
            )),
            .layoutCommand(.init(
                stageID: "layout.command",
                requestPath: "requests/layout-command.json"
            )),
            .nativeDRC(.init(
                stageID: "signoff.drc",
                layoutPath: "layout/top.json",
                topCell: "TOP"
            )),
            .nativeLVS(.init(
                stageID: "signoff.lvs",
                layoutNetlistPath: "netlist/layout.spice",
                schematicNetlistPath: "netlist/schematic.spice",
                topCell: "TOP"
            )),
            .pex(.init(
                stageID: "signoff.pex",
                layoutPath: "layout/top.gds",
                layoutFormat: .gds,
                sourceNetlistPath: "netlist/source.spice",
                topCell: "TOP",
                corners: [PEXCorner(id: "tt")],
                technology: .jsonFile(path: "pdk/pex-technology.json"),
                backendSelection: PEXBackendSelection(backendID: "native")
            )),
            .coreSpiceSimulation(.init(
                stageID: "simulation.core-spice",
                netlistInput: .path("netlist/simulation.spice")
            )),
            .postLayoutComparison(.init(
                stageID: "simulation.compare",
                preLayoutWaveformPath: "simulation/pre.csv",
                postLayoutWaveformPath: "simulation/post.csv"
            )),
            .rtlVerification(.init(
                stageID: "rtl.lint",
                analysis: .lint,
                rtlInput: .path("rtl/top.sv"),
                pdkInput: .path("pdk/manifest.json"),
                topModuleName: "top"
            )),
            .logicSynthesis(.init(
                stageID: "logic.synthesize",
                requestPath: "requests/logic-synthesis.json"
            )),
            .logicEquivalence(.init(
                stageID: "logic.equivalence",
                requestPath: "requests/logic-equivalence.json"
            )),
            .logicEvidenceValidation(.init(
                stageID: "logic.evidence-validation",
                reportPath: "reports/logic-evidence.json"
            )),
            .dftExecution(.init(
                stageID: "dft.scan",
                operation: .scanInsertion,
                requestPath: "requests/dft.json"
            )),
            .dftOracleCorrelation(.init(
                stageID: "dft.oracle-correlation",
                corpusInput: .path("dft/corpus.json"),
                observationsInput: .path("dft/observations.json")
            )),
            .processQualificationEvidenceBuild(.init(
                stageID: "tool-qualification.process-evidence-build",
                buildRequestInput: .path("qualification/build-request.json")
            )),
            .physicalDesign(.init(
                stageID: "physical.floorplan",
                requestInput: .path("requests/physical-design.json"),
                inputLayoutInput: .path("layout/input.json"),
                allowedStages: [.floorplan]
            )),
            .physicalReview(.init(
                stageID: "physical.review",
                manifestInput: .path("physical/manifest.json")
            )),
            .timingSTA(.init(
                stageID: "timing.sta",
                inputs: TimingSTAFlowInputs(
                    design: timingDesign,
                    libraries: [.path("timing/cells.lib")],
                    constraints: timingConstraints,
                    pdkManifest: timingPDK,
                    topDesignName: "top",
                    processID: "process",
                    pdkVersion: "1",
                    pdkDigest: pdkDigest,
                    modeIDs: ["functional"],
                    cornerIDs: ["tt"]
                )
            )),
            .timingSignalIntegrity(.init(
                stageID: "timing.signal-integrity",
                inputs: TimingSIFlowInputs(
                    design: timingDesign,
                    constraints: timingConstraints,
                    pdkManifest: timingPDK,
                    parasitics: timingParasitics,
                    topDesignName: "top",
                    processID: "process",
                    pdkVersion: "1",
                    pdkDigest: pdkDigest,
                    modeIDs: ["functional"]
                )
            )),
            .pdkDiscovery(.init(
                stageID: "pdk.discovery",
                searchRoots: [.path("pdk")]
            )),
            .pdkValidation(.init(
                stageID: "pdk.validation",
                manifestInput: .path("pdk/manifest.json")
            )),
            .pdkCorpus(.init(
                stageID: "pdk.corpus-validation",
                suiteInput: .path("pdk/corpus.json"),
                rootInput: .path("pdk")
            )),
            .pdkStandardView(.init(
                stageID: "pdk.standard-view-inspection",
                manifestInput: .path("pdk/manifest.json"),
                assetID: "cells-lef",
                format: .lef
            )),
            .pdkRuleDeck(.init(
                stageID: "pdk.rule-deck-inspection",
                manifestInput: .path("pdk/manifest.json"),
                assetID: "drc-deck"
            )),
            .pdkOracle(.init(
                stageID: "pdk.oracle-comparison",
                manifestInput: .path("pdk/manifest.json"),
                oracleInput: .path("pdk/oracle.json")
            )),
            .releaseEvidenceAssembly(.init(
                stageID: "release.evidence-assembly",
                requestInput: .path("requests/release-evidence.json")
            )),
            .releaseAuthorization(.init(
                stageID: "release.authorization",
                requestInput: .path("requests/release-authorization.json")
            )),
            .releaseSignoff(.init(
                stageID: "release.signoff",
                requestInput: .path("requests/release-signoff.json")
            )),
            .releaseTapeout(.init(
                stageID: "release.tapeout",
                requestInput: .path("requests/release-tapeout.json")
            )),
            .electricalStandardLayoutImport(.init(
                stageID: "electrical-signoff.standard-layout-import",
                layoutInput: .artifact(artifacts.layout),
                layoutFormat: .def,
                technologyInput: .artifact(artifacts.pdk),
                technologyFormat: .json,
                topCellName: "TOP"
            )),
            .electricalSignoff(.init(
                stageID: "electrical-signoff",
                requestPath: "requests/electrical-signoff.json"
            )),
            .electricalSignoffCorpus(.init(
                stageID: "electrical-signoff.corpus",
                specPath: "requests/electrical-corpus.json"
            )),
            .electricalRepairRevision(.init(
                stageID: "electrical-signoff.repair-revision",
                requestPath: "requests/electrical-repair.json"
            )),
        ]
    }

    private func makeRequestArtifacts() throws -> RequestArtifacts {
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "runtime-coverage-fixture",
            version: "1.0.0"
        )
        return RequestArtifacts(
            design: try artifact(
                path: "fixtures/design.json",
                kind: .rtl,
                format: .json,
                producer: producer
            ),
            constraints: try artifact(
                path: "fixtures/constraints.json",
                kind: .constraints,
                format: .json,
                producer: producer
            ),
            layout: try artifact(
                path: "fixtures/layout.json",
                kind: .layout,
                format: .json,
                producer: producer
            ),
            pdk: try artifact(
                path: "fixtures/pdk.json",
                kind: .technology,
                format: .json,
                producer: producer
            ),
            repairPlan: try artifact(
                path: "fixtures/repair-plan.json",
                kind: .report,
                format: .json,
                producer: producer
            )
        )
    }

    private func writeFactoryRequests(
        artifacts: RequestArtifacts,
        projectRoot: URL
    ) throws {
        let design = LogicDesignReference(
            artifact: artifacts.design,
            topDesignName: "TOP",
            designDigest: artifacts.design.digest.hexadecimalValue
        )
        let physicalDesign = PhysicalDesignReference(
            layoutArtifact: artifacts.layout,
            topCell: "TOP",
            layoutDigest: artifacts.layout.digest.hexadecimalValue
        )
        let pdk = PDKReference(
            manifest: artifacts.pdk,
            processID: "process",
            version: "1",
            digest: artifacts.pdk.digest.hexadecimalValue
        )
        let electricalRequest = ElectricalSignoffRequest(
            runID: "runtime-coverage",
            inputs: [artifacts.design, artifacts.layout, artifacts.pdk],
            design: design,
            physicalDesign: physicalDesign,
            pdk: pdk
        )
        try writeJSON(
            electricalRequest,
            path: "requests/electrical-signoff.json",
            projectRoot: projectRoot
        )
        let physicalRequest = PhysicalDesignRequest(
            runID: "runtime-coverage",
            inputs: [artifacts.design, artifacts.constraints, artifacts.pdk, artifacts.layout],
            design: design,
            constraints: artifacts.constraints,
            requestedModeIDs: ["functional"],
            pdk: pdk,
            inputLayout: physicalDesign,
            stage: .floorplan
        )
        let repairRequest = XcircuiteElectricalRepairRevisionRequest(
            runID: "runtime-coverage",
            repairPlanArtifact: artifacts.repairPlan,
            selectedCandidateID: "candidate-1",
            physicalDesignRequest: physicalRequest
        )
        try writeJSON(
            repairRequest,
            path: "requests/electrical-repair.json",
            projectRoot: projectRoot
        )
    }

    private func artifact(
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        producer: ProducerIdentity
    ) throws -> ArtifactReference {
        let bytes = Data(path.utf8)
        return ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format
            ),
            digest: try SHA256ContentDigester().digest(data: bytes),
            byteCount: UInt64(bytes.count),
            producer: producer
        )
    }

    private func writeJSON<Value: Encodable>(
        _ value: Value,
        path: String,
        projectRoot: URL
    ) throws {
        let url = projectRoot.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func expectedExecutorTypeSuffixes() -> [String: String] {
        [
            "logic.elaborate": "LogicElaborationFlowStageExecutor",
            "logic.lower": "LogicLoweringFlowStageExecutor",
            "logic.simulate": "LogicSimulationFlowStageExecutor",
            "logic.power-intent": "PowerIntentFlowStageExecutor",
            "layout.command": "LayoutCommandFlowStageExecutor",
            "signoff.drc": "DRCFlowStageExecutor",
            "signoff.lvs": "LVSFlowStageExecutor",
            "signoff.pex": "PEXFlowStageExecutor",
            "simulation.core-spice": "SimulationFlowStageExecutor",
            "simulation.compare": "PostLayoutComparisonFlowStageExecutor",
            "rtl.lint": "RTLVerificationFlowStageExecutor",
            "logic.synthesize": "LogicSynthesisFlowStageExecutor",
            "logic.equivalence": "LogicEquivalenceFlowStageExecutor",
            "logic.evidence-validation": "LogicEvidenceValidationFlowStageExecutor",
            "dft.scan": "DFTFlowStageExecutor",
            "dft.oracle-correlation": "DFTOracleCorrelationFlowStageExecutor",
            "tool-qualification.process-evidence-build": "ProcessQualificationEvidenceBuilderFlowStageExecutor",
            "physical.floorplan": "PhysicalDesignFlowStageExecutor",
            "physical.review": "PhysicalDesignReviewFlowStageExecutor",
            "timing.sta": "TimingSTAFlowStageExecutor",
            "timing.signal-integrity": "TimingSIFlowStageExecutor",
            "pdk.discovery": "PDKDiscoveryFlowStageExecutor",
            "pdk.validation": "PDKValidationFlowStageExecutor",
            "pdk.corpus-validation": "PDKCorpusValidationFlowStageExecutor",
            "pdk.standard-view-inspection": "PDKStandardViewInspectionFlowStageExecutor",
            "pdk.rule-deck-inspection": "PDKRuleDeckInspectionFlowStageExecutor",
            "pdk.oracle-comparison": "PDKOracleFlowStageExecutor",
            "release.evidence-assembly": "ReleaseSignoffEvidenceAssemblyFlowStageExecutor",
            "release.authorization": "ReleaseAuthorizationFlowStageExecutor",
            "release.signoff": "ReleaseSignoffFlowStageExecutor",
            "release.tapeout": "ReleaseTapeoutFlowStageExecutor",
            "electrical-signoff.standard-layout-import": "ElectricalStandardLayoutImportFlowStageExecutor",
            "electrical-signoff": "ElectricalSignoffFlowStageExecutor",
            "electrical-signoff.corpus": "ElectricalSignoffCorpusFlowStageExecutor",
            "electrical-signoff.repair-revision": "ElectricalSignoffRepairRevisionFlowStageExecutor",
        ]
    }
}

private struct RuntimeSpecKindProbe: Decodable {
    let executors: [Executor]

    struct Executor: Decodable {
        let kind: String
    }
}

private struct RequestArtifacts {
    let design: ArtifactReference
    let constraints: ArtifactReference
    let layout: ArtifactReference
    let pdk: ArtifactReference
    let repairPlan: ArtifactReference
}
