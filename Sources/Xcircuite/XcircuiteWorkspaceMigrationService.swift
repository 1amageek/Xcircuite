import Foundation
import CircuiteFoundation

/// Performs the one-time JSON shape migration required by Foundation schema v2.
/// Existing artifact locators receive the legacy role sentinel; no domain
/// verdict or run lifecycle field is inferred by this service.
public actor XcircuiteWorkspaceMigrationService {
    private let workspaceRoot: URL
    private let fileManager = FileManager.default

    public init(projectRoot: URL) throws {
        _ = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        self.workspaceRoot = projectRoot.standardizedFileURL
            .appending(path: ".xcircuite", directoryHint: .isDirectory)
    }

    public func migrateIfNeeded() throws -> XcircuiteMigrationReport {
        var migrated: [String] = []
        var skipped: [String] = []
        guard fileManager.fileExists(atPath: workspaceRoot.path(percentEncoded: false)) else {
            return XcircuiteMigrationReport(migratedFiles: [], skippedFiles: [])
        }
        guard let enumerator = fileManager.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw XcircuiteMigrationError.workspaceReadFailed(workspaceRoot.path)
        }

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "json" else { continue }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw XcircuiteMigrationError.workspaceReadFailed(
                    "\(url.path): \(error.localizedDescription)"
                )
            }
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                skipped.append(relativePath(for: url))
                continue
            }
            let changed = migrateObject(&object)
            guard changed else {
                skipped.append(relativePath(for: url))
                continue
            }
            let migratedData: Data
            do {
                migratedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                try migratedData.write(to: url, options: [.atomic])
            } catch {
                throw XcircuiteMigrationError.workspaceWriteFailed(
                    "\(url.path): \(error.localizedDescription)"
                )
            }
            migrated.append(relativePath(for: url))
        }
        return XcircuiteMigrationReport(migratedFiles: migrated, skippedFiles: skipped)
    }

    private func migrateObject(_ object: inout [String: Any]) -> Bool {
        var changed = migrateNestedValues(&object)
        if let schema = object["schemaVersion"] as? [String: Any],
           let major = schema["major"] as? Int,
           major == 1,
           object["artifacts"] != nil {
            object["schemaVersion"] = ["major": 2, "minor": 0, "patch": 0]
            changed = true
        }
        return changed
    }

    private func migrateNestedValues(_ object: inout [String: Any]) -> Bool {
        var changed = false
        if object["location"] != nil,
           object["kind"] != nil,
           object["format"] != nil,
           object["role"] == nil {
            object["role"] = ArtifactRole.legacyUnspecified.rawValue
            changed = true
        }
        for key in object.keys {
            if var nested = object[key] as? [String: Any], migrateNestedValues(&nested) {
                object[key] = nested
                changed = true
            } else if var values = object[key] as? [[String: Any]] {
                var nestedChanged = false
                for index in values.indices where migrateNestedValues(&values[index]) {
                    nestedChanged = true
                }
                if nestedChanged {
                    object[key] = values
                    changed = true
                }
            }
        }
        return changed
    }

    private func relativePath(for url: URL) -> String {
        let root = workspaceRoot.path(percentEncoded: false)
        let path = url.path(percentEncoded: false)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
