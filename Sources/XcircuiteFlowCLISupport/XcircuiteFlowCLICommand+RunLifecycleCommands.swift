import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Xcircuite

extension XcircuiteFlowCLICommand {
    static func inspectRun(arguments: [String]) async throws -> String {
        let options = try parseRunLifecycleOptions(arguments)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let summary = try await DefaultFlowRunLedgerInspector(
            reviewBundler: makeReviewBundler(store: store)
        ).inspectRun(
            runID: options.runID,
            projectRoot: options.projectRoot
        )
        return try encode(summary, pretty: options.pretty)
    }

    static func reviewRun(arguments: [String]) async throws -> String {
        let options = try parseRunLifecycleOptions(arguments)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let bundle = try await makeReviewBundler(store: store).makeReviewBundle(
            runID: options.runID,
            projectRoot: options.projectRoot
        )
        return try encode(bundle, pretty: options.pretty)
    }

    static func buildStageArtifactLadder(arguments: [String]) async throws -> String {
        let options = try parseRunLifecycleOptions(arguments)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let result = try await DefaultFlowRunStageArtifactLadderBuilder(
            loader: store,
            reviewBundler: makeReviewBundler(store: store),
            persistence: store
        ).buildStageArtifactLadder(runID: options.runID, projectRoot: options.projectRoot)
        return try encode(result, pretty: options.pretty)
    }

    static func buildDecisionPacket(arguments: [String]) async throws -> String {
        let options = try parseRunLifecycleOptions(arguments)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let result = try await DefaultFlowRunDecisionPacketBuilder(
            reviewBundler: makeReviewBundler(store: store),
            persistence: store
        ).buildDecisionPacket(runID: options.runID, projectRoot: options.projectRoot)
        return try encode(result, pretty: options.pretty)
    }

    static func validateDecisionPacket(arguments: [String]) async throws -> String {
        let options = try parseRunLifecycleOptions(arguments)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let result = try await makeDecisionPacketValidator(store: store).validateDecisionPacket(
            runID: options.runID,
            projectRoot: options.projectRoot
        )
        return try encode(result, pretty: options.pretty)
    }

