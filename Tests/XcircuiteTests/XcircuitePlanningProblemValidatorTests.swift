import Foundation
import PEXEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite planning problem validator")
struct XcircuitePlanningProblemValidatorTests {
    @Test func validatePlanningProblemCLIPersistsValidationArtifact() async throws {
        let root = try makeTemporaryRoot("planning-problem-validation-cli")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-validate", inProjectAt: root)
        let problem = makePlanningProblem(includeSymbolicGoals: true)
        let problemRef = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-validate",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "validate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-validate",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuitePlanningProblemValidationResult.self, from: data)

        #expect(result.status == "valid")
        #expect(result.problemID == "run-validate-drc-repair-problem")
        #expect(result.problemPath == problemRef.path)
        #expect(result.validation.status == "valid")
        #expect(result.validation.diagnostics == [])
        #expect(result.validation.sourceRefCount == 1)
        #expect(result.validation.initialStateRefCount == 1)
        #expect(result.validation.assumptionCount == 1)
        #expect(result.validation.riskClassificationCount == 1)
        #expect(result.validation.objectiveCount == 1)
        #expect(result.validation.candidateActionCount == 1)
        #expect(result.validation.verificationGateCount == 2)
        #expect(result.validationArtifact.id.rawValue == XcircuitePlanningArtifactStore.planningProblemValidationArtifactID)
        #expect(result.validationArtifact.locator.location.value == ".xcircuite/runs/run-validate/planning/problem-validation.json")
        #expect(!result.validationArtifact.digest.hexadecimalValue.isEmpty)
        #expect(result.validationArtifact.byteCount > 0)
        let translationAuditArtifact = try #require(result.problemTranslationAuditArtifact)
        #expect(translationAuditArtifact.id.rawValue == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID)
        #expect(translationAuditArtifact.locator.location.value == ".xcircuite/runs/run-validate/planning/problem-translation-audit.json")
        #expect(result.validation.problemTranslationAuditArtifactID == translationAuditArtifact.id.rawValue)
        #expect(result.validation.problemTranslationAuditPath == translationAuditArtifact.locator.location.value)
        let actionDomainArtifact = try #require(result.actionDomainSnapshotArtifact)
        #expect(actionDomainArtifact.id.rawValue == XcircuitePlanningArtifactStore.actionDomainArtifactID)
        #expect(result.validation.actionDomainSnapshotPath == actionDomainArtifact.locator.location.value)

        let persisted = try store.readJSON(
            XcircuitePlanningProblemValidation.self,
            from: root.appending(path: result.validationArtifact.locator.location.value)
        )
        #expect(persisted == result.validation)

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-validate/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.planningProblemValidationArtifactID
                && $0.path == result.validationArtifact.locator.location.value
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID
                && $0.path == translationAuditArtifact.locator.location.value
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
                && $0.path == actionDomainArtifact.locator.location.value
        })
    }

    @Test func validatePlanningProblemRejectsStaleProblemArtifact() throws {
        let root = try makeTemporaryRoot("planning-problem-validation-stale-artifact")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-validate", inProjectAt: root)
        let problemRef = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makePlanningProblem(includeSymbolicGoals: true),
            runID: "run-validate",
            projectRoot: root
        )
        let problemURL = root.appending(path: problemRef.path)
        let original = try String(contentsOf: problemURL, encoding: .utf8)
        try "\(original)\n".write(to: problemURL, atomically: true, encoding: .utf8)

        do {
            _ = try XcircuitePlanningProblemValidator().validatePlanningProblem(
                request: XcircuitePlanningProblemValidationRequest(runID: "run-validate"),
                projectRoot: root
            )
            Issue.record("Expected stale planning problem artifact rejection")
        } catch let error as XcircuitePlanningProblemValidationError {
            guard case .artifactIntegrityFailed(let path, let status, _) = error else {
                Issue.record("Unexpected validation error: \(error)")
                return
            }
            #expect(path == problemRef.path)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    @Test func validatePlanningProblemRecordsBlockingTranslationAuditGate() async throws {
        let root = try makeTemporaryRoot("planning-problem-validation-audit-block")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-validate", inProjectAt: root)
        var problem = makePlanningProblem(includeSymbolicGoals: true)
        problem.objectives[0].sourceRefIDs = []
        _ = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-validate",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "validate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-validate",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuitePlanningProblemValidationResult.self, from: data)

        #expect(result.status == "invalid")
        #expect(result.validation.diagnostics.contains {
            $0.severity == "error" && $0.code == "problem-translation-audit-blocking"
        })
        let auditArtifact = try #require(result.problemTranslationAuditArtifact)
        let audit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: auditArtifact.path)
        )
        #expect(audit.blocking == true)
        #expect(audit.diagnostics.contains { $0.code == "orphan-objective" })
    }

    @Test func validatePlanningProblemCLIAcceptsGeneratedPEXMetricRecoveryProblem() async throws {
        let root = try makeTemporaryRoot("pex-metric-recovery-validation-cli")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-pex", inProjectAt: root)
        let summaryPath = ".xcircuite/runs/run-pex/stages/009-pex/raw/pex-summary.json"
        let layoutPath = ".xcircuite/runs/run-pex/stages/006-layout/raw/layout.gds"
        let technologyPath = "tech/pex-technology.json"
        let metricReportPath = "reports/post-layout-metrics.json"
        try registerJSONArtifact(
            makePEXSummary(),
            artifactID: "pex-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: "run-pex"
        )
        try registerDataArtifact(
            Data("GDS payload\n".utf8),
            artifactID: "layout-gds",
            path: layoutPath,
            kind: .layout,
            format: .gdsii,
            root: root,
            runID: "run-pex"
        )
        try registerDataArtifact(
            Data(#"{"processName":"test_process","stack":[],"logicalToPhysicalLayerMap":{},"vias":[],"defaultExtractionRules":{"reductionPolicy":"none"},"backendHints":{}}"#.utf8),
            artifactID: "pex-technology",
            path: technologyPath,
            kind: .technology,
            format: .json,
            root: root,
            runID: "run-pex"
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "reports"),
            withIntermediateDirectories: true
        )
        try store.writeJSON(
            makePostLayoutMetricReport(),
            to: root.appending(path: metricReportPath),
            forProjectAt: root
        )

        let generationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-pex",
                "--source",
                "pex-summary",
                "--layout-artifact-id",
                "layout-gds",
                "--source-netlist-path",
                "circuits/top.postpex.spice",
                "--technology-artifact-id",
                "pex-technology",
                "--metric-report-path",
                metricReportPath,
            ]
        )
        let generationData = try #require(generationJSON.data(using: .utf8))
        let generation = try JSONDecoder().decode(
            XcircuitePlanningProblemGenerationResult.self,
            from: generationData
        )
        let problem = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: generation.problemArtifact.path)
        )
        let actionDomainRef = try #require(problem.initialStateRefs.first {
            $0.refID == "action-domain-snapshot"
        })
        let pexRecoveryAction = try #require(problem.candidateActions.first {
            $0.operationID == "pex.metric-recovery-objective"
        })

        let validationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "validate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-pex",
                "--pretty",
            ]
        )
        let validationData = try #require(validationJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(
            XcircuitePlanningProblemValidationResult.self,
            from: validationData
        )

        #expect(generation.status == "generated")
        #expect(generation.problemID == "run-pex-pex-recovery-problem")
        #expect(generation.problemArtifact.artifactID == XcircuitePlanningArtifactStore.problemArtifactID)
        #expect(generation.metricReportPath == metricReportPath)
        #expect(pexRecoveryAction.maturity == "implemented")
        #expect(pexRecoveryAction.requiredInputRefs.contains("post-layout-metric-report"))
        #expect(pexRecoveryAction.requiredInputRefs.contains("pex-technology-ref"))
        #expect(pexRecoveryAction.verificationGates.contains("simulation-metric-gate"))

        #expect(result.status == "valid")
        #expect(result.validation.status == "valid")
        #expect(result.validation.diagnostics == [])
        #expect(result.validation.problemID == generation.problemID)
        #expect(result.validation.problemPath == generation.problemArtifact.path)
        #expect(result.validation.candidateActionCount == problem.candidateActions.count)
        #expect(result.validation.objectiveCount == problem.objectives.count)
        #expect(result.validation.actionDomainSnapshotPath == actionDomainRef.path)

        let actionDomainArtifact = try #require(result.actionDomainSnapshotArtifact)
        #expect(actionDomainArtifact.locator.location.value == actionDomainRef.path)
        let snapshot = try store.readJSON(
            XcircuitePlanningActionDomainSnapshot.self,
            from: root.appending(path: actionDomainArtifact.locator.location.value)
        )
        let pexDomain = try #require(snapshot.domains.first { $0.domainID == "pex-extraction" })
        #expect(pexDomain.ownerPackages.contains("PEXEngine"))
        #expect(pexDomain.ownerPackages.contains("Xcircuite"))
        let pexRecoveryOperation = try #require(pexDomain.operations.first {
            $0.operationID == "pex.metric-recovery-objective"
        })
        #expect(pexRecoveryOperation.maturity == pexRecoveryAction.maturity)
        #expect(pexRecoveryOperation.inputRefs.contains("action-domain-snapshot"))
        #expect(pexRecoveryOperation.producedArtifacts.contains("planning-problem"))
        #expect(pexRecoveryOperation.verificationGates.contains("simulation-metric-gate"))

        let auditArtifact = try #require(result.problemTranslationAuditArtifact)
        let audit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: auditArtifact.path)
        )
        #expect(audit.blocking == false)
        #expect(audit.nextActions == ["validate-planning-problem"])

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-pex/manifest.json")
        )
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.problemArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.planningProblemValidationArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID })
    }

    @Test func validatorRejectsObjectiveWithoutSymbolicGoalAtoms() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-validate",
            generatedAt: "2026-06-21T00:00:00Z"
        )
        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: makePlanningProblem(includeSymbolicGoals: false),
            problemPath: ".xcircuite/runs/run-validate/planning/problem.json",
            actionDomainSnapshot: snapshot
        )

        #expect(validation.status == "invalid")
        #expect(validation.diagnostics.contains {
            $0.severity == "error"
                && $0.code == "objective-goal-atoms-missing"
                && $0.objectiveID == "drc-width-fixed"
        })
    }

    @Test func validatorReportsMissingActionDomainAndInputRefs() throws {
        let snapshot = XcircuitePlanningActionDomainSnapshot(
            runID: "run-validate",
            generatedAt: "2026-06-21T00:00:00Z",
            domains: []
        )
        var problem = makePlanningProblem(includeSymbolicGoals: true)
        problem.candidateActions[0].requiredInputRefs = ["missing-layout-ref"]

        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: problem,
            problemPath: ".xcircuite/runs/run-validate/planning/problem.json",
            actionDomainSnapshot: snapshot
        )

        #expect(validation.status == "invalid")
        #expect(validation.diagnostics.contains {
            $0.code == "action-domain-ref-unsupported"
        })
        #expect(validation.diagnostics.contains {
            $0.code == "candidate-action-required-ref-missing"
                && $0.refID == "missing-layout-ref"
        })
        #expect(validation.diagnostics.contains {
            $0.code == "unsupported-action-domain"
                && $0.actionID == "layout-fix-width"
        })
    }

    @Test func validatorRejectsCandidateActionWithUndeclaredVerificationGate() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-validate",
            generatedAt: "2026-06-21T00:00:00Z"
        )
        var problem = makePlanningProblem(includeSymbolicGoals: true)
        problem.candidateActions[0].verificationGates = ["native-drc", "missing-signoff-gate"]

        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: problem,
            problemPath: ".xcircuite/runs/run-validate/planning/problem.json",
            actionDomainSnapshot: snapshot
        )

        #expect(validation.status == "invalid")
        #expect(validation.diagnostics.contains {
            $0.severity == "error"
                && $0.code == "candidate-action-gate-not-declared"
                && $0.actionID == "layout-fix-width"
                && $0.gateID == "missing-signoff-gate"
        })
    }

    @Test func validatorRejectsUnresolvedRequiredAssumptionAndHighRiskWithoutApproval() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-validate",
            generatedAt: "2026-06-21T00:00:00Z"
        )
        var problem = makePlanningProblem(includeSymbolicGoals: true)
        problem.assumptions[0].status = "unresolved"
        problem.riskClassifications[0] = XcircuitePlanningRiskClassification(
            riskID: "policy-mutation-risk",
            category: "policy-mutation",
            severity: "high",
            scope: "candidate-plan",
            description: "Policy mutation changes signoff semantics.",
            affectedObjectiveIDs: ["drc-width-fixed"],
            affectedActionIDs: ["layout-fix-width"]
        )

        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: problem,
            problemPath: ".xcircuite/runs/run-validate/planning/problem.json",
            actionDomainSnapshot: snapshot
        )

        #expect(validation.status == "invalid")
        #expect(validation.assumptionCount == 1)
        #expect(validation.riskClassificationCount == 1)
        #expect(validation.diagnostics.contains {
            $0.severity == "error"
                && $0.code == "required-assumption-unresolved"
                && $0.assumptionID == "summary-current"
        })
        #expect(validation.diagnostics.contains {
            $0.severity == "error"
                && $0.code == "high-risk-approval-missing"
                && $0.riskID == "policy-mutation-risk"
        })
    }

    @Test func validatorRejectsPEXRecoveryMaturityMismatchWhenActionDomainIsStale() throws {
        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makePEXRecoveryProblem(
            runID: "run-pex",
            summary: makePEXSummary(),
            summaryArtifactPath: ".xcircuite/runs/run-pex/stages/009-pex/raw/pex-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-pex/stages/006-layout/raw/layout.gds",
            sourceNetlistPath: "circuits/top.postpex.spice",
            technologyArtifactPath: "tech/pex-technology.json",
            metricReportPath: "reports/post-layout-metrics.json",
            metricReport: makePostLayoutMetricReport()
        )
        var snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "run-pex",
            generatedAt: "2026-06-21T00:00:00Z"
        )
        let pexDomainIndex = try #require(snapshot.domains.firstIndex {
            $0.domainID == "pex-extraction"
        })
        let recoveryOperationIndex = try #require(snapshot.domains[pexDomainIndex].operations.firstIndex {
            $0.operationID == "pex.metric-recovery-objective"
        })
        snapshot.domains[pexDomainIndex].operations[recoveryOperationIndex].maturity = "planned"

        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: problem,
            problemPath: ".xcircuite/runs/run-pex/planning/problem.json",
            actionDomainSnapshot: snapshot
        )

        #expect(validation.status == "invalid")
        #expect(validation.diagnostics.contains {
            $0.severity == "error"
                && $0.code == "action-domain-maturity-mismatch"
                && $0.actionID == "pex-metric-recovery-1"
        })
    }

    private func makePlanningProblem(includeSymbolicGoals: Bool) -> XcircuiteCircuitPlanningProblem {
        let evidence: [String: XcircuiteJSONValue]
        if includeSymbolicGoals {
            evidence = [
                "symbolicGoalAtoms": .array([
                    .string("rect-shape-created"),
                    .string("artifact:layout-document"),
                ]),
            ]
        } else {
            evidence = [:]
        }

        return XcircuiteCircuitPlanningProblem(
            problemID: "run-validate-drc-repair-problem",
            runID: "run-validate",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "drc-summary",
                    kind: "drc-summary",
                    path: ".xcircuite/runs/run-validate/stages/drc/raw/drc-summary.json",
                    artifactID: "drc-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout",
                    path: ".xcircuite/runs/run-validate/stages/layout/raw/layout.gds"
                ),
            ],
            assumptions: [
                XcircuitePlanningAssumption(
                    assumptionID: "summary-current",
                    source: "test",
                    statement: "The DRC summary matches the layout state.",
                    status: "resolved",
                    confidence: 1,
                    sourceRefIDs: ["drc-summary"],
                    requiredBeforeExecution: true
                ),
            ],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "layout-edit-risk",
                    category: "layout-regression",
                    severity: "medium",
                    scope: "candidate-plan",
                    description: "Layout edits must preserve DRC and artifact integrity.",
                    affectedObjectiveIDs: ["drc-width-fixed"],
                    affectedActionIDs: ["layout-fix-width"],
                    mitigationActions: ["native-drc", "artifact-integrity"]
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "drc-width-fixed",
                    kind: "satisfy",
                    domain: "drc",
                    priority: "error",
                    sourceRefIDs: ["drc-summary"],
                    target: "no-active-violations-for-bucket",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair DRC width violation.",
                    evidence: evidence
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "drc-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "The repaired candidate must pass DRC.",
                    sourceRefIDs: ["drc-summary"]
                ),
            ],
            actionDomainRefs: ["layout-edit"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "layout-fix-width",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Use a concrete layout edit to repair width.",
                    sourceObjectiveIDs: ["drc-width-fixed"],
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-drc"],
                    parameterHints: [
                        "symbolicEffects": .array([
                            .string("rect-shape-created"),
                            .string("artifact:layout-document"),
                        ]),
                    ]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "Edited artifacts must be registered and hashed."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "The candidate must pass native DRC."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makePEXSummary() -> PEXRunSummaryReport {
        PEXRunSummaryReport(
            manifestURL: URL(filePath: "/tmp/pex-manifest.json"),
            completeness: PEXArtifactCompletenessReport(status: .complete, issues: []),
            summary: PEXRunSummary(
                runID: "pex-run-1",
                status: "success",
                backendID: "mock-pex",
                corners: [
                    PEXCornerParasiticSummary(
                        cornerID: "tt",
                        status: "success",
                        netCount: 2,
                        elementCount: 4,
                        topNets: [
                            PEXNetParasiticSummary(
                                name: "OUT",
                                groundCapF: 2.0e-12,
                                couplingCapF: 1.0e-12,
                                resistanceOhm: 42,
                                nodeCount: 3
                            ),
                        ],
                        diagnostics: [
                            PEXRunSummaryDiagnostic(
                                severity: "warning",
                                code: "PEX_WARN_COUPLING",
                                message: "Coupling capacitance is concentrated on OUT."
                            ),
                        ]
                    ),
                ]
            )
        )
    }

    private func makePostLayoutMetricReport() -> PostLayoutComparisonReport {
        PostLayoutComparisonReport(
            status: "completed",
            preLayoutPointCount: 100,
            postLayoutPointCount: 100,
            sweepVariable: "time",
            comparedPointCount: 100,
            maxAbsoluteDelta: 0.15,
            maxRelativeDelta: 0.30,
            comparedVariables: [
                PostLayoutVariableComparison(
                    variableName: "vout",
                    pointCount: 100,
                    maxAbsoluteDelta: 0.15,
                    maxRelativeDelta: 0.30
                ),
            ],
            requiredPostVariables: [
                PostLayoutRequiredVariableResult(variableName: "vout", present: true),
                PostLayoutRequiredVariableResult(variableName: "clk", present: false),
            ],
            oscillationMetrics: [
                PostLayoutOscillationMetricComparison(
                    variableName: "vout",
                    preLayout: PostLayoutOscillationMetric(
                        amplitude: 1.0,
                        frequency: 1_000_000,
                        averagePeriod: 1.0e-6,
                        transitionCount: 10,
                        dutyCycle: 0.50
                    ),
                    postLayout: PostLayoutOscillationMetric(
                        amplitude: 0.82,
                        frequency: 820_000,
                        averagePeriod: 1.22e-6,
                        transitionCount: 8,
                        dutyCycle: 0.57
                    ),
                    frequencyRelativeDelta: 0.18,
                    violations: ["frequency-relative-delta"]
                ),
            ],
            missingInPostLayout: ["clk"],
            addedInPostLayout: [],
            diagnostics: ["post-layout waveform delta exceeded tolerance"],
            gateStatus: "failed",
            gateViolations: ["vout relative delta exceeded tolerance"]
        )
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

    private func registerDataArtifact(
        _ data: Data,
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
        try data.write(to: url, options: .atomic)
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
}
