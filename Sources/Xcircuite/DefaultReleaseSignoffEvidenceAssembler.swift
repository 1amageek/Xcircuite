import CircuiteFoundation
import DesignFlowKernel
import DFTCore
import DRCEngine
import ElectricalSignoffCore
import ElectricalSignoffEngine
import Foundation
import LogicIR
import LogicSimulation
import LogicSynthesis
import PowerIntent
import PEXEngine
import PhysicalDesignCore
import ReleaseCore
import RTLVerificationCore
import SignalIntegrityEngine
import STAEngine
import TimingCore
import ToolQualification
import LVSEngine

public struct DefaultReleaseSignoffEvidenceAssembler: ReleaseSignoffEvidenceAssembling {
    private let qualificationValidator: any ToolProcessQualificationEvidenceValidating

    public init(
        qualificationValidator: any ToolProcessQualificationEvidenceValidating =
            ToolProcessQualificationEvidenceValidator()
    ) {
        self.qualificationValidator = qualificationValidator
    }

    public func assemble(
        _ request: ReleaseSignoffEvidenceAssemblyRequest,
        reading artifacts: any FlowArtifactPersisting
    ) async throws -> [ReleaseSignoffEvidenceReference] {
        try validate(request)
        _ = try await artifacts.loadArtifactContent(for: request.designArtifact)
        _ = try await artifacts.loadArtifactContent(for: request.pdkArtifact)

        var records: [ReleaseSignoffEvidenceReference] = []
        for source in request.sources.sorted(by: { $0.axis < $1.axis }) {
            try validate(source)
            _ = try await artifacts.loadArtifactContent(for: source.requestArtifact)
            let resultData = try await artifacts.loadArtifactContent(for: source.resultArtifact)
            for sourceArtifact in source.allArtifacts {
                _ = try await artifacts.loadArtifactContent(for: sourceArtifact)
            }
            let qualificationData = try await artifacts.loadArtifactContent(
                for: source.qualificationArtifact
            )
            let qualification: ToolProcessQualificationEvidence
            do {
                qualification = try JSONDecoder().decode(
                    ToolProcessQualificationEvidence.self,
                    from: qualificationData
                )
                try await qualificationValidator.validate(
                    qualification,
                    reading: QualificationArtifactReader(persistence: artifacts),
                    at: request.evaluatedAt
                )
            } catch {
                throw ReleaseSignoffEvidenceAssemblyError.invalidQualification(
                    error.localizedDescription
                )
            }
            try validate(
                qualification,
                pdkArtifact: request.pdkArtifact
            )

            let evaluatedEvidence = try await evaluate(
                source,
                data: resultData,
                runID: request.runID,
                designDigest: request.designArtifact.digest.hexadecimalValue,
                qualification: qualification,
                reading: artifacts
            )
            try validateDeclaredInputs(
                source,
                provenance: evaluatedEvidence.provenance
            )
            try validateOperationalProvenance(
                evaluatedEvidence.provenance,
                resultArtifact: source.resultArtifact,
                qualification: qualification,
                designArtifact: request.designArtifact,
                pdkArtifact: request.pdkArtifact,
                evaluatedAt: request.evaluatedAt
            )
            let inputs = uniqueArtifacts(evaluatedEvidence.provenance.inputs)
            records.append(ReleaseSignoffEvidenceReference(
                evidenceID: evidenceID(
                    runID: request.runID,
                    source: source,
                    qualificationID: qualification.qualificationID
                ),
                axis: source.axis,
                artifact: source.resultArtifact,
                designDigest: request.designArtifact.digest.hexadecimalValue,
                pdkDigest: request.pdkArtifact.digest.hexadecimalValue,
                toolID: qualification.toolID,
                toolVersion: qualification.scope.toolVersion,
                toolBinaryDigest: qualification.scope.binaryDigest,
                inputArtifacts: inputs,
                executionProvenance: evaluatedEvidence.provenance,
                processQualification: qualification,
                disposition: evaluatedEvidence.evaluation.disposition,
                reason: evaluatedEvidence.evaluation.reason
            ))
        }
        return records
    }

