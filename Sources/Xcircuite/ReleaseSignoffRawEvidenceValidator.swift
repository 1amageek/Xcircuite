import CircuiteFoundation
import DesignFlowKernel
import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import TimingCore
import ToolQualification

struct ReleaseSignoffRawEvidenceValidator: Sendable {
    func validateTiming(
        provenance: ExecutionProvenance,
        resultArtifacts: [ArtifactReference],
        qualificationScope: ToolQualificationScope,
        rawEvidence: [ArtifactReference],
        reading artifacts: any FlowArtifactPersisting
    ) async throws {
        try requireQualifiedProducer(
            provenance.producer,
            qualificationScope: qualificationScope
        )
        guard provenance.invocation != nil,
              provenance.environment != nil,
              !resultArtifacts.isEmpty,
              Set(resultArtifacts).count == resultArtifacts.count,
              Set(resultArtifacts) == Set(rawEvidence) else {
            throw violation("timing raw evidence must exactly match the canonical result artifacts")
        }
        try validateProducerBoundArtifacts(rawEvidence, producer: provenance.producer)
        for artifact in rawEvidence {
            _ = try await artifacts.loadArtifactContent(for: artifact)
        }
    }

    func validatePEX(
        _ result: PEXRunResult,
        qualificationScope: ToolQualificationScope,
        manifestArtifact: ArtifactReference?,
        rawEvidence: [ArtifactReference],
        reading artifacts: any FlowArtifactPersisting
    ) async throws {
        let producer = result.provenance.producer
        try requireQualifiedProducer(producer, qualificationScope: qualificationScope)
        guard result.status == .success,
              result.artifactManifest.version == PEXArtifactManifest.currentVersion,
              result.artifactManifest.status == .success,
              result.artifactManifest.provenance == result.provenance,
              result.artifactManifest.runID == result.runID,
              result.artifactManifest.requestHash == result.requestHash,
              let manifestArtifact,
              rawEvidence.contains(manifestArtifact) else {
            throw violation("PEX raw evidence requires a successful canonical manifest")
        }
        let retainedManifest = try await retainedArtifact(
            manifestArtifact,
            matching: result.manifestURL,
            producer: producer,
            reading: artifacts
        )
        let decodedManifest = try decode(PEXArtifactManifest.self, from: retainedManifest.data)
        guard decodedManifest == result.artifactManifest else {
            throw violation("retained PEX manifest does not equal the canonical result manifest")
        }
        let expectedArtifacts = Set(result.artifacts + [manifestArtifact])
        guard Set(rawEvidence) == expectedArtifacts else {
            throw violation("PEX raw evidence does not exactly cover the canonical manifest artifacts")
        }
        try validateProducerBoundArtifacts(rawEvidence, producer: producer)
        for artifact in rawEvidence {
            _ = try await artifacts.loadArtifactContent(for: artifact)
        }
    }

    func validateDRC(
        _ execution: DRCExecutionResult,
        qualificationScope: ToolQualificationScope,
        manifestArtifact: ArtifactReference?,
        reportArtifact: ArtifactReference?,
        rawEvidence: [ArtifactReference],
        reading artifacts: any FlowArtifactPersisting
    ) async throws {
        let producer = execution.provenance.producer
        try validateProducerBoundArtifacts(rawEvidence, producer: producer)
        guard let manifestURL = execution.artifactManifestURL,
              let reportURL = execution.reportURL,
              let manifestArtifact,
              let reportArtifact,
              rawEvidence.contains(manifestArtifact),
              rawEvidence.contains(reportArtifact) else {
            throw violation("DRC release evidence requires raw report and manifest URLs")
        }
        let retainedManifest = try await retainedArtifact(
            manifestArtifact,
            matching: manifestURL,
            producer: producer,
            reading: artifacts
        )
        let manifest = try decode(DRCArtifactManifest.self, from: retainedManifest.data)
        guard manifest.schemaVersion == DRCArtifactManifest.currentSchemaVersion,
              manifest.producer == producer,
              manifest.backendID == execution.result.backendID,
              manifest.backendIdentity == execution.result.backendIdentity,
              manifest.toolName == execution.result.toolName,
              manifest.completed == execution.result.completed,
              manifest.passed == execution.result.passed,
              manifest.verdict == execution.result.verdict,
              manifest.completed,
              manifest.passed,
              manifest.verdict == .passed,
              manifest.runID == execution.artifactRunID,
              manifest.runID != nil,
              manifest.requestSHA256 != nil,
              manifest.requestEnvironmentSHA256 != nil,
              manifest.artifactRootSHA256 != nil else {
            throw violation("DRC manifest identity, commitments, or release verdict do not match the canonical result")
        }
        try requireQualifiedProducer(producer, qualificationScope: qualificationScope)
        try validateManifestRecord(
            id: "manifest",
            path: manifestURL,
            records: manifest.outputs,
            manifestReference: retainedManifest.reference
        )
        try await validateOutputCoverage(
            manifest.outputs,
            required: [("report", .report)],
            reportURL: reportURL,
            reportArtifact: reportArtifact,
            artifacts: rawEvidence,
            producer: producer,
            reading: artifacts
        )
        try validateDRCInputCoverage(
            manifest.inputs,
            provenanceInputs: execution.provenance.inputs
        )

        let onDiskData = try readOnDiskArtifact(manifestURL)
        guard onDiskData == retainedManifest.data else {
            throw violation("retained DRC manifest differs from the engine manifest on disk")
        }
        let issues = try DRCArtifactManifestVerifier().verify(
            manifestURL: manifestURL,
            requireSignature: execution.request.options.requireSignedArtifacts,
            trustedPublicKey: execution.request.options.trustedArtifactPublicKey
        )
        guard issues.isEmpty else {
            throw violation(
                "DRC manifest integrity verification failed: "
                    + issues.map(\.code).sorted().joined(separator: ", ")
            )
        }
    }

