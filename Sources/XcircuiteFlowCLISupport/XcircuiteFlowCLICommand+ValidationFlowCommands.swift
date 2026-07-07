import DesignFlowKernel
import Foundation
import Xcircuite
import XcircuitePackage

extension XcircuiteFlowCLICommand {
    static func validatePlanningProblem(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var actionDomainArtifactID: String?
        var actionDomainPath: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--action-domain-artifact-id":
                actionDomainArtifactID = try parser.requiredValue(after: argument)
            case "--action-domain-path":
                actionDomainPath = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return validatePlanningProblemHelpText
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

        let result = try XcircuitePlanningProblemValidator().validatePlanningProblem(
            request: XcircuitePlanningProblemValidationRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                actionDomainArtifactID: actionDomainArtifactID,
                actionDomainPath: actionDomainPath
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func auditProblemTranslation(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return auditProblemTranslationHelpText
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

        let result = try XcircuiteProblemTranslationAuditor().auditProblemTranslation(
            request: XcircuiteProblemTranslationAuditRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func validateSpecs(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runSpecURL: URL?
        var runtimeConfigURL: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-spec":
                runSpecURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--runtime-config":
                runtimeConfigURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return validateHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard runSpecURL != nil || runtimeConfigURL != nil else {
            throw XcircuiteFlowCLIError.missingOption("--run-spec or --runtime-config")
        }

        let runSpec = try runSpecURL.map { try XcircuiteFlowRunSpec.load(from: $0) }
        let runtimeSpec = try runtimeConfigURL.map { try XcircuiteFlowRuntimeSpec.load(from: $0) }

        if let runSpec, let runtimeSpec {
            try runtimeSpec.validateCoverage(for: runSpec, projectRoot: projectRoot)
        } else if let runSpec {
            try runSpec.validate()
        } else if let runtimeSpec {
            try runtimeSpec.validate(projectRoot: projectRoot)
        }

        var validated: [String] = []
        if runSpec != nil {
            validated.append("runSpec")
        }
        if runtimeSpec != nil {
            validated.append("runtimeConfig")
        }
        if runSpec != nil && runtimeSpec != nil {
            validated.append("coverage")
        }

        return try encode(
            ValidationOutput(
                status: "valid",
                validated: validated,
                runSpecPath: runSpecURL?.path(percentEncoded: false),
                runtimeConfigPath: runtimeConfigURL?.path(percentEncoded: false),
                runStageCount: runSpec?.stages.count,
                runtimeExecutorCount: runtimeSpec?.executors.count
            ),
            pretty: pretty
        )
    }

    static func inspectToolchainProfile(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runtimeConfigURL: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--runtime-config":
                runtimeConfigURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return inspectToolchainProfileHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let runtimeConfigURL else {
            throw XcircuiteFlowCLIError.missingOption("--runtime-config")
        }

        let runtimeSpec = try XcircuiteFlowRuntimeSpec.load(from: runtimeConfigURL)
        let inspection = try XcircuiteFlowToolchainProfileInspector().inspect(
            request: XcircuiteFlowToolchainProfileInspectionRequest(
                runtimeSpec: runtimeSpec,
                runtimeConfigURL: runtimeConfigURL,
                projectRoot: projectRoot
            )
        )
        return try encode(inspection, pretty: pretty)
    }

    static func inspectTechnologyCatalog(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runtimeConfigURL: URL?
        var catalogPaths: [String] = []
        var pdkRootPaths: [String] = []
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--runtime-config":
                runtimeConfigURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--catalog-path":
                catalogPaths.append(try parser.requiredValue(after: argument))
            case "--pdk-root":
                pdkRootPaths.append(try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return inspectTechnologyCatalogHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        if let runtimeConfigURL {
            let runtimeSpec = try XcircuiteFlowRuntimeSpec.load(from: runtimeConfigURL)
            if let catalogPath = runtimeSpec.toolchainProfile?.technologyCatalogPath {
                catalogPaths.append(catalogPath)
            }
        }
        catalogPaths = stableUnique(catalogPaths)
        pdkRootPaths = stableUnique(pdkRootPaths)
        guard !catalogPaths.isEmpty || !pdkRootPaths.isEmpty else {
            throw XcircuiteFlowCLIError.missingOption("--catalog-path, --runtime-config, or --pdk-root")
        }

        let inventory = XcircuiteFlowTechnologyCatalogInspector().inspect(
            request: XcircuiteFlowTechnologyCatalogInventoryRequest(
                catalogPaths: catalogPaths,
                pdkRootPaths: pdkRootPaths,
                projectRoot: projectRoot
            )
        )
        return try encode(inventory, pretty: pretty)
    }

    static func attachEvidence(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var runtimeConfig: URL?
        var evidenceURL: URL?
        var stageID: String?
        var outputURL: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--runtime-config":
                runtimeConfig = URL(filePath: try parser.requiredValue(after: argument))
            case "--evidence":
                evidenceURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--stage-id":
                stageID = try parser.requiredValue(after: argument)
            case "--out":
                outputURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return attachEvidenceHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let runtimeConfig else {
            throw XcircuiteFlowCLIError.missingOption("--runtime-config")
        }
        guard let evidenceURL else {
            throw XcircuiteFlowCLIError.missingOption("--evidence")
        }
        guard let stageID else {
            throw XcircuiteFlowCLIError.missingOption("--stage-id")
        }

        let evidenceExport = try XcircuiteFlowEvidenceExport.load(from: evidenceURL)
        let updatedRuntimeSpec = try XcircuiteFlowRuntimeSpec
            .load(from: runtimeConfig)
            .attachingEvidence(from: evidenceExport, toStageID: stageID)

        if let outputURL {
            try write(updatedRuntimeSpec, to: outputURL, pretty: pretty)
            return try encode(
                EvidenceAttachmentOutput(
                    status: "attached",
                    stageID: stageID,
                    evidenceID: evidenceExport.toolEvidence.evidenceID,
                    evidenceKind: evidenceExport.toolEvidence.kind.rawValue,
                    outputPath: outputURL.path(percentEncoded: false)
                ),
                pretty: pretty
            )
        }

        return try encode(updatedRuntimeSpec, pretty: pretty)
    }

    static func resumeRun(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var runtimeConfig: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--runtime-config":
                runtimeConfig = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return resumeRunHelpText
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
        guard let runtimeConfig else {
            throw XcircuiteFlowCLIError.missingOption("--runtime-config")
        }

        let runtime = try XcircuiteFlowRuntimeSpec
            .load(from: runtimeConfig)
            .makeRuntime(projectRoot: projectRoot)
        let result = try await runtime.resume(
            request: FlowRunResumeRequest(projectRoot: projectRoot, runID: runID)
        )
        return try encode(result, pretty: pretty)
    }

    static func runFlow(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runSpec: URL?
        var runtimeConfig: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-spec":
                runSpec = URL(filePath: try parser.requiredValue(after: argument))
            case "--runtime-config":
                runtimeConfig = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return runHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runSpec else {
            throw XcircuiteFlowCLIError.missingOption("--run-spec")
        }
        guard let runtimeConfig else {
            throw XcircuiteFlowCLIError.missingOption("--runtime-config")
        }

        let runtimeSpec = try XcircuiteFlowRuntimeSpec.load(from: runtimeConfig)
        let loadedRunSpec = try XcircuiteFlowRunSpec.load(from: runSpec)
        try runtimeSpec.validateCoverage(
            for: loadedRunSpec,
            projectRoot: projectRoot,
            requireCompleteToolEvidence: false
        )
        let runtime = try runtimeSpec.makeRuntime(projectRoot: projectRoot)
        let request = try loadedRunSpec.makeRequest(projectRoot: projectRoot)
        let result = try await runtime.run(request: request)
        return try encode(result, pretty: pretty)
    }
}
