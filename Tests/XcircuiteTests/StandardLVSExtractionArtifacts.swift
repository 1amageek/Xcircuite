import CryptoKit
import Foundation
import LayoutLVSExtraction

struct StandardLVSExtractionArtifacts: Sendable, Hashable {
    let profilePath: String
    let deckPath: String
    let processProfileID: String
}

func writeStandardLVSExtractionArtifacts(
    to root: URL
) throws -> StandardLVSExtractionArtifacts {
    let technologyDirectory = root.appending(path: "tech")
    try FileManager.default.createDirectory(
        at: technologyDirectory,
        withIntermediateDirectories: true
    )
    let deckData = Data("generated-mos-fixture-deck-v1".utf8)
    let deckURL = technologyDirectory.appending(path: "extraction.deck")
    try deckData.write(to: deckURL, options: [.atomic])
    let digest = SHA256.hash(data: deckData)
        .map { String(format: "%02x", $0) }
        .joined()
    let fixture = GeneratedMOSLayoutExtractionProfileFactory().makeProfile()
    let profile = LayoutExtractionProcessProfile(
        processID: fixture.processID,
        processProfileID: fixture.processProfileID,
        extractionDeckDigest: digest,
        productionEligible: fixture.productionEligible,
        parameterValueConvention: fixture.parameterValueConvention,
        conductorLayers: fixture.conductorLayers,
        connectionRules: fixture.connectionRules,
        mosRules: fixture.mosRules
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let profileURL = technologyDirectory.appending(path: "layout-extraction-profile.json")
    try encoder.encode(profile).write(to: profileURL, options: [.atomic])
    return StandardLVSExtractionArtifacts(
        profilePath: "tech/layout-extraction-profile.json",
        deckPath: "tech/extraction.deck",
        processProfileID: fixture.processProfileID
    )
}