    func validateLVS(
        _ execution: LVSExecutionResult,
        qualificationScope: ToolQualificationScope,
        manifestArtifact: ArtifactReference?,
        reportArtifact: ArtifactReference?,
        rawEvidence: [ArtifactReference],
        reading artifacts: any FlowArtifactPersisting
    ) async throws {
        let producer = execution.provenance.producer
        try validateProducerBoundArtifacts(rawEvidence, producer: producer)
        guard let manifestURL = execution.artifactManifestURL,
              let reportURL = execution.reportURL,
              let manifestArtifact,
              let reportArtifact,
              rawEvidence.contains(manifestArtifact),
              rawEvidence.contains(reportArtifact) else {
            throw violation("LVS release evidence requires raw report and manifest URLs")
        }
        let retainedManifest = try await retainedArtifact(
            manifestArtifact,
            matching: manifestURL,
            producer: producer,
            reading: artifacts
        )
        let manifest = try decode(LVSArtifactManifest.self, from: retainedManifest.data)
        let normalizedDigest = try LVSNormalizedResultDigester().digest(execution)
        guard manifest.schemaVersion == LVSArtifactManifest.currentSchemaVersion,
              manifest.producer == producer,
              manifest.backendID == execution.result.backendID,
              manifest.toolName == execution.result.toolName,
              manifest.executionStatus == execution.result.executionStatus,
              manifest.verdict == execution.result.verdict,
              manifest.readiness == execution.result.readiness,
              manifest.blockingReasons == execution.result.blockingReasons,
              manifest.executionStatus == .completed,
              manifest.verdict == .match,
              manifest.readiness == .ready,
              manifest.blockingReasons.isEmpty,
              manifest.normalizedResultDigest?.caseInsensitiveCompare(normalizedDigest) == .orderedSame else {
            throw violation("LVS manifest identity, normalized result, or release verdict do not match the canonical result")
        }
        try requireQualifiedProducer(producer, qualificationScope: qualificationScope)
        try validateLVSImplementationIdentity(
            manifest.implementationIdentity,
            request: execution.request,
            producer: producer,
            qualificationScope: qualificationScope
        )
        guard manifest.outputs.allSatisfy({
            $0.sourceReference == nil && $0.derivedReference == nil
        }) else {
            throw violation("LVS output manifest records must not claim input or derived artifact identities")
        }
        try validateManifestRecord(
            id: "manifest",
            path: manifestURL,
            records: manifest.outputs,
            manifestReference: retainedManifest.reference
        )
        try await validateOutputCoverage(
            manifest.outputs,
            required: [("report", .report)],
            reportURL: reportURL,
            reportArtifact: reportArtifact,
            artifacts: rawEvidence,
            producer: producer,
            reading: artifacts
        )
        try validateLVSInputCoverage(
            manifest.inputs,
            provenanceInputs: execution.provenance.inputs,
            allowsDerivedLayoutNetlist: execution.request.layoutGDSURL != nil
        )
        let onDiskData = try readOnDiskArtifact(manifestURL)
        guard onDiskData == retainedManifest.data else {
            throw violation("retained LVS manifest differs from the engine manifest on disk")
        }
        try validateManifestFiles(
            manifest.inputs + manifest.outputs,
            relativeTo: manifestURL.deletingLastPathComponent()
        )
    }

