import DesignFlowKernel
import Foundation
import Xcircuite
import XcircuitePackage

extension XcircuiteFlowCLICommand {
    static func collectGeneratedLayoutSignoffCorpus(arguments: [String]) throws -> String {
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
        let collector = XcircuiteGeneratedLayoutSignoffCorpusCollector()
        let report = try persist
            ? collector.collectAndPersist(request: request, projectRoot: projectRoot)
            : collector.collect(request: request, projectRoot: projectRoot)
        return try encode(report, pretty: pretty)
    }

    static func qualifyGeneratedLayoutSignoffCorpus(arguments: [String]) throws -> String {
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
                return qualifyGeneratedLayoutSignoffCorpusHelpText
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
        let policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
        if let policyURL {
            policy = try decodeJSONFile(
                XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy.self,
                from: policyURL,
                option: "--policy"
            )
        } else {
            policy = .defaultPolicy(requiredCoverageTags: report.summary.requiredCoverageTags)
        }

        let qualifier = XcircuiteGeneratedLayoutSignoffCorpusQualifier()
        let result = try persist
            ? qualifier.qualifyAndPersist(report: report, policy: policy, projectRoot: projectRoot)
            : qualifier.qualify(report: report, policy: policy)
        return try encode(result, pretty: pretty)
    }

    static func attachGeneratedLayoutReadyOracleEvidence(arguments: [String]) throws -> String {
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
        let attacher = XcircuiteGeneratedLayoutReadyOracleEvidenceAttacher()
        let result = try persist
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

    static func auditGeneratedLayoutSignoffCorpusCoverage(arguments: [String]) throws -> String {
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
        let auditor = XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditor()
        let audit = try persist
            ? auditor.auditAndPersist(report: report, policy: policy, projectRoot: projectRoot)
            : auditor.audit(report: report, policy: policy)
        return try encode(audit, pretty: pretty)
    }

    static func assessGeneratedLayoutSignoffPromotion(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var qualificationURL: URL?
        var retainedSignoffReportURL: URL?
        var promotionID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--qualification":
                qualificationURL = URL(filePath: try parser.requiredValue(after: argument))
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
        guard let qualificationURL else {
            throw XcircuiteFlowCLIError.missingOption("--qualification")
        }

        let qualification = try decodeJSONFile(
            XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.self,
            from: qualificationURL,
            option: "--qualification"
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
        let assessor = XcircuiteGeneratedLayoutSignoffPromotionAssessor()
        let assessment = try persist
            ? assessor.assessAndPersist(
                request: request,
                qualification: qualification,
                retainedSignoffReport: retainedReport,
                retainedSignoffReportURL: retainedSignoffReportURL,
                projectRoot: projectRoot
            )
            : assessor.assess(
                request: request,
                qualification: qualification,
                retainedSignoffReport: retainedReport,
                retainedSignoffReportURL: retainedSignoffReportURL
            )
        return try encode(assessment, pretty: pretty)
    }

    static func collectGeneratedLayoutFailureLadder(arguments: [String]) throws -> String {
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
        let collector = XcircuiteGeneratedLayoutFailureLadderCollector()
        let report = try persist
            ? collector.collectAndPersist(request: request, projectRoot: projectRoot)
            : collector.collect(request: request, projectRoot: projectRoot)
        return try encode(report, pretty: pretty)
    }

    static func auditGeneratedLayoutFailureLadderCoverage(arguments: [String]) throws -> String {
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
        let auditor = XcircuiteGeneratedLayoutFailureLadderCoverageAuditor()
        let audit = try persist
            ? auditor.auditAndPersist(reports: reports, policy: policy, projectRoot: projectRoot)
            : auditor.audit(reports: reports, policy: policy)
        return try encode(audit, pretty: pretty)
    }
}
