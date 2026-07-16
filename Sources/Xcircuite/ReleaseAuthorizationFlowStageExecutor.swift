import CircuiteFoundation
import DesignFlowKernel
import Foundation
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
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(
                ReleaseAuthorizationRequest.self,
                from: Data(contentsOf: requestURL)
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

            let result = try await authorizerFactory(context.projectRoot).execute(request)
            try await context.checkCancellation()
            let resultArtifact = try await support.persistResult(
                result,
                stageID: stageID,
                artifactID: "release-authorization-result",
                context: context
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
                artifacts: [resultArtifact] + result.artifacts
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
