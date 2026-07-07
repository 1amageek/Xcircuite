import Foundation
import ToolQualification
import XcircuitePackage

public struct XcircuiteSymbolicPlannerInstalledSolverLaneResolver: Sendable {
    private let artifactStore: XcircuitePlanningArtifactStore

    public init(
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore()
    ) {
        self.artifactStore = artifactStore
    }

    public func discover(
        request: XcircuiteSymbolicPlannerInstalledSolverLaneRequest,
        projectRoot: URL
    ) throws -> XcircuiteSymbolicPlannerInstalledSolverLaneDiscoveryResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        try XcircuiteIdentifierValidator().validate(request.laneID, kind: .artifactID)
        let searchPaths = normalizedSearchPaths(request.searchPaths)
        let specs = request.candidates.isEmpty ? Self.defaultCandidateSpecs() : request.candidates
        let candidates = specs.map { candidate in
            candidateResult(candidate, searchPaths: searchPaths)
        }
        let availableCandidates = candidates.filter { $0.status == "available" }
        let diagnostics = diagnosticsForLane(
            candidates: candidates,
            availableCandidates: availableCandidates
        )
        let batchRequest = batchRequest(
            request: request,
            specs: specs,
            candidates: candidates
        )
        let lane = XcircuiteSymbolicPlannerInstalledSolverLane(
            status: availableCandidates.isEmpty ? "missing-installed-solvers" : "available",
            runID: request.runID,
            laneID: request.laneID,
            selectionPolicy: request.selectionPolicy,
            searchedPaths: searchPaths,
            candidateCount: candidates.count,
            availableCandidateCount: availableCandidates.count,
            unavailableCandidateCount: candidates.count - availableCandidates.count,
            candidates: candidates,
            batchRequest: batchRequest,
            diagnostics: diagnostics
        )
        let artifact = try artifactStore.persistSymbolicPlannerInstalledSolverLane(
            lane,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerInstalledSolverLaneDiscoveryResult(
            lane: lane,
            laneArtifact: artifact
        )
    }

    public static func defaultCandidateSpecs() -> [XcircuiteSymbolicPlannerInstalledSolverCandidateSpec] {
        [
            XcircuiteSymbolicPlannerInstalledSolverCandidateSpec(
                candidateID: "fast-downward",
                toolID: "fast-downward",
                displayName: "Fast Downward",
                solverFamily: "fast-downward",
                executableNames: ["fast-downward.py", "fast-downward", "downward"],
                arguments: ["{domain}", "{problem}", "--plan-file", "{solverPlan}", "--search", "astar(lmcut())"],
                certificateFormat: "fast-downward-text",
                requireOptimality: true
            ),
            XcircuiteSymbolicPlannerInstalledSolverCandidateSpec(
                candidateID: "metric-ff",
                toolID: "metric-ff",
                displayName: "Metric-FF",
                solverFamily: "metric-ff",
                executableNames: ["metric-ff", "ff"],
                arguments: ["-o", "{domain}", "-f", "{problem}"],
                certificateFormat: "metric-ff-text"
            ),
            XcircuiteSymbolicPlannerInstalledSolverCandidateSpec(
                candidateID: "optic",
                toolID: "optic",
                displayName: "OPTIC",
                solverFamily: "optic",
                executableNames: ["optic", "optic-clp"],
                arguments: ["{domain}", "{problem}"],
                certificateFormat: "optic-text"
            ),
            XcircuiteSymbolicPlannerInstalledSolverCandidateSpec(
                candidateID: "madagascar",
                toolID: "madagascar",
                displayName: "Madagascar",
                solverFamily: "madagascar",
                executableNames: ["M", "Mp", "madagascar"],
                arguments: ["{domain}", "{problem}"],
                certificateFormat: "madagascar-text"
            ),
        ]
    }

    private func candidateResult(
        _ candidate: XcircuiteSymbolicPlannerInstalledSolverCandidateSpec,
        searchPaths: [String]
    ) -> XcircuiteSymbolicPlannerInstalledSolverCandidateResult {
        let resolution = resolveExecutable(candidate, searchPaths: searchPaths)
        let descriptor = resolution.status == "available" && resolution.executablePath != nil
            ? PlanningToolDescriptors.symbolicPlannerSolver(
                toolID: candidate.toolID,
                displayName: candidate.displayName,
                version: "installed",
                executablePath: resolution.executablePath ?? "",
                level: .unknown
            )
            : nil
        return XcircuiteSymbolicPlannerInstalledSolverCandidateResult(
            candidateID: candidate.candidateID,
            toolID: candidate.toolID,
            displayName: candidate.displayName,
            solverFamily: candidate.solverFamily,
            status: resolution.status,
            executablePath: resolution.executablePath,
            executableNames: candidate.executableNames,
            searchedPaths: searchPaths,
            certificateFormat: candidate.certificateFormat,
            requireOptimality: candidate.requireOptimality,
            requireNativeCertificate: candidate.requireNativeCertificate,
            descriptor: descriptor,
            diagnostics: resolution.diagnostics
        )
    }