    private func validate(_ request: ReleaseSignoffEvidenceAssemblyRequest) throws {
        guard request.schemaVersion == ReleaseSignoffEvidenceAssemblyRequest.currentSchemaVersion else {
            throw ReleaseSignoffEvidenceAssemblyError.invalidSchemaVersion(request.schemaVersion)
        }
        let runID = request.runID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runID.isEmpty,
              runID != ".",
              runID != "..",
              !runID.contains("/"),
              !runID.contains("\\") else {
            throw ReleaseSignoffEvidenceAssemblyError.invalidRunID(request.runID)
        }
        guard !request.sources.isEmpty else {
            throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                "at least one domain result source is required"
            )
        }
        var axes = Set<ReleaseSignoffAxis>()
        for source in request.sources where !axes.insert(source.axis).inserted {
            throw ReleaseSignoffEvidenceAssemblyError.duplicateAxis(source.axis)
        }
        for artifact in [request.designArtifact, request.pdkArtifact] {
            guard artifact.digest.algorithm == .sha256, artifact.byteCount > 0 else {
                throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                    "design and PDK artifacts require SHA-256 identity and non-zero byte count"
                )
            }
        }
    }

    private func validate(_ source: ReleaseSignoffEvidenceSource) throws {
        let allowedAxes: Set<ReleaseSignoffAxis>
        switch source.producer {
        case .logicSimulation:
            allowedAxes = [.simulation]
        case .logicSynthesisEquivalence:
            allowedAxes = [.logicSynthesisEquivalence]
        case .rtlVerification:
            allowedAxes = [.rtlLint, .clockDomainCrossing, .resetDomainCrossing, .formalProof]
        case .dft:
            allowedAxes = [.scanInsertion, .automaticTestPatternGeneration, .builtInSelfTest]
        case .powerIntent:
            allowedAxes = [.powerIntent]
        case .staticTiming:
            allowedAxes = [.timing]
        case .signalIntegrity:
            allowedAxes = [.crosstalkNoise]
        case .designRuleCheck:
            allowedAxes = [.drc, .antenna]
        case .layoutVersusSchematic:
            allowedAxes = [.lvs]
        case .parasiticExtraction:
            allowedAxes = [.pex]
        case .physicalDesign:
            allowedAxes = [.density, .metalFill, .designForManufacturability]
        case .electricalSignoff:
            allowedAxes = [.electromigration, .irDrop, .erc, .esd, .latchUp, .aging]
        }
        guard allowedAxes.contains(source.axis) else {
            throw ReleaseSignoffEvidenceAssemblyError.unsupportedProducer(
                source.producer,
                source.axis
            )
        }
        guard source.resultArtifact.kind == .report,
              source.resultArtifact.format == .json,
              source.resultArtifact.digest.algorithm == .sha256,
              source.resultArtifact.byteCount > 0,
              source.requestArtifact.kind == .request,
              source.requestArtifact.format == .json,
              source.requestArtifact.digest.algorithm == .sha256,
              source.requestArtifact.byteCount > 0,
              source.qualificationArtifact.kind == .evidence,
              source.qualificationArtifact.format == .json,
              source.qualificationArtifact.digest.algorithm == .sha256,
            source.qualificationArtifact.byteCount > 0 else {
            throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                "domain request, result, and qualification must be non-empty SHA-256 JSON artifacts"
            )
        }
        let categorizedArtifacts = source.executionInputs
            + source.derivedInputs
            + source.rawEvidence
            + source.qualificationEvidence
        guard Set(categorizedArtifacts).count == categorizedArtifacts.count else {
            throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                "release evidence artifact categories must be disjoint and contain unique references"
            )
        }
        switch source.producer {
        case .designRuleCheck, .layoutVersusSchematic:
            guard let manifest = source.manifestArtifact,
                  let report = source.reportArtifact,
                  source.rawEvidence.contains(manifest),
                  source.rawEvidence.contains(report) else {
                throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                    "DRC and LVS sources require explicit manifest and report references in raw evidence"
                )
            }
        case .parasiticExtraction:
            guard let manifest = source.manifestArtifact,
                  source.rawEvidence.contains(manifest) else {
                throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                    "PEX sources require an explicit manifest reference in raw evidence"
                )
            }
        case .staticTiming, .signalIntegrity:
            guard !source.rawEvidence.isEmpty else {
                throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                    "timing sources require exact raw result artifact references"
                )
            }
        default:
            break
        }
    }

    private func validateDeclaredInputs(
        _ source: ReleaseSignoffEvidenceSource,
        provenance: ExecutionProvenance
    ) throws {
        let declaredInputs = source.executionInputs + source.derivedInputs
        guard !declaredInputs.isEmpty,
              Set(declaredInputs).count == declaredInputs.count,
              Set(declaredInputs) == Set(provenance.inputs) else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "declared execution and derived inputs do not exactly match execution provenance"
            )
        }
    }

    private func validate(
        _ qualification: ToolProcessQualificationEvidence,
        pdkArtifact: ArtifactReference
    ) throws {
        guard qualification.scope.pdkDigest?.caseInsensitiveCompare(
            pdkArtifact.digest.hexadecimalValue
        ) == .orderedSame else {
            throw ReleaseSignoffEvidenceAssemblyError.invalidQualification(
                "qualification PDK digest does not match the release PDK artifact"
            )
        }
    }

    private func validateOperationalProvenance(
        _ provenance: ExecutionProvenance,
        resultArtifact: ArtifactReference,
        qualification: ToolProcessQualificationEvidence,
        designArtifact: ArtifactReference,
        pdkArtifact: ArtifactReference,
        evaluatedAt: Date
    ) throws {
        let qualifiedImplementation = [provenance.producer] + provenance.supportingTools
        guard qualifiedImplementation.contains(where: {
            $0.version == qualification.scope.toolVersion
                && $0.identifier == qualification.scope.implementationID
                && $0.build?.caseInsensitiveCompare(
                    qualification.scope.binaryDigest
                ) == .orderedSame
        }) else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "execution provenance does not identify the qualified implementation, version, and executable digest"
            )
        }
        guard provenance.inputs.contains(where: {
            matchesImmutableArtifact($0, designArtifact)
        }), provenance.inputs.contains(where: {
            matchesImmutableArtifact($0, pdkArtifact)
        }) else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "execution provenance does not bind the exact release design and PDK artifacts"
            )
        }
        guard provenance.completedAt <= evaluatedAt else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "execution completed after the release evidence evaluation time"
            )
        }
        guard provenance.invocation != nil, provenance.environment != nil else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "execution provenance must retain its invocation and environment fingerprint"
            )
        }
        guard let artifactProducer = resultArtifact.producer else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "result artifact does not retain its producer identity"
            )
        }
        guard artifactProducer == provenance.producer else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "result artifact producer does not match execution provenance"
            )
        }
    }

    private func evaluate(
        _ source: ReleaseSignoffEvidenceSource,
        data: Data,
        runID: String,
        designDigest: String,
        qualification: ToolProcessQualificationEvidence,
        reading artifacts: any FlowArtifactPersisting
    ) async throws -> EvaluatedEvidence {
        let requestData = try await artifacts.loadArtifactContent(for: source.requestArtifact)
        switch source.producer {
        case .logicSimulation:
            let request = try decode(LogicSimulationRequest.self, from: requestData)
            try request.validate()
            try requireRunID(request.runID, expected: runID)
            let result = try decode(LogicSimulationResult.self, from: data)
            try requireRunID(result.runID, expected: runID)
            try requireExactInputs(request.inputs, provenance: result.provenance)
            try await verify(result.artifacts, reading: artifacts)
            return EvaluatedEvidence(
                evaluation: executionEvaluation(
                    result.status,
                    passed: result.payload.assertionFailureCount == 0,
                    failureReason: "Functional simulation reported assertion failures."
                ),
                provenance: result.provenance
            )
        case .logicSynthesisEquivalence:
            let evidence = try decode(LogicSynthesisEquivalenceEvidence.self, from: data)
            try evidence.validate()
            try requireRunID(evidence.runID, expected: runID)
            let request = try decode(LogicSynthesisEquivalenceRequest.self, from: requestData)
            try request.validate()
            try requireRunID(request.runID, expected: runID)
            try requireExactInputs(
                [
                    request.sourceDesign.artifact,
                    request.mappedDesign.artifact,
                    request.synthesisProvenance,
                    request.pdkArtifact,
                ],
                provenance: evidence.provenance
            )
            guard request.mappedDesign.designDigest.caseInsensitiveCompare(designDigest) == .orderedSame else {
                throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                    "mapped design digest does not match the release design artifact"
                )
            }
            if let proofArtifact = evidence.proofArtifact {
                _ = try await artifacts.loadArtifactContent(for: proofArtifact)
            }
            let acceptance = NativeLogicSynthesisAcceptanceEvaluator().evaluate(
                request: request,
                evidence: evidence
            )
            return EvaluatedEvidence(
                evaluation: acceptance.state == .accepted
                    ? Evaluation(disposition: .passed, reason: nil)
                    : Evaluation(
                        disposition: .failed,
                        reason: acceptance.diagnostics.map(\.summary).joined(separator: " ")
                    ),
                provenance: evidence.provenance
            )
        case .rtlVerification:
            let request = try decode(RTLVerificationRequest.self, from: requestData)
            try requireRunID(request.runID, expected: runID)
            try requireRTLAnalysis(request.analysis, for: source.axis)
            let result = try decode(RTLVerificationResult.self, from: data)
            try requireRunID(result.runID, expected: runID)
            try requireRTLAnalysis(result.payload.analysis, for: source.axis)
            try requireExactInputs(request.executionInputArtifacts, provenance: result.provenance)
            try await verify(result.artifacts, reading: artifacts)
            let hasSignoffFinding = result.payload.findings.contains {
                $0.severity == .error || $0.severity == .warning
            }
            let semanticPass = source.axis != .formalProof
                ? !hasSignoffFinding
                : !hasSignoffFinding
                    && result.payload.proofStatus == "proved"
                    && !result.payload.proofArtifactIDs.isEmpty
            return EvaluatedEvidence(
                evaluation: executionEvaluation(
                    result.status,
                    passed: semanticPass,
                    failureReason: source.axis == .formalProof
                        ? "Formal equivalence did not retain a completed proof."
                        : "RTL verification retained unresolved findings."
                ),
                provenance: result.provenance
            )
        case .dft:
            let request = try decode(DFTRequest.self, from: requestData)
            try requireRunID(request.runID, expected: runID)
            let operation = try dftOperation(for: source.axis)
            guard request.operation == operation,
                  request.validationIssues(for: operation).isEmpty else {
                throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                    "DFT request is invalid for release axis \(source.axis.rawValue)"
                )
            }
            let result = try decode(DFTResult.self, from: data)
            try requireRunID(result.runID, expected: runID)
            try DFTResultValidator().validate(result, for: request)
            try requireExactInputs(request.executionInputArtifacts, provenance: result.provenance)
            try await verify(result.artifacts, reading: artifacts)
            let semanticPass: Bool
            if result.status == .completed,
               !result.diagnostics.contains(where: { $0.severity == .error }) {
                try await DFTResultSemanticVerifier().validate(
                    result,
                    for: request,
                    reading: DFTArtifactReader(persistence: artifacts)
                )
                semanticPass = true
            } else {
                semanticPass = false
            }
            return EvaluatedEvidence(
                evaluation: executionEvaluation(
                    result.status,
                    passed: semanticPass,
                    failureReason: "DFT execution did not retain release-eligible semantic evidence."
                ),
                provenance: result.provenance
            )
        case .powerIntent:
            let request = try decode(PowerIntentParsingRequest.self, from: requestData)
            try requireRunID(request.runID, expected: runID)
            let result = try decode(PowerIntentParsingResult.self, from: data)
            try requireRunID(result.runID, expected: runID)
            try requireExactInputs(request.inputs, provenance: result.provenance)
            try await verify(result.artifacts, reading: artifacts)
            guard result.status != .completed
                || result.payload.reference != nil
                    && result.payload.intent != nil
                    && result.payload.validation?.isValid == true
                    && result.payload.domainCount > 0 else {
                return EvaluatedEvidence(
                    evaluation: Evaluation(
                        disposition: .blocked,
                        reason: "Power intent has no validated domain-bearing canonical result."
                    ),
                    provenance: result.provenance
                )
            }
            return EvaluatedEvidence(
                evaluation: executionEvaluation(
                    result.status,
                    passed: true,
                    failureReason: "Power-intent validation failed."
                ),
                provenance: result.provenance
            )
        case .staticTiming:
            let request = try decode(STARequest.self, from: requestData)
            try requireRunID(request.runID, expected: runID)
            try requireQualifiedOperatingCorners(
                request.requestedCornerIDs,
                qualification: qualification,
                producer: source.producer
            )
            let result = try decode(STAExecutionResult.self, from: data)
            try requireRunID(result.runID, expected: runID)
            let provenance = result.evidence.provenance
            try requireExactInputs(request.inputs, provenance: provenance)
            try await verify(result.artifacts, reading: artifacts)
            try await ReleaseSignoffRawEvidenceValidator().validateTiming(
                provenance: provenance,
                resultArtifacts: result.artifacts,
                qualificationScope: qualification.scope,
                rawEvidence: source.rawEvidence,
                reading: artifacts
            )
            let requestedCorners = Set(request.requestedCornerIDs)
            let requestedModes = Set(request.requestedModeIDs)
            let coverageComplete = !result.payload.analyzedCorners.isEmpty
                && requestedCorners.isSubset(of: Set(result.payload.analyzedCorners))
                && requestedModes.isSubset(of: Set(result.payload.analyzedModes))
                && result.payload.provenance.isCompleteForSTA
            return EvaluatedEvidence(
                evaluation: timingEvaluation(
                    result.status,
                    passed: coverageComplete && result.payload.violations.isEmpty,
                    failureReason: "Static timing did not close every requested mode and corner without violations."
                ),
                provenance: provenance
            )
        case .signalIntegrity:
            let request = try decode(SignalIntegrityRequest.self, from: requestData)
            try requireRunID(request.runID, expected: runID)
            let result = try decode(SignalIntegrityExecutionResult.self, from: data)
            try requireRunID(result.runID, expected: runID)
            let provenance = result.evidence.provenance
            try requireExactInputs(request.inputs, provenance: provenance)
            try await verify(result.artifacts, reading: artifacts)
            try await ReleaseSignoffRawEvidenceValidator().validateTiming(
                provenance: provenance,
                resultArtifacts: result.artifacts,
                qualificationScope: qualification.scope,
                rawEvidence: source.rawEvidence,
                reading: artifacts
            )
            let modesCovered = Set(request.requestedModeIDs)
                .isSubset(of: Set(result.payload.analyzedModes))
            return EvaluatedEvidence(
                evaluation: timingEvaluation(
                    result.status,
                    passed: modesCovered
                        && result.payload.provenance.isCompleteForSignalIntegrity
                        && result.payload.violationCount == 0
                        && result.payload.violations.isEmpty,
                    failureReason: "Signal-integrity analysis retained crosstalk violations or incomplete mode coverage."
                ),
                provenance: provenance
            )
        case .designRuleCheck:
            let request = try decode(DRCRequest.self, from: requestData)
            let result = try decode(DRCExecutionResult.self, from: data)
            guard result.request == request else {
                throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                    "DRC result does not embed the exact retained request"
                )
            }
            try requireExactInputs(request.executionInputArtifacts, provenance: result.provenance)
            if source.axis == .antenna, !request.options.requireAntennaRules {
                throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                    "antenna signoff requires an explicit antenna-rule DRC request"
                )
            }
            try await ReleaseSignoffRawEvidenceValidator().validateDRC(
                result,
                qualificationScope: qualification.scope,
                manifestArtifact: source.manifestArtifact,
                reportArtifact: source.reportArtifact,
                rawEvidence: source.rawEvidence,
                reading: artifacts
            )
            return EvaluatedEvidence(
                evaluation: result.result.passed
                    ? Evaluation(disposition: .passed, reason: nil)
                    : Evaluation(
                        disposition: result.result.completed ? .failed : .blocked,
                        reason: "DRC did not complete with a clean qualified rule-deck result."
                    ),
                provenance: result.provenance
            )
        case .layoutVersusSchematic:
            let request = try decode(LVSRequest.self, from: requestData)
            let result = try decode(LVSExecutionResult.self, from: data)
            guard result.request == request else {
                throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                    "LVS result does not embed the exact retained request"
                )
            }
            try requireExactInputs(
                result.comparisonRequest.executionInputArtifacts,
                provenance: result.provenance
            )
            try await ReleaseSignoffRawEvidenceValidator().validateLVS(
                result,
                qualificationScope: qualification.scope,
                manifestArtifact: source.manifestArtifact,
                reportArtifact: source.reportArtifact,
                rawEvidence: source.rawEvidence,
                reading: artifacts
            )
            return EvaluatedEvidence(
                evaluation: result.result.passed
                    ? Evaluation(disposition: .passed, reason: nil)
                    : Evaluation(
                        disposition: result.result.executionStatus == .completed ? .failed : .blocked,
                        reason: "LVS did not complete with an exact connectivity match."
                    ),
                provenance: result.provenance
            )
        case .parasiticExtraction:
            let request = try decode(PEXRunRequest.self, from: requestData)
            try requireQualifiedOperatingCorners(
                request.corners.map { $0.id.value },
                qualification: qualification,
                producer: source.producer
            )
            let result = try decode(PEXRunResult.self, from: data)
            let provenance = result.provenance
            try requireExactInputs(
                source.executionInputs + source.derivedInputs,
                provenance: provenance
            )
            try await verify(result.artifacts, reading: artifacts)
            try await ReleaseSignoffRawEvidenceValidator().validatePEX(
                result,
                qualificationScope: qualification.scope,
                manifestArtifact: source.manifestArtifact,
                rawEvidence: source.rawEvidence,
                reading: artifacts
            )
            let inputRecords = result.artifactManifest.artifacts.filter {
                $0.stage == .inputValidation || $0.stage == .technologyResolution
            }
            guard try PEXRequestHash.compute(for: request, inputArtifacts: inputRecords)
                == result.requestHash,
                  result.requestHash == result.artifactManifest.requestHash else {
                throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                    "PEX request hash does not match the retained request and manifest inputs"
                )
            }
            let requestedCorners = Set(request.corners.map(\.id))
            let completedCorners = Set(
                result.cornerResults.filter { $0.status == .success && $0.ir != nil }.map(\.cornerID)
            )
            return EvaluatedEvidence(
                evaluation: result.status == .success
                    && requestedCorners == completedCorners
                    ? Evaluation(disposition: .passed, reason: nil)
                    : Evaluation(
                        disposition: result.status == .failed ? .failed : .blocked,
                        reason: "PEX did not retain a successful parasitic IR for every requested corner."
                    ),
                provenance: provenance
            )
        case .physicalDesign:
            let request = try decode(PhysicalDesignRequest.self, from: requestData)
            try requireRunID(request.runID, expected: runID)
            try requirePhysicalStage(request.stage, for: source.axis)
            let result = try decode(PhysicalDesignResult.self, from: data)
            try requireRunID(result.runID, expected: runID)
            try requireExactInputs(request.inputs, provenance: result.provenance)
            try await verify(result.artifacts, reading: artifacts)
            return EvaluatedEvidence(
                evaluation: try await physicalDesignEvaluation(
                    result,
                    request: request,
                    axis: source.axis,
                    qualification: qualification,
                    supportingArtifacts: source.rawEvidence,
                    reading: artifacts
                ),
                provenance: result.provenance
            )
        case .electricalSignoff:
            let request = try decode(ElectricalSignoffRequest.self, from: requestData)
            try request.validate()
            try requireRunID(request.runID, expected: runID)
            try requireQualifiedOperatingCorners(
                request.configuration.operatingConditions.map(\.pdkCornerID),
                qualification: qualification,
                producer: source.producer
            )
            let result = try decode(ElectricalSignoffRunResult.self, from: data)
            try result.validate()
            try requireRunID(result.runID, expected: runID)
            guard Set(result.cornerResults.keys)
                == Set(request.configuration.operatingConditions.map(\.id)) else {
                throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                    "electrical result does not cover every requested operating condition"
                )
            }
            try requireExactInputs(request.executionInputArtifacts, provenance: result.provenance)
            try await verify(result.artifacts, reading: artifacts)
            return EvaluatedEvidence(
                evaluation: try electricalEvaluation(result, axis: source.axis),
                provenance: result.provenance
            )
        }
    }

    private func requireRTLAnalysis(
        _ analysis: RTLVerificationAnalysis,
        for axis: ReleaseSignoffAxis
    ) throws {
        let expected: RTLVerificationAnalysis
        switch axis {
        case .rtlLint: expected = .lint
        case .clockDomainCrossing: expected = .cdc
        case .resetDomainCrossing: expected = .rdc
        case .formalProof: expected = .formalEquivalence
        default:
            throw ReleaseSignoffEvidenceAssemblyError.unsupportedProducer(
                .rtlVerification,
                axis
            )
        }
        guard analysis == expected else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "RTL analysis \(analysis.rawValue) cannot supply axis \(axis.rawValue)"
            )
        }
    }

    private func dftOperation(for axis: ReleaseSignoffAxis) throws -> DFTOperation {
        switch axis {
        case .scanInsertion: .scanInsertion
        case .automaticTestPatternGeneration: .atpg
        case .builtInSelfTest: .bist
        default:
            throw ReleaseSignoffEvidenceAssemblyError.unsupportedProducer(.dft, axis)
        }
    }

    private func requirePhysicalStage(
        _ stage: PhysicalDesignStage,
        for axis: ReleaseSignoffAxis
    ) throws {
        let expected: PhysicalDesignStage
        switch axis {
        case .density, .metalFill:
            expected = .fillInsertion
        case .designForManufacturability:
            expected = .hotspotRepair
        default:
            throw ReleaseSignoffEvidenceAssemblyError.unsupportedProducer(
                .physicalDesign,
                axis
            )
        }
        guard stage == expected else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "physical stage \(stage.rawValue) cannot supply axis \(axis.rawValue)"
            )
        }
    }

    private func physicalDesignEvaluation(
        _ result: PhysicalDesignResult,
        request: PhysicalDesignRequest,
        axis: ReleaseSignoffAxis,
        qualification: ToolProcessQualificationEvidence,
        supportingArtifacts: [ArtifactReference],
        reading artifacts: any FlowArtifactPersisting
    ) async throws -> Evaluation {
        switch result.status {
        case .completed:
            guard let physicalDesign = result.payload.physicalDesign,
                  let manifestReference = result.payload.runManifest,
                  let completionReference = result.payload.stageCompletionEvidence,
                  request.executionIntent == .productionImplementation,
                  result.payload.claims.geometry == .verified,
                  result.artifacts.contains(manifestReference),
                  result.artifacts.contains(completionReference),
                  supportingArtifacts.contains(manifestReference),
                  supportingArtifacts.contains(completionReference) else {
                return Evaluation(
                    disposition: .blocked,
                    reason: "Physical-design execution completed without a verified canonical layout and retained run manifest."
                )
            }
            let manifestData = try await artifacts.loadArtifactContent(for: manifestReference)
            let manifest: PhysicalDesignRunManifest
            do {
                manifest = try PhysicalDesignJSONCodec().decode(
                    PhysicalDesignRunManifest.self,
                    from: manifestData
                )
            } catch {
                throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                    "could not decode PhysicalDesignRunManifest: \(error.localizedDescription)"
                )
            }
            guard manifest.validationDiagnostics().isEmpty,
                  manifest.runID == result.runID,
                  manifest.stage == request.stage,
                  manifest.status == .completed,
                  manifest.proposedLayout == physicalDesign,
                  manifest.claims == result.payload.claims,
                  manifest.executionIntent == .productionImplementation,
                  let productionConfiguration = manifest.productionConfiguration,
                  productionConfiguration == request.productionConfiguration,
                  let processEvidenceReference = manifest.processEvidence,
                  result.artifacts.contains(processEvidenceReference),
                  supportingArtifacts.contains(processEvidenceReference) else {
                throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                    "physical-design run manifest does not match the request and canonical result"
                )
            }
            let processEvidenceData = try await artifacts.loadArtifactContent(
                for: processEvidenceReference
            )
            let processEvidence: PhysicalDesignProcessEvidence
            do {
                processEvidence = try PhysicalDesignJSONCodec().decode(
                    PhysicalDesignProcessEvidence.self,
                    from: processEvidenceData
                )
            } catch {
                throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                    "could not decode PhysicalDesignProcessEvidence: \(error.localizedDescription)"
                )
            }
            guard processEvidence.runID == result.runID,
                  processEvidence.stage == request.stage,
                  processEvidence.backendID == productionConfiguration.backendID,
                  processEvidence.executable == productionConfiguration.executable,
                  processEvidence.observedVersion == productionConfiguration.executable.expectedVersion,
                  processEvidence.inputs == request.inputs,
                  processEvidence.invocation == result.provenance.invocation,
                  processEvidence.environment == result.provenance.environment,
                  processEvidence.termination == .completed,
                  processEvidence.exitCode == 0,
                  processEvidence.startedAt >= result.provenance.startedAt,
                  processEvidence.completedAt <= result.provenance.completedAt,
                  processEvidence.outputs.contains(completionReference),
                  qualification.scope.implementationID == productionConfiguration.executable.toolID,
                  qualification.scope.toolVersion == processEvidence.observedVersion,
                  qualification.scope.binaryDigest.caseInsensitiveCompare(
                      productionConfiguration.executable.digest.hexadecimalValue
                  ) == .orderedSame else {
                throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                    "physical-design process evidence does not match the production request, executable, or qualification"
                )
            }
            let completionData = try await artifacts.loadArtifactContent(
                for: completionReference
            )
            let completion: PhysicalDesignStageCompletionEvidence
            do {
                completion = try PhysicalDesignJSONCodec().decode(
                    PhysicalDesignStageCompletionEvidence.self,
                    from: completionData
                )
            } catch {
                throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                    "could not decode PhysicalDesignStageCompletionEvidence: \(error.localizedDescription)"
                )
            }
            guard completion.isValid,
                  completion.runID == result.runID,
                  completion.stage == request.stage,
                  completion.outputLayout == physicalDesign.layoutArtifact,
                  completion.metrics == result.payload.metrics,
                  completion.completedAt <= result.provenance.completedAt else {
                throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                    "physical-design completion evidence does not match the result stage, output, metrics, or execution interval"
                )
            }
            let metrics = Dictionary(
                grouping: result.payload.metrics,
                by: \.name
            )
            guard metrics.values.allSatisfy({ $0.count == 1 }) else {
                throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                    "physical-design signoff metrics must have unique names"
                )
            }
            let passed: Bool
            switch axis {
            case .density:
                let density = metrics["fillDensity"]?.first?.value
                let maximum = request.configuration.repairConstraints?
                    .maximumFillDensity
                if let density, let maximum {
                    passed = density.isFinite
                        && maximum.isFinite
                        && density > 0
                        && density <= maximum
                } else {
                    passed = false
                }
            case .metalFill:
                passed = metrics["fillCount"]?.first.map {
                    $0.value.isFinite && $0.value > 0
                } == true
            case .designForManufacturability:
                passed = metrics["unresolvedHotspotCount"]?.first.map {
                    $0.value.isFinite && $0.value == 0
                } == true
                    && metrics["hotspotsRepaired"]?.first.map {
                        $0.value.isFinite && $0.value > 0
                    } == true
            default:
                throw ReleaseSignoffEvidenceAssemblyError.unsupportedProducer(
                    .physicalDesign,
                    axis
                )
            }
            return passed
                ? Evaluation(disposition: .passed, reason: nil)
                : Evaluation(
                    disposition: .failed,
                    reason: "Physical-design axis-specific metrics did not satisfy the retained release limits."
                )
        case .failed:
            return Evaluation(
                disposition: .failed,
                reason: "Physical-design verification failed."
            )
        case .blocked, .cancelled:
            return Evaluation(
                disposition: .blocked,
                reason: "Physical-design verification was blocked or cancelled."
            )
        }
    }

    private func timingEvaluation(
        _ status: TimingExecutionStatus,
        passed: Bool,
        failureReason: String
    ) -> Evaluation {
        switch status {
        case .completed:
            return passed
                ? Evaluation(disposition: .passed, reason: nil)
                : Evaluation(disposition: .failed, reason: failureReason)
        case .failed:
            return Evaluation(disposition: .failed, reason: failureReason)
        case .blocked, .cancelled:
            return Evaluation(disposition: .blocked, reason: failureReason)
        }
    }

    private func requireExactInputs(
        _ expected: [ArtifactReference],
        provenance: ExecutionProvenance
    ) throws {
        guard Set(expected) == Set(provenance.inputs),
              expected.count == Set(expected).count,
              provenance.inputs.count == Set(provenance.inputs).count else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "typed request inputs and execution provenance inputs differ"
            )
        }
    }

    private func matchesImmutableArtifact(
        _ lhs: ArtifactReference,
        _ rhs: ArtifactReference
    ) -> Bool {
        lhs == rhs
    }

    private func requireQualifiedOperatingCorners(
        _ requiredCornerIDs: [String],
        qualification: ToolProcessQualificationEvidence,
        producer: ReleaseSignoffEvidenceProducer
    ) throws {
        try ReleaseOperatingCornerQualificationValidator().validate(
            requiredCornerIDs: requiredCornerIDs,
            qualifiedCornerIDs: qualification.qualifiedOperatingCornerIDs,
            producer: producer
        )
    }

    private func electricalEvaluation(
        _ result: ElectricalSignoffRunResult,
        axis: ReleaseSignoffAxis
    ) throws -> Evaluation {
        let electricalAxis: ElectricalSignoffAnalysisAxis
        switch axis {
        case .electromigration, .irDrop: electricalAxis = .powerIntegrity
        case .erc: electricalAxis = .erc
        case .esd: electricalAxis = .esd
        case .latchUp: electricalAxis = .latchUp
        case .aging: electricalAxis = .aging
        default:
            throw ReleaseSignoffEvidenceAssemblyError.unsupportedProducer(
                .electricalSignoff,
                axis
            )
        }
        let cornerResults = result.cornerResults.values.compactMap { $0[electricalAxis] }
        let candidates = cornerResults.isEmpty
            ? result.axisResults[electricalAxis].map { [$0] } ?? []
            : cornerResults
        guard !candidates.isEmpty else {
            throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                "electrical result does not contain \(electricalAxis.rawValue) evidence"
            )
        }
        if candidates.contains(where: { $0.status == .failed }) {
            return Evaluation(disposition: .failed, reason: "Electrical analysis failed.")
        }
        if candidates.contains(where: { $0.status == .blocked || $0.status == .cancelled }) {
            return Evaluation(disposition: .blocked, reason: "Electrical analysis was blocked or cancelled.")
        }
        let passed: Bool
        switch axis {
        case .electromigration:
            passed = try electricalMetricPass(
                candidates,
                metricNames: ["segment-current-density", "via-current-density"],
                findingPrefix: "electrical.em."
            )
        case .irDrop:
            passed = try electricalMetricPass(
                candidates,
                metricNames: ["static-ir-drop", "dynamic-ir-drop"],
                findingPrefix: "electrical.ir."
            )
        default:
            passed = candidates.allSatisfy { $0.payload.violationCount == 0 }
        }
        return passed
            ? Evaluation(disposition: .passed, reason: nil)
            : Evaluation(
                disposition: .failed,
                reason: "Electrical \(axis.rawValue) limits were not satisfied in every operating corner."
            )
    }

    private func electricalMetricPass(
        _ results: [ElectricalSignoffResult],
        metricNames: Set<String>,
        findingPrefix: String
    ) throws -> Bool {
        for result in results {
            let metrics = result.payload.metrics.filter { metricNames.contains($0.name) }
            guard Set(metrics.map(\.name)) == metricNames else {
                throw ReleaseSignoffEvidenceAssemblyError.resultContractViolation(
                    "power-integrity result is missing required metrics for \(findingPrefix)"
                )
            }
            if metrics.contains(where: { $0.passed != true })
                || result.payload.findings.contains(where: { $0.code.hasPrefix(findingPrefix) }) {
                return false
            }
        }
        return true
    }

    private func executionEvaluation(
        _ status: LogicIR.LogicExecutionStatus,
        passed: Bool,
        failureReason: String
    ) -> Evaluation {
        switch status {
        case .completed:
            passed
                ? Evaluation(disposition: .passed, reason: nil)
                : Evaluation(disposition: .failed, reason: failureReason)
        case .failed:
            Evaluation(disposition: .failed, reason: failureReason)
        case .blocked, .cancelled:
            Evaluation(disposition: .blocked, reason: failureReason)
        }
    }

    private func executionEvaluation(
        _ status: RTLExecutionStatus,
        passed: Bool,
        failureReason: String
    ) -> Evaluation {
        switch status {
        case .completed:
            passed
                ? Evaluation(disposition: .passed, reason: nil)
                : Evaluation(disposition: .failed, reason: failureReason)
        case .failed:
            Evaluation(disposition: .failed, reason: failureReason)
        case .blocked, .cancelled:
            Evaluation(disposition: .blocked, reason: failureReason)
        }
    }

    private func executionEvaluation(
        _ status: DFTExecutionStatus,
        passed: Bool,
        failureReason: String
    ) -> Evaluation {
        switch status {
        case .completed:
            passed
                ? Evaluation(disposition: .passed, reason: nil)
                : Evaluation(disposition: .failed, reason: failureReason)
        case .failed:
            Evaluation(disposition: .failed, reason: failureReason)
        case .blocked, .cancelled:
            Evaluation(disposition: .blocked, reason: failureReason)
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ReleaseSignoffEvidenceAssemblyError.invalidArtifact(
                "could not decode \(String(describing: type)): \(error.localizedDescription)"
            )
        }
    }

    private func requireRunID(_ actual: String, expected: String) throws {
        guard actual == expected else {
            throw ReleaseSignoffEvidenceAssemblyError.resultIdentityMismatch(
                "expected run \(expected), found \(actual)"
            )
        }
    }

    private func verify(
        _ references: [ArtifactReference],
        reading artifacts: any FlowArtifactPersisting
    ) async throws {
        for reference in Set(references) {
            _ = try await artifacts.loadArtifactContent(for: reference)
        }
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func evidenceID(
        runID: String,
        source: ReleaseSignoffEvidenceSource,
        qualificationID: String
    ) -> String {
        "\(runID).\(source.axis.rawValue).\(source.resultArtifact.id.rawValue).\(qualificationID)"
    }
}

private extension DefaultReleaseSignoffEvidenceAssembler {
    struct DFTArtifactReader: DFTArtifactReading {
        let persistence: any FlowArtifactPersisting

        func data(for reference: ArtifactReference) async throws -> Data {
            try await persistence.loadArtifactContent(for: reference)
        }
    }

    struct EvaluatedEvidence: Sendable, Hashable {
        var evaluation: Evaluation
        var provenance: ExecutionProvenance
    }

    struct Evaluation: Sendable, Hashable {
        var disposition: SignoffEvidenceDisposition
        var reason: String?
    }

    struct QualificationArtifactReader: ToolQualificationArtifactReading {
        let persistence: any FlowArtifactPersisting

        func verifiedData(for reference: ArtifactReference) async throws -> Data {
            try await persistence.loadArtifactContent(for: reference)
        }
    }
}
