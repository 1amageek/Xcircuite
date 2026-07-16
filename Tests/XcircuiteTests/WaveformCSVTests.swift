import Testing
@testable import Xcircuite

@Suite("Waveform CSV parser", .timeLimit(.minutes(1)))
struct WaveformCSVTests {
    @Test func parserRejectsEmptySweepHeader() async throws {
        #expect(throws: WaveformCSVError.invalidCSV("golden waveform sweep variable name is empty.")) {
            _ = try WaveformCSV.parse(",V(out)\n0,1\n", label: "golden")
        }
    }

    @Test func parserRejectsEmptyVariableHeader() async throws {
        #expect(throws: WaveformCSVError.invalidCSV("golden waveform contains an empty variable name.")) {
            _ = try WaveformCSV.parse("time,\n0,1\n", label: "golden")
        }
    }

    @Test func parserRejectsCanonicalDuplicateVariableHeaders() async throws {
        #expect(throws: WaveformCSVError.invalidCSV(
            "candidate waveform contains duplicate variable v(out) after normalization."
        )) {
            _ = try WaveformCSV.parse("time,V(out),v(out)\n0,1,1\n", label: "candidate")
        }
    }

    @Test func parserRejectsDecreasingSweepValuesWithDataLineNumber() async throws {
        #expect(throws: WaveformCSVError.invalidCSV(
            "candidate waveform sweep values must be monotonic at row 3."
        )) {
            _ = try WaveformCSV.parse("time,V(out)\n1,1\n0,0\n", label: "candidate")
        }
    }

    @Test func parserNormalizesUnitDecoratedHeadersAndTrimsNumericFields() async throws {
        let waveform = try WaveformCSV.parse("time [s],V(out) [V]\n 0 , 1 \n", label: "candidate")

        #expect(waveform.sweepName == "time")
        #expect(waveform.variableNames == ["V(out)"])
        #expect(waveform.sweepValues == [0])
        #expect(waveform.series(named: "V(out)") == [1])
    }
}