    private func validateProducerBoundArtifacts(
        _ references: [ArtifactReference],
        producer: ProducerIdentity
    ) throws {
        guard !references.isEmpty,
              Set(references).count == references.count,
              references.allSatisfy({ $0.producer == producer }) else {
            throw violation("raw signoff artifacts must be unique and retain the execution producer")
        }
    }

    private func retainedArtifact(
        _ reference: ArtifactReference,
        matching url: URL,
        producer: ProducerIdentity,
        reading artifacts: any FlowArtifactPersisting
    ) async throws -> (reference: ArtifactReference, data: Data) {
        guard reference.producer == producer,
              reference.digest.algorithm == .sha256,
              reference.byteCount > 0 else {
            throw violation("raw artifact \(url.lastPathComponent) has an invalid retained reference")
        }
        let data = try await artifacts.loadArtifactContent(for: reference)
        let sourceData = try readOnDiskArtifact(url)
        guard data == sourceData,
              reference.byteCount == UInt64(data.count),
              try SHA256ContentDigester().digest(data: data) == reference.digest else {
            throw violation("raw artifact \(url.lastPathComponent) does not match its explicit retained reference")
        }
        return (reference, data)
    }

    private func validateManifestRecord<Record>(
        id: String,
        path: URL,
        records: [Record],
        manifestReference: ArtifactReference
    ) throws where Record: RawManifestRecord {
        let matches = records.filter { $0.recordID == id && $0.isManifest }
        let recordedURL = try matches.first.map {
            try containedManifestURL(
                $0.recordPath,
                relativeTo: path.deletingLastPathComponent()
            )
        }
        guard matches.count == 1, let record = matches.first,
              record.byteCountValue == nil,
              record.sha256Value == nil,
              recordedURL?.standardizedFileURL == path.standardizedFileURL,
              manifestReference.locator.role == .output,
              manifestReference.kind == .report,
              manifestReference.format == .json else {
            throw violation("manifest must contain one unhashed self record bound to the retained manifest")
        }
    }

    private func validateOutputCoverage<Record>(
        _ records: [Record],
        required: [(String, Record.KindValue)],
        reportURL: URL,
        reportArtifact: ArtifactReference,
        artifacts: [ArtifactReference],
        producer: ProducerIdentity,
        reading persistence: any FlowArtifactPersisting
    ) async throws where Record: RawManifestRecord {
        guard Set(records.map(\.recordID)).count == records.count else {
            throw violation("raw artifact manifest contains duplicate output record IDs")
        }
        for requirement in required {
            let matches = records.filter {
                $0.recordID == requirement.0 && $0.kindValue == requirement.1
            }
            let recordedReportURL = try matches.first.map {
                try containedManifestURL(
                    $0.recordPath,
                    relativeTo: reportURL.deletingLastPathComponent()
                )
            }
            guard matches.count == 1, let record = matches.first,
                  recordedReportURL?.standardizedFileURL == reportURL.standardizedFileURL,
                  record.sha256Value?.caseInsensitiveCompare(
                      reportArtifact.digest.hexadecimalValue
                  ) == .orderedSame,
                  record.byteCountValue == Int(reportArtifact.byteCount),
                  (record.byteCountValue ?? 0) > 0 else {
                throw violation("raw artifact manifest is missing required output \(requirement.0)")
            }
        }
        _ = try await retainedArtifact(
            reportArtifact,
            matching: reportURL,
            producer: producer,
            reading: persistence
        )
        for record in records where !record.isManifest {
            guard let count = record.byteCountValue,
                  count >= 0,
                  let sha256 = record.sha256Value,
                  isSHA256(sha256) else {
                throw violation("manifest output \(record.recordID) has incomplete integrity identity")
            }
            let matches = artifacts.filter {
                $0.producer == producer
                    && $0.digest.algorithm == .sha256
                    && $0.digest.hexadecimalValue.caseInsensitiveCompare(sha256) == .orderedSame
                    && $0.byteCount == UInt64(count)
            }
            guard matches.count == 1, let reference = matches.first else {
                throw violation("manifest output \(record.recordID) is not uniquely retained in release evidence")
            }
            _ = try await persistence.loadArtifactContent(for: reference)
        }
    }

