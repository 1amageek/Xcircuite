import DRCEngine
import Foundation
import LVSEngine
import Testing
@testable import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite signoff repair formulation builder")
struct XcircuiteSignoffRepairFormulationBuilderTests {
    @Test func signoffRepairHintsCLICompilesAuditableFormulationProblemAndPDDLExport() async throws {
        let root = try makeTemporaryRoot("signoff-repair-formulation")
        defer { removeTemporaryRoot(root) }
        let runID = "run-signoff-formulation"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: store)
        try await writeReports(root: root, runID: runID, registerArtifacts: true)

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "formulate-signoff-repair-planning-problem",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--drc-repair-hints",
            "reports/drc-repair-hints.json",
            "--lvs-repair-hints",
            "reports/lvs-repair-hints.json",
            "--problem-id",
            "signoff-repair-problem",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteSignoffRepairFormulationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "compiled")
        #expect(result.sourceReports.map(\.sourceKind) == ["drc", "lvs"])
        #expect(result.sourceReports.allSatisfy { $0.integrityStatus == "verified" })
        #expect(result.sourceReports.allSatisfy { ($0.sha256 ?? "").isEmpty == false })
        #expect(result.sourceReports.allSatisfy { ($0.byteCount ?? 0) > 0 })
        #expect(result.compilation.formulationArtifact.path == ".xcircuite/runs/\(runID)/planning/repair-formulation.json")
        #expect(result.compilation.problemArtifact.path == ".xcircuite/runs/\(runID)/planning/problem.json")

        let formulation = try await store.readJSON(
            XcircuiteRepairPlanFormulation.self,
            from: result.compilation.formulationArtifact.path
        )
        #expect(formulation.formulationID == "signoff-repair-formulation-\(runID)")
        #expect(formulation.sourceRefs.map(\.refID) == ["drc-repair-hints", "lvs-repair-hints"])
        #expect(formulation.sourceRefs.allSatisfy { $0.metadata["artifactIntegrityStatus"] == .text("verified") })
        #expect(formulation.sourceRefs.allSatisfy { $0.metadata["artifactSHA256"] != nil })
        #expect(formulation.initialStateRefs.contains { $0.refID == "action-domain-snapshot" })
        #expect(formulation.goals.map(\.domain).sorted() == ["drc", "lvs"])
        #expect(formulation.actions.map(\.operationID).sorted() == ["layout.resize-shape", "lvs.policy-repair"])
        #expect(formulation.riskClassifications.contains { $0.requiredApprovals == ["lvs-policy-review"] })
        #expect(formulation.constraints.contains { $0.kind == "human-approval" })

        let problem = try await store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: result.compilation.problemArtifact.path
        )
        #expect(problem.problemID == "signoff-repair-problem")
        #expect(problem.sourceRefs.first?.kind == "repair-plan-formulation")
        #expect(problem.actionDomainRefs.sorted() == ["layout-edit", "lvs-signoff"])
        #expect(problem.candidateActions.contains {
            $0.domainID == "layout-edit" && $0.operationID == "layout.resize-shape"
        })
        #expect(problem.candidateActions.contains {
            $0.domainID == "lvs-signoff" && $0.operationID == "lvs.policy-repair"
        })

        let validationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "validate-planning-problem",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--pretty",
        ])
        let validation = try JSONDecoder().decode(
            XcircuitePlanningProblemValidationResult.self,
            from: try #require(validationJSON.data(using: .utf8))
        )
        #expect(validation.validation.status == "valid")

        let pddlJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "export-symbolic-planner-problem",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--pretty",
        ])
        let pddlResult = try JSONDecoder().decode(
            XcircuiteSymbolicPlannerPDDLExportResult.self,
            from: try #require(pddlJSON.data(using: .utf8))
        )
        #expect(pddlResult.export.actionMappings.map(\.operationID).sorted() == [
            "layout.resize-shape",
            "lvs.policy-repair",
        ])
        #expect(pddlResult.export.atomMappings.contains {
            $0.atom == "drc-min-width-cleared" && $0.roles.contains("goal")
        })
        #expect(pddlResult.export.atomMappings.contains {
            $0.atom == "lvs-modelmismatch-resolved" && $0.roles.contains("goal")
        })

        let ledger = try await store.loadRunLedger(runID: runID)
        let artifactIDs = Set(ledger.runManifest.artifacts.map(\.artifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.actionDomainArtifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.repairPlanFormulationArtifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.problemArtifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.planningProblemValidationArtifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID))
    }

    @Test func builderRejectsSignoffRepairReportsWithoutActionableHints() async throws {
        let root = try makeTemporaryRoot("signoff-repair-empty")
        defer { removeTemporaryRoot(root) }
        let runID = "run-signoff-empty"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: store)
        let reportsDirectory = root.appending(path: "reports")
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        try writeJSON(
            DRCRepairHintReport(
                status: "ready",
                reportURL: nil,
                backendID: "native-gds",
                topCell: "INV",
                activeDiagnosticCount: 0,
                hintCount: 0,
                hints: [],
                unsupportedDiagnosticIndexes: []
            ),
            to: reportsDirectory.appending(path: "drc-repair-hints.json")
        )
        let reportRef = try await store.makeArtifactReference(
            forProjectRelativePath: "reports/drc-repair-hints.json",
            artifactID: "drc-repair-hints",
            kind: .report,
            format: .json,
        )
        _ = try await retainTestArtifact(reportRef, runID: runID, store: store, projectRoot: root)

        do {
            _ = try await XcircuiteSignoffRepairFormulationBuilder(
                workspaceStore: store,
                artifactStore: artifactStore
            ).compile(
                request: XcircuiteSignoffRepairFormulationRequest(
                    runID: runID,
                    drcRepairHintPath: "reports/drc-repair-hints.json"
                ),
                projectRoot: root
            )
            Issue.record("Expected empty signoff repair hints to be rejected.")
        } catch let error as XcircuiteSignoffRepairFormulationError {
            #expect(error == .noActionableHints)
        }
    }

    @Test func builderRejectsUnregisteredRepairHintReportPath() async throws {
        let root = try makeTemporaryRoot("signoff-repair-unregistered-report")
        defer { removeTemporaryRoot(root) }
        let runID = "run-signoff-unregistered"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: store)
        try await writeReports(root: root, runID: runID, registerArtifacts: false)

        do {
            _ = try await XcircuiteSignoffRepairFormulationBuilder(
                workspaceStore: store,
                artifactStore: artifactStore
            ).compile(
                request: XcircuiteSignoffRepairFormulationRequest(
                    runID: runID,
                    drcRepairHintPath: "reports/drc-repair-hints.json"
                ),
                projectRoot: root
            )
            Issue.record("Expected unregistered repair hint report rejection.")
        } catch let error as XcircuiteSignoffRepairFormulationError {
            guard case .unregisteredRepairHintReport(let sourceKind, let path) = error else {
                Issue.record("Unexpected signoff repair formulation error: \(error)")
                return
            }
            #expect(sourceKind == "drc")
            #expect(path == "reports/drc-repair-hints.json")
        }
    }

    @Test func builderRejectsStaleRegisteredRepairHintReport() async throws {
        let root = try makeTemporaryRoot("signoff-repair-stale-report")
        defer { removeTemporaryRoot(root) }
        let runID = "run-signoff-stale"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: store)
        try await writeReports(root: root, runID: runID, registerArtifacts: true)
        let reportURL = root.appending(path: "reports/drc-repair-hints.json")
        let original = try String(contentsOf: reportURL, encoding: .utf8)
        try "\(original)\n".write(to: reportURL, atomically: true, encoding: .utf8)

        do {
            _ = try await XcircuiteSignoffRepairFormulationBuilder(
                workspaceStore: store,
                artifactStore: artifactStore
            ).compile(
                request: XcircuiteSignoffRepairFormulationRequest(
                    runID: runID,
                    drcRepairHintPath: "reports/drc-repair-hints.json"
                ),
                projectRoot: root
            )
            Issue.record("Expected stale repair hint report rejection.")
        } catch let error as XcircuiteSignoffRepairFormulationError {
            guard case .repairHintArtifactIntegrityFailed(let sourceKind, let path, let status, _) = error else {
                Issue.record("Unexpected signoff repair formulation error: \(error)")
                return
            }
            #expect(sourceKind == "drc")
            #expect(path == "reports/drc-repair-hints.json")
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    private func writeReports(root: URL, runID: String, registerArtifacts: Bool) async throws {
        let reportsDirectory = root.appending(path: "reports")
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try writeJSON(
            makeDRCRepairHints(),
            to: reportsDirectory.appending(path: "drc-repair-hints.json")
        )
        try writeJSON(
            makeLVSRepairHints(),
            to: reportsDirectory.appending(path: "lvs-repair-hints.json")
        )
        guard registerArtifacts else { return }
        let drcRef = try StageArtifactReferenceBuilder().reference(
            for: reportsDirectory.appending(path: "drc-repair-hints.json"),
            projectRoot: root,
            artifactID: "drc-repair-hints",
            kind: .report,
            format: .json,
        )
        let lvsRef = try StageArtifactReferenceBuilder().reference(
            for: reportsDirectory.appending(path: "lvs-repair-hints.json"),
            projectRoot: root,
            artifactID: "lvs-repair-hints",
            kind: .report,
            format: .json,
        )
        _ = try await retainTestArtifact(drcRef, runID: runID, store: store, projectRoot: root)
        _ = try await retainTestArtifact(lvsRef, runID: runID, store: store, projectRoot: root)
    }

    private func makeDRCRepairHints() -> DRCRepairHintReport {
        DRCRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native-gds",
            topCell: "INV",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                DRCRepairHint(
                    hintID: "drc-repair-0-min-width",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.resize-shape",
                    confidence: "high",
                    ruleID: "MIN_WIDTH",
                    kind: "min_width",
                    layer: "met1",
                    targetShapeIDs: ["shape-thin"],
                    relatedNetIDs: ["out"],
                    region: DRCRegion(x: 10, y: 20, width: 2, height: 1),
                    measured: 0.12,
                    required: 0.14,
                    numericParameters: [
                        "deltaMaxX": 0.02,
                        "deltaMaxY": 0,
                    ],
                    stringParameters: [
                        "layer": "met1",
                        "shapeID": "shape-thin",
                        "unit": "um",
                    ],
                    verificationGates: ["artifact-integrity", "native-drc", "native-lvs"],
                    rationale: "MIN_WIDTH maps to layout.resize-shape because the diagnostic exposes an existing shape."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func makeLVSRepairHints() -> LVSRepairHintReport {
        LVSRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "INV",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                LVSRepairHint(
                    hintID: "lvs-repair-0-model",
                    sourceDiagnosticIndex: 0,
                    operationID: "lvs.policy-repair",
                    confidence: "medium",
                    ruleID: "LVS_MODEL_MISMATCH",
                    category: "modelMismatch",
                    componentSignature: "mos|D,G,S,B",
                    parameterName: nil,
                    layoutModel: "nfet_01v8",
                    schematicModel: "sky130_fd_pr__nfet_01v8",
                    layoutValue: nil,
                    schematicValue: nil,
                    layoutPorts: ["D", "G", "S", "B"],
                    schematicPorts: ["D", "G", "S", "B"],
                    layoutCount: 1,
                    schematicCount: 1,
                    stringParameters: [
                        "policyKind": "model-equivalence",
                        "layoutModel": "nfet_01v8",
                        "schematicModel": "sky130_fd_pr__nfet_01v8",
                    ],
                    verificationGates: ["approval-gate", "native-lvs", "artifact-integrity"],
                    rationale: "LVS_MODEL_MISMATCH maps to lvs.policy-repair because an approved model equivalence may be required."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root \(root.path(percentEncoded: false)): \(error)")
        }
    }
}
