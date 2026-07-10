import DRCEngine
import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import XcircuitePackage

@Suite("Xcircuite DRC repair loop")
struct XcircuiteDRCRepairLoopTests {
    @Test func repairHintArtifactDrivesCLIPlanningAndVerifiedNotchRepair() async throws {
        let root = try makeTemporaryRoot("repair-hint-artifact-cli-loop")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let runID = "run-hint-notch"
        let layoutPath = "layout/notch-layout.json"
        let layoutNetlistPath = "circuits/layout.spice"
        let schematicNetlistPath = "circuits/schematic.spice"
        let summaryPath = ".xcircuite/runs/\(runID)/stages/native-drc/drc-summary.json"
        let repairHintPath = ".xcircuite/runs/\(runID)/stages/native-drc/drc-repair-hints.json"
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeNotchLayoutDocument(path: layoutPath, root: root)
        try writeMatchingLVSNetlists(
            layoutPath: layoutNetlistPath,
            schematicPath: schematicNetlistPath,
            root: root
        )

        let executionResult = try makeNotchExecutionResult(
            runID: runID,
            layoutPath: layoutPath,
            root: root
        )
        let summary = DRCRunSummaryBuilder().build(result: executionResult)
        let repairHints = DRCRepairHintBuilder().build(result: executionResult)
        try registerJSONArtifact(
            summary,
            artifactID: "drc-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )
        try registerJSONArtifact(
            repairHints,
            artifactID: "drc-repair-hints",
            path: repairHintPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )
        try registerExistingArtifact(
            artifactID: "layout-document",
            path: layoutPath,
            kind: .layout,
            format: .json,
            root: root,
            runID: runID
        )

        let generationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--source",
                "drc-summary",
                "--layout-artifact-id",
                "layout-document",
                "--repair-hint-artifact-id",
                "drc-repair-hints",
                "--layout-netlist-path",
                layoutNetlistPath,
                "--schematic-netlist-path",
                schematicNetlistPath,
            ]
        )
        let generationData = try #require(generationJSON.data(using: .utf8))
        let generation = try JSONDecoder().decode(
            XcircuitePlanningProblemGenerationResult.self,
            from: generationData
        )
        #expect(generation.status == "generated")
        #expect(generation.summaryPath == summaryPath)
        #expect(generation.repairHintPath == repairHintPath)

