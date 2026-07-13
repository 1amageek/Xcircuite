import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite improvement planning artifacts")
struct XcircuiteImprovementPlanningArtifactTests {
    @Test func cp7ArtifactsPersistIntoRunManifest() throws {
        let root = try makeTemporaryRoot("cp7-artifacts")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)

        let planningStore = XcircuitePlanningArtifactStore()
        let thresholdRef = try planningStore.persistMetricThresholdProfile(
            makeThresholdProfile(),
            runID: "run-1",
            projectRoot: root
        )
        let calibrationRef = try planningStore.persistCostCalibrationReport(
            makeCalibrationReport(thresholdArtifactID: thresholdRef.artifactID),
            runID: "run-1",
            projectRoot: root
        )
        let paretoRef = try planningStore.persistParetoCandidates(
            try makeParetoSet(thresholdArtifactID: thresholdRef.artifactID, calibrationArtifactID: calibrationRef.artifactID),
            runID: "run-1",
            projectRoot: root
        )
        let loopRef = try planningStore.persistImprovementLoop(
            makeImprovementLoop(
                thresholdArtifactID: thresholdRef.artifactID,
                calibrationArtifactID: calibrationRef.artifactID,
                paretoArtifactID: paretoRef.artifactID
            ),
            runID: "run-1",
            projectRoot: root
        )

        #expect(thresholdRef.path == ".xcircuite/runs/run-1/planning/metric-threshold-profile.json")
        #expect(calibrationRef.path == ".xcircuite/runs/run-1/planning/cost-calibration.json")
        #expect(paretoRef.path == ".xcircuite/runs/run-1/planning/pareto-candidates.jsonl")
        #expect(loopRef.path == ".xcircuite/runs/run-1/planning/improvement-loop.json")
        #expect([thresholdRef, calibrationRef, paretoRef, loopRef].allSatisfy { $0.sha256 != nil && $0.byteCount != nil })

        let persistedProfile = try packageStore.readJSON(
            XcircuiteMetricThresholdProfile.self,
            from: root.appending(path: thresholdRef.path)
        )
        #expect(persistedProfile.thresholds.map(\.metricID) == ["metric-vfinal"])

        let persistedCalibration = try packageStore.readJSON(
            XcircuiteCostCalibrationReport.self,
            from: root.appending(path: calibrationRef.path)
        )
        #expect(persistedCalibration.thresholdProfileArtifactID == thresholdRef.artifactID)
        #expect(persistedCalibration.calibratedTerms.first?.calibratedWeight == 2.0)

        let paretoCandidates = try readJSONLines(
            XcircuiteParetoCandidateSet.Candidate.self,
            from: root.appending(path: paretoRef.path)
        )
        #expect(paretoCandidates.map(\.candidateID) == ["candidate-a", "candidate-b"])
        #expect(paretoCandidates.first?.runID == "run-1")

        let persistedLoop = try packageStore.readJSON(
            XcircuiteImprovementLoopResult.self,
            from: root.appending(path: loopRef.path)
        )
        #expect(persistedLoop.thresholdProfileArtifactID == thresholdRef.artifactID)
        #expect(persistedLoop.costCalibrationArtifactID == calibrationRef.artifactID)
        #expect(persistedLoop.paretoCandidateArtifactID == paretoRef.artifactID)

