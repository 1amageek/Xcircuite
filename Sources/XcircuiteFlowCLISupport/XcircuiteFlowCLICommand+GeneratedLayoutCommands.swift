import DesignFlowKernel
import Foundation
import Xcircuite
import DesignFlowKernel

extension XcircuiteFlowCLICommand {
    static func collectGeneratedLayoutSignoffCorpus(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var requestURL: URL?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--request":
                requestURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return collectGeneratedLayoutSignoffCorpusHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let requestURL else {
            throw XcircuiteFlowCLIError.missingOption("--request")
        }

        let request = try decodeJSONFile(
            XcircuiteGeneratedLayoutSignoffCorpusRequest.self,
            from: requestURL,
            option: "--request"
        )
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let collector = XcircuiteGeneratedLayoutSignoffCorpusCollector(
            ledgerLoader: workspaceStore,
            reviewBundler: makeReviewBundler(store: workspaceStore),
            workspaceStore: workspaceStore
        )
        let report = try await persist
            ? collector.collectAndPersist(request: request, projectRoot: projectRoot)
            : collector.collect(request: request, projectRoot: projectRoot)
        return try encode(report, pretty: pretty)
    }

    static func validateGeneratedLayoutSignoffCorpus(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var reportURL: URL?
        var policyURL: URL?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--report":
                reportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--policy":
                policyURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return validateGeneratedLayoutSignoffCorpusHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let reportURL else {
            throw XcircuiteFlowCLIError.missingOption("--report")
        }

        let report = try decodeJSONFile(
            XcircuiteGeneratedLayoutSignoffCorpusReport.self,
            from: reportURL,
            option: "--report"
        )
        let policy: XcircuiteGeneratedLayoutSignoffCorpusValidationPolicy
        if let policyURL {
            policy = try decodeJSONFile(
                XcircuiteGeneratedLayoutSignoffCorpusValidationPolicy.self,
                from: policyURL,
                option: "--policy"
            )
        } else {
            policy = .defaultPolicy(requiredCoverageTags: report.summary.requiredCoverageTags)
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let validator = XcircuiteGeneratedLayoutSignoffCorpusValidator(workspaceStore: workspaceStore)
        let result = try await persist
            ? validator.validateAndPersist(report: report, policy: policy, projectRoot: projectRoot)
            : validator.validate(report: report, policy: policy)
        return try encode(result, pretty: pretty)
    }

    static func attachGeneratedLayoutReadyOracleEvidence(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var reportURL: URL?
        var retainedSignoffReportURL: URL?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--report":
                reportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--retained-signoff-report":
                retainedSignoffReportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return attachGeneratedLayoutReadyOracleEvidenceHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let reportURL else {
            throw XcircuiteFlowCLIError.missingOption("--report")
        }
        guard let retainedSignoffReportURL else {
            throw XcircuiteFlowCLIError.missingOption("--retained-signoff-report")
        }

        let report = try decodeJSONFile(
            XcircuiteGeneratedLayoutSignoffCorpusReport.self,
            from: reportURL,
            option: "--report"
        )
        let retainedReport = try decodeJSONFile(
            XcircuiteRetainedSignoffReport.self,
            from: retainedSignoffReportURL,
            option: "--retained-signoff-report"
        )
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let attacher = XcircuiteGeneratedLayoutReadyOracleEvidenceAttacher(workspaceStore: workspaceStore)
        let result = try await persist
            ? attacher.attachAndPersist(
                report: report,
                retainedSignoffReport: retainedReport,
                retainedSignoffReportURL: retainedSignoffReportURL,
                projectRoot: projectRoot
            )
            : attacher.attach(
                report: report,
                retainedSignoffReport: retainedReport,
                retainedSignoffReportURL: retainedSignoffReportURL
            )
        return try encode(result, pretty: pretty)
    }

    static func auditGeneratedLayoutSignoffCorpusCoverage(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var reportURL: URL?
        var policyURL: URL?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--report":
                reportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--policy":
                policyURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return auditGeneratedLayoutSignoffCorpusCoverageHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let reportURL else {
            throw XcircuiteFlowCLIError.missingOption("--report")
        }
        guard let policyURL else {
            throw XcircuiteFlowCLIError.missingOption("--policy")
        }

        let report = try decodeJSONFile(
            XcircuiteGeneratedLayoutSignoffCorpusReport.self,
            from: reportURL,
            option: "--report"
        )
        let policy = try decodeJSONFile(
            XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy.self,
            from: policyURL,
            option: "--policy"
        )
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let auditor = XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditor(workspaceStore: workspaceStore)
        let audit = try await persist
            ? auditor.auditAndPersist(report: report, policy: policy, projectRoot: projectRoot)
            : auditor.audit(report: report, policy: policy)
        return try encode(audit, pretty: pretty)
    }

    static func assessGeneratedLayoutSignoffPromotion(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var validationURL: URL?
        var retainedSignoffReportURL: URL?
        var promotionID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--validation":
                validationURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--retained-signoff-report":
                retainedSignoffReportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--promotion-id":
                promotionID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return assessGeneratedLayoutSignoffPromotionHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let validationURL else {
            throw XcircuiteFlowCLIError.missingOption("--validation")
        }

        let validation = try decodeJSONFile(
            XcircuiteGeneratedLayoutSignoffCorpusValidationResult.self,
            from: validationURL,
            option: "--validation"
        )
        let retainedReport: XcircuiteRetainedSignoffReport?
        if let retainedSignoffReportURL {
            retainedReport = try decodeJSONFile(
                XcircuiteRetainedSignoffReport.self,
                from: retainedSignoffReportURL,
                option: "--retained-signoff-report"
            )
        } else {
            retainedReport = nil
        }
        let request = XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
            promotionID: promotionID ?? "generated-layout-signoff-promotion"
        )
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let assessor = XcircuiteGeneratedLayoutSignoffPromotionAssessor(workspaceStore: workspaceStore)
        let assessment = try await persist
            ? assessor.assessAndPersist(
                request: request,
                validation: validation,
                retainedSignoffReport: retainedReport,
                retainedSignoffReportURL: retainedSignoffReportURL,
                projectRoot: projectRoot
            )
            : assessor.assess(
                request: request,
                validation: validation,
                retainedSignoffReport: retainedReport,
                retainedSignoffReportURL: retainedSignoffReportURL
            )
        return try encode(assessment, pretty: pretty)
    }