        let problem = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: generation.problemArtifact.path)
        )
        #expect(problem.sourceRefs.contains {
            $0.refID == "drc-repair-hints" && $0.path == repairHintPath
        })
        #expect(problem.objectives.first?.evidence["sourceEngineOperation"] == .string("drc.export-repair-hints"))
        #expect(problem.candidateActions.map(\.operationID) == ["layout.add-rect"])
        #expect(problem.candidateActions.first?.parameterHints["sourceRepairHintID"] == .string("drc-repair-0-M1-notch"))

        let candidateJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let candidateData = try #require(candidateJSON.data(using: .utf8))
        let candidateGeneration = try JSONDecoder().decode(
            XcircuiteCandidatePlanGenerationResult.self,
            from: candidateData
        )
        #expect(candidateGeneration.executionReadiness == "ready")

        let executionJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let executionData = try #require(executionJSON.data(using: .utf8))
        let execution = try JSONDecoder().decode(
            XcircuiteCandidatePlanExecutionResult.self,
            from: executionData
        )
        #expect(execution.status == "executed")

        let verificationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "verify-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--mode",
                "post-execution",
            ]
        )
        let verificationData = try #require(verificationJSON.data(using: .utf8))
        let verification = try JSONDecoder().decode(
            XcircuiteCandidatePlanVerificationResult.self,
            from: verificationData
        )
        #expect(verification.status == "accepted")
        #expect(verification.accepted)

        let verificationDocument = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: verification.planVerificationArtifact.path)
        )
        #expect(verificationDocument.gateResults.contains { $0.gateID == "native-drc" && $0.status == "passed" })
        #expect(verificationDocument.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" })
        #expect(verificationDocument.goalCoverageStatus == "covered")
        #expect(verificationDocument.missingGoalAtoms.isEmpty)
        #expect(verificationDocument.finalSymbolicState.contains("rect-shape-created"))
        #expect(verificationDocument.finalSymbolicState.contains("artifact:layout-document"))
        #expect(verificationDocument.artifactRefs.contains { $0.artifactID == "planning-native-drc-summary" })
        #expect(verificationDocument.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" })
    }

    @Test func notchRepairPlanFromDiagnosticFillsRegionAndPassesNativeDRC() async throws {
        let root = try makeTemporaryRoot("notch-diagnostic-repair-loop")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let runID = "run-notch"
        let layoutPath = "layout/notch-layout.json"
        let layoutNetlistPath = "circuits/layout.spice"
        let schematicNetlistPath = "circuits/schematic.spice"
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeNotchLayoutDocument(path: layoutPath, root: root)
        try writeMatchingLVSNetlists(
            layoutPath: layoutNetlistPath,
            schematicPath: schematicNetlistPath,
            root: root
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: runID,
            summary: makeNotchSummary(runID: runID),
            summaryArtifactPath: ".xcircuite/runs/\(runID)/stages/native-drc/drc-summary.json",
            layoutArtifactPath: layoutPath,
            layoutNetlistPath: layoutNetlistPath,
            schematicNetlistPath: schematicNetlistPath
        )
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: runID,
            projectRoot: root
        )

        let generation = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: runID),
            projectRoot: root
        )
        #expect(generation.executionReadiness == "ready")
        let generatedPlan = try store.readJSON(
            XcircuiteCandidatePlan.self,
            from: root.appending(path: generation.candidatePlanArtifact.path)
        )
        let step = try #require(generatedPlan.steps.first)
        #expect(step.operationID == "layout.add-rect")
        #expect(step.requiredInputRefs == ["layout-ref"])
        #expect(step.parameterHints["inputDocumentPath"] == nil)
        #expect(step.parameterHints["originX"] == .number(1.0))
        #expect(step.parameterHints["originY"] == .number(0.0))
        #expect(step.parameterHints["width"] == .number(0.2))
        #expect(step.parameterHints["height"] == .number(2.0))
        #expect(step.parameterHints["shapeID"] == nil)
        #expect(step.parameterHints["drcRules"] != nil)
        #expect(step.parameterHints["lvsInputs"] != nil)

        let execution = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: runID),
            projectRoot: root
        )
        #expect(execution.status == "executed")
        let finalLayoutRef = try #require(
            execution.producedArtifacts.first { $0.artifactID == "candidate-step-1-layout-document" }
        )
        let finalLayoutText = try String(
            contentsOf: root.appending(path: finalLayoutRef.path),
            encoding: .utf8
        )
        #expect(finalLayoutText.contains("10000000-0000-0000-0000-00000000000D"))

        let verification = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: runID,
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )
        let verificationDocument = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: verification.planVerificationArtifact.path)
        )
        #expect(verificationDocument.gateResults.contains { $0.gateID == "native-drc" && $0.status == "passed" })
        #expect(verificationDocument.artifactRefs.contains { $0.artifactID == "planning-native-drc-summary" })
        #expect(verificationDocument.goalCoverageStatus == "covered")
        #expect(verificationDocument.missingGoalAtoms.isEmpty)
        #expect(verificationDocument.finalSymbolicState.contains("rect-shape-created"))
        #expect(verificationDocument.finalSymbolicState.contains("artifact:layout-document"))
        #expect(verification.status == "accepted")
        #expect(verification.accepted)
        #expect(verification.nextActions.isEmpty)
        #expect(verificationDocument.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" })
        #expect(verificationDocument.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" })
    }

    @Test func closedDRCRepairLoopRejectsFailingCandidateAndAcceptsRepairedLayout() async throws {
        let root = try makeTemporaryRoot("closed-drc-repair-loop")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try prepareRun(root: root, runID: "run-1")

        try persistCandidatePlan(makeDRCPlan(runID: "run-1", planID: "run-1-drc-width-failing-plan", width: 0.5), root: root)
        _ = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-1"),
            projectRoot: root
        )

        let rejected = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-1",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(rejected.status == "rejected")
        #expect(rejected.accepted == false)
        #expect(rejected.nextActions.contains("repair-verification-gate:native-drc"))
        let rejectedVerification = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: rejected.planVerificationArtifact.path)
        )
        #expect(rejectedVerification.gateResults.contains { $0.gateID == "native-drc" && $0.status == "failed" })
        #expect(rejectedVerification.diagnostics.contains { $0.code == "M1.width" })
        let rejectedPlansArtifact = try #require(rejected.rejectedPlansArtifact)
        let rejectedRecordsAfterFailure = try readJSONLines(
            XcircuiteRejectedPlanRecord.self,
            from: root.appending(path: rejectedPlansArtifact.path)
        )
        let rejectedRecord = try #require(rejectedRecordsAfterFailure.last)
        #expect(rejectedRecord.status == "rejected")
        #expect(rejectedRecord.planID == "run-1-drc-width-failing-plan")
        #expect(rejectedRecord.failedGateIDs.contains("native-drc"))
        #expect(rejectedRecord.diagnostics.contains { $0.code == "M1.width" })

        try persistCandidatePlan(makeDRCPlan(runID: "run-1", planID: "run-1-drc-width-repaired-plan", width: 2.0), root: root)
        _ = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-1"),
            projectRoot: root
        )

        let accepted = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-1",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(accepted.status == "accepted")
        #expect(accepted.accepted)
        #expect(accepted.nextActions.isEmpty)
        let acceptedVerification = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: accepted.planVerificationArtifact.path)
        )
        #expect(acceptedVerification.gateResults.contains { $0.gateID == "native-drc" && $0.status == "passed" })
        #expect(acceptedVerification.artifactRefs.contains { $0.artifactID == "planning-native-drc-summary" })
        #expect(acceptedVerification.artifactRefs.contains { $0.artifactID == "planning-native-drc-layout" })

        let rejectedRecordsAfterRepair = try readJSONLines(
            XcircuiteRejectedPlanRecord.self,
            from: root.appending(path: rejectedPlansArtifact.path)
        )
        #expect(rejectedRecordsAfterRepair.count == 1)
        #expect(rejectedRecordsAfterRepair.first?.planID == "run-1-drc-width-failing-plan")

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.contains { $0.artifactID == "planning-native-drc-summary" })
        #expect(manifest.artifacts.contains { $0.artifactID == "planning-native-drc-layout" })
        #expect(FileManager.default.fileExists(
            atPath: root.appending(path: ".xcircuite/runs/run-1/design-diff.json").path(percentEncoded: false)
        ))
        let action = try #require(store.loadRunActions(runID: "run-1", inProjectAt: root).last)
        #expect(action.status == .succeeded)
    }

    private func prepareRun(root: URL, runID: String) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makeDRCProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )
    }

    private func makeDRCProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-drc-repair-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "drc-m1-width",
                    kind: "satisfy",
                    domain: "drc",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "no-active-width-violations",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair the M1 minimum-width violation."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "native-drc-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "The repaired layout must pass native DRC.",
                    sourceRefIDs: []
                ),
            ],
            actionDomainRefs: ["layout-edit", "drc-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "layout-add-m1-rect",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Resize the M1 rectangle and rerun native DRC.",
                    sourceObjectiveIDs: ["drc-m1-width"],
                    requiredInputRefs: [],
                    verificationGates: ["artifact-integrity", "native-drc"]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate layout must pass native DRC."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeDRCPlan(runID: String, planID: String, width: Double) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: planID,
            problemID: "\(runID)-drc-repair-problem",
            runID: runID,
            strategy: "closed-drc-width-repair",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "layout-add-m1-rect",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["drc-m1-width"],
                    requiredInputRefs: [],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "native-drc"],
                    reason: "Materialize the candidate M1 rectangle and verify the width rule.",
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000010001"),
                        "shapeID": .string("10000000-0000-0000-0000-000000010003"),
                        "cellName": .string("top"),
                        "layer": .string("M1"),
                        "originX": .number(0),
                        "originY": .number(0),
                        "width": .number(width),
                        "height": .number(1),
                        "drcRules": .array([
                            .object([
                                "id": .string("M1.width"),
                                "kind": .string("minimumWidth"),
                                "layer": .string("M1"),
                                "value": .number(1.0),
                            ]),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate layout must pass native DRC."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func makeNotchSummary(runID: String) -> DRCRunSummaryReport {
        DRCRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: DRCRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native DRC",
                topCell: "top",
                layoutFormat: "layout-document-json",
                passed: false,
                completed: true,
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeViolationCount: 1,
                waivedViolationCount: 0,
                violationBuckets: [
                    DRCViolationBucketSummary(
                        ruleID: "M1.notch",
                        kind: "minimumNotch",
                        layer: "M1",
                        activeCount: 1,
                        waivedCount: 0,
                        maxMeasured: 0.2,
                        required: 0.5,
                        representativeRegion: DRCRegion(x: 1.0, y: 0.0, width: 0.2, height: 2.0),
                        relatedShapeIDs: [
                            "10000000-0000-0000-0000-000000000202",
                            "10000000-0000-0000-0000-000000000203",
                            "10000000-0000-0000-0000-000000000204",
                        ],
                        relatedNetIDs: [],
                        suggestedFixes: ["fill notch region"]
                    ),
                ],
                unusedWaiverIDs: []
            )
        )
    }

    private func writeNotchLayoutDocument(path: String, root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let text = """
        {
          "cells" : [
            {
              "constraints" : [],
              "id" : "10000000-0000-0000-0000-000000000201",
              "instances" : [],
              "labels" : [],
              "name" : "top",
              "nets" : [],
              "pins" : [],
              "properties" : {},
              "shapes" : [
                {
                  "geometry" : {
                    "kind" : "rect",
                    "rect" : {
                      "origin" : { "x" : 0, "y" : 0 },
                      "size" : { "height" : 3, "width" : 1 }
                    }
                  },
                  "id" : "10000000-0000-0000-0000-000000000202",
                  "layer" : { "name" : "M1", "purpose" : "drawing" },
                  "properties" : {}
                },
                {
                  "geometry" : {
                    "kind" : "rect",
                    "rect" : {
                      "origin" : { "x" : 1.2, "y" : 0 },
                      "size" : { "height" : 3, "width" : 1 }
                    }
                  },
                  "id" : "10000000-0000-0000-0000-000000000203",
                  "layer" : { "name" : "M1", "purpose" : "drawing" },
                  "properties" : {}
                },
                {
                  "geometry" : {
                    "kind" : "rect",
                    "rect" : {
                      "origin" : { "x" : 0, "y" : 2 },
                      "size" : { "height" : 1, "width" : 2.2 }
                    }
                  },
                  "id" : "10000000-0000-0000-0000-000000000204",
                  "layer" : { "name" : "M1", "purpose" : "drawing" },
                  "properties" : {}
                }
              ],
              "vias" : []
            }
          ],
          "id" : "10000000-0000-0000-0000-000000000200",
          "name" : "notch-layout",
          "topCellID" : "10000000-0000-0000-0000-000000000201",
          "units" : { "dbuPerMicron" : 1000 }
        }
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMatchingLVSNetlists(
        layoutPath: String,
        schematicPath: String,
        root: URL
    ) throws {
        let netlist = """
        .subckt top in out vdd vss
        M1 out in vdd vdd pmos W=1u L=0.15u
        M2 out in vss vss nmos W=1u L=0.15u
        .ends top
        """
        try writeText(netlist, path: layoutPath, root: root)
        try writeText(netlist, path: schematicPath, root: root)
    }

    private func writeText(_ text: String, path: String, root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func persistCandidatePlan(_ plan: XcircuiteCandidatePlan, root: URL) throws {
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            plan,
            runID: plan.runID,
            projectRoot: root
        )
    }

    private func makeNotchExecutionResult(
        runID: String,
        layoutPath: String,
        root: URL
    ) throws -> DRCExecutionResult {
        let layoutURL = try XcircuitePackageStore().url(
            forProjectRelativePath: layoutPath,
            inProjectAt: root
        )
        return DRCExecutionResult(
            request: DRCRequest(
                layoutURL: layoutURL,
                topCell: "top",
                backendSelection: DRCBackendSelection(backendID: "native")
            ),
            result: DRCResult(
                backendID: "native",
                toolName: "Native DRC",
                success: true,
                completed: true,
                logPath: ".xcircuite/runs/\(runID)/stages/native-drc/drc.log",
                diagnostics: [
                    DRCDiagnostic(
                        severity: .error,
                        message: "M1 notch is below the required width.",
                        ruleID: "M1.notch",
                        count: 1,
                        kind: "minimumNotch",
                        layer: "M1",
                        measured: 0.2,
                        required: 0.5,
                        unit: "um",
                        region: DRCRegion(x: 1.0, y: 0.0, width: 0.2, height: 2.0),
                        relatedShapeIDs: [
                            "10000000-0000-0000-0000-000000000202",
                            "10000000-0000-0000-0000-000000000203",
                            "10000000-0000-0000-0000-000000000204",
                        ],
                        suggestedFix: "fill notch region",
                        rawLine: "M1.notch minimumNotch measured=0.2 required=0.5"
                    ),
                ]
            )
        )
    }

    private func registerJSONArtifact<T: Encodable>(
        _ value: T,
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(value, to: url, forProjectAt: root)
        try registerExistingArtifact(
            artifactID: artifactID,
            path: path,
            kind: kind,
            format: format,
            root: root,
            runID: runID
        )
    }

    private func registerExistingArtifact(
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let reference = try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: root,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: root)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteDRCRepairLoopTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .map { line in
                try decoder.decode(type, from: Data(line.utf8))
            }
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
