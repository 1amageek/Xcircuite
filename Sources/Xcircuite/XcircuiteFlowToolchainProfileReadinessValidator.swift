import Foundation
import XcircuitePackage

public struct XcircuiteFlowToolchainProfileReadinessValidator: Sendable {
    public init() {}

    public func report(
        for profile: XcircuiteFlowToolchainProfile,
        projectRoot: URL? = nil
    ) -> XcircuiteFlowToolchainProfileReadinessReport {
        let issues = readinessIssues(for: profile, projectRoot: projectRoot)
        return XcircuiteFlowToolchainProfileReadinessReport(
            profileID: profile.profileID,
            pdkID: profile.pdkID,
            technologyCatalogID: profile.technologyCatalogID,
            technologyCatalogPath: profile.technologyCatalogPath,
            status: issues.isEmpty ? .passed : .failed,
            issues: issues
        )
    }

    public func validate(
        _ profile: XcircuiteFlowToolchainProfile,
        projectRoot: URL? = nil
    ) throws {
        guard let issue = readinessIssues(for: profile, projectRoot: projectRoot).first else {
            return
        }
        switch issue.code {
        case Self.missingFieldCode:
            throw XcircuiteFlowRuntimeSpecError.missingToolchainProfileField(issue.field)
        default:
            throw XcircuiteFlowRuntimeSpecError.invalidToolchainProfileField(issue.field)
        }
    }

    private static let missingFieldCode = "missing-field"
    private static let invalidFieldCode = "invalid-field"
    private static let missingCatalogEntryCode = "missing-catalog-entry"
    private static let missingCatalogFileCode = "missing-catalog-file"

    private func readinessIssues(
        for profile: XcircuiteFlowToolchainProfile,
        projectRoot: URL?
    ) -> [XcircuiteFlowToolchainProfileReadinessIssue] {
        var issues: [XcircuiteFlowToolchainProfileReadinessIssue] = []
        validateRequiredIdentifier(profile.profileID, field: "profileID", into: &issues)
        validateRequiredIdentifier(profile.pdkID, field: "pdkID", into: &issues)
        validateRequiredIdentifier(profile.technologyCatalogID, field: "technologyCatalogID", into: &issues)
        if let technologyCatalogPath = profile.technologyCatalogPath {
            validateTechnologyCatalogPath(
                technologyCatalogPath,
                profile: profile,
                projectRoot: projectRoot,
                into: &issues
            )
        }
        if let input = profile.drcTechnologyInput {
            validate(input, field: "drcTechnologyInput", into: &issues)
        }
        if let input = profile.lvsTechnologyInput {
            validate(input, field: "lvsTechnologyInput", into: &issues)
        }
        if let technology = profile.pexTechnology {
            validate(technology, field: "pexTechnology", into: &issues)
        }
        return issues
    }