    static func collectGeneratedLayoutFailureLadder(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var ladderID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--ladder-id":
                ladderID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return collectGeneratedLayoutFailureLadderHelpText
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

        let request = XcircuiteGeneratedLayoutFailureLadderRequest(
            ladderID: ladderID ?? "generated-layout-failure-ladder-\(runID)",
            runID: runID
        )
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let collector = XcircuiteGeneratedLayoutFailureLadderCollector(
            ledgerLoader: workspaceStore,
            reviewBundler: makeReviewBundler(store: workspaceStore),
            workspaceStore: workspaceStore
        )
        let report = try await persist
            ? collector.collectAndPersist(request: request, projectRoot: projectRoot)
            : collector.collect(request: request, projectRoot: projectRoot)
        return try encode(report, pretty: pretty)
    }

    static func auditGeneratedLayoutFailureLadderCoverage(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var policyURL: URL?
        var reportURLs: [URL] = []
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--policy":
                policyURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--report":
                reportURLs.append(URL(filePath: try parser.requiredValue(after: argument)))
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return auditGeneratedLayoutFailureLadderCoverageHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let policyURL else {
            throw XcircuiteFlowCLIError.missingOption("--policy")
        }
        guard !reportURLs.isEmpty else {
            throw XcircuiteFlowCLIError.missingOption("--report")
        }

        let policy = try decodeJSONFile(
            XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy.self,
            from: policyURL,
            option: "--policy"
        )
        let reports = try reportURLs.map { reportURL in
            try decodeJSONFile(
                XcircuiteGeneratedLayoutFailureLadderReport.self,
                from: reportURL,
                option: "--report"
            )
        }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let auditor = XcircuiteGeneratedLayoutFailureLadderCoverageAuditor(workspaceStore: workspaceStore)
        let audit = try await persist
            ? auditor.auditAndPersist(reports: reports, policy: policy, projectRoot: projectRoot)
            : auditor.audit(reports: reports, policy: policy)
        return try encode(audit, pretty: pretty)
    }
}
