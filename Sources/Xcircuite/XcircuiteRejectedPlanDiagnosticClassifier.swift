import Foundation

public struct XcircuiteRejectedPlanDiagnosticClassifier: Sendable {
    public init() {}

    public func classify(
        verification: XcircuitePlanVerification,
        status: String
    ) -> [XcircuiteRejectedPlanDiagnosticClassification] {
        let failedStepIDs = verification.stepResults
            .filter { $0.status == "failed" || $0.status == "blocked" }
            .map(\.stepID)
        let failedGateIDs = verification.gateResults
            .filter { $0.status == "failed" || $0.status == "blocked" }
            .map(\.gateID)
        let artifactIDs = ([verification.candidatePlanRef] + verification.artifactRefs)
            .compactMap(\.artifactID)
        let diagnostics = allDiagnostics(in: verification)
        var accumulators: [XcircuiteRejectedPlanDiagnosticClass: Accumulator] = [:]

        for diagnostic in diagnostics {
            for diagnosticClass in diagnosticClasses(for: diagnostic) {
                accumulators[diagnosticClass, default: Accumulator(diagnosticClass: diagnosticClass)]
                    .add(
                        diagnostic: diagnostic,
                        failedStepIDs: failedStepIDs,
                        failedGateIDs: failedGateIDs,
                        artifactIDs: artifactIDs,
                        nextActions: verification.nextActions
                    )
            }
        }

        for gate in verification.gateResults where gate.status == "failed" || gate.status == "blocked" {
            let gateClass = gate.diagnostics.contains { diagnosticClasses(for: $0).contains(.externalToolBlocker) }
                ? XcircuiteRejectedPlanDiagnosticClass.externalToolBlocker
                : XcircuiteRejectedPlanDiagnosticClass.failedVerificationGate
            accumulators[gateClass, default: Accumulator(diagnosticClass: gateClass)]
                .add(
                    reasonCodes: ["gate_status_\(gate.status)"],
                    severity: gate.status == "failed" ? "error" : "warning",
                    failedStepIDs: gate.sourceStepIDs,
                    failedGateIDs: [gate.gateID],
                    artifactIDs: artifactIDs,
                    nextActions: verification.nextActions
                )
        }

        if !verification.missingGoalAtoms.isEmpty
            || diagnostics.contains(where: { diagnosticClasses(for: $0).contains(.objectiveRegression) })
        {
            accumulators[.objectiveRegression, default: Accumulator(diagnosticClass: .objectiveRegression)]
                .add(
                    reasonCodes: verification.missingGoalAtoms.isEmpty ? ["objective_metric_failed"] : ["missing_goal_atoms"],
                    severity: status == "rejected" ? "error" : "warning",
                    failedStepIDs: failedStepIDs,
                    failedGateIDs: failedGateIDs,
                    artifactIDs: artifactIDs,
                    nextActions: verification.nextActions
                )
        }

        if accumulators.isEmpty && (status == "rejected" || status == "blocked") {
            accumulators[.failedVerificationGate, default: Accumulator(diagnosticClass: .failedVerificationGate)]
                .add(
                    reasonCodes: ["plan_\(status)"],
                    severity: status == "rejected" ? "error" : "warning",
                    failedStepIDs: failedStepIDs,
                    failedGateIDs: failedGateIDs,
                    artifactIDs: artifactIDs,
                    nextActions: verification.nextActions
                )
        }

        return accumulators.values
            .map { $0.classification(status: status, planID: verification.planID) }
            .sorted { $0.classificationID < $1.classificationID }
    }

    public func classify(
        record: XcircuiteRejectedPlanRecord
    ) -> [XcircuiteRejectedPlanDiagnosticClassification] {
        var accumulators: [XcircuiteRejectedPlanDiagnosticClass: Accumulator] = [:]
        for diagnostic in record.diagnostics {
            for diagnosticClass in diagnosticClasses(for: diagnostic) {
                accumulators[diagnosticClass, default: Accumulator(diagnosticClass: diagnosticClass)]
                    .add(
                        diagnostic: diagnostic,
                        failedStepIDs: record.failedStepIDs,
                        failedGateIDs: record.failedGateIDs,
                        artifactIDs: record.artifactRefs.compactMap(\.artifactID),
                        nextActions: record.nextActions
                    )
            }
        }
        if accumulators.isEmpty && (record.status == "rejected" || record.status == "blocked") {
            accumulators[.failedVerificationGate, default: Accumulator(diagnosticClass: .failedVerificationGate)]
                .add(
                    reasonCodes: ["plan_\(record.status)"],
                    severity: record.status == "rejected" ? "error" : "warning",
                    failedStepIDs: record.failedStepIDs,
                    failedGateIDs: record.failedGateIDs,
                    artifactIDs: record.artifactRefs.compactMap(\.artifactID),
                    nextActions: record.nextActions
                )
        }
        return accumulators.values
            .map { $0.classification(status: record.status, planID: record.planID) }
            .sorted { $0.classificationID < $1.classificationID }
    }

    private func allDiagnostics(
        in verification: XcircuitePlanVerification
    ) -> [XcircuitePlanVerificationDiagnostic] {
        verification.diagnostics
            + verification.stepResults.flatMap(\.diagnostics)
            + verification.gateResults.flatMap(\.diagnostics)
            + verification.correctnessGateResults.flatMap(\.diagnostics)
    }

