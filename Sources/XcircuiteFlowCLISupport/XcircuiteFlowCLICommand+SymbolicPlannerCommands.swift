import DesignFlowKernel
import Foundation
import Xcircuite
import XcircuitePackage

extension XcircuiteFlowCLICommand {
    static func symbolicPlannerFeatureMatrix(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return symbolicPlannerFeatureMatrixHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        return try encode(
            XcircuiteSymbolicPlannerFeatureMatrixProvider().currentMatrix(),
            pretty: pretty
        )
    }

    static func exportSymbolicPlannerProblem(arguments: [String]) throws -> String {
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
                return exportSymbolicPlannerProblemHelpText
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

        let result = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(
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

    static func importSymbolicPlannerPlan(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var problemArtifactID: String?
        var problemPath: String?
        var pddlExportArtifactID: String?
        var pddlExportPath: String?
        var solverPlanArtifactID: String?
        var solverPlanPath: String?
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
            case "--pddl-export-artifact-id":
                pddlExportArtifactID = try parser.requiredValue(after: argument)
            case "--pddl-export-path":
                pddlExportPath = try parser.requiredValue(after: argument)
            case "--solver-plan-artifact-id":
                solverPlanArtifactID = try parser.requiredValue(after: argument)
            case "--solver-plan-path":
                solverPlanPath = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return importSymbolicPlannerPlanHelpText
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

        let result = try XcircuiteSymbolicPlannerPlanImporter().importSolverPlan(
            request: XcircuiteSymbolicPlannerPlanImportRequest(
                runID: runID,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                pddlExportArtifactID: pddlExportArtifactID,
                pddlExportPath: pddlExportPath,
                solverPlanArtifactID: solverPlanArtifactID,
                solverPlanPath: solverPlanPath
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func runSymbolicPlannerSolver(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var executablePath: String?
        var solverArguments: [String] = []
        var timeoutSeconds: Double = 300
        var domainArtifactID: String?
        var domainPath: String?
        var problemArtifactID: String?
        var problemPath: String?
        var pddlExportArtifactID: String?
        var pddlExportPath: String?
        var workingDirectoryPath: String?
        var solverPlanOutputPath: String?
        var importCandidatePlan = true
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--executable-path":
                executablePath = try parser.requiredValue(after: argument)
            case "--arg":
                solverArguments.append(try parser.requiredValue(after: argument))
            case "--timeout-seconds":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Double(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                timeoutSeconds = parsed
            case "--domain-artifact-id":
                domainArtifactID = try parser.requiredValue(after: argument)
            case "--domain-path":
                domainPath = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--pddl-export-artifact-id":
                pddlExportArtifactID = try parser.requiredValue(after: argument)
            case "--pddl-export-path":
                pddlExportPath = try parser.requiredValue(after: argument)
            case "--working-directory-path":
                workingDirectoryPath = try parser.requiredValue(after: argument)
            case "--solver-plan-output-path":
                solverPlanOutputPath = try parser.requiredValue(after: argument)
            case "--no-import":
                importCandidatePlan = false
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return runSymbolicPlannerSolverHelpText
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
        guard let executablePath else {
            throw XcircuiteFlowCLIError.missingOption("--executable-path")
        }

        let result = try await XcircuiteSymbolicPlannerSolverRunner().solve(
            request: XcircuiteSymbolicPlannerSolverRequest(
                runID: runID,
                executablePath: executablePath,
                arguments: solverArguments,
                timeoutSeconds: timeoutSeconds,
                domainArtifactID: domainArtifactID,
                domainPath: domainPath,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                pddlExportArtifactID: pddlExportArtifactID,
                pddlExportPath: pddlExportPath,
                workingDirectoryPath: workingDirectoryPath,
                solverPlanOutputPath: solverPlanOutputPath,
                importCandidatePlan: importCandidatePlan
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func qualifySymbolicPlannerSolver(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var toolID = "external-symbolic-planner"
        var executablePath: String?
        var solverArguments: [String] = []
        var timeoutSeconds: Double = 300
        var expectedActionIDs: [String] = []
        var requireGoalCoverage = true
        var requireOptimality = false
        var maximumSolverCost: Double?
        var requireNativeCertificate = false
        var requireProofValidation = false
        var policyID = "symbolic-planner-solver-qualification-v1"
        var domainArtifactID: String?
        var domainPath: String?
        var problemArtifactID: String?
        var problemPath: String?
        var pddlExportArtifactID: String?
        var pddlExportPath: String?
        var workingDirectoryPath: String?
        var solverPlanOutputPath: String?
        var certificateArtifactID: String?
        var certificatePath: String?
        var certificateFormat = "auto"
        var proofArtifactID: String?
        var proofPath: String?
        var proofCheckerExecutablePath: String?
        var proofCheckerArguments: [String] = []
        var proofCheckerTimeoutSeconds: Double = 30
        var proofCheckerWorkingDirectoryPath: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--tool-id":
                toolID = try parser.requiredValue(after: argument)
            case "--executable-path":
                executablePath = try parser.requiredValue(after: argument)
            case "--arg":
                solverArguments.append(try parser.requiredValue(after: argument))
            case "--timeout-seconds":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Double(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                timeoutSeconds = parsed
            case "--expected-action-id":
                expectedActionIDs.append(try parser.requiredValue(after: argument))
            case "--allow-missing-goal-coverage":
                requireGoalCoverage = false
            case "--require-optimality":
                requireOptimality = true
            case "--require-native-certificate":
                requireNativeCertificate = true
            case "--max-solver-cost":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Double(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                maximumSolverCost = parsed
            case "--require-proof-validation":
                requireProofValidation = true
            case "--policy-id":
                policyID = try parser.requiredValue(after: argument)
            case "--domain-artifact-id":
                domainArtifactID = try parser.requiredValue(after: argument)
            case "--domain-path":
                domainPath = try parser.requiredValue(after: argument)
            case "--problem-artifact-id":
                problemArtifactID = try parser.requiredValue(after: argument)
            case "--problem-path":
                problemPath = try parser.requiredValue(after: argument)
            case "--pddl-export-artifact-id":
                pddlExportArtifactID = try parser.requiredValue(after: argument)
            case "--pddl-export-path":
                pddlExportPath = try parser.requiredValue(after: argument)
            case "--working-directory-path":
                workingDirectoryPath = try parser.requiredValue(after: argument)
            case "--solver-plan-output-path":
                solverPlanOutputPath = try parser.requiredValue(after: argument)
            case "--certificate-artifact-id":
                certificateArtifactID = try parser.requiredValue(after: argument)
            case "--certificate-path":
                certificatePath = try parser.requiredValue(after: argument)
            case "--certificate-format":
                certificateFormat = try parser.requiredValue(after: argument)
            case "--proof-artifact-id":
                proofArtifactID = try parser.requiredValue(after: argument)
            case "--proof-path":
                proofPath = try parser.requiredValue(after: argument)
            case "--proof-checker-executable-path":
                proofCheckerExecutablePath = try parser.requiredValue(after: argument)
            case "--proof-checker-arg":
                proofCheckerArguments.append(try parser.requiredValue(after: argument))
            case "--proof-checker-timeout-seconds":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Double(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                proofCheckerTimeoutSeconds = parsed
            case "--proof-checker-working-directory-path":
                proofCheckerWorkingDirectoryPath = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return qualifySymbolicPlannerSolverHelpText
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
        guard let executablePath else {
            throw XcircuiteFlowCLIError.missingOption("--executable-path")
        }

        let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverQualificationRequest(
                runID: runID,
                toolID: toolID,
                executablePath: executablePath,
                arguments: solverArguments,
                timeoutSeconds: timeoutSeconds,
                expectedActionIDs: expectedActionIDs,
                requireGoalCoverage: requireGoalCoverage,
                requireOptimality: requireOptimality,
                maximumSolverCost: maximumSolverCost,
                requireNativeCertificate: requireNativeCertificate,
                requireProofValidation: requireProofValidation,
                policyID: policyID,
                domainArtifactID: domainArtifactID,
                domainPath: domainPath,
                problemArtifactID: problemArtifactID,
                problemPath: problemPath,
                pddlExportArtifactID: pddlExportArtifactID,
                pddlExportPath: pddlExportPath,
                workingDirectoryPath: workingDirectoryPath,
                solverPlanOutputPath: solverPlanOutputPath,
                certificateArtifactID: certificateArtifactID,
                certificatePath: certificatePath,
                certificateFormat: certificateFormat,
                proofArtifactID: proofArtifactID,
                proofPath: proofPath,
                proofCheckerExecutablePath: proofCheckerExecutablePath,
                proofCheckerArguments: proofCheckerArguments,
                proofCheckerTimeoutSeconds: proofCheckerTimeoutSeconds,
                proofCheckerWorkingDirectoryPath: proofCheckerWorkingDirectoryPath
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func compareSymbolicPlannerSolverFamily(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var comparisonID = "solver-family-1"
        var qualificationArtifactIDs: [String] = []
        var qualificationPaths: [String] = []
        var selectionPolicy = "prefer-qualified-health-replay-goals-proof-optimality-cost"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--comparison-id":
                comparisonID = try parser.requiredValue(after: argument)
            case "--qualification-artifact-id":
                qualificationArtifactIDs.append(try parser.requiredValue(after: argument))
            case "--qualification-path":
                qualificationPaths.append(try parser.requiredValue(after: argument))
            case "--selection-policy":
                selectionPolicy = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return compareSymbolicPlannerSolverFamilyHelpText
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
        let result = try XcircuiteSymbolicPlannerSolverFamilyComparator().compare(
            request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest(
                runID: runID,
                comparisonID: comparisonID,
                qualificationArtifactIDs: qualificationArtifactIDs,
                qualificationPaths: qualificationPaths,
                selectionPolicy: selectionPolicy
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func promoteSymbolicPlannerSolverFamilySelection(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var comparisonID = "solver-family-1"
        var comparisonArtifactID: String?
        var comparisonPath: String?
        var selectedCandidateIndex: Int?
        var requireQualified = true
        var verifyPromotedPlan = true
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--comparison-id":
                comparisonID = try parser.requiredValue(after: argument)
            case "--comparison-artifact-id":
                comparisonArtifactID = try parser.requiredValue(after: argument)
            case "--comparison-path":
                comparisonPath = try parser.requiredValue(after: argument)
            case "--candidate-index":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Int(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                selectedCandidateIndex = parsed
            case "--allow-unqualified":
                requireQualified = false
            case "--skip-verification":
                verifyPromotedPlan = false
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return promoteSymbolicPlannerSolverFamilySelectionHelpText
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
        let result = try await XcircuiteSymbolicPlannerSolverFamilyPromoter().promote(
            request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest(
                runID: runID,
                comparisonID: comparisonID,
                comparisonArtifactID: comparisonArtifactID,
                comparisonPath: comparisonPath,
                selectedCandidateIndex: selectedCandidateIndex,
                requireQualified: requireQualified,
                verifyPromotedPlan: verifyPromotedPlan
            ),
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func runSymbolicPlannerSolverFamily(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var specPath: String?
        var comparisonID: String?
        var promoteSelectedPlan: Bool?
        var requireQualifiedPromotion: Bool?
        var verifyPromotedPlan: Bool?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--spec":
                specPath = try parser.requiredValue(after: argument)
            case "--comparison-id":
                comparisonID = try parser.requiredValue(after: argument)
            case "--no-promote":
                promoteSelectedPlan = false
            case "--allow-unqualified-promotion":
                requireQualifiedPromotion = false
            case "--skip-promotion-verification":
                verifyPromotedPlan = false
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return runSymbolicPlannerSolverFamilyHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let specPath else {
            throw XcircuiteFlowCLIError.missingOption("--spec")
        }

        var request = try XcircuitePackageStore().readJSON(
            XcircuiteSymbolicPlannerSolverFamilyBatchRequest.self,
            from: URL(filePath: specPath)
        )
        if let comparisonID {
            request.comparisonID = comparisonID
        }
        if let promoteSelectedPlan {
            request.promoteSelectedPlan = promoteSelectedPlan
        }
        if let requireQualifiedPromotion {
            request.requireQualifiedPromotion = requireQualifiedPromotion
        }
        if let verifyPromotedPlan {
            request.verifyPromotedPlan = verifyPromotedPlan
        }

        let result = try await XcircuiteSymbolicPlannerSolverFamilyBatchRunner().run(
            request: request,
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func discoverInstalledSymbolicPlannerSolvers(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var laneID = "installed-symbolic-planner-solvers"
        var selectionPolicy = "prefer-qualified-health-replay-goals-proof-optimality-cost"
        var searchPaths: [String] = []
        var promoteSelectedPlan = false
        var requireQualifiedPromotion = true
        var verifyPromotedPlan = true
        var batchSpecOutputPath: String?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--lane-id":
                laneID = try parser.requiredValue(after: argument)
            case "--selection-policy":
                selectionPolicy = try parser.requiredValue(after: argument)
            case "--search-path":
                searchPaths.append(try parser.requiredValue(after: argument))
            case "--promote-selected-plan":
                promoteSelectedPlan = true
            case "--allow-unqualified-promotion":
                requireQualifiedPromotion = false
            case "--skip-promotion-verification":
                verifyPromotedPlan = false
            case "--batch-spec-output-path":
                batchSpecOutputPath = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return discoverInstalledSymbolicPlannerSolversHelpText
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

        let result = try XcircuiteSymbolicPlannerInstalledSolverLaneResolver().discover(
            request: XcircuiteSymbolicPlannerInstalledSolverLaneRequest(
                runID: runID,
                laneID: laneID,
                selectionPolicy: selectionPolicy,
                searchPaths: searchPaths,
                promoteSelectedPlan: promoteSelectedPlan,
                requireQualifiedPromotion: requireQualifiedPromotion,
                verifyPromotedPlan: verifyPromotedPlan
            ),
            projectRoot: projectRoot
        )
        if let batchSpecOutputPath,
           let batchRequest = result.lane.batchRequest {
            try XcircuitePackageStore().writeJSON(
                batchRequest,
                to: URL(filePath: batchSpecOutputPath),
                forProjectAt: projectRoot
            )
        }
        return try encode(result, pretty: pretty)
    }

    static func qualifySymbolicPlannerSolverCorpus(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var suiteSpecPath: String?
        var suiteID: String?
        var toolID: String?
        var executablePath: String?
        var solverArguments: [String] = []
        var didProvideSolverArguments = false
        var timeoutSeconds: Double?
        var policyID: String?
        var caseValues: [String] = []
        var requiredCoverageTags: [String] = []
        var caseCoverageValues: [String] = []
        var requireGoalCoverage = true
        var requireOptimality = false
        var maximumSolverCost: Double?
        var requireProofValidation = false
        var proofCheckerExecutablePath: String?
        var proofCheckerArguments: [String] = []
        var proofCheckerTimeoutSeconds: Double = 30
        var proofCheckerWorkingDirectoryPath: String?
        var caseProofValues: [String] = []
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--suite-spec":
                suiteSpecPath = try parser.requiredValue(after: argument)
            case "--suite-id":
                suiteID = try parser.requiredValue(after: argument)
            case "--tool-id":
                toolID = try parser.requiredValue(after: argument)
            case "--executable-path":
                executablePath = try parser.requiredValue(after: argument)
            case "--arg":
                didProvideSolverArguments = true
                solverArguments.append(try parser.requiredValue(after: argument))
            case "--timeout-seconds":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Double(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                timeoutSeconds = parsed
            case "--policy-id":
                policyID = try parser.requiredValue(after: argument)
            case "--required-coverage-tag":
                requiredCoverageTags.append(try parser.requiredValue(after: argument))
            case "--case":
                caseValues.append(try parser.requiredValue(after: argument))
            case "--case-coverage":
                caseCoverageValues.append(try parser.requiredValue(after: argument))
            case "--allow-missing-goal-coverage":
                requireGoalCoverage = false
            case "--require-optimality":
                requireOptimality = true
            case "--max-solver-cost":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Double(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                maximumSolverCost = parsed
            case "--require-proof-validation":
                requireProofValidation = true
            case "--proof-checker-executable-path":
                proofCheckerExecutablePath = try parser.requiredValue(after: argument)
            case "--proof-checker-arg":
                proofCheckerArguments.append(try parser.requiredValue(after: argument))
            case "--proof-checker-timeout-seconds":
                let value = try parser.requiredValue(after: argument)
                guard let parsed = Double(value) else {
                    throw XcircuiteFlowCLIError.invalidValue(option: argument, value: value)
                }
                proofCheckerTimeoutSeconds = parsed
            case "--proof-checker-working-directory-path":
                proofCheckerWorkingDirectoryPath = try parser.requiredValue(after: argument)
            case "--case-proof":
                caseProofValues.append(try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return qualifySymbolicPlannerSolverCorpusHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }

        let request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest
        if let suiteSpecPath {
            guard suiteID == nil,
                  toolID == nil,
                  executablePath == nil,
                  !didProvideSolverArguments,
                  timeoutSeconds == nil,
                  policyID == nil,
                  requiredCoverageTags.isEmpty,
                  caseValues.isEmpty,
                  caseCoverageValues.isEmpty,
                  !requireOptimality,
                  maximumSolverCost == nil,
                  !requireProofValidation,
                  proofCheckerExecutablePath == nil,
                  proofCheckerArguments.isEmpty,
                  proofCheckerTimeoutSeconds == 30,
                  proofCheckerWorkingDirectoryPath == nil,
                  caseProofValues.isEmpty,
                  requireGoalCoverage else {
                throw XcircuiteFlowCLIError.invalidValue(
                    option: "--suite-spec",
                    value: "cannot be combined with per-suite qualification options"
                )
            }
            request = try XcircuitePackageStore()
                .readJSON(
                    XcircuiteSymbolicPlannerSolverCorpusSuiteSpec.self,
                    from: URL(filePath: suiteSpecPath)
                )
                .qualificationRequest
        } else {
            guard let suiteID else {
                throw XcircuiteFlowCLIError.missingOption("--suite-id")
            }
            guard let executablePath else {
                throw XcircuiteFlowCLIError.missingOption("--executable-path")
            }
            guard !caseValues.isEmpty else {
                throw XcircuiteFlowCLIError.missingOption("--case")
            }
            let coverageByCaseID = try parseCorpusCaseCoverage(caseCoverageValues)
            let proofPathByCaseID = try parseCorpusCaseProofPaths(caseProofValues)
            let cases = try caseValues.map {
                let caseID = try parseCorpusCaseID($0)
                return try parseCorpusCase(
                    $0,
                    coverageTags: coverageByCaseID[caseID, default: []],
                    requireGoalCoverage: requireGoalCoverage,
                    requireOptimality: requireOptimality,
                    maximumSolverCost: maximumSolverCost,
                    proofPath: proofPathByCaseID[caseID]
                )
            }
            request = XcircuiteSymbolicPlannerSolverCorpusQualificationRequest(
                suiteID: suiteID,
                toolID: toolID ?? "external-symbolic-planner",
                executablePath: executablePath,
                arguments: solverArguments,
                timeoutSeconds: timeoutSeconds ?? 300,
                policyID: policyID ?? "symbolic-planner-solver-corpus-qualification-v1",
                requiredCoverageTags: requiredCoverageTags,
                requireProofValidation: requireProofValidation,
                proofCheckerExecutablePath: proofCheckerExecutablePath,
                proofCheckerArguments: proofCheckerArguments,
                proofCheckerTimeoutSeconds: proofCheckerTimeoutSeconds,
                proofCheckerWorkingDirectoryPath: proofCheckerWorkingDirectoryPath,
                cases: cases
            )
        }

        let result = try await XcircuiteSymbolicPlannerSolverCorpusQualifier().qualify(
            request: request,
            projectRoot: projectRoot
        )
        return try encode(result, pretty: pretty)
    }

    static func parseCorpusCase(
        _ rawValue: String,
        coverageTags: [String],
        requireGoalCoverage: Bool,
        requireOptimality: Bool,
        maximumSolverCost: Double?,
        proofPath: String?
    ) throws -> XcircuiteSymbolicPlannerSolverCorpusCaseRequest {
        let runID = try parseCorpusCaseID(rawValue)
        let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let expectedActionIDs: [String]
        if parts.count == 2 {
            expectedActionIDs = parts[1]
                .split(separator: ",", omittingEmptySubsequences: true)
                .map(String.init)
        } else {
            expectedActionIDs = []
        }
        return XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
            caseID: runID,
            runID: runID,
            expectedActionIDs: expectedActionIDs,
            coverageTags: coverageTags,
            requireGoalCoverage: requireGoalCoverage,
            requireOptimality: requireOptimality,
            maximumSolverCost: maximumSolverCost,
            proofPath: proofPath
        )
    }

    static func parseCorpusCaseID(_ rawValue: String) throws -> String {
        let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let runIDPart = parts.first, !runIDPart.isEmpty else {
            throw XcircuiteFlowCLIError.invalidValue(option: "--case", value: rawValue)
        }
        return String(runIDPart)
    }

    static func parseCorpusCaseCoverage(_ rawValues: [String]) throws -> [String: [String]] {
        var coverageByCaseID: [String: [String]] = [:]
        for rawValue in rawValues {
            let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let caseIDPart = parts.first, !caseIDPart.isEmpty else {
                throw XcircuiteFlowCLIError.invalidValue(option: "--case-coverage", value: rawValue)
            }
            let coverageTags = parts[1]
                .split(separator: ",", omittingEmptySubsequences: true)
                .map(String.init)
            coverageByCaseID[String(caseIDPart), default: []].append(contentsOf: coverageTags)
        }
        return coverageByCaseID
    }

    static func parseCorpusCaseProofPaths(_ rawValues: [String]) throws -> [String: String] {
        var proofPathByCaseID: [String: String] = [:]
        for rawValue in rawValues {
            let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let caseIDPart = parts.first,
                  !caseIDPart.isEmpty,
                  !parts[1].isEmpty else {
                throw XcircuiteFlowCLIError.invalidValue(option: "--case-proof", value: rawValue)
            }
            proofPathByCaseID[String(caseIDPart)] = String(parts[1])
        }
        return proofPathByCaseID
    }
}