    private func validateTechnologyCatalogPath(
        _ catalogPath: String,
        profile: XcircuiteFlowToolchainProfile,
        projectRoot: URL?,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        let initialIssueCount = issues.count
        validateRuntimePath(catalogPath, field: "technologyCatalogPath", into: &issues)
        guard issues.count == initialIssueCount else {
            return
        }
        guard let projectRoot else {
            return
        }
        guard profile.pdkID != nil, profile.technologyCatalogID != nil else {
            return
        }

        let catalogURL: URL
        do {
            catalogURL = try XcircuiteFlowRuntimeSpec.resolvePath(catalogPath, projectRoot: projectRoot)
        } catch {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.invalidFieldCode,
                    field: "technologyCatalogPath",
                    message: "technologyCatalogPath could not be resolved from projectRoot."
                )
            )
            return
        }

        let catalog: XcircuiteFlowTechnologyCatalog
        do {
            let data = try Data(contentsOf: catalogURL)
            catalog = try JSONDecoder().decode(XcircuiteFlowTechnologyCatalog.self, from: data)
        } catch {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.invalidFieldCode,
                    field: "technologyCatalogPath",
                    message: "technologyCatalogPath must point to a readable technology catalog JSON file."
                )
            )
            return
        }

        guard catalog.schemaVersion == 1 else {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.invalidFieldCode,
                    field: "technologyCatalogPath",
                    message: "Technology catalog schemaVersion must be 1."
                )
            )
            return
        }

        guard let technologyCatalogID = profile.technologyCatalogID,
              let pdkID = profile.pdkID else {
            return
        }

        guard let entry = catalog.entries.first(where: {
            $0.technologyCatalogID == technologyCatalogID && $0.pdkID == pdkID
        }) else {
            let catalogIDExists = catalog.entries.contains { $0.technologyCatalogID == technologyCatalogID }
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.missingCatalogEntryCode,
                    field: catalogIDExists ? "pdkID" : "technologyCatalogID",
                    message: "technologyCatalogPath must contain an entry matching technologyCatalogID and pdkID."
                )
            )
            return
        }

        if let profileID = profile.profileID,
           let profileIDs = entry.profileIDs,
           !profileIDs.isEmpty,
           !profileIDs.contains(profileID) {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.missingCatalogEntryCode,
                    field: "profileID",
                    message: "Technology catalog entry does not allow this profileID."
                )
            )
        }

        for requiredFile in entry.requiredFiles ?? [] {
            validateCatalogRequiredFile(
                requiredFile,
                catalogURL: catalogURL,
                into: &issues
            )
        }
    }

    private func validateCatalogRequiredFile(
        _ requiredFile: XcircuiteFlowTechnologyCatalogRequiredFile,
        catalogURL: URL,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        let fieldBase: String
        if requiredFile.purpose.isEmpty {
            fieldBase = "technologyCatalog.requiredFiles"
        } else {
            fieldBase = "technologyCatalog.requiredFiles.\(requiredFile.purpose)"
        }

        validateIdentifier(
            requiredFile.purpose,
            kind: .artifactID,
            field: "\(fieldBase).purpose",
            into: &issues
        )

        let initialIssueCount = issues.count
        validateRuntimePath(requiredFile.path, field: "\(fieldBase).path", into: &issues)
        guard issues.count == initialIssueCount else {
            return
        }

        let fileURL = resolveCatalogRequiredFile(requiredFile.path, catalogURL: catalogURL)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: fileURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        guard exists, !isDirectory.boolValue else {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.missingCatalogFileCode,
                    field: fieldBase,
                    message: "Technology catalog required file is missing."
                )
            )
            return
        }
    }

    private func resolveCatalogRequiredFile(_ path: String, catalogURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        return catalogURL.deletingLastPathComponent().appending(path: path)
    }

    private func validateRequiredIdentifier(
        _ value: String?,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        guard let value, !value.isEmpty else {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.missingFieldCode,
                    field: field,
                    message: "\(field) is required when a toolchain profile is present."
                )
            )
            return
        }
        do {
            try XcircuiteIdentifierValidator().validate(value, kind: .artifactID)
        } catch {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.invalidFieldCode,
                    field: field,
                    message: "\(field) must be a stable machine-readable identifier."
                )
            )
        }
    }

    private func validate(
        _ reference: XcircuiteFlowInputReference,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        switch reference {
        case .path(let path):
            validateRuntimePath(path, field: field, into: &issues)
        case .stageArtifact(let artifact):
            validateStageArtifact(artifact, field: field, into: &issues)
        case .stageRawArtifact(let artifact):
            validateStageRawArtifact(artifact, field: field, into: &issues)
        }
    }

    private func validate(
        _ technology: XcircuitePEXTechnologySpec,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        switch technology {
        case .jsonFile(let path):
            validateRuntimePath(path, field: "\(field).path", into: &issues)
        case .input(let reference):
            validate(reference, field: "\(field).input", into: &issues)
        case .inline(let technology):
            guard !technology.processName.isEmpty else {
                issues.append(
                    XcircuiteFlowToolchainProfileReadinessIssue(
                        code: Self.invalidFieldCode,
                        field: "\(field).inline.processName",
                        message: "Inline PEX technology must include processName."
                    )
                )
                return
            }
        }
    }

    private func validateStageArtifact(
        _ artifact: XcircuiteFlowInputReference.StageArtifact,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        validateIdentifier(artifact.stageID, kind: .stageID, field: "\(field).stageID", into: &issues)
        if let artifactID = artifact.artifactID {
            validateIdentifier(artifactID, kind: .artifactID, field: "\(field).artifactID", into: &issues)
        }
        if let pathSuffix = artifact.pathSuffix {
            validateRelativePath(pathSuffix, field: "\(field).pathSuffix", into: &issues)
        }
    }

    private func validateStageRawArtifact(
        _ artifact: XcircuiteFlowInputReference.StageRawArtifact,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        validateIdentifier(artifact.stageID, kind: .stageID, field: "\(field).stageID", into: &issues)
        validateRelativePath(artifact.relativePath, field: "\(field).relativePath", into: &issues)
    }

    private func validateIdentifier(
        _ value: String,
        kind: XcircuiteIdentifierKind,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        do {
            try XcircuiteIdentifierValidator().validate(value, kind: kind)
        } catch {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.invalidFieldCode,
                    field: field,
                    message: "\(field) must be a valid \(kind.rawValue)."
                )
            )
        }
    }

    private func validateRuntimePath(
        _ path: String,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        guard !path.isEmpty, !path.hasPrefix("~"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.invalidFieldCode,
                    field: field,
                    message: "\(field) must be an explicit runtime path without home or parent traversal."
                )
            )
            return
        }
    }

    private func validateRelativePath(
        _ path: String,
        field: String,
        into issues: inout [XcircuiteFlowToolchainProfileReadinessIssue]
    ) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !components.contains(where: { $0.isEmpty || $0 == ".." }) else {
            issues.append(
                XcircuiteFlowToolchainProfileReadinessIssue(
                    code: Self.invalidFieldCode,
                    field: field,
                    message: "\(field) must be a safe relative artifact path."
                )
            )
            return
        }
    }
}
