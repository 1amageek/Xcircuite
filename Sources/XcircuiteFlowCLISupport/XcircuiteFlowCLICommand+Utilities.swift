import DesignFlowKernel
import Foundation
import Xcircuite
import XcircuitePackage

extension XcircuiteFlowCLICommand {
    static func encode<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw XcircuiteFlowCLIError.encodeFailed(error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw XcircuiteFlowCLIError.encodeFailed("JSON output was not valid UTF-8.")
        }
        return text
    }

    static func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            unique.append(value)
        }
        return unique
    }

    static func decodeJSONFile<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        option: String
    ) throws -> T {
        let data = try readInputFileData(from: url, option: option)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw XcircuiteFlowCLIError.readFailed(
                "Invalid JSON for \(option) at \(url.path(percentEncoded: false)): \(decodingErrorDescription(error))"
            )
        } catch {
            throw XcircuiteFlowCLIError.readFailed(
                "Failed to decode JSON for \(option) at \(url.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
    }

    static func readInputFileData(from url: URL, option: String) throws -> Data {
        let path = url.path(percentEncoded: false)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw XcircuiteFlowCLIError.readFailed("Missing file for \(option): \(path)")
        }
        guard !isDirectory.boolValue else {
            throw XcircuiteFlowCLIError.readFailed("Expected file for \(option), got directory: \(path)")
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw XcircuiteFlowCLIError.readFailed(
                "Failed to read file for \(option) at \(path): \(error.localizedDescription)"
            )
        }
    }

    private static func decodingErrorDescription(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            return context.debugDescription
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath))."
        case .typeMismatch(let type, let context):
            return "Expected \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing \(type) at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "$"
        }
        return codingPath.map(\.stringValue).joined(separator: ".")
    }

    static func write<T: Encodable>(_ value: T, to url: URL, pretty: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        do {
            let data = try encoder.encode(value)
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw XcircuiteFlowCLIError.writeFailed(error.localizedDescription)
        }
    }
}