        let manifest = try packageStore.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        for reference in [thresholdRef, calibrationRef, paretoRef, loopRef] {
            #expect(manifest.artifacts.contains {
                $0.artifactID == reference.artifactID
                    && $0.path == reference.path
                    && $0.sha256 == reference.sha256
                    && $0.byteCount == reference.byteCount
            })
        }
    }

    @Test func paretoCandidateSetRejectsMalformedDecisionEvidence() throws {
        let validMetric = try XcircuiteParetoCandidateSet.Metric(
            metricID: "metric-vfinal",
            value: 1.25,
            normalizedValue: 0.0,
            direction: "at-least",
            unit: "V"
        )
        let validCandidate = try XcircuiteParetoCandidateSet.Candidate(
            runID: "run-1",
            problemID: "problem-1",
            generatedAt: "2026-06-22T00:00:02Z",
            candidateID: "candidate-a",
            sourceCandidateID: "parameter-candidate-a",
            frontierRank: 1,
            metrics: [validMetric],
            gateStatuses: ["simulation-metric-gate": "passed"],
            rationale: "Meets the threshold with low cost."
        )

        func expectParetoValidationFailure(
            expectedError: XcircuiteParetoCandidateSetValidationError,
            operation: () throws -> Void
        ) {
            do {
                try operation()
                Issue.record("Expected Pareto candidate validation to fail.")
            } catch let error as XcircuiteParetoCandidateSetValidationError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected Pareto candidate validation error: \(error)")
            }
        }

        expectParetoValidationFailure(
            expectedError: .nonFiniteMetricValue(metricID: "metric-vfinal", field: "value")
        ) {
            _ = try XcircuiteParetoCandidateSet.Metric(
                metricID: "metric-vfinal",
                value: .infinity,
                normalizedValue: 0.0,
                direction: "at-least",
                unit: "V"
            )
        }
        expectParetoValidationFailure(
            expectedError: .invalidFrontierRank(candidateID: "candidate-a", rank: 0)
        ) {
            _ = try XcircuiteParetoCandidateSet.Candidate(
                runID: "run-1",
                problemID: "problem-1",
                generatedAt: "2026-06-22T00:00:02Z",
                candidateID: "candidate-a",
                frontierRank: 0,
                metrics: [validMetric],
                gateStatuses: ["simulation-metric-gate": "passed"],
                rationale: "Invalid rank."
            )
        }
        expectParetoValidationFailure(
            expectedError: .selfDominatedCandidateID("candidate-a")
        ) {
            _ = try XcircuiteParetoCandidateSet.Candidate(
                runID: "run-1",
                problemID: "problem-1",
                generatedAt: "2026-06-22T00:00:02Z",
                candidateID: "candidate-a",
                frontierRank: 1,
                dominatedByCandidateIDs: ["candidate-a"],
                metrics: [validMetric],
                gateStatuses: ["simulation-metric-gate": "passed"],
                rationale: "Invalid dominance."
            )
        }
        expectParetoValidationFailure(
            expectedError: .duplicateIdentifier(
                field: "sourceCandidateArtifactIDs",
                value: "planning-parameter-candidates"
            )
        ) {
            _ = try XcircuiteParetoCandidateSet(
                runID: "run-1",
                problemID: "problem-1",
                generatedAt: "2026-06-22T00:00:02Z",
                sourceCandidateArtifactIDs: [
                    "planning-parameter-candidates",
                    "planning-parameter-candidates",
                ],
                candidates: [validCandidate]
            )
        }
        expectParetoValidationFailure(
            expectedError: .candidateRunMismatch(
                candidateID: "candidate-a",
                expected: "run-2",
                actual: "run-1"
            )
        ) {
            _ = try XcircuiteParetoCandidateSet(
                runID: "run-2",
                problemID: "problem-1",
                generatedAt: "2026-06-22T00:00:02Z",
                candidates: [validCandidate]
            )
        }
        expectParetoValidationFailure(
            expectedError: .candidateProblemUnexpected(candidateID: "candidate-a", actual: "problem-1")
        ) {
            _ = try XcircuiteParetoCandidateSet(
                runID: "run-1",
                generatedAt: "2026-06-22T00:00:02Z",
                candidates: [validCandidate]
            )
        }
        expectParetoValidationFailure(
            expectedError: .unknownSelectedCandidateID("candidate-missing")
        ) {
            _ = try XcircuiteParetoCandidateSet(
                runID: "run-1",
                problemID: "problem-1",
                generatedAt: "2026-06-22T00:00:02Z",
                candidates: [validCandidate],
                selectedCandidateID: "candidate-missing"
            )
        }

        let invalidCandidateJSON = Data(
            """
            {
              "runID": "run-1",
              "problemID": "problem-1",
              "generatedAt": "2026-06-22T00:00:02Z",
              "candidateID": "candidate-a",
              "frontierRank": 0,
              "dominatedByCandidateIDs": [],
              "metrics": [],
              "gateStatuses": {},
              "rationale": "Invalid rank."
            }
            """.utf8
        )
        expectParetoValidationFailure(
            expectedError: .invalidFrontierRank(candidateID: "candidate-a", rank: 0)
        ) {
            _ = try JSONDecoder().decode(
                XcircuiteParetoCandidateSet.Candidate.self,
                from: invalidCandidateJSON
            )
        }
    }

    @Test func generateImprovementArtifactsCLIReadsNumericRepairLoopOutcome() async throws {
        let root = try makeTemporaryRoot("cp7-cli")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)

        let planningStore = XcircuitePlanningArtifactStore()
        try planningStore.persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-1",
            projectRoot: root
        )
        let selectionTraceRef = try planningStore.persistParameterCandidateSelectionTrace(
            makeSelectionTrace(),
            runID: "run-1",
            projectRoot: root
        )
        try planningStore.persistNumericRepairLoop(
            makeNumericRepairLoop(selectionTraceRef: selectionTraceRef),
            runID: "run-1",
            projectRoot: root
        )

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "generate-improvement-artifacts",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--generated-at",
            "2026-06-22T00:00:03Z",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteImprovementPlanningArtifactGenerationResult.self,
            from: try #require(output.data(using: .utf8))
        )

        #expect(result.status == "generated")
        #expect(!result.accepted)
        #expect(result.iterationCount == 1)
        #expect(result.thresholdProfileArtifact.path == ".xcircuite/runs/run-1/planning/metric-threshold-profile.json")
        #expect(result.costCalibrationArtifact.path == ".xcircuite/runs/run-1/planning/cost-calibration.json")
        #expect(result.paretoCandidatesArtifact.path == ".xcircuite/runs/run-1/planning/pareto-candidates.jsonl")
        #expect(result.improvementLoopArtifact.path == ".xcircuite/runs/run-1/planning/improvement-loop.json")
        #expect(result.rejectedFeedbackLearningReportArtifact?.path == ".xcircuite/runs/run-1/planning/rejected-feedback-learning-report.json")

        let profile = try packageStore.readJSON(
            XcircuiteMetricThresholdProfile.self,
            from: root.appending(path: result.thresholdProfileArtifact.path)
        )
        #expect(profile.thresholds.first?.metricID == "metric-vfinal")
        #expect(profile.thresholds.first?.targetValue == 0.889)

        let calibration = try packageStore.readJSON(
            XcircuiteCostCalibrationReport.self,
            from: root.appending(path: result.costCalibrationArtifact.path)
        )
        #expect(calibration.observations.first?.candidateID == "iteration-1-candidate-a")
        #expect(calibration.observations.first?.failedGateIDs == ["simulation-metric-gate"])
        #expect(calibration.calibratedTerms.first?.gateID == "simulation-metric-gate")

        let paretoCandidates = try readJSONLines(
            XcircuiteParetoCandidateSet.Candidate.self,
            from: root.appending(path: result.paretoCandidatesArtifact.path)
        )
        #expect(paretoCandidates.first?.candidateID == "iteration-1-candidate-a")
        #expect(paretoCandidates.first?.gateStatuses["simulation-metric-gate"] == "failed")

        let loop = try packageStore.readJSON(
            XcircuiteImprovementLoopResult.self,
            from: root.appending(path: result.improvementLoopArtifact.path)
        )
        #expect(loop.status == "iteration-limit-reached")
        #expect(loop.iterations.first?.failedGateIDs == ["simulation-metric-gate"])

        let manifest = try packageStore.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        for reference in [
            result.thresholdProfileArtifact,
            result.costCalibrationArtifact,
            result.paretoCandidatesArtifact,
            result.improvementLoopArtifact,
            result.rejectedFeedbackLearningReportArtifact,
        ].compactMap({ $0 }) {
            #expect(manifest.artifacts.contains {
                $0.artifactID == reference.artifactID
                    && $0.path == reference.path
                    && $0.sha256 == reference.sha256
                    && $0.byteCount == reference.byteCount
            })
        }
    }

    @Test func rejectedFeedbackLearningReportPersistsRankImpactAndFailureProvenance() async throws {
        let root = try makeTemporaryRoot("feedback-learning")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)

        let planningStore = XcircuitePlanningArtifactStore()
        try planningStore.persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-1",
            projectRoot: root
        )
        let rejectedPlansRef = try planningStore.appendRejectedPlan(
            makeRejectedPlanRecord(),
            runID: "run-1",
            projectRoot: root
        )
        let selectionTraceRef = try planningStore.persistParameterCandidateSelectionTrace(
            makeRankChangingSelectionTrace(rejectedPlansPath: rejectedPlansRef.path),
            runID: "run-1",
            projectRoot: root
        )
        try planningStore.persistNumericRepairLoop(
            makeNumericRepairLoopWithRankChange(
                selectionTraceRef: selectionTraceRef,
                rejectedPlansRef: rejectedPlansRef
            ),
            runID: "run-1",
            projectRoot: root
        )

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "generate-improvement-artifacts",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-1",
            "--generated-at",
            "2026-06-22T00:00:04Z",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteImprovementPlanningArtifactGenerationResult.self,
            from: try #require(output.data(using: .utf8))
        )
        let learningRef = try #require(result.rejectedFeedbackLearningReportArtifact)
        let report = try packageStore.readJSON(
            XcircuiteRejectedFeedbackLearningReport.self,
            from: root.appending(path: learningRef.path)
        )

        #expect(report.rejectedPlansPath == rejectedPlansRef.path)
        #expect(report.rejectedRecordCount == 1)
        #expect(report.impactedCandidateCount == 1)
        #expect(report.penalizedCandidateCount == 1)
        #expect(report.rankChangedCandidateCount == 1)
        #expect(report.scoreDeltaCandidateCount == 1)
        #expect(report.retainedFailedGateIDs == ["simulation-metric-gate"])
        #expect(report.retainedDiagnosticCodes == ["metric-failed"])
        let impact = try #require(report.feedbackImpacts.first)
        #expect(impact.candidateID == "candidate-a")
        #expect(impact.feedbackFreeRank == 1)
        #expect(impact.feedbackAwareRank == 2)
        #expect(impact.rankDelta == 1)
        #expect(impact.feedbackPenalty == 1.0)
        #expect(impact.sourceRejectionIDs == ["rejection-a"])
        #expect(impact.sourcePlanIDs == ["plan-a"])

        let manifest = try packageStore.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.rejectedFeedbackLearningReportArtifactID
                && $0.path == learningRef.path
                && $0.sha256 == learningRef.sha256
                && $0.byteCount == learningRef.byteCount
        })
    }

    @Test func rejectedFeedbackLearningReportRejectsMalformedDecisionEvidence() throws {
        let validImpact = try makeValidRejectedFeedbackImpact()
        let longProvenanceID =
            "run-cp7-run-cp7-numeric-repair-problem-run-cp7-numeric-repair-problem-parameter-candidate-metric-search-1-R1-1000-ohm-edit-plan-post-execution-rejected"
        let longProvenanceImpact = try makeValidRejectedFeedbackImpact(
            sourceRejectionIDs: [longProvenanceID],
            sourcePlanIDs: [longProvenanceID]
        )
        #expect(longProvenanceImpact.sourceRejectionIDs == [longProvenanceID])

        #expect(throws: XcircuiteRejectedFeedbackLearningReportValidationError.unsupportedSchemaVersion(2)) {
            _ = try makeValidRejectedFeedbackLearningReport(
                schemaVersion: 2,
                feedbackImpacts: [validImpact]
            )
        }
        #expect(throws: XcircuiteRejectedFeedbackLearningReportValidationError.invalidProjectRelativePath(
            field: "numericRepairLoopPath",
            path: "../escape.json"
        )) {
            _ = try makeValidRejectedFeedbackLearningReport(
                numericRepairLoopPath: "../escape.json",
                feedbackImpacts: [validImpact]
            )
        }
        #expect(throws: XcircuiteRejectedFeedbackLearningReportValidationError.countMismatch(
            field: "impactedCandidateCount",
            expected: 1,
            actual: 0
        )) {
            _ = try makeValidRejectedFeedbackLearningReport(
                impactedCandidateCount: 0,
                feedbackImpacts: [validImpact]
            )
        }
        #expect(throws: XcircuiteRejectedFeedbackLearningReportValidationError.rankDeltaMismatch(
            candidateID: "candidate-a",
            expected: 1,
            actual: 0
        )) {
            _ = try makeValidRejectedFeedbackImpact(rankDelta: 0)
        }
        #expect(throws: XcircuiteRejectedFeedbackLearningReportValidationError.nonFiniteValue(
            field: "totalScore",
            candidateID: "candidate-a",
            value: .infinity
        )) {
            _ = try makeValidRejectedFeedbackImpact(totalScore: .infinity)
        }
        #expect(throws: XcircuiteRejectedFeedbackLearningReportValidationError.negativeValue(
            field: "penaltyComponents.appliedPenalty",
            candidateID: "candidate-a",
            value: -1.0
        )) {
            _ = try makeValidRejectedFeedbackImpact(penaltyComponents: [
                XcircuiteParameterCandidateFeedbackPenaltyComponent(
                    componentID: "candidate-feedback:candidate-a",
                    itemCount: 1,
                    unitPenalty: 1.0,
                    appliedPenalty: -1.0
                ),
            ])
        }

        let malformedReportJSON = """
        {
          "schemaVersion": 1,
          "runID": "run-1",
          "problemID": "problem-1",
          "generatedAt": "2026-06-22T00:00:04Z",
          "numericRepairLoopPath": ".xcircuite/runs/run-1/planning/numeric-repair-loop.json",
          "rejectedPlansPath": ".xcircuite/runs/run-1/planning/rejected-plans.jsonl",
          "rejectedRecordCount": 1,
          "selectionTraceArtifactIDs": ["planning-selection-trace"],
          "impactedCandidateCount": 0,
          "penalizedCandidateCount": 1,
          "rankChangedCandidateCount": 1,
          "scoreDeltaCandidateCount": 1,
          "retainedFailedGateIDs": ["simulation-metric-gate"],
          "retainedDiagnosticCodes": ["metric-failed"],
          "feedbackImpacts": [
            {
              "iterationIndex": 0,
              "candidateID": "candidate-a",
              "feedbackFreeRank": 1,
              "feedbackAwareRank": 2,
              "rankDelta": 1,
              "baseCost": 0.5,
              "feedbackPenalty": 1.0,
              "totalScore": 1.5,
              "feedbackStatuses": ["rejected"],
              "failedGateIDs": ["simulation-metric-gate"],
              "diagnosticCodes": ["metric-failed"],
              "penaltyComponents": [
                {
                  "componentID": "candidate-feedback:candidate-a",
                  "itemCount": 1,
                  "unitPenalty": 1.0,
                  "appliedPenalty": 1.0
                }
              ],
              "sourceRejectionIDs": ["rejection-a"],
              "sourcePlanIDs": ["plan-a"]
            }
          ],
          "diagnostics": ["learning-report-generated"]
        }
        """
        #expect(throws: XcircuiteRejectedFeedbackLearningReportValidationError.countMismatch(
            field: "impactedCandidateCount",
            expected: 1,
            actual: 0
        )) {
            _ = try JSONDecoder().decode(
                XcircuiteRejectedFeedbackLearningReport.self,
                from: Data(malformedReportJSON.utf8)
            )
        }
    }

    @Test func generationRejectsAmbiguousCanonicalManifest() throws {
        let root = try makeTemporaryRoot("duplicate-manifest-artifact")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)

        let planningStore = XcircuitePlanningArtifactStore()
        try planningStore.persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-1",
            projectRoot: root
        )
        let selectionTraceRef = try planningStore.persistParameterCandidateSelectionTrace(
            makeSelectionTrace(),
            runID: "run-1",
            projectRoot: root
        )
        try planningStore.persistNumericRepairLoop(
            makeNumericRepairLoop(selectionTraceRef: selectionTraceRef),
            runID: "run-1",
            projectRoot: root
        )

        let stalePath = ".xcircuite/runs/run-1/planning/stale-numeric-repair-loop.json"
        let manifestURL = root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        let staleReference = XcircuiteFileReference(
            artifactID: XcircuitePlanningArtifactStore.numericRepairLoopArtifactID,
            path: stalePath,
            kind: .other,
            format: .json,
            producedByRunID: "run-1"
        )
        try XcircuiteRunManifestTamper.append([staleReference], to: manifestURL)

        #expect(throws: XcircuitePackageError.decodeFailed(
            "manifest.json: Invalid run manifest for run-1: artifactID 'planning-numeric-repair-loop' must be unique."
        )) {
            try XcircuiteImprovementPlanningArtifactGenerator().generateImprovementPlanningArtifacts(
                request: XcircuiteImprovementPlanningArtifactGenerationRequest(
                    runID: "run-1",
                    generatedAt: "2026-06-22T00:00:05Z"
                ),
                projectRoot: root
            )
        }
    }

    @Test func generationRejectsStaleLoopIterationCount() throws {
        let root = try makeTemporaryRoot("stale-loop-count")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)

        let planningStore = XcircuitePlanningArtifactStore()
        try planningStore.persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-1",
            projectRoot: root
        )
        let selectionTraceRef = try planningStore.persistParameterCandidateSelectionTrace(
            makeSelectionTrace(),
            runID: "run-1",
            projectRoot: root
        )
        var loop = makeNumericRepairLoop(selectionTraceRef: selectionTraceRef)
        loop.iterationCount = 2
        try planningStore.persistNumericRepairLoop(
            loop,
            runID: "run-1",
            projectRoot: root
        )

        #expect(throws: XcircuiteImprovementPlanningArtifactGenerationError.loopIterationCountMismatch(
            reported: 2,
            actual: 1
        )) {
            try XcircuiteImprovementPlanningArtifactGenerator().generateImprovementPlanningArtifacts(
                request: XcircuiteImprovementPlanningArtifactGenerationRequest(
                    runID: "run-1",
                    generatedAt: "2026-06-22T00:00:06Z"
                ),
                projectRoot: root
            )
        }
    }

    @Test func generationRejectsDuplicateSelectionCandidateIDs() throws {
        let root = try makeTemporaryRoot("duplicate-selection-candidate")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)

        let planningStore = XcircuitePlanningArtifactStore()
        try planningStore.persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-1",
            projectRoot: root
        )
        let selectionTraceRef = try planningStore.persistParameterCandidateSelectionTrace(
            makeSelectionTraceWithDuplicateCandidateID(),
            runID: "run-1",
            projectRoot: root
        )
        try planningStore.persistNumericRepairLoop(
            makeNumericRepairLoop(selectionTraceRef: selectionTraceRef),
            runID: "run-1",
            projectRoot: root
        )

        #expect(throws: XcircuiteImprovementPlanningArtifactGenerationError.duplicateSelectionCandidateID(
            iterationIndex: 1,
            candidateID: "candidate-a"
        )) {
            try XcircuiteImprovementPlanningArtifactGenerator().generateImprovementPlanningArtifacts(
                request: XcircuiteImprovementPlanningArtifactGenerationRequest(
                    runID: "run-1",
                    generatedAt: "2026-06-22T00:00:07Z"
                ),
                projectRoot: root
            )
        }
    }

    @Test func generationRejectsSelectionTraceRunMismatch() throws {
        let root = try makeTemporaryRoot("selection-trace-run-mismatch")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)

        let planningStore = XcircuitePlanningArtifactStore()
        try planningStore.persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-1",
            projectRoot: root
        )
        var staleTrace = makeSelectionTrace()
        staleTrace.runID = "run-stale"
        let selectionTraceRef = try persistSelectionTraceWithoutRunGate(
            staleTrace,
            runID: "run-1",
            projectRoot: root,
            packageStore: packageStore
        )
        try planningStore.persistNumericRepairLoop(
            makeNumericRepairLoop(selectionTraceRef: selectionTraceRef),
            runID: "run-1",
            projectRoot: root
        )

        #expect(throws: XcircuiteImprovementPlanningArtifactGenerationError.runMismatch(
            expected: "run-1",
            actual: "run-stale"
        )) {
            try XcircuiteImprovementPlanningArtifactGenerator().generateImprovementPlanningArtifacts(
                request: XcircuiteImprovementPlanningArtifactGenerationRequest(
                    runID: "run-1",
                    generatedAt: "2026-06-22T00:00:08Z"
                ),
                projectRoot: root
            )
        }
    }

    private func makeValidRejectedFeedbackLearningReport(
        schemaVersion: Int = 1,
        runID: String = "run-1",
        problemID: String? = "problem-1",
        generatedAt: String = "2026-06-22T00:00:04Z",
        numericRepairLoopPath: String = ".xcircuite/runs/run-1/planning/numeric-repair-loop.json",
        rejectedPlansPath: String? = ".xcircuite/runs/run-1/planning/rejected-plans.jsonl",
        rejectedRecordCount: Int = 1,
        selectionTraceArtifactIDs: [String] = ["planning-selection-trace"],
        impactedCandidateCount: Int? = nil,
        penalizedCandidateCount: Int? = nil,
        rankChangedCandidateCount: Int? = nil,
        scoreDeltaCandidateCount: Int? = nil,
        retainedFailedGateIDs: [String] = ["simulation-metric-gate"],
        retainedDiagnosticCodes: [String] = ["metric-failed"],
        feedbackImpacts: [XcircuiteRejectedFeedbackLearningReport.FeedbackImpact]? = nil,
        diagnostics: [String] = ["learning-report-generated"]
    ) throws -> XcircuiteRejectedFeedbackLearningReport {
        let impacts: [XcircuiteRejectedFeedbackLearningReport.FeedbackImpact]
        if let feedbackImpacts {
            impacts = feedbackImpacts
        } else {
            impacts = [try makeValidRejectedFeedbackImpact()]
        }
        return try XcircuiteRejectedFeedbackLearningReport(
            schemaVersion: schemaVersion,
            runID: runID,
            problemID: problemID,
            generatedAt: generatedAt,
            numericRepairLoopPath: numericRepairLoopPath,
            rejectedPlansPath: rejectedPlansPath,
            rejectedRecordCount: rejectedRecordCount,
            selectionTraceArtifactIDs: selectionTraceArtifactIDs,
            impactedCandidateCount: impactedCandidateCount ?? impacts.count,
            penalizedCandidateCount: penalizedCandidateCount ?? impacts.filter { $0.feedbackPenalty > 0 }.count,
            rankChangedCandidateCount: rankChangedCandidateCount ?? impacts.filter { $0.rankDelta != 0 }.count,
            scoreDeltaCandidateCount: scoreDeltaCandidateCount ?? impacts.filter {
                $0.feedbackPenalty > 0 || !$0.penaltyComponents.isEmpty
            }.count,
            retainedFailedGateIDs: retainedFailedGateIDs,
            retainedDiagnosticCodes: retainedDiagnosticCodes,
            feedbackImpacts: impacts,
            diagnostics: diagnostics
        )
    }

    private func makeValidRejectedFeedbackImpact(
        iterationIndex: Int = 0,
        candidateID: String = "candidate-a",
        feedbackFreeRank: Int = 1,
        feedbackAwareRank: Int = 2,
        rankDelta: Int = 1,
        baseCost: Double = 0.5,
        feedbackPenalty: Double = 1.0,
        totalScore: Double = 1.5,
        feedbackStatuses: [String] = ["rejected"],
        failedGateIDs: [String] = ["simulation-metric-gate"],
        diagnosticCodes: [String] = ["metric-failed"],
        penaltyComponents: [XcircuiteParameterCandidateFeedbackPenaltyComponent]? = nil,
        sourceRejectionIDs: [String] = ["rejection-a"],
        sourcePlanIDs: [String] = ["plan-a"]
    ) throws -> XcircuiteRejectedFeedbackLearningReport.FeedbackImpact {
        let components = penaltyComponents ?? [
            XcircuiteParameterCandidateFeedbackPenaltyComponent(
                componentID: "candidate-feedback:candidate-a",
                itemCount: 1,
                unitPenalty: 1.0,
                appliedPenalty: 1.0
            ),
        ]
        return try XcircuiteRejectedFeedbackLearningReport.FeedbackImpact(
            iterationIndex: iterationIndex,
            candidateID: candidateID,
            feedbackFreeRank: feedbackFreeRank,
            feedbackAwareRank: feedbackAwareRank,
            rankDelta: rankDelta,
            baseCost: baseCost,
            feedbackPenalty: feedbackPenalty,
            totalScore: totalScore,
            feedbackStatuses: feedbackStatuses,
            failedGateIDs: failedGateIDs,
            diagnosticCodes: diagnosticCodes,
            penaltyComponents: components,
            sourceRejectionIDs: sourceRejectionIDs,
            sourcePlanIDs: sourcePlanIDs
        )
    }

    private func makeThresholdProfile() -> XcircuiteMetricThresholdProfile {
        XcircuiteMetricThresholdProfile(
            runID: "run-1",
            problemID: "problem-1",
            profileID: "profile-1",
            generatedAt: "2026-06-22T00:00:00Z",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "spec-1",
                    kind: "design-spec",
                    path: "specs/design.json"
                ),
            ],
            thresholds: [
                XcircuiteMetricThresholdProfile.Threshold(
                    metricID: "metric-vfinal",
                    objectiveID: "objective-vfinal",
                    domain: "simulation",
                    metricName: "vfinal",
                    direction: "at-least",
                    targetValue: 1.2,
                    tolerance: 0.01,
                    unit: "V",
                    severity: "error",
                    sourceRefIDs: ["spec-1"]
                ),
            ],
            policyNotes: ["design-specific metric threshold"]
        )
    }

    private func makePlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "problem-1",
            runID: "run-1",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "simulation-summary",
                    kind: "simulation-metric-report",
                    path: ".xcircuite/runs/run-1/planning/verification/simulation-metric/simulation-summary.json",
                    artifactID: "planning-simulation-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "source-netlist-ref",
                    kind: "source-netlist",
                    path: "circuits/rc.cir"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "metric-vfinal",
                    kind: "improve",
                    domain: "simulation",
                    priority: "error",
                    sourceRefIDs: ["simulation-summary"],
                    target: "measurement-within-tolerance",
                    currentValue: .number(1.0),
                    requiredValue: .number(0.889),
                    unit: "V",
                    description: "Recover simulation metric by bounded parameter search.",
                    evidence: [
                        "metricName": .string("vfinal"),
                        "tolerance": .number(0.02),
                    ]
                ),
            ],
            constraints: [],
            actionDomainRefs: ["simulation-analysis"],
            candidateActions: [],
            costModel: XcircuitePlanningCostModel(
                strategy: "minimize-distance-from-nominal",
                terms: []
            ),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric-gate",
                    required: true,
                    description: "Candidate parameters must satisfy simulation metrics."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: [
                    "planning/problem.json",
                    "planning/numeric-repair-loop.json",
                ],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeSelectionTrace() -> XcircuiteParameterCandidateSelectionTrace {
        XcircuiteParameterCandidateSelectionTrace(
            runID: "run-1",
            problemID: "problem-1",
            strategy: "parameter-candidate-to-netlist-edit",
            parameterCandidatesPath: ".xcircuite/runs/run-1/planning/parameter-candidates.jsonl",
            rejectedPlansPath: nil,
            feedbackWeighting: .defaultPolicy(),
            includeRejectedCandidates: false,
            selectedCandidateID: "candidate-a",
            selectedTotalScore: 1.5,
            rankedCandidates: [
                XcircuiteParameterCandidateSelectionScore(
                    candidateID: "candidate-a",
                    rank: 1,
                    baseCost: 1.0,
                    feedbackPenalty: 0.5,
                    totalScore: 1.5,
                    selectionState: "selected",
                    feedbackStatuses: ["candidate-rejected"],
                    failedGateIDs: ["simulation-metric-gate"],
                    diagnosticCodes: [],
                    nextActions: ["inspect-simulation-metric-gate"]
                ),
            ]
        )
    }

    private func makeSelectionTraceWithDuplicateCandidateID() -> XcircuiteParameterCandidateSelectionTrace {
        var trace = makeSelectionTrace()
        trace.rankedCandidates.append(XcircuiteParameterCandidateSelectionScore(
            candidateID: "candidate-a",
            rank: 2,
            baseCost: 2.0,
            feedbackPenalty: 0,
            totalScore: 2.0,
            selectionState: "duplicate",
            feedbackStatuses: [],
            failedGateIDs: [],
            diagnosticCodes: [],
            nextActions: []
        ))
        return trace
    }

    private func makeRankChangingSelectionTrace(rejectedPlansPath: String) -> XcircuiteParameterCandidateSelectionTrace {
        XcircuiteParameterCandidateSelectionTrace(
            runID: "run-1",
            problemID: "problem-1",
            strategy: "feedback-aware-bounded-refinement",
            parameterCandidatesPath: ".xcircuite/runs/run-1/planning/parameter-candidates.jsonl",
            rejectedPlansPath: rejectedPlansPath,
            feedbackWeighting: .defaultPolicy(),
            includeRejectedCandidates: false,
            selectedCandidateID: "candidate-b",
            selectedTotalScore: 1.0,
            rankedCandidates: [
                XcircuiteParameterCandidateSelectionScore(
                    candidateID: "candidate-b",
                    rank: 1,
                    baseCost: 1.0,
                    feedbackPenalty: 0,
                    totalScore: 1.0,
                    selectionState: "selected",
                    feedbackStatuses: [],
                    failedGateIDs: [],
                    diagnosticCodes: [],
                    nextActions: []
                ),
                XcircuiteParameterCandidateSelectionScore(
                    candidateID: "candidate-a",
                    rank: 2,
                    baseCost: 0.5,
                    feedbackPenalty: 1.0,
                    totalScore: 1.5,
                    feedbackPenaltyComponents: [
                        XcircuiteParameterCandidateFeedbackPenaltyComponent(
                            componentID: "candidate-feedback:candidate-a",
                            itemCount: 1,
                            unitPenalty: 1.0,
                            appliedPenalty: 1.0
                        ),
                    ],
                    selectionState: "feedback-penalized",
                    feedbackStatuses: ["rejected"],
                    failedGateIDs: ["simulation-metric-gate"],
                    diagnosticCodes: ["metric-failed"],
                    nextActions: ["inspect-simulation-metric-gate"]
                ),
            ]
        )
    }

    private func makeRejectedPlanRecord() -> XcircuiteRejectedPlanRecord {
        XcircuiteRejectedPlanRecord(
            rejectionID: "rejection-a",
            runID: "run-1",
            problemID: "problem-1",
            planID: "plan-a",
            verificationMode: "post-execution",
            status: "rejected",
            sourceParameterCandidateIDs: ["candidate-a"],
            failedStepIDs: ["step-a"],
            failedGateIDs: ["simulation-metric-gate"],
            candidatePlanRef: dummyPlanningReference(
                artifactID: "planning-candidate-plan",
                path: ".xcircuite/runs/run-1/planning/candidate-plan.json"
            ),
            planVerificationRef: dummyPlanningReference(
                artifactID: "planning-plan-verification",
                path: ".xcircuite/runs/run-1/planning/plan-verification.json"
            ),
            artifactRefs: [],
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "metric-failed",
                    message: "Simulation metric gate failed.",
                    stepID: "step-a",
                    gateID: "simulation-metric-gate"
                ),
            ],
            nextActions: ["inspect-simulation-metric-gate"]
        )
    }

    private func dummyPlanningReference(artifactID: String, path: String) -> XcircuiteFileReference {
        XcircuiteFileReference(
            artifactID: artifactID,
            path: path,
            kind: .other,
            format: .json,
            producedByRunID: "run-1"
        )
    }

    private func makeNumericRepairLoop(
        selectionTraceRef: XcircuiteFileReference
    ) -> XcircuiteNumericRepairLoopResult {
        XcircuiteNumericRepairLoopResult(
            status: "iteration-limit-reached",
            runID: "run-1",
            problemID: "problem-1",
            loopArtifactPath: ".xcircuite/runs/run-1/planning/numeric-repair-loop.json",
            maxIterations: 1,
            iterationCount: 1,
            accepted: false,
            selectedCandidateID: "candidate-a",
            finalPlanID: "plan-a",
            iterations: [
                XcircuiteNumericRepairLoopIteration(
                    iterationIndex: 1,
                    status: "rejected",
                    candidateGenerationStrategy: "feedback-aware-bounded-refinement",
                    synthesisStrategy: "parameter-candidate-to-netlist-edit",
                    verificationMode: "post-execution",
                    candidateGenerationStatus: "generated",
                    selectedCandidateID: "candidate-a",
                    selectedCandidateRank: 1,
                    planID: "plan-a",
                    verificationStatus: "rejected",
                    accepted: false,
                    selectionTraceArtifact: selectionTraceRef,
                    diagnostics: [
                        XcircuiteNumericRepairLoopDiagnostic(
                            severity: "warning",
                            code: "candidate-rejected",
                            message: "Selected candidate failed simulation metric verification.",
                            iterationIndex: 1
                        ),
                    ],
                    nextActions: ["inspect-simulation-metric-gate"]
                ),
            ],
            diagnostics: [
                XcircuiteNumericRepairLoopDiagnostic(
                    severity: "warning",
                    code: "candidate-rejected",
                    message: "Selected candidate failed simulation metric verification.",
                    iterationIndex: 1
                ),
            ],
            nextActions: ["inspect-numeric-repair-loop"]
        )
    }

    private func makeNumericRepairLoopWithRankChange(
        selectionTraceRef: XcircuiteFileReference,
        rejectedPlansRef: XcircuiteFileReference
    ) -> XcircuiteNumericRepairLoopResult {
        XcircuiteNumericRepairLoopResult(
            status: "iteration-limit-reached",
            runID: "run-1",
            problemID: "problem-1",
            loopArtifactPath: ".xcircuite/runs/run-1/planning/numeric-repair-loop.json",
            maxIterations: 1,
            iterationCount: 1,
            accepted: false,
            selectedCandidateID: "candidate-b",
            finalPlanID: "plan-b",
            iterations: [
                XcircuiteNumericRepairLoopIteration(
                    iterationIndex: 1,
                    status: "rejected",
                    candidateGenerationStrategy: "feedback-aware-bounded-refinement",
                    synthesisStrategy: "parameter-candidate-to-netlist-edit",
                    verificationMode: "post-execution",
                    candidateGenerationStatus: "generated",
                    selectedCandidateID: "candidate-b",
                    selectedCandidateRank: 1,
                    planID: "plan-b",
                    verificationStatus: "rejected",
                    accepted: false,
                    selectionTraceArtifact: selectionTraceRef,
                    rejectedPlansArtifact: rejectedPlansRef,
                    diagnostics: [
                        XcircuiteNumericRepairLoopDiagnostic(
                            severity: "warning",
                            code: "candidate-rejected",
                            message: "Selected candidate failed simulation metric verification.",
                            iterationIndex: 1
                        ),
                    ],
                    nextActions: ["inspect-simulation-metric-gate"]
                ),
            ],
            diagnostics: [
                XcircuiteNumericRepairLoopDiagnostic(
                    severity: "warning",
                    code: "candidate-rejected",
                    message: "Selected candidate failed simulation metric verification.",
                    iterationIndex: 1
                ),
            ],
            nextActions: ["inspect-numeric-repair-loop"]
        )
    }

    private func makeCalibrationReport(thresholdArtifactID: String?) -> XcircuiteCostCalibrationReport {
        XcircuiteCostCalibrationReport(
            runID: "run-1",
            problemID: "problem-1",
            calibrationID: "calibration-1",
            generatedAt: "2026-06-22T00:00:01Z",
            thresholdProfileArtifactID: thresholdArtifactID,
            inputArtifactIDs: ["planning-parameter-candidate-selection-trace"],
            calibratedTerms: [
                XcircuiteCostCalibrationReport.Term(
                    termID: "feedback.global.native-drc",
                    gateID: "native-drc",
                    baseWeight: 1.0,
                    calibratedWeight: 2.0,
                    evidenceCount: 3,
                    rationale: "Rejected DRC candidates should be penalized more strongly."
                ),
            ],
            observations: [
                XcircuiteCostCalibrationReport.Observation(
                    candidateID: "candidate-a",
                    accepted: false,
                    selectedTotalScore: 1.5,
                    failedGateIDs: ["native-drc"],
                    sourceArtifactIDs: ["planning-rejected-plans"]
                ),
            ]
        )
    }

    private func makeParetoSet(
        thresholdArtifactID: String?,
        calibrationArtifactID: String?
    ) throws -> XcircuiteParetoCandidateSet {
        try XcircuiteParetoCandidateSet(
            runID: "run-1",
            problemID: "problem-1",
            generatedAt: "2026-06-22T00:00:02Z",
            thresholdProfileArtifactID: thresholdArtifactID,
            costCalibrationArtifactID: calibrationArtifactID,
            sourceCandidateArtifactIDs: ["planning-parameter-candidates"],
            candidates: [
                try XcircuiteParetoCandidateSet.Candidate(
                    runID: "run-1",
                    problemID: "problem-1",
                    generatedAt: "2026-06-22T00:00:02Z",
                    candidateID: "candidate-a",
                    sourceCandidateID: "parameter-candidate-a",
                    frontierRank: 1,
                    metrics: [
                        try XcircuiteParetoCandidateSet.Metric(
                            metricID: "metric-vfinal",
                            value: 1.25,
                            normalizedValue: 0.0,
                            direction: "at-least",
                            unit: "V"
                        ),
                    ],
                    gateStatuses: ["simulation-metric-gate": "passed"],
                    rationale: "Meets the threshold with low cost."
                ),
                try XcircuiteParetoCandidateSet.Candidate(
                    runID: "run-1",
                    problemID: "problem-1",
                    generatedAt: "2026-06-22T00:00:02Z",
                    candidateID: "candidate-b",
                    sourceCandidateID: "parameter-candidate-b",
                    frontierRank: 2,
                    dominatedByCandidateIDs: ["candidate-a"],
                    metrics: [
                        try XcircuiteParetoCandidateSet.Metric(
                            metricID: "metric-vfinal",
                            value: 1.22,
                            normalizedValue: 0.25,
                            direction: "at-least",
                            unit: "V"
                        ),
                    ],
                    gateStatuses: ["simulation-metric-gate": "passed"],
                    rationale: "Feasible but dominated by candidate-a."
                ),
            ],
            selectedCandidateID: "candidate-a"
        )
    }

    private func makeImprovementLoop(
        thresholdArtifactID: String?,
        calibrationArtifactID: String?,
        paretoArtifactID: String?
    ) -> XcircuiteImprovementLoopResult {
        XcircuiteImprovementLoopResult(
            runID: "run-1",
            problemID: "problem-1",
            loopID: "improvement-loop-1",
            status: "accepted",
            thresholdProfileArtifactID: thresholdArtifactID,
            costCalibrationArtifactID: calibrationArtifactID,
            paretoCandidateArtifactID: paretoArtifactID,
            iterationCount: 1,
            acceptedCandidateID: "candidate-a",
            iterations: [
                XcircuiteImprovementLoopResult.Iteration(
                    iterationIndex: 1,
                    status: "accepted",
                    selectedCandidateID: "candidate-a",
                    accepted: true,
                    producedArtifactIDs: [paretoArtifactID].compactMap { $0 }
                ),
            ]
        )
    }

    private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .map { line in
                try decoder.decode(T.self, from: Data(line.utf8))
            }
    }

    private func persistSelectionTraceWithoutRunGate(
        _ trace: XcircuiteParameterCandidateSelectionTrace,
        runID: String,
        projectRoot: URL,
        packageStore: XcircuitePackageStore
    ) throws -> XcircuiteFileReference {
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let tracePath = ".xcircuite/runs/\(runID)/planning/parameter-candidate-selection-trace.json"
        let traceURL = runDirectory.appending(path: "planning/parameter-candidate-selection-trace.json")
        try packageStore.writeJSON(trace, to: traceURL, forProjectAt: projectRoot)
        let reference = try packageStore.fileReference(
            forProjectRelativePath: tracePath,
            artifactID: XcircuitePlanningArtifactStore.parameterCandidateSelectionTraceArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try packageStore.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteImprovementPlanningArtifactTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            print("Failed to remove temporary root: \(error)")
        }
    }
}
