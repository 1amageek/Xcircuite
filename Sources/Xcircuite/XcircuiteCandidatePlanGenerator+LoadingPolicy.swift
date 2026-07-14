import Foundation
import DesignFlowKernel

extension XcircuiteCandidatePlanGenerator {
    func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try workspaceStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    func loadOrPersistActionDomainSnapshot(
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ActionDomainSnapshotContext {
        let resolved = try XcircuiteActionDomainSnapshotResolver(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).loadDefaultOrPersist(
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
        return ActionDomainSnapshotContext(snapshot: resolved.snapshot, reference: resolved.reference)
    }

    func loadRejectedPlanFeedback(
        request: XcircuiteCandidatePlanGenerationRequest,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> XcircuiteRejectedPlanFeedbackSummary {
        let path = try optionalPath(
            explicitPath: request.rejectedPlansPath,
            artifactID: request.rejectedPlansArtifactID ?? XcircuitePlanningArtifactStore.rejectedPlansArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        guard let path else {
            return emptyRejectedPlanFeedback(runID: request.runID)
        }
        let records = try readRejectedPlanRecords(path: path, projectRoot: projectRoot)
        if let mismatched = records.first(where: { $0.runID != request.runID }) {
            throw XcircuiteCandidatePlanGenerationError.runMismatch(
                expected: request.runID,
                actual: mismatched.runID
            )
        }
        return XcircuiteRejectedPlanFeedbackBuilder().makeFeedbackSummary(
            runID: request.runID,
            path: path,
            records: records
        )
    }

    func loadCalibrationContext(
        request: XcircuiteCandidatePlanGenerationRequest,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> SymbolicCalibrationContext? {
        let useDefaultArtifacts = calibrationLearningEnabled(request.strategy)
        let thresholdProfilePath = try optionalPath(
            explicitPath: request.metricThresholdProfilePath,
            artifactID: request.metricThresholdProfileArtifactID
                ?? (useDefaultArtifacts ? XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID : nil),
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let costCalibrationPath = try optionalPath(
            explicitPath: request.costCalibrationPath,
            artifactID: request.costCalibrationArtifactID
                ?? (useDefaultArtifacts ? XcircuitePlanningArtifactStore.costCalibrationArtifactID : nil),
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let paretoCandidatesPath = try optionalPath(
            explicitPath: request.paretoCandidatesPath,
            artifactID: request.paretoCandidatesArtifactID
                ?? (useDefaultArtifacts ? XcircuitePlanningArtifactStore.paretoCandidatesArtifactID : nil),
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        guard thresholdProfilePath != nil || costCalibrationPath != nil || paretoCandidatesPath != nil else {
            return nil
        }
        let thresholdProfile = try thresholdProfilePath.map {
            try readThresholdProfile(path: $0, runID: request.runID, projectRoot: projectRoot)
        }
        let costCalibration = try costCalibrationPath.map {
            try readCostCalibration(path: $0, runID: request.runID, projectRoot: projectRoot)
        }
        let paretoCandidates = try paretoCandidatesPath.map {
            try readParetoCandidates(path: $0, runID: request.runID, projectRoot: projectRoot)
        } ?? []
        return SymbolicCalibrationContext(
            thresholdProfilePath: thresholdProfilePath,
            thresholdProfile: thresholdProfile,
            costCalibrationPath: costCalibrationPath,
            costCalibration: costCalibration,
            paretoCandidatesPath: paretoCandidatesPath,
            paretoCandidates: paretoCandidates
        )
    }

    func selectPolicy(
        request: XcircuiteCandidatePlanGenerationRequest,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> SymbolicPolicySelection {
        let calibrationPolicy = try normalizedCalibrationPolicy(request.calibrationPolicy)
        let baseStrategy = request.strategy
        guard calibrationPolicy == "cp7-feedback" else {
            return SymbolicPolicySelection(
                strategy: baseStrategy,
                trace: XcircuiteSymbolicPlannerPolicyTrace(
                    calibrationPolicy: calibrationPolicy,
                    baseStrategy: baseStrategy,
                    selectedStrategy: baseStrategy,
                    usesCalibrationArtifacts: false,
                    reasonCodes: ["calibration-policy-disabled"]
                )
            )
        }

        let thresholdProfile = try calibrationArtifactReference(
            explicitPath: request.metricThresholdProfilePath,
            artifactID: request.metricThresholdProfileArtifactID,
            defaultArtifactID: XcircuitePlanningArtifactStore.metricThresholdProfileArtifactID,
            format: .json,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let costCalibration = try calibrationArtifactReference(
            explicitPath: request.costCalibrationPath,
            artifactID: request.costCalibrationArtifactID,
            defaultArtifactID: XcircuitePlanningArtifactStore.costCalibrationArtifactID,
            format: .json,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let paretoCandidates = try calibrationArtifactReference(
            explicitPath: request.paretoCandidatesPath,
            artifactID: request.paretoCandidatesArtifactID,
            defaultArtifactID: XcircuitePlanningArtifactStore.paretoCandidatesArtifactID,
            format: .text,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let availableArtifactCount = [
            thresholdProfile,
            costCalibration,
            paretoCandidates,
        ].compactMap { $0 }.count
        guard availableArtifactCount > 0 else {
            return SymbolicPolicySelection(
                strategy: baseStrategy,
                trace: XcircuiteSymbolicPlannerPolicyTrace(
                    calibrationPolicy: calibrationPolicy,
                    baseStrategy: baseStrategy,
                    selectedStrategy: baseStrategy,
                    usesCalibrationArtifacts: false,
                    reasonCodes: ["cp7-artifacts-not-available"],
                    diagnostics: [
                        "No CP7 calibration artifacts were found in explicit request refs or the run manifest.",
                    ]
                )
            )
        }

        let selectedStrategy = calibratedStrategy(for: baseStrategy)
        guard selectedStrategy != baseStrategy || calibrationLearningEnabled(baseStrategy) else {
            return SymbolicPolicySelection(
                strategy: baseStrategy,
                trace: XcircuiteSymbolicPlannerPolicyTrace(
                    calibrationPolicy: calibrationPolicy,
                    baseStrategy: baseStrategy,
                    selectedStrategy: baseStrategy,
                    usesCalibrationArtifacts: false,
                    metricThresholdProfileArtifact: thresholdProfile,
                    costCalibrationArtifact: costCalibration,
                    paretoCandidatesArtifact: paretoCandidates,
                    reasonCodes: ["unsupported-base-strategy-for-cp7-calibration"],
                    diagnostics: [
                        "Base symbolic strategy \(baseStrategy) does not declare CP7 calibration support.",
                    ]
                )
            )
        }

        return SymbolicPolicySelection(
            strategy: selectedStrategy,
            trace: XcircuiteSymbolicPlannerPolicyTrace(
                calibrationPolicy: calibrationPolicy,
                baseStrategy: baseStrategy,
                selectedStrategy: selectedStrategy,
                usesCalibrationArtifacts: true,
                metricThresholdProfileArtifact: thresholdProfile,
                costCalibrationArtifact: costCalibration,
                paretoCandidatesArtifact: paretoCandidates,
                reasonCodes: [
                    "cp7-artifacts-available",
                    "calibrated-symbolic-strategy-selected",
                ]
            )
        )
    }

    func normalizedCalibrationPolicy(_ value: String?) throws -> String {
        let policy = storedCalibrationPolicy(value)
        switch policy {
        case "disabled":
            return "disabled"
        case "cp7-feedback":
            return "cp7-feedback"
        default:
            throw XcircuiteCandidatePlanGenerationError.invalidCalibrationPolicy(policy)
        }
    }

    func storedCalibrationPolicy(_ value: String?) -> String {
        let policy = (value ?? "disabled").trimmingCharacters(in: .whitespacesAndNewlines)
        return policy.isEmpty ? "disabled" : policy
    }

    func calibratedStrategy(for strategy: String) -> String {
        switch strategy {
        case "first-ready-action-per-objective":
            return "calibrated-first-ready-action-per-objective"
        case "state-aware-objective-ordering":
            return "calibrated-state-aware-objective-ordering"
        default:
            return strategy
        }
    }

    func calibrationArtifactReference(
        explicitPath: String?,
        artifactID: String?,
        defaultArtifactID: String,
        format: XcircuiteFileFormat,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference? {
        if let explicitPath {
            return try workspaceStore.fileReference(
                forProjectRelativePath: explicitPath,
                artifactID: artifactID ?? defaultArtifactID,
                kind: .other,
                format: format,
                inProjectAt: projectRoot
            )
        }
        let resolvedArtifactID = artifactID ?? defaultArtifactID
        return try verifiedManifestArtifactReference(
            artifactID: resolvedArtifactID,
            expectedKind: .other,
            expectedFormat: format,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
    }

    func calibrationLearningEnabled(_ strategy: String) -> Bool {
        strategy == "calibrated-first-ready-action-per-objective"
            || strategy == "calibrated-state-aware-objective-ordering"
    }

    func emptyRejectedPlanFeedback(runID: String) -> XcircuiteRejectedPlanFeedbackSummary {
        XcircuiteRejectedPlanFeedbackSummary(
            runID: runID,
            rejectedPlansPath: nil,
            recordCount: 0,
            candidateFeedback: [],
            globalFeedback: [],
            excludedCandidateIDs: []
        )
    }

    func optionalPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> String? {
        if let explicitPath {
            _ = try workspaceStore.url(forProjectRelativePath: explicitPath, inProjectAt: projectRoot)
            return explicitPath
        }
        guard let artifactID else {
            return nil
        }
        return try verifiedManifestArtifactReference(
            artifactID: artifactID,
            expectedKind: nil,
            expectedFormat: nil,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )?.path
    }

    func readRejectedPlanRecords(
        path: String,
        projectRoot: URL
    ) throws -> [XcircuiteRejectedPlanRecord] {
        let url = try workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        let text = try String(contentsOf: url, encoding: .utf8)
        var records: [XcircuiteRejectedPlanRecord] = []
        for (index, line) in text.split(separator: "\n").enumerated() {
            do {
                let data = Data(String(line).utf8)
                records.append(try JSONDecoder().decode(XcircuiteRejectedPlanRecord.self, from: data))
            } catch {
                throw XcircuiteCandidatePlanGenerationError.invalidRejectedPlanJSONLine(
                    path: path,
                    line: index + 1
                )
            }
        }
        return records
    }

    func readThresholdProfile(
        path: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteMetricThresholdProfile {
        let profile = try workspaceStore.readJSON(
            XcircuiteMetricThresholdProfile.self,
            from: workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        )
        guard profile.runID == runID else {
            throw XcircuiteCandidatePlanGenerationError.runMismatch(
                expected: runID,
                actual: profile.runID
            )
        }
        return profile
    }

    func readCostCalibration(
        path: String,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteCostCalibrationReport {
        let report = try workspaceStore.readJSON(
            XcircuiteCostCalibrationReport.self,
            from: workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        )
        guard report.runID == runID else {
            throw XcircuiteCandidatePlanGenerationError.runMismatch(
                expected: runID,
                actual: report.runID
            )
        }
        return report
    }

    func readParetoCandidates(
        path: String,
        runID: String,
        projectRoot: URL
    ) throws -> [XcircuiteParetoCandidateSet.Candidate] {
        let url = try workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        let text = try String(contentsOf: url, encoding: .utf8)
        var candidates: [XcircuiteParetoCandidateSet.Candidate] = []
        for (index, line) in text.split(separator: "\n").enumerated() {
            do {
                let data = Data(String(line).utf8)
                let candidate = try JSONDecoder().decode(
                    XcircuiteParetoCandidateSet.Candidate.self,
                    from: data
                )
                guard candidate.runID == runID else {
                    throw XcircuiteCandidatePlanGenerationError.runMismatch(
                        expected: runID,
                        actual: candidate.runID
                    )
                }
                candidates.append(candidate)
            } catch let error as XcircuiteCandidatePlanGenerationError {
                throw error
            } catch {
                throw XcircuiteCandidatePlanGenerationError.invalidParetoCandidateJSONLine(
                    path: path,
                    line: index + 1
                )
            }
        }
        return candidates
    }

    func requiredPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> String {
        if let explicitPath {
            _ = try workspaceStore.url(forProjectRelativePath: explicitPath, inProjectAt: projectRoot)
            return explicitPath
        }
        guard let artifactID else {
            throw XcircuiteCandidatePlanGenerationError.missingProblemReference
        }
        guard let reference = try verifiedManifestArtifactReference(
            artifactID: artifactID,
            expectedKind: nil,
            expectedFormat: nil,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        ) else {
            throw XcircuiteCandidatePlanGenerationError.artifactNotFound(runID: runID, artifactID: artifactID)
        }
        return reference.path
    }

    func verifiedManifestArtifactReference(
        artifactID: String,
        expectedKind: XcircuiteFileKind?,
        expectedFormat: XcircuiteFileFormat?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference? {
        guard let reference = manifest.artifacts.first(where: { $0.artifactID == artifactID }) else {
            return nil
        }
        if let expectedKind, reference.kind != expectedKind {
            throw XcircuiteCandidatePlanGenerationError.invalidArtifactReference(
                path: reference.path,
                reason: "artifact kind \(reference.kind.rawValue) does not match expected \(expectedKind.rawValue)."
            )
        }
        if let expectedFormat, reference.format != expectedFormat {
            throw XcircuiteCandidatePlanGenerationError.invalidArtifactReference(
                path: reference.path,
                reason: "artifact format \(reference.format.rawValue) does not match expected \(expectedFormat.rawValue)."
            )
        }
        if let producedByRunID = reference.producedByRunID, producedByRunID != runID {
            throw XcircuiteCandidatePlanGenerationError.artifactProducerRunMismatch(
                expected: runID,
                actual: producedByRunID
            )
        }
        let verifier = XcircuiteFileReferenceVerifier()
        let integrity = verifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuiteCandidatePlanGenerationError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.status,
                message: integrity.message
            )
        }
        return reference
    }

    func identifier(_ rawValue: String) throws -> String {
        let allowedScalars = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        let sanitizedScalars = rawValue.unicodeScalars.map { scalar in
            allowedScalars.contains(scalar)
                ? String(scalar)
                : "-"
        }
        let collapsed = sanitizedScalars.joined()
            .split(separator: "-")
            .joined(separator: "-")
        let trimmed = String(collapsed.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        let value = trimmed.isEmpty ? "candidate-plan" : trimmed
        try XcircuiteIdentifierValidator().validate(value, kind: .artifactID)
        return value
    }
}