    func validateDRCInputCoverage(
        _ records: [DRCArtifactRecord],
        provenanceInputs: [ArtifactReference]
    ) throws {
        guard Set(records.map(\.id)).count == records.count else {
            throw violation("DRC manifest contains duplicate input record IDs")
        }
        let references = try records.map { record -> ArtifactReference in
            guard let reference = record.sourceReference,
                  reference.locator.role == .input,
                  drcSourceKind(for: record.kind) == reference.locator.kind,
                  recordMatchesReference(record, reference: reference) else {
                throw violation("DRC manifest input \(record.id) does not retain its exact source artifact identity")
            }
            return reference
        }
        guard Set(references).count == references.count,
              Set(provenanceInputs).count == provenanceInputs.count,
              Set(references) == Set(provenanceInputs) else {
            throw violation("DRC manifest inputs do not exactly cover execution provenance inputs")
        }
    }

    func validateLVSInputCoverage(
        _ records: [LVSArtifactRecord],
        provenanceInputs: [ArtifactReference],
        allowsDerivedLayoutNetlist: Bool
    ) throws {
        guard Set(records.map(\.id)).count == records.count else {
            throw violation("LVS manifest contains duplicate input record IDs")
        }
        let references = try records.map { record -> ArtifactReference in
            switch (record.sourceReference, record.derivedReference) {
            case let (.some(source), .none):
                guard source.locator.role == .input,
                      lvsSourceKind(for: record.kind) == source.locator.kind,
                      recordMatchesReference(record, reference: source) else {
                    throw violation("LVS manifest input \(record.id) does not retain its exact source artifact identity")
                }
                return source
            case let (.none, .some(derived)):
                guard allowsDerivedLayoutNetlist,
                      record.kind == .layoutNetlist,
                      derived.locator.role == .output,
                      derived.locator.kind == .netlist,
                      derived.producer != nil,
                      recordMatchesReference(record, reference: derived) else {
                    throw violation("LVS manifest input \(record.id) has an invalid derived layout-netlist identity")
                }
                return derived
            case (.some(_), .some(_)), (.none, .none):
                throw violation("LVS manifest input \(record.id) must identify exactly one source or derived artifact")
            }
        }
        guard Set(references).count == references.count,
              Set(provenanceInputs).count == provenanceInputs.count,
              Set(references) == Set(provenanceInputs) else {
            throw violation("LVS manifest inputs do not exactly cover execution provenance inputs")
        }
    }

    private func recordMatchesReference(
        _ record: DRCArtifactRecord,
        reference: ArtifactReference
    ) -> Bool {
        guard let byteCount = record.byteCount,
              byteCount >= 0,
              let sha256 = record.sha256 else {
            return false
        }
        return reference.digest.algorithm == .sha256
            && reference.digest.hexadecimalValue.caseInsensitiveCompare(sha256) == .orderedSame
            && reference.byteCount == UInt64(byteCount)
    }

    private func recordMatchesReference(
        _ record: LVSArtifactRecord,
        reference: ArtifactReference
    ) -> Bool {
        guard let byteCount = record.byteCount,
              byteCount >= 0,
              let sha256 = record.sha256 else {
            return false
        }
        return reference.digest.algorithm == .sha256
            && reference.digest.hexadecimalValue.caseInsensitiveCompare(sha256) == .orderedSame
            && reference.byteCount == UInt64(byteCount)
    }

    private func drcSourceKind(for kind: DRCArtifactRecord.Kind) -> ArtifactKind? {
        switch kind {
        case .layout: .layout
        case .technology: .technology
        case .waiver: .constraint
        case .report, .log, .manifest: nil
        }
    }

    private func lvsSourceKind(for kind: LVSArtifactRecord.Kind) -> ArtifactKind? {
        switch kind {
        case .layout: .layout
        case .layoutNetlist, .schematicNetlist: .netlist
        case .technology, .extractionProfile: .technology
        case .extractionDeck: .ruleDeck
        case .waiver, .modelEquivalence, .terminalEquivalence, .devicePolicy: .constraint
        case .report, .log, .manifest, .correspondence, .extractionReport, .transformLedger: nil
        }
    }

