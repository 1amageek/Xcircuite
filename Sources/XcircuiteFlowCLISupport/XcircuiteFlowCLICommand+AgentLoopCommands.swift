import DesignFlowKernel
import Foundation
import Xcircuite
import DesignFlowKernel

extension XcircuiteFlowCLICommand {
    static func summarizeLoop(arguments: [String]) async throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return summarizeLoopHelpText
        }
        let options = try parseAgentLoopOptions(arguments: arguments)
        let profile = try loadAgentLoopProfile(from: options.profileURL)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let workspaceID = try await workspaceID(for: store)
        let result = try await DefaultFlowRunLoopSnapshotBuilder(
            loader: store,
            evidencePersistence: store
        ).summarizeLoop(
            runID: options.runID,
            workspaceID: workspaceID,
            profile: profile,
            persist: options.persist
        )
        return try encode(result, pretty: options.pretty)
    }

    static func evaluateRunGuard(arguments: [String]) async throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return evaluateRunGuardHelpText
        }
        let options = try parseAgentLoopOptions(arguments: arguments)
        let profile = try loadAgentLoopProfile(from: options.profileURL)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let workspaceID = try await workspaceID(for: store)
        let snapshotBuilder = DefaultFlowRunLoopSnapshotBuilder(
            loader: store,
            evidencePersistence: store
        )
        let result = try await DefaultFlowRunGuardEvaluator(
            snapshotBuilder: snapshotBuilder,
            persistence: store
        ).evaluateRunGuard(
            runID: options.runID,
            workspaceID: workspaceID,
            profile: profile,
            persist: options.persist
        )
        return try encode(result, pretty: options.pretty)
    }

    static func compareArtifacts(arguments: [String]) async throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return compareArtifactsHelpText
        }
        let options = try parseEvaluationOptions(arguments: arguments)
        let profile = try loadEvaluationProfile(from: options.profileURL)
        let store = try XcircuiteWorkspaceStore(projectRoot: options.projectRoot)
        let workspaceID = try await workspaceID(for: store)
        let result = try await DefaultFlowRunCrossArtifactEvaluator(
            loader: store,
            evidencePersistence: store
        ).compareArtifacts(
            runID: options.runID,
            workspaceID: workspaceID,
            profile: profile,
            persist: options.persist
        )
        return try encode(result, pretty: options.pretty)
    }

    static func writeOpAmpEvaluationProfile(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return writeOpAmpEvaluationProfileHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var outURL: URL?
        var profileID = "opamp-evaluation-profile"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--profile-id":
                profileID = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let outURL else {
            throw XcircuiteFlowCLIError.missingOption("--out")
        }

        let profile = OpAmpEvaluationProfileFactory().makeProfile(profileID: profileID)
        try write(profile, to: outURL, pretty: pretty)
        return try encode(profile, pretty: pretty)
    }

    private static func parseAgentLoopOptions(arguments: [String]) throws -> AgentLoopCLIOptions {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var profileURL: URL?
        var persist = true
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--profile":
                profileURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--no-persist":
                persist = false
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        return AgentLoopCLIOptions(
            projectRoot: projectRoot,
            runID: runID,
            profileURL: profileURL,
            persist: persist,
            pretty: pretty
        )
    }

    private static func loadAgentLoopProfile(from url: URL?) throws -> FlowAgentLoopProfile {
        guard let url else {
            return .makeDefault()
        }
        let profile = try decodeJSONFile(
            FlowAgentLoopProfile.self,
            from: url,
            option: "--profile"
        )
        do {
            try FlowAgentLoopProfileValidator().validate(profile)
        } catch {
            throw XcircuiteFlowCLIError.invalidValue(
                option: "--profile",
                value: url.path(percentEncoded: false)
            )
        }
        return profile
    }

    private static func parseEvaluationOptions(arguments: [String]) throws -> EvaluationCLIOptions {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var profileURL: URL?
        var persist = true
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--profile":
                profileURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--no-persist":
                persist = false
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }

        return EvaluationCLIOptions(
            projectRoot: projectRoot,
            runID: runID,
            profileURL: profileURL,
            persist: persist,
            pretty: pretty
        )
    }

    private static func loadEvaluationProfile(from url: URL?) throws -> FlowEvaluationProfile? {
        guard let url else {
            return nil
        }
        return try decodeJSONFile(
            FlowEvaluationProfile.self,
            from: url,
            option: "--profile"
        )
    }

    private static func workspaceID(
        for store: XcircuiteWorkspaceStore
    ) async throws -> FlowWorkspaceID {
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }
}

private struct AgentLoopCLIOptions {
    var projectRoot: URL
    var runID: String
    var profileURL: URL?
    var persist: Bool
    var pretty: Bool
}

private struct EvaluationCLIOptions {
    var projectRoot: URL
    var runID: String
    var profileURL: URL?
    var persist: Bool
    var pretty: Bool
}
