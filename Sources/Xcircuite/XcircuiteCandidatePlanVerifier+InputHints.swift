import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func stringHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> String? {
        guard case .text(let value) = step.parameterHints[key] else {
            return nil
        }
        return value
    }

    func stringArrayHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> [String]? {
        guard case .textList(let values) = step.parameterHints[key] else {
            return nil
        }
        let strings = values
        return strings.isEmpty ? nil : strings
    }

    func intHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> Int? {
        guard case .scalar(let value) = step.parameterHints[key] else {
            return nil
        }
        guard value.rounded(.towardZero) == value else {
            return nil
        }
        return Int(value)
    }

    func boolHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> Bool? {
        guard case .boolean(let value) = step.parameterHints[key] else {
            return nil
        }
        return value
    }

}
