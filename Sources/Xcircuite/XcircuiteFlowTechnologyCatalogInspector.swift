import Foundation
import DesignFlowKernel

public struct XcircuiteFlowTechnologyCatalogInspector: XcircuiteFlowTechnologyCatalogInspecting {
    private struct PDKRootInspection: Sendable, Hashable {
        var inventory: XcircuiteFlowTechnologyCatalogPDKRootInventory
        var url: URL?
    }

    private struct ResolvedRequiredFilePath: Sendable, Hashable {
        var url: URL
        var source: String
    }

    public init() {}

    public func inspect(
        request: XcircuiteFlowTechnologyCatalogInventoryRequest
    ) -> XcircuiteFlowTechnologyCatalogInventory {
        let pdkRootInspections = stableUnique(request.pdkRootPaths).map {
            inspectPDKRoot(
                path: $0,
                projectRoot: request.projectRoot,
                maximumDepth: max(0, request.maximumCatalogDiscoveryDepth)
            )
        }
        let pdkRoots = pdkRootInspections.map(\.inventory)
        let pdkRootURLs = pdkRootInspections.compactMap(\.url)
        let discoveredCatalogPaths = pdkRoots.flatMap(\.discoveredCatalogPaths)
        let catalogPaths = stableUnique(request.catalogPaths + discoveredCatalogPaths)
        let catalogs = catalogPaths.map {
            inspectCatalog(path: $0, projectRoot: request.projectRoot, pdkRootURLs: pdkRootURLs)
        }
        var inventoryIssues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
        if catalogPaths.isEmpty {
            inventoryIssues.append(
                issue(
                    code: "no-technology-catalogs-found",
                    field: "catalogPaths",
                    message: "At least one explicit or PDK-root-discovered technology catalog is required."
                )
            )
        }
        let entryCount = catalogs.reduce(0) { $0 + $1.entries.count }
        let failedPDKRootCount = pdkRoots.filter { $0.status == .failed }.count
        let failedCatalogCount = catalogs.filter { $0.status == .failed }.count
        let failedEntryCount = catalogs.reduce(0) { count, catalog in
            count + catalog.entries.filter { $0.status == .failed }.count
        }
        let missingRequiredFileCount = catalogs.reduce(0) { count, catalog in
            count + catalog.entries.reduce(0) { entryCount, entry in
                entryCount + entry.requiredFiles.filter { !$0.exists || $0.isDirectory }.count
            }
        }
        return XcircuiteFlowTechnologyCatalogInventory(
            projectRootPath: request.projectRoot?.path(percentEncoded: false),
            pdkRoots: pdkRoots,
            discoveredCatalogCount: discoveredCatalogPaths.count,
            catalogCount: catalogs.count,
            entryCount: entryCount,
            failedPDKRootCount: failedPDKRootCount,
            failedCatalogCount: failedCatalogCount,
            failedEntryCount: failedEntryCount,
            missingRequiredFileCount: missingRequiredFileCount,
            catalogs: catalogs,
            status: inventoryIssues.isEmpty && failedPDKRootCount == 0 && failedCatalogCount == 0 && failedEntryCount == 0 ? .passed : .failed,
            issues: inventoryIssues
        )
    }

