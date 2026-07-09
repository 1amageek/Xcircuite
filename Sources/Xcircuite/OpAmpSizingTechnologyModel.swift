import Foundation

public struct OpAmpSizingTechnologyModel: Sendable, Hashable, Codable {
    public var modelID: String
    public var nmosModelName: String
    public var pmosModelName: String
    public var minimumLength: Double
    public var minimumWidth: Double
    public var maximumWidth: Double
    public var nmosMobilityCox: Double
    public var pmosMobilityCox: Double
    public var nmosLambda: Double
    public var pmosLambda: Double
    public var nominalNmosThreshold: Double
    public var nominalPmosThreshold: Double
    public var defaultInputGMOverID: Double
    public var defaultOutputGMOverID: Double
    public var defaultBiasGMOverID: Double
    public var maximumDeviceCurrent: Double

    public init(
        modelID: String,
        nmosModelName: String = "nmos_l1",
        pmosModelName: String = "pmos_l1",
        minimumLength: Double,
        minimumWidth: Double,
        maximumWidth: Double,
        nmosMobilityCox: Double,
        pmosMobilityCox: Double,
        nmosLambda: Double,
        pmosLambda: Double,
        nominalNmosThreshold: Double,
        nominalPmosThreshold: Double,
        defaultInputGMOverID: Double,
        defaultOutputGMOverID: Double,
        defaultBiasGMOverID: Double,
        maximumDeviceCurrent: Double
    ) {
        self.modelID = modelID
        self.nmosModelName = nmosModelName
        self.pmosModelName = pmosModelName
        self.minimumLength = minimumLength
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.nmosMobilityCox = nmosMobilityCox
        self.pmosMobilityCox = pmosMobilityCox
        self.nmosLambda = nmosLambda
        self.pmosLambda = pmosLambda
        self.nominalNmosThreshold = nominalNmosThreshold
        self.nominalPmosThreshold = nominalPmosThreshold
        self.defaultInputGMOverID = defaultInputGMOverID
        self.defaultOutputGMOverID = defaultOutputGMOverID
        self.defaultBiasGMOverID = defaultBiasGMOverID
        self.maximumDeviceCurrent = maximumDeviceCurrent
    }

    public static func genericCMOS180() -> OpAmpSizingTechnologyModel {
        OpAmpSizingTechnologyModel(
            modelID: "generic-cmos-180nm",
            minimumLength: 0.18e-6,
            minimumWidth: 0.24e-6,
            maximumWidth: 500e-6,
            nmosMobilityCox: 220e-6,
            pmosMobilityCox: 90e-6,
            nmosLambda: 0.08,
            pmosLambda: 0.1,
            nominalNmosThreshold: 0.45,
            nominalPmosThreshold: -0.45,
            defaultInputGMOverID: 16,
            defaultOutputGMOverID: 10,
            defaultBiasGMOverID: 12,
            maximumDeviceCurrent: 2.0e-3
        )
    }
}
