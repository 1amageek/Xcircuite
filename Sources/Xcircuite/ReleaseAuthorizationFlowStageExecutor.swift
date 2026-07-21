import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import ReleaseEngine
import ToolQualification

public struct ReleaseAuthorizationFlowStageExecutor: FlowStageExecutor {
    public typealias AuthorizerFactory = @Sendable (URL) throws -> any ReleaseAuthorizing

    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let authorizerFactory: AuthorizerFactory
    private let support: ReleaseStageExecutionSupport

    public init(
        stageID: String = "release.authorization",
        toolID: String = "native-release-authorization",
        requestInput: XcircuiteFlowInputReference,
        authorizerFactory: @escaping AuthorizerFactory = Self.makeDefaultAuthorizer
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.authorizerFactory = authorizerFactory
        self.support = ReleaseStageExecutionSupport()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let requestData = try Data(contentsOf: requestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decodedRequest = try decoder.decode(
                ReleaseAuthorizationRequest.self,
                from: requestData
            )
            let projectRoot = try context.xcircuiteProjectRoot()
            if let requestedProjectRoot = decodedRequest.projectRoot,
               URL(fileURLWithPath: requestedProjectRoot).standardizedFileURL
                != projectRoot.standardizedFileURL {
                return support.failureResult(
                    stageID: stage.stageID,
                    code: "RELEASE_AUTHORIZATION_PROJECT_ROOT_MISMATCH",
                    message: "Release authorization request project root does not match the flow context."
                )
            }
            let request = ReleaseAuthorizationRequest(
                runID: decodedRequest.runID,
                stageID: decodedRequest.stageID,
                signoffBundle: decodedRequest.signoffBundle,
                approval: decodedRequest.approval,
                toolTrustDecisions: decodedRequest.toolTrustDecisions,
                toolQualificationRequests: decodedRequest.toolQualificationRequests,
                requiredToolIDs: decodedRequest.requiredToolIDs,
                evaluatedAt: decodedRequest.evaluatedAt,
                projectRoot: projectRoot.path
            )
            let requestArtifact = try await support.persistRequest(
                try support.encodeRequest(request),
                stageID: stageID,
                artifactID: "release-authorization-request",
                context: context
            )
            guard request.runID == context.runID else {
                return support.failureResult(
                    stageID: stage.stageID,
                    code: "RELEASE_AUTHORIZATION_RUN_ID_MISMATCH",
                    message: "Release authorization request run ID does not match the flow context."
                )
            }
            guard request.stageID == stage.stageID else {
                return support.failureResult(
                    stageID: stage.stageID,
                    code: "RELEASE_AUTHORIZATION_STAGE_ID_MISMATCH",
                    message: "Release authorization request stage ID does not match the flow stage."
                )
            }

            let engineResult = try await authorizerFactory(
                projectRoot
            ).execute(request)
            let result = ReleaseAuthorizationResult(
                status: engineResult.status,
                signoffBundle: engineResult.signoffBundle,
                approval: engineResult.approval,
                diagnostics: engineResult.diagnostics,
                provenance: try support.provenance(
                    engineResult.evidence.provenance,
                    retaining: requestArtifact
                )
            )
            try await context.checkCancellation()
            let resultArtifact = try await support.persistResult(
                result,
                stageID: stageID,
                artifactID: "release-authorization-result",
                context: context,
                producer: result.evidence.provenance.producer
            )
            let diagnostics = result.diagnostics.map(Self.flowDiagnostic)
            let authorized = result.status == .authorized
            let gateStatus: FlowGateStatus = authorized ? .passed : .blocked
            return FlowStageResult(
                stageID: stage.stageID,
                status: authorized ? .succeeded : .blocked,
                diagnostics: diagnostics,
                gates: [FlowGateResult(
                    gateID: "release-authorization",
                    status: gateStatus,
                    diagnostics: diagnostics
                )],
                artifacts: [requestArtifact, resultArtifact] + result.artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stage.stageID,
                code: "RELEASE_AUTHORIZATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    public static func makeDefaultAuthorizer(projectRoot: URL) throws -> any ReleaseAuthorizing {
        let qualificationEngine = DefaultToolQualificationEngine(
            artifactReader: LocalToolQualificationArtifactReader(workspaceRoot: projectRoot),
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "xcircuite.release-authorization",
                version: "1.0.0"
            )
        )
        return DefaultReleaseAuthorizer(
            qualificationEngine: qualificationEngine,
            artifactReader: LocalReleaseArtifactReader(workspaceRoot: projectRoot)
        )
    }

    private static func flowDiagnostic(_ diagnostic: DesignDiagnostic) -> FlowDiagnostic {
        let severity: FlowDiagnosticSeverity
        switch diagnostic.severity {
        case .information:
            severity = .info
        case .warning:
            severity = .warning
        case .error:
            severity = .error
        }
        return FlowDiagnostic(
            severity: severity,
            code: diagnostic.code.rawValue,
            message: diagnostic.detail ?? diagnostic.summary
        )
    }
}