    private func inspectPDKRoot(
        path: String,
        projectRoot: URL?,
        maximumDepth: Int
    ) -> PDKRootInspection {
        var issues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
        let rootURL = resolveSafePath(
            path,
            field: "pdkRoot",
            projectRoot: projectRoot,
            missingProjectRootCode: "missing-project-root",
            invalidPathCode: "invalid-pdk-root-path",
            into: &issues
        )
        guard let rootURL else {
            return PDKRootInspection(
                inventory: XcircuiteFlowTechnologyCatalogPDKRootInventory(
                    requestedPath: path,
                    status: .failed,
                    issues: issues
                ),
                url: nil
            )
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: rootURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        guard exists, isDirectory.boolValue else {
            issues.append(
                issue(
                    code: exists ? "pdk-root-is-not-directory" : "missing-pdk-root",
                    field: "pdkRoot",
                    message: "PDK root must point to an existing directory."
                )
            )
            return PDKRootInspection(
                inventory: XcircuiteFlowTechnologyCatalogPDKRootInventory(
                    requestedPath: path,
                    resolvedPath: rootURL.path(percentEncoded: false),
                    status: .failed,
                    issues: issues
                ),
                url: nil
            )
        }

        let discoveredCatalogPaths = discoverTechnologyCatalogs(
            in: rootURL,
            maximumDepth: maximumDepth,
            issues: &issues
        )
        return PDKRootInspection(
            inventory: XcircuiteFlowTechnologyCatalogPDKRootInventory(
                requestedPath: path,
                resolvedPath: rootURL.path(percentEncoded: false),
                discoveredCatalogPaths: discoveredCatalogPaths,
                status: issues.isEmpty ? .passed : .failed,
                issues: issues
            ),
            url: rootURL
        )
    }

    private func inspectCatalog(
        path: String,
        projectRoot: URL?,
        pdkRootURLs: [URL]
    ) -> XcircuiteFlowTechnologyCatalogInventoryItem {
        var catalogIssues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
        let catalogURL = resolveCatalogPath(path, projectRoot: projectRoot, into: &catalogIssues)
        guard let catalogURL else {
            return XcircuiteFlowTechnologyCatalogInventoryItem(
                catalogPath: path,
                status: .failed,
                issues: catalogIssues
            )
        }

        let catalog: XcircuiteFlowTechnologyCatalog
        do {
            let data = try Data(contentsOf: catalogURL)
            catalog = try JSONDecoder().decode(XcircuiteFlowTechnologyCatalog.self, from: data)
        } catch {
            catalogIssues.append(
                issue(
                    code: "catalog-unreadable",
                    field: "catalogPath",
                    message: "Catalog path must point to a readable technology catalog JSON file."
                )
            )
            return XcircuiteFlowTechnologyCatalogInventoryItem(
                catalogPath: path,
                resolvedCatalogPath: catalogURL.path(percentEncoded: false),
                status: .failed,
                issues: catalogIssues
            )
        }

        if catalog.schemaVersion != 1 {
            catalogIssues.append(
                issue(
                    code: "unsupported-schema-version",
                    field: "schemaVersion",
                    message: "Technology catalog schemaVersion must be 1."
                )
            )
        }

        let duplicateKeys = duplicateEntryKeys(in: catalog.entries)
        for duplicateKey in duplicateKeys {
            catalogIssues.append(
                issue(
                    code: "duplicate-entry",
                    field: "entries",
                    message: "Technology catalog contains duplicate entry \(duplicateKey)."
                )
            )
        }

        let entries = catalog.entries.map {
            inspectEntry($0, catalogURL: catalogURL, pdkRootURLs: pdkRootURLs, duplicateKeys: duplicateKeys)
        }
        let failedEntries = entries.contains { $0.status == .failed }
        return XcircuiteFlowTechnologyCatalogInventoryItem(
            catalogPath: path,
            resolvedCatalogPath: catalogURL.path(percentEncoded: false),
            schemaVersion: catalog.schemaVersion,
            entries: entries,
            status: catalogIssues.isEmpty && !failedEntries ? .passed : .failed,
            issues: catalogIssues
        )
    }

    private func inspectEntry(
        _ entry: XcircuiteFlowTechnologyCatalogEntry,
        catalogURL: URL,
        pdkRootURLs: [URL],
        duplicateKeys: Set<String>
    ) -> XcircuiteFlowTechnologyCatalogEntryInventory {
        var entryIssues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
        validateIdentifier(entry.technologyCatalogID, field: "technologyCatalogID", into: &entryIssues)
        validateIdentifier(entry.pdkID, field: "pdkID", into: &entryIssues)
        for profileID in entry.profileIDs ?? [] {
            validateIdentifier(profileID, field: "profileIDs", into: &entryIssues)
        }
        if duplicateKeys.contains(entryKey(entry)) {
            entryIssues.append(
                issue(
                    code: "duplicate-entry",
                    field: "technologyCatalogID",
                    message: "Entry duplicates another technologyCatalogID and pdkID pair."
                )
            )
        }

        let requiredFiles = (entry.requiredFiles ?? []).map {
            inspectRequiredFile($0, catalogURL: catalogURL, pdkRootURLs: pdkRootURLs)
        }
        let requiredFileFailed = requiredFiles.contains { $0.status == .failed }
        return XcircuiteFlowTechnologyCatalogEntryInventory(
            technologyCatalogID: entry.technologyCatalogID,
            pdkID: entry.pdkID,
            profileIDs: entry.profileIDs ?? [],
            requiredFiles: requiredFiles,
            metadata: entry.metadata,
            status: entryIssues.isEmpty && !requiredFileFailed ? .passed : .failed,
            issues: entryIssues
        )
    }

    private func inspectRequiredFile(
        _ requiredFile: XcircuiteFlowTechnologyCatalogRequiredFile,
        catalogURL: URL,
        pdkRootURLs: [URL]
    ) -> XcircuiteFlowTechnologyCatalogRequiredFileInventory {
        var issues: [XcircuiteFlowTechnologyCatalogInventoryIssue] = []
        validateIdentifier(requiredFile.purpose, field: "purpose", into: &issues)
        let resolvedFile = resolveRequiredFilePath(
            requiredFile.path,
            catalogURL: catalogURL,
            pdkRootURLs: pdkRootURLs,
            into: &issues
        )
        guard let resolvedFile else {
            return XcircuiteFlowTechnologyCatalogRequiredFileInventory(
                purpose: requiredFile.purpose,
                path: requiredFile.path,
                exists: false,
                isDirectory: false,
                status: .failed,
                issues: issues
            )
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: resolvedFile.url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        if !exists {
            issues.append(
                issue(
                    code: "missing-required-file",
                    field: "path",
                    message: "Technology catalog required file is missing."
                )
            )
        }
        if exists, isDirectory.boolValue {
            issues.append(
                issue(
                    code: "required-file-is-directory",
                    field: "path",
                    message: "Technology catalog required file points to a directory."
                )
            )
        }
        return XcircuiteFlowTechnologyCatalogRequiredFileInventory(
            purpose: requiredFile.purpose,
            path: requiredFile.path,
            resolvedPath: resolvedFile.url.path(percentEncoded: false),
            resolutionSource: resolvedFile.source,
            exists: exists,
            isDirectory: isDirectory.boolValue,
            status: issues.isEmpty ? .passed : .failed,
            issues: issues
        )
    }

    private func resolveCatalogPath(
        _ path: String,
        projectRoot: URL?,
        into issues: inout [XcircuiteFlowTechnologyCatalogInventoryIssue]
    ) -> URL? {
        resolveSafePath(
            path,
            field: "catalogPath",
            projectRoot: projectRoot,
            missingProjectRootCode: "missing-project-root",
            invalidPathCode: "invalid-catalog-path",
            into: &issues
        )
    }

    private func resolveRequiredFilePath(
        _ path: String,
        catalogURL: URL,
        pdkRootURLs: [URL],
        into issues: inout [XcircuiteFlowTechnologyCatalogInventoryIssue]
    ) -> ResolvedRequiredFilePath? {
        guard !path.isEmpty, !path.hasPrefix("~"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            issues.append(
                issue(
                    code: "invalid-required-file-path",
                    field: "path",
                    message: "Required file path must not be empty and must not use home or parent traversal."
                )
            )
            return nil
        }
        if path.hasPrefix("/") {
            return ResolvedRequiredFilePath(url: URL(filePath: path), source: "absolute")
        }
        let catalogCandidate = catalogURL.deletingLastPathComponent().appending(path: path)
        if fileExists(at: catalogCandidate) {
            return ResolvedRequiredFilePath(url: catalogCandidate, source: "catalog-directory")
        }
        for pdkRootURL in pdkRootURLs {
            let candidate = pdkRootURL.appending(path: path)
            if fileExists(at: candidate) {
                return ResolvedRequiredFilePath(url: candidate, source: "pdk-root")
            }
        }
        return ResolvedRequiredFilePath(url: catalogCandidate, source: "catalog-directory")
    }

    private func resolveSafePath(
        _ path: String,
        field: String,
        projectRoot: URL?,
        missingProjectRootCode: String,
        invalidPathCode: String,
        into issues: inout [XcircuiteFlowTechnologyCatalogInventoryIssue]
    ) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("~"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            issues.append(
                issue(
                    code: invalidPathCode,
                    field: field,
                    message: "\(field) must not be empty and must not use home or parent traversal."
                )
            )
            return nil
        }
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        guard let projectRoot else {
            issues.append(
                issue(
                    code: missingProjectRootCode,
                    field: "projectRoot",
                    message: "Relative \(field) paths require projectRoot."
                )
            )
            return nil
        }
        return projectRoot.appending(path: path)
    }

    private func discoverTechnologyCatalogs(
        in rootURL: URL,
        maximumDepth: Int,
        issues: inout [XcircuiteFlowTechnologyCatalogInventoryIssue]
    ) -> [String] {
        var discovered: [String] = []
        discoverTechnologyCatalogs(
            in: rootURL,
            depth: 0,
            maximumDepth: maximumDepth,
            discovered: &discovered,
            issues: &issues
        )
        return stableUnique(discovered).sorted()
    }

    private func discoverTechnologyCatalogs(
        in directoryURL: URL,
        depth: Int,
        maximumDepth: Int,
        discovered: inout [String],
        issues: inout [XcircuiteFlowTechnologyCatalogInventoryIssue]
    ) {
        guard depth <= maximumDepth else {
            return
        }
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            issues.append(
                issue(
                    code: "pdk-root-unreadable",
                    field: "pdkRoot",
                    message: "PDK root discovery could not read a directory."
                )
            )
            return
        }

        for url in contents {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            } catch {
                issues.append(
                    issue(
                        code: "pdk-root-entry-unreadable",
                        field: "pdkRoot",
                        message: "PDK root discovery could not inspect a directory entry."
                    )
                )
                continue
            }
            if values.isSymbolicLink == true {
                continue
            }
            if values.isDirectory == true {
                discoverTechnologyCatalogs(
                    in: url,
                    depth: depth + 1,
                    maximumDepth: maximumDepth,
                    discovered: &discovered,
                    issues: &issues
                )
            } else if isTechnologyCatalogCandidate(url) {
                discovered.append(url.path(percentEncoded: false))
            }
        }
    }

    private func isTechnologyCatalogCandidate(_ url: URL) -> Bool {
        let supportedNames: Set<String> = ["catalog.json", "technology-catalog.json"]
        guard supportedNames.contains(url.lastPathComponent) else {
            return false
        }
        do {
            let data = try Data(contentsOf: url)
            _ = try JSONDecoder().decode(XcircuiteFlowTechnologyCatalog.self, from: data)
            return true
        } catch {
            return false
        }
    }

    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            unique.append(value)
        }
        return unique
    }

    private func validateIdentifier(
        _ value: String,
        field: String,
        into issues: inout [XcircuiteFlowTechnologyCatalogInventoryIssue]
    ) {
        do {
            try FlowIdentifierValidator().validate(value, kind: .artifactID)
        } catch {
            issues.append(
                issue(
                    code: "invalid-identifier",
                    field: field,
                    message: "\(field) must be a stable machine-readable identifier."
                )
            )
        }
    }

    private func duplicateEntryKeys(in entries: [XcircuiteFlowTechnologyCatalogEntry]) -> Set<String> {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for entry in entries {
            let key = entryKey(entry)
            if seen.contains(key) {
                duplicates.insert(key)
            } else {
                seen.insert(key)
            }
        }
        return duplicates
    }

    private func entryKey(_ entry: XcircuiteFlowTechnologyCatalogEntry) -> String {
        "\(entry.technologyCatalogID)::\(entry.pdkID)"
    }

    private func issue(
        code: String,
        field: String,
        message: String
    ) -> XcircuiteFlowTechnologyCatalogInventoryIssue {
        XcircuiteFlowTechnologyCatalogInventoryIssue(
            code: code,
            field: field,
            message: message
        )
    }
}
