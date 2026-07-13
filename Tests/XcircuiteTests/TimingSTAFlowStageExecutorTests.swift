import STAEngine
import Foundation
import Testing
import Xcircuite

@Suite("Timing STA flow adapter")
struct TimingSTAFlowStageExecutorTests {
    @Test("adapter configuration is Codable and targets the timing stage")
    func configurationRoundTrip() throws {
        let inputs = TimingSTAFlowInputs(
            design: .path("design.json"),
            libraries: [.path("library.lib")],
            constraints: .path("constraints.sdc"),
            pdkManifest: .path("pdk.json"),
            topDesignName: "top",
            processID: "test-process",
            pdkVersion: "1",
            pdkDigest: "digest",
            modeIDs: ["functional"],
            cornerIDs: ["typical"],
            analysisKinds: [.setup, .hold]
        )
        let encoded = try Foundation.JSONEncoder().encode(inputs)
        let decoded = try Foundation.JSONDecoder().decode(TimingSTAFlowInputs.self, from: encoded)
        let executor = TimingSTAFlowStageExecutor(inputs: decoded)
        #expect(executor.stageID == "timing.sta")
        #expect(executor.toolID == "native-sta")
        #expect(decoded.modeIDs == ["functional"])
        #expect(decoded.cornerIDs == ["typical"])
    }
}
