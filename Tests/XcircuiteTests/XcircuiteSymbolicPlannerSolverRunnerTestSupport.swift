import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

extension XcircuiteSymbolicPlannerSolverRunnerTests {
func prepareRun(
    root: URL,
    runID: String,
    repair: DRCRepairFixture = .width,
    includeViolationAtom: Bool = true,
    workspaceStore: XcircuiteWorkspaceStore,
    artifactStore: XcircuitePlanningArtifactStore
) async throws {
    try await prepareTestRun(runID: runID, store: workspaceStore)
    _ = try await artifactStore.persistPlanningProblem(
        makePlanningProblem(
            runID: runID,
            repair: repair,
            includeViolationAtom: includeViolationAtom
        ),
        runID: runID,
        projectRoot: root
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    _ = try await workspaceStore.persistArtifact(
        content: encoder.encode(makeActionDomainSnapshot(runID: runID, repair: repair)),
        id: try ArtifactID(rawValue: XcircuitePlanningArtifactStore.actionDomainArtifactID),
        locator: ArtifactLocator(
            location: try ArtifactLocation(
                workspaceRelativePath: ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json"
            ),
            role: .output,
            kind: .other,
            format: .json
        ),
        runID: runID,
        mode: .replaceable
    )
}

func makePlanningProblem(
    runID: String,
    repair: DRCRepairFixture = .width,
    includeViolationAtom: Bool = true
) -> XcircuiteCircuitPlanningProblem {
    XcircuiteCircuitPlanningProblem(
        problemID: "\(runID)-problem",
        runID: runID,
        sourceRefs: [
            XcircuitePlanningReference(
                refID: "layout-drc-input",
                kind: "layout",
                artifactID: "layout-json",
                metadata: includeViolationAtom
                    ? ["symbolicStateAtoms": .textList([repair.violationAtom])]
                    : [:]
            ),
        ],
        initialStateRefs: [],
        objectives: [
            XcircuitePlanningObjective(
                objectiveID: "objective-1",
                kind: "satisfy",
                domain: "drc",
                priority: "error",
                sourceRefIDs: ["layout-drc-input"],
                target: repair.target,
                currentValue: .scalar(1),
                requiredValue: .scalar(0),
                description: repair.objectiveDescription,
                evidence: [
                    "symbolicGoalAtoms": .textList([repair.goalAtom]),
                ]
            ),
        ],
        constraints: [],
        actionDomainRefs: ["drc-signoff"],
        candidateActions: [
            XcircuitePlanningCandidateAction(
                actionID: repair.actionID,
                domainID: "drc-signoff",
                operationID: repair.operationID,
                maturity: "implemented",
                reason: repair.actionReason,
                sourceObjectiveIDs: ["objective-1"],
                requiredInputRefs: ["layout-drc-input"],
                verificationGates: ["native-drc"]
            ),
        ],
        costModel: XcircuitePlanningCostModel(strategy: "symbolic-planner-solver", terms: []),
        verificationGates: [
            XcircuitePlanningVerificationGate(
                gateID: "native-drc",
                required: true,
                description: "Candidate must pass DRC."
            ),
        ],
        resumeContract: XcircuitePlanningResumeContract(
            mode: "run-ledger",
            requiredArtifacts: ["planning/problem.json"],
            blockedStates: ["candidate-rejected"]
        )
    )
}

func makeActionDomainSnapshot(
    runID: String,
    repair: DRCRepairFixture = .width
) -> XcircuitePlanningActionDomainSnapshot {
    XcircuitePlanningActionDomainSnapshot(
        runID: runID,
        generatedAt: "2026-06-20T00:00:00Z",
        domains: [
            XcircuiteActionDomain(
                domainID: "drc-signoff",
                ownerPackages: ["DRCEngine", "Xcircuite"],
                operations: [
                    XcircuiteActionDomainOperation(
                        operationID: repair.operationID,
                        maturity: "implemented",
                        inputRefs: ["layout-drc-input"],
                        preconditions: [repair.violationAtom],
                        effects: [repair.goalAtom],
                        producedArtifacts: ["drc-summary"],
                        verificationGates: ["native-drc"],
                        reversible: true
                    ),
                ]
            ),
        ]
    )
}

struct DRCRepairFixture: Sendable, Hashable {
    var runID: String
    var actionID: String
    var operationID: String
    var violationAtom: String
    var goalAtom: String
    var target: String
    var objectiveDescription: String
    var actionReason: String

    static let width = DRCRepairFixture(
        runID: "run-drc-width",
        actionID: "fix-m1-width",
        operationID: "drc.repair-width",
        violationAtom: "drc-width-violation",
        goalAtom: "drc-width-fixed",
        target: "no-width-violation",
        objectiveDescription: "Repair width violation.",
        actionReason: "Repair M1 width."
    )

    static let spacing = DRCRepairFixture(
        runID: "run-drc-spacing",
        actionID: "fix-m1-spacing",
        operationID: "drc.repair-spacing",
        violationAtom: "drc-spacing-violation",
        goalAtom: "drc-spacing-fixed",
        target: "no-spacing-violation",
        objectiveDescription: "Repair spacing violation.",
        actionReason: "Repair M1 spacing."
    )

    static let enclosure = DRCRepairFixture(
        runID: "run-drc-enclosure",
        actionID: "fix-via-enclosure",
        operationID: "drc.repair-enclosure",
        violationAtom: "drc-enclosure-violation",
        goalAtom: "drc-enclosure-fixed",
        target: "no-enclosure-violation",
        objectiveDescription: "Repair enclosure violation.",
        actionReason: "Repair via enclosure."
    )

    static let overlapShort = DRCRepairFixture(
        runID: "run-drc-overlap-short",
        actionID: "fix-different-net-overlap",
        operationID: "drc.repair-overlap-short",
        violationAtom: "drc-overlap-short-violation",
        goalAtom: "drc-overlap-short-fixed",
        target: "no-different-net-overlap-short",
        objectiveDescription: "Repair different-net overlap short violation.",
        actionReason: "Separate overlapping different-net shapes."
    )

    static let minimumDensity = DRCRepairFixture(
        runID: "run-drc-minimum-density",
        actionID: "fix-minimum-density",
        operationID: "drc.repair-minimum-density",
        violationAtom: "drc-minimum-density-violation",
        goalAtom: "drc-minimum-density-fixed",
        target: "minimum-density-covered",
        objectiveDescription: "Repair minimum density violation.",
        actionReason: "Add density fill or adjust geometry to satisfy the density window."
    )

    static let antenna = DRCRepairFixture(
        runID: "run-drc-antenna",
        actionID: "fix-antenna-ratio",
        operationID: "drc.repair-antenna-ratio",
        violationAtom: "drc-antenna-violation",
        goalAtom: "drc-antenna-fixed",
        target: "antenna-ratio-covered",
        objectiveDescription: "Repair antenna ratio violation.",
        actionReason: "Add a diode, jumper, or layer transition to reduce antenna exposure."
    )

    static let routing = DRCRepairFixture(
        runID: "run-drc-routing",
        actionID: "fix-drc-routing-detour",
        operationID: "drc.repair-routing-detour",
        violationAtom: "drc-routing-violation",
        goalAtom: "drc-routing-fixed",
        target: "routing-clean",
        objectiveDescription: "Repair DRC routing violation.",
        actionReason: "Reroute or detour geometry to satisfy local DRC constraints."
    )

    static let notch = DRCRepairFixture(
        runID: "run-drc-notch",
        actionID: "fix-drc-notch",
        operationID: "drc.repair-notch",
        violationAtom: "drc-notch-violation",
        goalAtom: "drc-notch-fixed",
        target: "notch-clean",
        objectiveDescription: "Repair notch DRC violation.",
        actionReason: "Remove or widen notched geometry to satisfy notch rules."
    )

    static let grid = DRCRepairFixture(
        runID: "run-drc-grid",
        actionID: "fix-drc-grid-alignment",
        operationID: "drc.repair-grid-alignment",
        violationAtom: "drc-grid-violation",
        goalAtom: "drc-grid-fixed",
        target: "grid-aligned",
        objectiveDescription: "Repair manufacturing grid DRC violation.",
        actionReason: "Snap geometry to the manufacturing grid."
    )

    static let cut = DRCRepairFixture(
        runID: "run-drc-cut",
        actionID: "fix-drc-cut-rule",
        operationID: "drc.repair-cut-rule",
        violationAtom: "drc-cut-violation",
        goalAtom: "drc-cut-fixed",
        target: "cut-rule-clean",
        objectiveDescription: "Repair cut-rule DRC violation.",
        actionReason: "Adjust cut geometry or count to satisfy cut rules."
    )
}

func makeTemporaryRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func removeTemporaryRoot(_ root: URL) {
    do {
        try FileManager.default.removeItem(at: root)
    } catch {
        Issue.record("Failed to remove temporary root: \(error)")
    }
}

func parseChildPID(from standardOutput: String) -> pid_t? {
    for line in standardOutput.split(whereSeparator: \.isNewline) {
        guard line.hasPrefix("child=") else { continue }
        return pid_t(String(line.dropFirst("child=".count)))
    }
    return nil
}

func waitForChildPID(at url: URL) async throws -> pid_t? {
    for _ in 0..<200 {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            let text = try String(contentsOf: url, encoding: .utf8)
            if let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    return nil
}

func isProcessAlive(_ pid: pid_t) -> Bool {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    if Darwin.kill(pid, 0) == 0 {
        return true
    }
    return errno == EPERM
    #else
    return false
    #endif
}

func waitForProcessExit(_ pid: pid_t, timeoutSeconds: Double) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if !isProcessAlive(pid) {
            return true
        }
        do {
            try await Task.sleep(nanoseconds: 20_000_000)
        } catch {
            return !isProcessAlive(pid)
        }
    }
    return !isProcessAlive(pid)
}

func writeMockPlanner(to solverURL: URL, planText: String) throws {
    let script = """
        #!/bin/sh
        printf '\(planText)'
        """
    try Data(script.utf8).write(to: solverURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )
}

func writeMockProofChecker(
    to checkerURL: URL,
    expectedText: String,
    success: Bool
) throws {
    let failureExit = success ? 3 : 4
    let script = """
        #!/bin/sh
        if grep -q '\(expectedText)' "$1"; then
          echo 'proof valid'
          exit \(success ? 0 : failureExit)
        fi
        echo 'proof invalid' >&2
        exit \(failureExit)
        """
    try Data(script.utf8).write(to: checkerURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: checkerURL.path(percentEncoded: false)
    )
}

func writeDRCRepairMockPlanner(to solverURL: URL) throws {
    let script = """
        #!/bin/sh
        case "$1" in
          *run-drc-width*) printf '0.000: (a-fix-m1-width) [1.000]\\n' ;;
          *run-drc-spacing*) printf '0.000: (a-fix-m1-spacing) [1.000]\\n' ;;
          *run-drc-enclosure*) printf '0.000: (a-fix-via-enclosure) [1.000]\\n' ;;
          *run-drc-overlap-short*) printf '0.000: (a-fix-different-net-overlap) [1.000]\\n' ;;
          *run-drc-minimum-density*) printf '0.000: (a-fix-minimum-density) [1.000]\\n' ;;
          *run-drc-antenna*) printf '0.000: (a-fix-antenna-ratio) [1.000]\\n' ;;
          *run-drc-routing*) printf '0.000: (a-fix-drc-routing-detour) [1.000]\\n' ;;
          *run-drc-notch*) printf '0.000: (a-fix-drc-notch) [1.000]\\n' ;;
          *run-drc-grid*) printf '0.000: (a-fix-drc-grid-alignment) [1.000]\\n' ;;
          *run-drc-cut*) printf '0.000: (a-fix-drc-cut-rule) [1.000]\\n' ;;
          *) exit 2 ;;
        esac
        """
    try Data(script.utf8).write(to: solverURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )
}
}
