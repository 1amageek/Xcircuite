import Foundation

public struct OpAmpSizedDevice: Sendable, Hashable, Codable {
    public enum DeviceKind: String, Sendable, Hashable, Codable {
        case nmos
        case pmos
        case capacitor
        case resistor
        case currentSource
    }

    public var instanceName: String
    public var role: String
    public var deviceKind: DeviceKind
    public var modelName: String?
    public var width: Double?
    public var length: Double?
    public var fingers: Int
    public var multiplier: Int
    public var value: Double?
    public var unit: String?
    public var drainCurrent: Double?
    public var transconductance: Double?
    public var outputResistance: Double?
    public var overdriveVoltage: Double?

    public init(
        instanceName: String,
        role: String,
        deviceKind: DeviceKind,
        modelName: String? = nil,
        width: Double? = nil,
        length: Double? = nil,
        fingers: Int = 1,
        multiplier: Int = 1,
        value: Double? = nil,
        unit: String? = nil,
        drainCurrent: Double? = nil,
        transconductance: Double? = nil,
        outputResistance: Double? = nil,
        overdriveVoltage: Double? = nil
    ) {
        self.instanceName = instanceName
        self.role = role
        self.deviceKind = deviceKind
        self.modelName = modelName
        self.width = width
        self.length = length
        self.fingers = fingers
        self.multiplier = multiplier
        self.value = value
        self.unit = unit
        self.drainCurrent = drainCurrent
        self.transconductance = transconductance
        self.outputResistance = outputResistance
        self.overdriveVoltage = overdriveVoltage
    }
}
