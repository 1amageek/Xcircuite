import CircuiteFoundation
import Foundation

enum XcircuiteRunLedgerTamperError: Error {
    case invalidLedgerObject
    case invalidRunManifestObject
    case invalidArtifactObject
}

enum XcircuiteRunLedgerTamper {
    static func append(
        _ references: [ArtifactReference],
        to ledgerURL: URL
    ) throws {
        let ledgerData = try Data(contentsOf: ledgerURL)
        guard var ledger = try JSONSerialization.jsonObject(with: ledgerData) as? [String: Any] else {
            throw XcircuiteRunLedgerTamperError.invalidLedgerObject
        }
        guard var runManifest = ledger["runManifest"] as? [String: Any] else {
            throw XcircuiteRunLedgerTamperError.invalidRunManifestObject
        }

        let encodedReferences = try references.map { reference -> [String: Any] in
            let data = try JSONEncoder().encode(reference)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw XcircuiteRunLedgerTamperError.invalidArtifactObject
            }
            return object
        }

        var ledgerArtifacts = ledger["artifacts"] as? [[String: Any]] ?? []
        ledgerArtifacts.append(contentsOf: encodedReferences)
        ledger["artifacts"] = ledgerArtifacts

        var manifestArtifacts = runManifest["artifacts"] as? [[String: Any]] ?? []
        manifestArtifacts.append(contentsOf: encodedReferences)
        runManifest["artifacts"] = manifestArtifacts
        ledger["runManifest"] = runManifest

        let updatedData = try JSONSerialization.data(
            withJSONObject: ledger,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedData.write(to: ledgerURL, options: .atomic)
    }
}