    private func diagnosticClasses(
        for diagnostic: XcircuitePlanVerificationDiagnostic
    ) -> [XcircuiteRejectedPlanDiagnosticClass] {
        let text = [
            diagnostic.code,
            diagnostic.message,
            diagnostic.stepID,
            diagnostic.gateID,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        var classes: [XcircuiteRejectedPlanDiagnosticClass] = []

        if containsAny(text, [
            "unsupported-action-domain",
            "unsupported-operation",
            "operation-not-implemented",
            "action-domain-maturity-mismatch",
        ]) {
            classes.append(.unsupportedOperation)
        }
        if containsAny(text, [
            "missing-input",
            "unbound-operation-input",
            "unproven-operation-precondition",
            "gate-input-missing",
            "planning-problem-missing",
            "provide-input",
        ]) {
            classes.append(.missingInput)
        }
        if containsAny(text, [
            "tool",
            "external",
            "backend",
            "readiness",
            "magic",
            "netgen",
            "openrcx",
            "pdk",
            "executable",
        ]) {
            classes.append(.externalToolBlocker)
        }
        if containsAny(text, [
            "artifact currentness",
            "artifact-currentness",
            "stale",
            "artifact-integrity",
            "currentness",
            "digest",
            "sha",
            "hash",
            "byte count",
            "byte-count",
            "bytecount",
            "manifest",
        ]) {
            classes.append(.staleArtifact)
        }
        if containsAny(text, [
            "missing-goal-atom",
            "objective",
            "goal",
            "regression",
            "measurement",
            "metric-failed",
            "out_of_tolerance",
            "out-of-tolerance",
            "missed target",
        ]) {
            classes.append(.objectiveRegression)
        }
        if containsAny(text, [
            "calibration-uncertainty",
            "calibration_uncertainty",
            "uncalibrated",
            "posterior-variance",
            "posterior variance",
            "calibration-coefficient",
            "calibration coefficient",
            "confidence",
        ]) {
            classes.append(.calibrationUncertainty)
        }
        if diagnostic.gateID != nil
            || containsAny(text, ["gate", "failed", "rejected", "verification"])
        {
            classes.append(.failedVerificationGate)
        }
        return XcircuiteRejectedPlanDiagnosticClassification.unique(classes.map(\.rawValue))
            .compactMap(XcircuiteRejectedPlanDiagnosticClass.init(rawValue:))
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private struct Accumulator: Sendable {
        let diagnosticClass: XcircuiteRejectedPlanDiagnosticClass
        var severity: String = "info"
        var reasonCodes: [String] = []
        var failedStepIDs: [String] = []
        var failedGateIDs: [String] = []
        var diagnosticCodes: [String] = []
        var artifactIDs: [String] = []
        var nextActions: [String] = []

        mutating func add(
            diagnostic: XcircuitePlanVerificationDiagnostic,
            failedStepIDs: [String],
            failedGateIDs: [String],
            artifactIDs: [String],
            nextActions: [String]
        ) {
            add(
                reasonCodes: [diagnostic.code],
                severity: diagnostic.severity,
                failedStepIDs: [diagnostic.stepID].compactMap { $0 } + failedStepIDs,
                failedGateIDs: [diagnostic.gateID].compactMap { $0 } + failedGateIDs,
                diagnosticCodes: [diagnostic.code],
                artifactIDs: artifactIDs,
                nextActions: nextActions
            )
        }

        mutating func add(
            reasonCodes: [String],
            severity: String,
            failedStepIDs: [String] = [],
            failedGateIDs: [String] = [],
            diagnosticCodes: [String] = [],
            artifactIDs: [String] = [],
            nextActions: [String] = []
        ) {
            self.severity = maxSeverity(self.severity, severity)
            self.reasonCodes.append(contentsOf: reasonCodes)
            self.failedStepIDs.append(contentsOf: failedStepIDs)
            self.failedGateIDs.append(contentsOf: failedGateIDs)
            self.diagnosticCodes.append(contentsOf: diagnosticCodes)
            self.artifactIDs.append(contentsOf: artifactIDs)
            self.nextActions.append(contentsOf: nextActions)
        }

        func classification(
            status: String,
            planID: String
        ) -> XcircuiteRejectedPlanDiagnosticClassification {
            XcircuiteRejectedPlanDiagnosticClassification(
                classificationID: "\(planID):\(diagnosticClass.rawValue)",
                diagnosticClass: diagnosticClass,
                severity: severity,
                reasonCodes: reasonCodes,
                status: status,
                planID: planID,
                failedStepIDs: failedStepIDs,
                failedGateIDs: failedGateIDs,
                diagnosticCodes: diagnosticCodes,
                artifactIDs: artifactIDs,
                nextActions: nextActions
            )
        }

        private func maxSeverity(_ lhs: String, _ rhs: String) -> String {
            rank(rhs) > rank(lhs) ? rhs : lhs
        }

        private func rank(_ severity: String) -> Int {
            switch severity {
            case "error":
                return 3
            case "warning":
                return 2
            case "info":
                return 1
            default:
                return 0
            }
        }
    }
}