    private func batchRequest(
        request: XcircuiteSymbolicPlannerInstalledSolverLaneRequest,
        specs: [XcircuiteSymbolicPlannerInstalledSolverCandidateSpec],
        candidates: [XcircuiteSymbolicPlannerInstalledSolverCandidateResult]
    ) -> XcircuiteSymbolicPlannerSolverFamilyBatchRequest? {
        let available = zip(specs, candidates)
            .filter { $0.1.status == "available" && $0.1.executablePath != nil }
        guard !available.isEmpty else {
            return nil
        }
        return XcircuiteSymbolicPlannerSolverFamilyBatchRequest(
            runID: request.runID,
            comparisonID: request.laneID,
            selectionPolicy: request.selectionPolicy,
            candidates: available.map { spec, result in
                XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                    candidateID: spec.candidateID,
                    toolID: spec.toolID,
                    executablePath: result.executablePath ?? "",
                    arguments: spec.arguments,
                    timeoutSeconds: spec.timeoutSeconds,
                    requireOptimality: spec.requireOptimality,
                    requireNativeCertificate: spec.requireNativeCertificate,
                    certificateFormat: spec.certificateFormat
                )
            },
            promoteSelectedPlan: request.promoteSelectedPlan,
            requireQualifiedPromotion: request.requireQualifiedPromotion,
            verifyPromotedPlan: request.verifyPromotedPlan
        )
    }

    private func resolveExecutable(
        _ candidate: XcircuiteSymbolicPlannerInstalledSolverCandidateSpec,
        searchPaths: [String]
    ) -> (status: String, executablePath: String?, diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]) {
        if let executablePath = candidate.executablePath {
            return resolveExplicitExecutable(executablePath, candidate: candidate)
        }
        var presentButNotExecutablePath: String?
        var presentButNotExecutableDiagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
        for executableName in candidate.executableNames {
            if executableName.contains("/") {
                let resolution = resolveExplicitExecutable(executableName, candidate: candidate)
                if resolution.status == "available" {
                    return resolution
                }
                if resolution.status == "not-executable" {
                    if presentButNotExecutablePath == nil {
                        presentButNotExecutablePath = resolution.executablePath
                    }
                    presentButNotExecutableDiagnostics.append(contentsOf: resolution.diagnostics)
                }
                continue
            }
            for searchPath in searchPaths {
                let path = URL(filePath: searchPath)
                    .appending(path: executableName)
                    .path(percentEncoded: false)
                if FileManager.default.isExecutableFile(atPath: path) {
                    return (status: "available", executablePath: path, diagnostics: [])
                }
                if FileManager.default.fileExists(atPath: path) {
                    if presentButNotExecutablePath == nil {
                        presentButNotExecutablePath = path
                    }
                    presentButNotExecutableDiagnostics.append(
                        diagnostic(
                            severity: "error",
                            code: "installed-solver-not-executable",
                            message: "Installed symbolic planner candidate \(candidate.toolID) exists at \(path), but is not executable."
                        )
                    )
                }
            }
        }
        if let presentButNotExecutablePath {
            return (
                status: "not-executable",
                executablePath: presentButNotExecutablePath,
                diagnostics: presentButNotExecutableDiagnostics
            )
        }
        return (
            status: "missing",
            executablePath: nil,
            diagnostics: [
                diagnostic(
                    severity: "warning",
                    code: "installed-solver-missing",
                    message: "Installed symbolic planner candidate \(candidate.toolID) was not found in configured search paths."
                ),
            ]
        )
    }

    private func resolveExplicitExecutable(
        _ executablePath: String,
        candidate: XcircuiteSymbolicPlannerInstalledSolverCandidateSpec
    ) -> (status: String, executablePath: String?, diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]) {
        if FileManager.default.isExecutableFile(atPath: executablePath) {
            return (status: "available", executablePath: executablePath, diagnostics: [])
        }
        if FileManager.default.fileExists(atPath: executablePath) {
            return (
                status: "not-executable",
                executablePath: executablePath,
                diagnostics: [
                    diagnostic(
                        severity: "error",
                        code: "installed-solver-not-executable",
                        message: "Installed symbolic planner candidate \(candidate.toolID) exists at \(executablePath), but is not executable."
                    ),
                ]
            )
        }
        return (
            status: "missing",
            executablePath: nil,
            diagnostics: [
                diagnostic(
                    severity: "warning",
                    code: "installed-solver-missing",
                    message: "Installed symbolic planner candidate \(candidate.toolID) was not found at \(executablePath)."
                ),
            ]
        )
    }

    private func normalizedSearchPaths(_ explicitSearchPaths: [String]) -> [String] {
        let paths = explicitSearchPaths.isEmpty
            ? (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            : explicitSearchPaths
        var result: [String] = []
        for path in paths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !result.contains(trimmed) {
                result.append(trimmed)
            }
        }
        return result
    }

    private func diagnosticsForLane(
        candidates: [XcircuiteSymbolicPlannerInstalledSolverCandidateResult],
        availableCandidates: [XcircuiteSymbolicPlannerInstalledSolverCandidateResult]
    ) -> [XcircuiteSymbolicPlannerSolverDiagnostic] {
        if availableCandidates.isEmpty {
            return [
                diagnostic(
                    severity: "warning",
                    code: "installed-solver-lane-empty",
                    message: "No installed symbolic planner candidates were available for this lane."
                ),
            ]
        }
        let notExecutableCount = candidates.filter { $0.status == "not-executable" }.count
        guard notExecutableCount > 0 else {
            return []
        }
        return [
            diagnostic(
                severity: "warning",
                code: "installed-solver-lane-partial",
                message: "\(notExecutableCount) installed symbolic planner candidate(s) were present but not executable."
            ),
        ]
    }

    private func diagnostic(
        severity: String,
        code: String,
        message: String
    ) -> XcircuiteSymbolicPlannerSolverDiagnostic {
        XcircuiteSymbolicPlannerSolverDiagnostic(
            severity: severity,
            code: code,
            message: message
        )
    }
}
