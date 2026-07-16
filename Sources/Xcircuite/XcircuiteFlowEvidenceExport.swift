import Foundation
import ToolQualification

public struct XcircuiteFlowEvidenceExport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var status: String?
    public var reportPath: String?
    public var reportSHA256: String?
    public var toolEvidence: ToolEvidence

    public init(
        schemaVersion: Int = 1,
        status: String? = nil,
        reportPath: String? = nil,
        reportSHA256: String? = nil,
        toolEvidence: ToolEvidence
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.reportPath = reportPath
        self.reportSHA256 = reportSHA256
        self.toolEvidence = toolEvidence
    }

    public static func load(from url: URL) throws -> XcircuiteFlowEvidenceExport {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(url.path(percentEncoded: false))
        }
        let export = try JSONDecoder().decode(XcircuiteFlowEvidenceExport.self, from: data)
        guard export.schemaVersion == Self.currentSchemaVersion else {
            throw XcircuiteFlowRuntimeSpecError.unsupportedEvidenceExportSchemaVersion(export.schemaVersion)
        }
        try export.validate()
        return export
    }

    public func validate() throws {
        if let status {
            let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["passed", "qualified"].contains(normalizedStatus) else {
                throw XcircuiteFlowRuntimeSpecError.invalidEvidenceExport(
                    field: "status",
                    reason: "status must be passed or qualified before it can be attached as runtime trust evidence"
                )
            }
        }

        if let reportPath {
            guard let artifactPath = toolEvidence.artifact?.path else {
                throw XcircuiteFlowRuntimeSpecError.invalidEvidenceExport(
                    field: "reportPath",
                    reason: "reportPath requires toolEvidence.artifact.path"
                )
            }
            guard artifactPath == reportPath else {
                throw XcircuiteFlowRuntimeSpecError.invalidEvidenceExport(
                    field: "reportPath",
                    reason: "reportPath must match toolEvidence.artifact.path"
                )
            }
        }

        if let reportSHA256 {
            guard let artifactSHA256 = toolEvidence.artifact?.sha256 else {
                throw XcircuiteFlowRuntimeSpecError.invalidEvidenceExport(
                    field: "reportSHA256",
                    reason: "reportSHA256 requires toolEvidence.artifact.sha256"
                )
            }
            guard artifactSHA256.lowercased() == reportSHA256.lowercased() else {
                throw XcircuiteFlowRuntimeSpecError.invalidEvidenceExport(
                    field: "reportSHA256",
                    reason: "reportSHA256 must match toolEvidence.artifact.sha256"
                )
            }
        }
    }
}