    static func buildReleaseEnvelope(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var maximumAge = 30
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--max-evidence-age-days": maximumAge = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        let options = try requireRunOptions(root: root, runID: runID, pretty: pretty)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let result = try await DefaultFlowRunReleaseEnvelopeBuilder(
            decisionPacketValidator: makeDecisionPacketValidator(store: store),
            loader: store,
            persistence: store
        ).buildReleaseEnvelope(
            runID: options.runID,
            projectRoot: options.projectRoot,
            maxEvidenceAgeDays: maximumAge
        )
        return try encode(result, pretty: options.pretty)
    }

    static func collectReleaseEvidence(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var dashboardPath: String?
        var contractPath: String?
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--signoff-dashboard": dashboardPath = try parser.requiredValue(after: argument)
            case "--contract-report": contractPath = try parser.requiredValue(after: argument)
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        let options = try requireRunOptions(root: root, runID: runID, pretty: pretty)
        guard let dashboardPath else { throw XcircuiteFlowCLIError.missingOption("--signoff-dashboard") }
        guard let contractPath else { throw XcircuiteFlowCLIError.missingOption("--contract-report") }
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let dashboard = try await store.makeArtifactReference(
            forProjectRelativePath: try workspacePath(dashboardPath, projectRoot: options.projectRoot),
            artifactID: "release-signoff-dashboard-input",
            role: .input,
            kind: .report,
            format: .json
        )
        let contract = try await store.makeArtifactReference(
            forProjectRelativePath: try workspacePath(contractPath, projectRoot: options.projectRoot),
            artifactID: "release-contract-report-input",
            role: .input,
            kind: .report,
            format: .json
        )
        let result = try await DefaultFlowRunReleaseEvidenceCollector(persistence: store).collectReleaseEvidence(
            runID: options.runID,
            projectRoot: options.projectRoot,
            signoffDashboard: dashboard,
            contractReport: contract
        )
        return try encode(result, pretty: options.pretty)
    }

    static func buildRetentionIndex(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var workflowRunID: String?
        var dashboardPath: String?
        var historyPath: String?
        var previousEntryCount: Int?
        var retentionDays: Int?
        var minimumRetentionDays: Int?
        var recordedAt = Date()
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--workflow-run-id": workflowRunID = try parser.requiredValue(after: argument)
            case "--source-dashboard": dashboardPath = try parser.requiredValue(after: argument)
            case "--history": historyPath = try parser.requiredValue(after: argument)
            case "--previous-entry-count": previousEntryCount = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--retention-days": retentionDays = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--minimum-retention-days": minimumRetentionDays = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--recorded-at": recordedAt = try parseTimestamp(try parser.requiredValue(after: argument), option: argument)
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        let options = try requireRunOptions(root: root, runID: runID, pretty: pretty)
        guard let workflowRunID else { throw XcircuiteFlowCLIError.missingOption("--workflow-run-id") }
        guard let dashboardPath else { throw XcircuiteFlowCLIError.missingOption("--source-dashboard") }
        guard let historyPath else { throw XcircuiteFlowCLIError.missingOption("--history") }
        guard let previousEntryCount else { throw XcircuiteFlowCLIError.missingOption("--previous-entry-count") }
        guard let retentionDays else { throw XcircuiteFlowCLIError.missingOption("--retention-days") }
        guard let minimumRetentionDays else { throw XcircuiteFlowCLIError.missingOption("--minimum-retention-days") }
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let dashboard = try await store.makeArtifactReference(
            forProjectRelativePath: try workspacePath(dashboardPath, projectRoot: options.projectRoot),
            artifactID: "retention-source-dashboard",
            role: .input,
            kind: .report,
            format: .json
        )
        let history = try await store.makeArtifactReference(
            forProjectRelativePath: try workspacePath(historyPath, projectRoot: options.projectRoot),
            artifactID: "retention-history",
            role: .input,
            kind: .release,
            format: try ArtifactFormat(rawValue: "json-lines")
        )
        let validator = DefaultFlowRunReleaseRetentionIndexValidator(persistence: store)
        let index = try await DefaultFlowRunReleaseRetentionIndexBuilder(
            persistence: store,
            validator: validator
        ).build(
            runID: options.runID,
            workflowRunID: workflowRunID,
            projectRoot: options.projectRoot,
            sourceDashboard: dashboard,
            history: history,
            previousEntryCount: previousEntryCount,
            retentionDays: retentionDays,
            minimumRetentionDays: minimumRetentionDays,
            recordedAt: recordedAt
        )
        let data = try JSONEncoder().encode(index)
        let artifact = try await store.persistArtifact(
            content: data,
            id: ArtifactID(rawValue: "qualification-retention-index"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: ".xcircuite/runs/\(options.runID)/qualification/retention-index.json"),
                role: .output,
                kind: .release,
                format: .json
            ),
            runID: options.runID,
            mode: .replaceable
        )
        return try encode(FlowRunReleaseRetentionIndexBuildResult(index: index, artifact: artifact), pretty: options.pretty)
    }

    static func validateRetentionIndex(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var maximumAge: Int?
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--max-evidence-age-days": maximumAge = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        let options = try requireRunOptions(root: root, runID: runID, pretty: pretty)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let reference = try await store.makeArtifactReference(
            forProjectRelativePath: ".xcircuite/runs/\(options.runID)/qualification/retention-index.json",
            artifactID: "qualification-retention-index",
            kind: .release,
            format: .json
        )
        let data = try await store.loadArtifactContent(for: reference)
        let index = try JSONDecoder().decode(FlowRunReleaseRetentionIndex.self, from: data)
        let result = try await DefaultFlowRunReleaseRetentionIndexValidator(persistence: store).validate(
            index: index,
            runID: options.runID,
            projectRoot: options.projectRoot,
            currentDate: Date(),
            maximumAgeSeconds: maximumAge.map { TimeInterval($0) * 86_400 }
        )
        return try encode(result, pretty: options.pretty)
    }

    static func approveGate(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var stageID: String?
        var verdict: FlowGateApprovalVerdict?
        var reviewer: String?
        var note = ""
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--stage-id": stageID = try parser.requiredValue(after: argument)
            case "--verdict":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = FlowGateApprovalVerdict(rawValue: value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                verdict = parsed
            case "--reviewer": reviewer = try parser.requiredValue(after: argument)
            case "--note": note = try parser.requiredValue(after: argument)
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        let options = try requireRunOptions(root: root, runID: runID, pretty: pretty)
        guard let stageID else { throw XcircuiteFlowCLIError.missingOption("--stage-id") }
        guard let verdict else { throw XcircuiteFlowCLIError.missingOption("--verdict") }
        guard let reviewer else { throw XcircuiteFlowCLIError.missingOption("--reviewer") }
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let inspector = DefaultFlowRunLedgerInspector(
            reviewBundler: makeReviewBundler(store: store)
        )
        let result = try await DefaultFlowGateApprovalRecorder(
            loader: store,
            inspector: inspector,
            ledgerPersistence: store
        ).recordApproval(FlowGateApprovalRequest(
            projectRoot: options.projectRoot,
            runID: options.runID,
            stageID: stageID,
            verdict: verdict,
            reviewer: reviewer,
            note: note
        ))
        return try encode(result, pretty: options.pretty)
    }

    static func requestCancellation(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var requestedBy: String?
        var reason: String?
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--requested-by": requestedBy = try parser.requiredValue(after: argument)
            case "--reason": reason = try parser.requiredValue(after: argument)
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        let options = try requireRunOptions(root: root, runID: runID, pretty: pretty)
        guard let requestedBy else { throw XcircuiteFlowCLIError.missingOption("--requested-by") }
        guard let reason else { throw XcircuiteFlowCLIError.missingOption("--reason") }
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let result = try await DefaultFlowRunCancellationRecorder(
            progressStore: FlowRunProgressStore(persistence: store)
        ).requestCancellation(
            projectRoot: options.projectRoot,
            runID: options.runID,
            requestedBy: requestedBy,
            reason: reason
        )
        return try encode(result, pretty: options.pretty)
    }

    static func progressRun(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var sequence = 0
        var timeout = 0
        var interval = 250
        var wait = false
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--since-sequence": sequence = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--timeout-ms": timeout = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--poll-interval-ms": interval = try parseInteger(try parser.requiredValue(after: argument), option: argument)
            case "--wait": wait = true
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        let options = try requireRunOptions(root: root, runID: runID, pretty: pretty)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let request = FlowRunProgressSubscriptionRequest(
            projectRoot: options.projectRoot,
            runID: options.runID,
            afterSequence: sequence,
            waitForNewEvents: wait,
            timeoutMilliseconds: timeout,
            pollIntervalMilliseconds: interval
        )
        let subscriber = DefaultFlowRunProgressSubscriber(
            progressStore: FlowRunProgressStore(persistence: store)
        )
        let snapshot = wait
            ? try await subscriber.waitForProgress(request: request)
            : try await subscriber.snapshot(request: request)
        return try encode(snapshot, pretty: options.pretty)
    }

    private static func parseRunLifecycleOptions(_ arguments: [String]) throws -> RunLifecycleOptions {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var root: URL?
        var runID: String?
        var pretty = false
        while let argument = parser.next() {
            switch argument {
            case "--project-root": root = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id": runID = try parser.requiredValue(after: argument)
            case "--pretty": pretty = true
            default: throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }
        return try requireRunOptions(root: root, runID: runID, pretty: pretty)
    }

    private static func requireRunOptions(root: URL?, runID: String?, pretty: Bool) throws -> RunLifecycleOptions {
        guard let root else { throw XcircuiteFlowCLIError.missingOption("--project-root") }
        guard let runID else { throw XcircuiteFlowCLIError.missingOption("--run-id") }
        return RunLifecycleOptions(projectRoot: root, runID: runID, pretty: pretty)
    }

    static func makeReviewBundler(store: XcircuiteWorkspaceStore) -> DefaultFlowRunReviewBundler {
        DefaultFlowRunReviewBundler(loader: store, persistence: store)
    }

    private static func makeDecisionPacketValidator(store: XcircuiteWorkspaceStore) -> DefaultFlowRunDecisionPacketValidator {
        DefaultFlowRunDecisionPacketValidator(
            loader: store,
            persistence: store,
            reviewBundler: makeReviewBundler(store: store)
        )
    }

    private static func parseInteger(_ value: String, option: String) throws -> Int {
        guard let result = Int(value) else {
            throw XcircuiteFlowCLIError.invalidValue(option: option, value: value)
        }
        return result
    }

    private static func parseTimestamp(_ value: String, option: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw XcircuiteFlowCLIError.invalidValue(option: option, value: value)
        }
        return date
    }

    private static func workspacePath(_ value: String, projectRoot: URL) throws -> String {
        let candidate = URL(filePath: value, relativeTo: projectRoot).standardizedFileURL
        let root = projectRoot.standardizedFileURL
        let rootPath = root.path(percentEncoded: false)
        let candidatePath = candidate.path(percentEncoded: false)
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            throw XcircuiteFlowCLIError.invalidValue(option: "artifact-path", value: value)
        }
        if candidatePath == rootPath {
            throw XcircuiteFlowCLIError.invalidValue(option: "artifact-path", value: value)
        }
        return String(candidatePath.dropFirst(rootPath.count + 1))
    }
}

private struct RunLifecycleOptions {
    let projectRoot: URL
    let runID: String
    let pretty: Bool
}