    private func validateLVSImplementationIdentity(
        _ identity: LVSImplementationIdentity?,
        request: LVSRequest,
        producer: ProducerIdentity,
        qualificationScope: ToolQualificationScope
    ) throws {
        let requiresIdentity = request.processProfileID != nil || request.extractionDeckURL != nil
        guard !requiresIdentity || identity != nil else {
            throw violation("LVS process-aware release evidence requires implementation identity")
        }
        guard let identity else {
            return
        }
        guard identity.isComplete,
              identity.implementationID == producer.identifier,
              identity.binaryDigest.caseInsensitiveCompare(producer.build ?? "") == .orderedSame,
              identity.algorithmVersion == qualificationScope.algorithmVersion,
              identity.processProfileID == qualificationScope.processProfileID,
              identity.deckDigest.caseInsensitiveCompare(qualificationScope.deckDigest) == .orderedSame else {
            throw violation("LVS implementation identity does not match execution and qualification scope")
        }
    }

    private func requireQualifiedProducer(
        _ producer: ProducerIdentity,
        qualificationScope: ToolQualificationScope
    ) throws {
        guard producer.identifier == qualificationScope.implementationID,
              producer.version == qualificationScope.toolVersion,
              producer.build?.caseInsensitiveCompare(qualificationScope.binaryDigest) == .orderedSame else {
            throw violation("raw evidence producer does not match the qualified implementation")
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw violation("could not decode raw \(String(describing: type)): \(error.localizedDescription)")
        }
    }

    private func readOnDiskArtifact(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw violation("could not re-read raw artifact \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

    private func validateManifestFiles<Record>(
        _ records: [Record],
        relativeTo baseDirectory: URL
    ) throws where Record: RawManifestRecord {
        var recordIDs = Set<String>()
        for record in records {
            guard recordIDs.insert(record.recordID).inserted else {
                throw violation("raw artifact manifest contains duplicate record ID \(record.recordID)")
            }
            guard !record.recordPath.isEmpty else {
                throw violation("raw artifact manifest contains an empty path")
            }
            if record.isManifest {
                guard record.recordID == "manifest",
                      record.byteCountValue == nil,
                      record.sha256Value == nil else {
                    throw violation("raw artifact manifest self record is invalid")
                }
                continue
            }
            guard let byteCount = record.byteCountValue,
                  byteCount >= 0,
                  let sha256 = record.sha256Value,
                  isSHA256(sha256) else {
                throw violation("manifest record \(record.recordID) has incomplete integrity identity")
            }
            let url = try containedManifestURL(record.recordPath, relativeTo: baseDirectory)
            let data = try readOnDiskArtifact(url)
            guard data.count == byteCount,
                  try SHA256ContentDigester().digest(data: data).hexadecimalValue
                    .caseInsensitiveCompare(sha256) == .orderedSame else {
                throw violation("manifest record \(record.recordID) failed on-disk integrity verification")
            }
        }
    }

    private func containedManifestURL(_ path: String, relativeTo baseDirectory: URL) throws -> URL {
        guard !path.hasPrefix("/"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw violation("manifest artifact path escapes its run directory: \(path)")
        }
        let resolvedBase = baseDirectory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = baseDirectory.appending(path: path).standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let basePath = resolvedBase.path(percentEncoded: false)
        let candidatePath = resolvedCandidate.path(percentEncoded: false)
        guard candidatePath.hasPrefix(basePath + "/") else {
            throw violation("manifest artifact path escapes its run directory: \(path)")
        }
        return resolvedCandidate
    }

    private func violation(_ message: String) -> ReleaseSignoffEvidenceAssemblyError {
        .resultContractViolation(message)
    }
}

private protocol RawManifestRecord {
    associatedtype KindValue: Equatable

    var recordID: String { get }
    var recordPath: String { get }
    var byteCountValue: Int? { get }
    var sha256Value: String? { get }
    var kindValue: KindValue { get }
    var isManifest: Bool { get }
}

extension DRCArtifactRecord: RawManifestRecord {
    fileprivate var recordID: String { id }
    fileprivate var recordPath: String { path }
    fileprivate var byteCountValue: Int? { byteCount }
    fileprivate var sha256Value: String? { sha256 }
    fileprivate var kindValue: Kind { kind }
    fileprivate var isManifest: Bool { kind == .manifest }
}

extension LVSArtifactRecord: RawManifestRecord {
    fileprivate var recordID: String { id }
    fileprivate var recordPath: String { path }
    fileprivate var byteCountValue: Int? { byteCount }
    fileprivate var sha256Value: String? { sha256 }
    fileprivate var kindValue: Kind { kind }
    fileprivate var isManifest: Bool { kind == .manifest }
}
