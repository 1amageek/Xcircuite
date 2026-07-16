import Foundation
import PEXEngine

struct FixturePEXExtractor: PEXExtracting {
    let backendID = "test-fixture"
    let capabilities = PEXBackendCapabilities(
        supportsCouplingCaps: true,
        supportsCornerSweep: true,
        supportsIncremental: false,
        supportsRCReduction: false,
        nativeOutputFormats: [.spef]
    )

    func prepare(_ context: PEXExecutionContext) async throws {
        try FileManager.default.createDirectory(
            at: context.rawOutputDirectory,
            withIntermediateDirectories: true
        )
    }

    func execute(_ context: PEXExecutionContext) async throws -> PEXAdapterExecutionResult {
        let temperatureScale = 1 + ((context.corner.temperature ?? 25) - 25) * 0.003
        let capacitance = 0.05 * temperatureScale
        let resistance = 10 * temperatureScale
        let spef = """
        *SPEF "IEEE 1481-1998"
        *DESIGN "\(context.topCell)"
        *DATE "2026-01-01"
        *VENDOR "XcircuiteTests"
        *PROGRAM "FixturePEXExtractor"
        *VERSION "1.0"
        *DESIGN_FLOW "EXTERNAL"
        *DIVIDER /
        *DELIMITER :
        *BUS_DELIMITER [ ]
        *T_UNIT 1 NS
        *C_UNIT 1 PF
        *R_UNIT 1 OHM
        *L_UNIT 1 HENRY

        *NAME_MAP
        *1 VDD
        *2 VSS

        *PORTS
        VDD I
        VSS O

        *D_NET VDD \(capacitance)
        *CONN
        *I \(context.topCell):VDD I
        *CAP
        1 VDD:1 \(capacitance)
        *RES
        1 VDD:1 VDD:2 \(resistance)
        *END

        *D_NET VSS \(capacitance * 2)
        *CONN
        *I \(context.topCell):VSS O
        *CAP
        1 VSS:1 \(capacitance * 2)
        *RES
        1 VSS:1 VSS:2 \(resistance * 2)
        *END
        """
        let outputURL = context.rawOutputDirectory.appending(path: "\(context.corner.id.value).spef")
        try Data(spef.utf8).write(to: outputURL, options: .atomic)
        return PEXAdapterExecutionResult(
            rawOutput: PEXRawOutput(
                format: .spef,
                fileURLs: [outputURL],
                metadata: ["generator": backendID]
            ),
            generatedArtifacts: [
                PEXGeneratedArtifact(
                    kind: .rawOutput,
                    stage: .backendExecution,
                    cornerID: context.corner.id,
                    url: outputURL
                ),
            ]
        )
    }

    func cleanup(_ context: PEXExecutionContext) async {}
}

func makeFixturePEXEngine() -> DefaultPEXEngine {
    DefaultPEXEngine(
        adapterRegistry: PEXAdapterRegistry(adapters: [FixturePEXExtractor()]),
        parserRegistry: PEXDefaultParsers.makeRegistry()
    )
}
