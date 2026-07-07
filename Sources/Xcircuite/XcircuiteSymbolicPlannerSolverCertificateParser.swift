import Foundation

public struct XcircuiteSymbolicPlannerSolverCertificateParser: Sendable {
    private struct TextFormatDetection: Sendable {
        var certificateFormat: String
        var solverFamily: String?
        var solverName: String?
    }

    public init() {}

    public func parse(
        text: String,
        requestedFormat: String = "auto"
    ) -> XcircuiteSymbolicPlannerSolverCertificateParseResultPayload {
        let format = requestedFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "auto"
            : requestedFormat
        if format == "generic-json" || looksLikeJSON(text) {
            return parseJSON(text: text, requestedFormat: format)
        }
        if supportedTextFormats().contains(format) {
            return parseText(text: text, requestedFormat: format)
        }
        return XcircuiteSymbolicPlannerSolverCertificateParseResultPayload(
            status: "failed",
            detectedFormat: nil,
            certificate: nil,
            diagnostics: [
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "native-certificate-format-unsupported",
                    message: "Unsupported native solver certificate format '\(format)'."
                ),
            ]
        )
    }

    private func parseJSON(
        text: String,
        requestedFormat: String
    ) -> XcircuiteSymbolicPlannerSolverCertificateParseResultPayload {
        guard let data = text.data(using: .utf8) else {
            return XcircuiteSymbolicPlannerSolverCertificateParseResultPayload(
                status: "failed",
                detectedFormat: "generic-json",
                certificate: nil,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "native-certificate-invalid-utf8",
                        message: "Native solver certificate is not valid UTF-8."
                    ),
                ]
            )
        }
        do {
            var certificate = try JSONDecoder().decode(
                XcircuiteSymbolicPlannerSolverCertificate.self,
                from: data
            )
            certificate.certificateFormat = certificate.certificateFormat.isEmpty
                ? "generic-json"
                : certificate.certificateFormat
            if certificate.claims.isEmpty {
                certificate.claims = claims(from: certificate)
            }
            return XcircuiteSymbolicPlannerSolverCertificateParseResultPayload(
                status: "parsed",
                detectedFormat: "generic-json",
                certificate: certificate,
                diagnostics: certificateDiagnostics(certificate)
            )
        } catch {
            return XcircuiteSymbolicPlannerSolverCertificateParseResultPayload(
                status: "failed",
                detectedFormat: "generic-json",
                certificate: nil,
                diagnostics: [
                    XcircuiteSymbolicPlannerSolverDiagnostic(
                        severity: "error",
                        code: "native-certificate-json-decode-failed",
                        message: "Native solver certificate JSON could not be decoded: \(error.localizedDescription)."
                    ),
                ]
            )
        }
    }

    private func parseText(
        text: String,
        requestedFormat: String
    ) -> XcircuiteSymbolicPlannerSolverCertificateParseResultPayload {
        let detection = detectTextFormat(text: text, requestedFormat: requestedFormat)
        var certificate = XcircuiteSymbolicPlannerSolverCertificate(
            solverName: detection.solverName,
            solverFamily: detection.solverFamily,
            certificateFormat: detection.certificateFormat
        )
        if let metadata = XcircuiteSymbolicPlannerSolverMetadataParser().parse(
            standardOutput: text,
            standardError: "",
            solverPlanText: nil
        ) {
            certificate.planCost = metadata.planCost
            certificate.planCostUnit = metadata.planCostUnit
            certificate.planLength = metadata.planLength
            certificate.makespan = metadata.makespan
            certificate.optimalityStatus = metadata.optimalityStatus
            certificate.evidenceLines.append(contentsOf: metadata.evidenceLines)
        }

        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            inspectPlannerFamilyLine(line, certificate: &certificate)
            inspect(line, certificate: &certificate)
        }

        finalizeCertificate(&certificate)

        certificate.evidenceLines = stableUnique(certificate.evidenceLines)
        certificate.claims = claims(from: certificate)
        let diagnostics = certificateDiagnostics(certificate)
        let hasEvidence = !certificate.evidenceLines.isEmpty || !certificate.claims.isEmpty
        return XcircuiteSymbolicPlannerSolverCertificateParseResultPayload(
            status: hasEvidence ? "parsed" : "failed",
            detectedFormat: certificate.certificateFormat,
            certificate: hasEvidence ? certificate : nil,
            diagnostics: hasEvidence ? diagnostics : [
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "native-certificate-no-recognized-claims",
                    message: "Native solver certificate did not contain recognized cost, optimality, proof, bound, or coverage claims."
                ),
            ]
        )
    }

    private func inspect(
        _ line: String,
        certificate: inout XcircuiteSymbolicPlannerSolverCertificate
    ) {
        if let value = stringValue(afterAny: ["certificate id", "certificate-id"], in: line) {
            certificate.certificateID = value
            appendEvidence(line, to: &certificate)
        }
        if let value = stringValue(afterAny: ["solver family", "solver-family", "planner family"], in: line) {
            certificate.solverFamily = normalizedFamily(value)
            appendEvidence(line, to: &certificate)
        }
        if let value = stringValue(afterAny: ["solver name", "solver", "planner"], in: line),
           line.range(of: "solver family", options: [.caseInsensitive]) == nil,
           line.range(of: "planner family", options: [.caseInsensitive]) == nil {
            certificate.solverName = value
            appendEvidence(line, to: &certificate)
        }
        if let value = stringValue(afterAny: ["status"], in: line) {
            certificate.status = normalizedStatus(value)
            appendEvidence(line, to: &certificate)
        }
        if let value = stringValue(afterAny: ["optimality", "optimality status"], in: line) {
            certificate.optimalityStatus = normalizedOptimality(value)
            appendEvidence(line, to: &certificate)
        }
        if let value = stringValue(afterAny: ["proof status", "proof", "certificate status"], in: line) {
            certificate.proofStatus = normalizedProofStatus(value)
            appendEvidence(line, to: &certificate)
        }
        if let value = numberValue(afterAny: ["lower bound", "lower-bound"], in: line) {
            certificate.lowerBound = value
            appendEvidence(line, to: &certificate)
        }
        if let value = numberValue(afterAny: ["upper bound", "upper-bound"], in: line) {
            certificate.upperBound = value
            appendEvidence(line, to: &certificate)
        }
        if let value = stringValue(afterAny: ["goal coverage", "goal-coverage"], in: line) {
            certificate.goalCoverageStatus = normalizedGoalCoverage(value)
            appendEvidence(line, to: &certificate)
        }
        if let value = listValue(afterAny: ["expected actions", "expected-action-ids"], in: line) {
            certificate.expectedActionIDs = value
            appendEvidence(line, to: &certificate)
        }
        if let value = listValue(afterAny: ["observed actions", "observed-action-ids"], in: line) {
            certificate.observedActionIDs = value
            appendEvidence(line, to: &certificate)
        }
    }

    private func claims(
        from certificate: XcircuiteSymbolicPlannerSolverCertificate
    ) -> [XcircuiteSymbolicPlannerSolverCertificateClaim] {
        var claims: [XcircuiteSymbolicPlannerSolverCertificateClaim] = []
        appendClaim(kind: "plan-cost", numericValue: certificate.planCost, unit: certificate.planCostUnit, claims: &claims)
        appendClaim(kind: "plan-length", numericValue: certificate.planLength.map(Double.init), unit: nil, claims: &claims)
        appendClaim(kind: "makespan", numericValue: certificate.makespan, unit: nil, claims: &claims)
        appendClaim(kind: "lower-bound", numericValue: certificate.lowerBound, unit: nil, claims: &claims)
        appendClaim(kind: "upper-bound", numericValue: certificate.upperBound, unit: nil, claims: &claims)
        if let optimalityStatus = certificate.optimalityStatus {
            appendClaim(kind: "optimality", value: optimalityStatus, claims: &claims)
        }
        if let proofStatus = certificate.proofStatus {
            appendClaim(kind: "proof", value: proofStatus, claims: &claims)
        }
        if let goalCoverageStatus = certificate.goalCoverageStatus {
            appendClaim(kind: "goal-coverage", value: goalCoverageStatus, claims: &claims)
        }
        if let solverFamily = certificate.solverFamily {
            appendClaim(kind: "solver-family", value: solverFamily, claims: &claims)
        }
        return claims
    }

    private func supportedTextFormats() -> Set<String> {
        [
            "auto",
            "generic-text",
            "fast-downward-text",
            "metric-ff-text",
            "optic-text",
            "madagascar-text",
        ]
    }

    private func detectTextFormat(
        text: String,
        requestedFormat: String
    ) -> TextFormatDetection {
        let format = requestedFormat == "auto" ? detectedTextFormat(text) : requestedFormat
        switch format {
        case "fast-downward-text":
            return TextFormatDetection(
                certificateFormat: "fast-downward-text",
                solverFamily: "fast-downward",
                solverName: "Fast Downward"
            )
        case "metric-ff-text":
            return TextFormatDetection(
                certificateFormat: "metric-ff-text",
                solverFamily: "metric-ff",
                solverName: "Metric-FF"
            )
        case "optic-text":
            return TextFormatDetection(
                certificateFormat: "optic-text",
                solverFamily: "optic",
                solverName: "OPTIC"
            )
        case "madagascar-text":
            return TextFormatDetection(
                certificateFormat: "madagascar-text",
                solverFamily: "madagascar",
                solverName: "Madagascar"
            )
        default:
            return TextFormatDetection(
                certificateFormat: "generic-text",
                solverFamily: nil,
                solverName: nil
            )
        }
    }

    private func detectedTextFormat(_ text: String) -> String {
        let lowercased = text.lowercased()
        if lowercased.contains("fast downward")
            || lowercased.contains("translate exit code")
            || lowercased.contains("search exit code")
            || (lowercased.contains("plan length:") && lowercased.contains("actual search time")) {
            return "fast-downward-text"
        }
        if lowercased.contains("metric-ff")
            || lowercased.contains("ff: found legal plan")
            || lowercased.contains("found legal plan as follows") {
            return "metric-ff-text"
        }
        if lowercased.contains("optic")
            || lowercased.contains(";;;; solution found")
            || lowercased.contains(";;;; plan found") {
            return "optic-text"
        }
        if lowercased.contains("madagascar")
            || lowercased.contains("m-stage")
            || lowercased.contains("plan found by madagascar") {
            return "madagascar-text"
        }
        return "generic-text"
    }

    private func inspectPlannerFamilyLine(
        _ line: String,
        certificate: inout XcircuiteSymbolicPlannerSolverCertificate
    ) {
        let lowercased = line.lowercased()
        if lowercased.contains("solution found")
            || lowercased.contains("found legal plan")
            || lowercased.contains("plan found") {
            certificate.status = "parsed"
            certificate.goalCoverageStatus = certificate.goalCoverageStatus ?? "covered"
            appendEvidence(line, to: &certificate)
        }
        if lowercased.contains("no solution")
            || lowercased.contains("search stopped without finding")
            || lowercased.contains("unsolvable") {
            certificate.status = "failed"
            certificate.goalCoverageStatus = "missing"
            appendEvidence(line, to: &certificate)
        }
        if lowercased.contains("optimal solution found")
            || lowercased.contains("solved optimally")
            || lowercased.contains("proved optimal")
            || lowercased.contains("optimal plan found") {
            certificate.optimalityStatus = "optimal"
            appendEvidence(line, to: &certificate)
        } else if lowercased.contains("not proven optimal")
            || lowercased.contains("not proved optimal")
            || lowercased.contains("optimality not proven")
            || lowercased.contains("suboptimal") {
            certificate.optimalityStatus = lowercased.contains("suboptimal") ? "satisficing" : "not-optimal"
            appendEvidence(line, to: &certificate)
        }
        if lowercased.contains("proof valid")
            || lowercased.contains("plan valid")
            || lowercased.contains("validation successful")
            || lowercased.contains("verified plan") {
            certificate.proofStatus = "validated"
            appendEvidence(line, to: &certificate)
        }
        if lowercased.contains("proof invalid")
            || lowercased.contains("plan invalid")
            || lowercased.contains("validation failed") {
            certificate.proofStatus = "failed"
            appendEvidence(line, to: &certificate)
        }
        if lowercased.contains("goal reached")
            || lowercased.contains("goals satisfied")
            || lowercased.contains("all goals satisfied") {
            certificate.goalCoverageStatus = "covered"
            appendEvidence(line, to: &certificate)
        }
        if lowercased.contains("goal not reached")
            || lowercased.contains("goals not satisfied")
            || lowercased.contains("missing goal") {
            certificate.goalCoverageStatus = "missing"
            appendEvidence(line, to: &certificate)
        }
        if certificate.upperBound == nil,
           let value = numberValue(afterAny: ["best solution cost", "incumbent cost", "upper bound"], in: line) {
            certificate.upperBound = value
            appendEvidence(line, to: &certificate)
        }
        if certificate.lowerBound == nil,
           let value = numberValue(afterAny: ["lower bound", "proven lower bound"], in: line) {
            certificate.lowerBound = value
            appendEvidence(line, to: &certificate)
        }
    }

    private func finalizeCertificate(
        _ certificate: inout XcircuiteSymbolicPlannerSolverCertificate
    ) {
        guard certificate.optimalityStatus == "optimal",
              let planCost = certificate.planCost else {
            return
        }
        if certificate.lowerBound == nil {
            certificate.lowerBound = planCost
        }
        if certificate.upperBound == nil {
            certificate.upperBound = planCost
        }
    }

    private func appendClaim(
        kind: String,
        value: String? = nil,
        numericValue: Double? = nil,
        unit: String? = nil,
        claims: inout [XcircuiteSymbolicPlannerSolverCertificateClaim]
    ) {
        guard value != nil || numericValue != nil else { return }
        claims.append(
            XcircuiteSymbolicPlannerSolverCertificateClaim(
                claimID: "claim-\(claims.count + 1)",
                kind: kind,
                status: "claimed",
                value: value,
                numericValue: numericValue,
                unit: unit
            )
        )
    }

    private func certificateDiagnostics(
        _ certificate: XcircuiteSymbolicPlannerSolverCertificate
    ) -> [XcircuiteSymbolicPlannerSolverDiagnostic] {
        var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
        if certificate.optimalityStatus == "optimal",
           let lowerBound = certificate.lowerBound,
           let upperBound = certificate.upperBound,
           !approximatelyEqual(lowerBound, upperBound) {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "native-certificate-inconsistent-optimal-bounds",
                    message: "Native solver certificate claims optimality but lower bound \(lowerBound) does not match upper bound \(upperBound)."
                )
            )
        }
        if certificate.proofStatus == "failed" || certificate.status == "failed" {
            diagnostics.append(
                XcircuiteSymbolicPlannerSolverDiagnostic(
                    severity: "error",
                    code: "native-certificate-failed-status",
                    message: "Native solver certificate carries a failed proof or certificate status."
                )
            )
        }
        return diagnostics
    }

    private func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }

    private func stringValue(afterAny markers: [String], in line: String) -> String? {
        for marker in markers {
            if let value = stringValue(after: marker, in: line) {
                return value
            }
        }
        return nil
    }

    private func stringValue(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }
        let suffix = line[range.upperBound...]
        guard let delimiter = suffix.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return nil
        }
        let value = suffix[suffix.index(after: delimiter)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func numberValue(afterAny markers: [String], in line: String) -> Double? {
        for marker in markers {
            if let value = numericSuffix(after: marker, in: line),
               let number = firstDouble(in: value) {
                return number
            }
        }
        return nil
    }

    private func numericSuffix(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }
        let rawSuffix = line[range.upperBound...]
        if let delimiter = rawSuffix.firstIndex(where: { $0 == ":" || $0 == "=" }) {
            return String(rawSuffix[rawSuffix.index(after: delimiter)...])
        }
        return String(rawSuffix)
    }

    private func normalizedFamily(_ value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.contains("fast") && lowercased.contains("downward") {
            return "fast-downward"
        }
        if lowercased.contains("metric") && lowercased.contains("ff") {
            return "metric-ff"
        }
        if lowercased.contains("optic") {
            return "optic"
        }
        if lowercased.contains("madagascar") {
            return "madagascar"
        }
        return lowercased
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private func listValue(afterAny markers: [String], in line: String) -> [String]? {
        guard let value = stringValue(afterAny: markers, in: line) else {
            return nil
        }
        let parts = value
            .split { $0 == "," || $0 == " " || $0 == "\t" }
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }

    private func normalizedStatus(_ value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.contains("fail") || lowercased.contains("invalid") {
            return "failed"
        }
        if lowercased.contains("valid") || lowercased.contains("parsed") || lowercased.contains("ok") {
            return "parsed"
        }
        return lowercased.replacingOccurrences(of: " ", with: "-")
    }

    private func normalizedOptimality(_ value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.contains("not") || lowercased.contains("suboptimal") || lowercased.contains("satisficing") {
            return lowercased.contains("satisficing") ? "satisficing" : "not-optimal"
        }
        if lowercased.contains("optimal") {
            return "optimal"
        }
        return lowercased.replacingOccurrences(of: " ", with: "-")
    }

    private func normalizedProofStatus(_ value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.contains("fail") || lowercased.contains("invalid") || lowercased.contains("reject") {
            return "failed"
        }
        if lowercased.contains("valid") || lowercased.contains("verified") || lowercased.contains("proven") {
            return "validated"
        }
        return lowercased.replacingOccurrences(of: " ", with: "-")
    }

    private func normalizedGoalCoverage(_ value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.contains("cover") || lowercased.contains("satisfied") {
            return "covered"
        }
        if lowercased.contains("missing") || lowercased.contains("uncovered") {
            return "missing"
        }
        return lowercased.replacingOccurrences(of: " ", with: "-")
    }

    private func appendEvidence(
        _ line: String,
        to certificate: inout XcircuiteSymbolicPlannerSolverCertificate
    ) {
        if !certificate.evidenceLines.contains(line) {
            certificate.evidenceLines.append(line)
        }
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private func firstDouble(in text: String) -> Double? {
        var candidate = ""
        var hasDigit = false
        var started = false
        var previousWasExponent = false

        for scalar in text.unicodeScalars {
            if !started {
                if isDigit(scalar) || scalar == "-" || scalar == "+" || scalar == "." {
                    started = true
                    candidate.append(String(scalar))
                    hasDigit = hasDigit || isDigit(scalar)
                    previousWasExponent = false
                }
                continue
            }

            if isDigit(scalar) || scalar == "." {
                candidate.append(String(scalar))
                hasDigit = hasDigit || isDigit(scalar)
                previousWasExponent = false
            } else if scalar == "e" || scalar == "E" {
                candidate.append(String(scalar))
                previousWasExponent = true
            } else if (scalar == "-" || scalar == "+") && previousWasExponent {
                candidate.append(String(scalar))
                previousWasExponent = false
            } else {
                break
            }
        }

        guard hasDigit else { return nil }
        return Double(candidate)
    }

    private func isDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar >= "0" && scalar <= "9"
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_001
    }
}
