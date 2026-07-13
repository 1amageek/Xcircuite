import CircuiteFoundation
import DesignFlowKernel
import Foundation

/// Keeps the current DesignFlowKernel stage record boundary explicit while
/// domain engines expose canonical Foundation artifacts and diagnostics.
///
/// FlowStageResult still stores the pre-foundation record shape. This
/// projection is intentionally limited to that boundary and does not enter
/// any engine API.
enum FoundationFlowProjection {
    static func legacyReference(from reference: ArtifactReference) -> XcircuiteFileReference {
        XcircuiteFileReference(
            artifactID: reference.id.rawValue,
            path: reference.path,
            kind: legacyKind(for: reference.kind),
            format: legacyFormat(for: reference.format),
            sha256: reference.sha256,
            byteCount: Int64(reference.byteCount)
        )
    }

    static func legacyReferences(from references: [ArtifactReference]) -> [XcircuiteFileReference] {
        references.map(legacyReference)
    }

    static func locator(
        from reference: XcircuiteFileReference,
        role: ArtifactRole = .input
    ) throws -> ArtifactLocator {
        ArtifactLocator(
            location: try location(for: reference.path),
            role: role,
            kind: try ArtifactKind(rawValue: canonicalKind(for: reference.kind)),
            format: try ArtifactFormat(rawValue: canonicalFormat(for: reference.format))
        )
    }

    static func artifactReference(
        from reference: XcircuiteFileReference,
        role: ArtifactRole = .input
    ) throws -> ArtifactReference {
        guard let sha256 = reference.sha256, !sha256.isEmpty else {
            throw FoundationFlowProjectionError.missingDigest(reference.path)
        }
        guard let byteCount = reference.byteCount, byteCount >= 0 else {
            throw FoundationFlowProjectionError.missingByteCount(reference.path)
        }
        return ArtifactReference(
            id: try reference.artifactID.map { try ArtifactID(rawValue: $0) },
            locator: try locator(from: reference, role: role),
            digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256),
            byteCount: UInt64(byteCount)
        )
    }

    static func flowDiagnostic(_ diagnostic: DesignDiagnostic) -> FlowDiagnostic {
        let detail = diagnostic.detail.map { value in " (\(value))" } ?? ""
        return FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.code.rawValue,
            message: diagnostic.summary + detail
        )
    }

    static func flowDiagnostics(_ diagnostics: [DesignDiagnostic]) -> [FlowDiagnostic] {
        diagnostics.map { flowDiagnostic($0) }
    }

    private static func flowSeverity(_ severity: DiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .information: .info
        case .warning: .warning
        case .error: .error
        }
    }

    private static func location(for path: String) throws -> ArtifactLocation {
        if path.hasPrefix("/") {
            return try ArtifactLocation(fileURL: URL(filePath: path))
        }
        return try ArtifactLocation(workspaceRelativePath: path)
    }

    private static func canonicalKind(for kind: XcircuiteFileKind) -> String {
        switch kind {
        case .powerIntent: "power-intent"
        case .timingLibrary: "timing-library"
        case .testPattern: "test-pattern"
        case .ruleDeck: "rule-deck"
        case .designDiff: "design-diff"
        default: kind.rawValue
        }
    }

    private static func canonicalFormat(for format: XcircuiteFileFormat) -> String {
        switch format {
        case .systemVerilog: "system-verilog"
        default: format.rawValue.lowercased()
        }
    }

    private static func legacyKind(for kind: ArtifactKind) -> XcircuiteFileKind {
        switch kind.rawValue {
        case "power-intent": .powerIntent
        case "timing-library": .timingLibrary
        case "test-pattern": .testPattern
        case "rule-deck": .ruleDeck
        case "design-diff": .designDiff
        case "request": .request
        case "rtl": .rtl
        case "netlist": .netlist
        case "layout": .layout
        case "technology": .technology
        case "constraint", "constraints": .constraint
        case "parasitic", "parasitics": .parasitic
        case "waveform": .waveform
        case "report": .report
        case "log": .log
        case "model": .model
        case "measurement": .measurement
        case "release": .release
        default: .other
        }
    }

    private static func legacyFormat(for format: ArtifactFormat) -> XcircuiteFileFormat {
        switch format.rawValue {
        case "spice": .spice
        case "system-verilog": .systemVerilog
        case "verilog": .verilog
        case "oasis": .oasis
        case "gdsii": .gdsii
        case "lef": .lef
        case "def": .def
        case "spef": .spef
        case "dspf": .dspf
        case "liberty": .liberty
        case "sdc": .sdc
        case "sdf": .sdf
        case "upf": .upf
        case "cpf": .cpf
        case "vcd": .vcd
        case "fst": .fst
        case "stil": .stil
        case "wgl": .wgl
        case "json": .json
        case "raw": .raw
        case "csv": .csv
        case "text": .text
        default: .unknown
        }
    }
}

enum FoundationFlowProjectionError: Error, LocalizedError, Sendable, Hashable {
    case missingDigest(String)
    case missingByteCount(String)

    var errorDescription: String? {
        switch self {
        case .missingDigest(let path): "Artifact digest is missing: \(path)"
        case .missingByteCount(let path): "Artifact byte count is missing: \(path)"
        }
    }
}
