import Foundation
import DesignFlowKernel

/// Persistence capability required by verified-improvement corpus qualification.
///
/// The qualifier depends on this narrow storage contract instead of a concrete
/// project store. Concrete `.xcircuite` persistence remains at the storage
/// boundary and can be replaced by a workspace-backed implementation.
public protocol VerifiedImprovementCorpusStoring: Sendable {
    func ensureDirectory(at url: URL) throws

    func url(
        forProjectRelativePath rawPath: String,
        inProjectAt projectRoot: URL
    ) throws -> URL

    func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        forProjectAt projectRoot: URL
    ) throws

    func readJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) throws -> T

    func fileReference(
        forProjectRelativePath path: String,
        artifactID: String?,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        inProjectAt projectRoot: URL,
        producedByRunID: String?,
        verifiedByRunID: String?
    ) throws -> XcircuiteFileReference

    func upsertFileReference(
        _ reference: XcircuiteFileReference,
        forProjectAt projectRoot: URL
    ) throws

    func loadRunManifest(
        runID: String,
        inProjectAt projectRoot: URL
    ) throws -> XcircuiteRunManifest
}

extension XcircuitePackageStore: VerifiedImprovementCorpusStoring {}
