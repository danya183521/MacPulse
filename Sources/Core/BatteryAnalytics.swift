import Foundation
import SwiftUI

struct BatteryHistoryPoint: Identifiable, Equatable {
    let date: Date
    let level: Double?
    let power: Double?
    let temperature: Double?
    let chargeRate: Double?
    var id: Date { date }
}

enum BatteryDisplayState: String {
    case charging, discharging, fullyCharged, notCharging, unavailable
    var titleKey: String {
        switch self {
        case .charging: "status.charging"
        case .discharging: "status.discharging"
        case .fullyCharged: "status.fullyCharged"
        case .notCharging: "status.notCharging"
        case .unavailable: "Unavailable"
        }
    }
}

enum BatteryInsight: Equatable {
    case normal, highEnergyUsage, batteryHot, charging, fullyCharged, calculating
    var titleKey: String {
        switch self {
        case .normal: "Normal"
        case .highEnergyUsage: "High Energy Usage"
        case .batteryHot: "Battery Hot"
        case .charging: "Charging"
        case .fullyCharged: "Fully Charged"
        case .calculating: "Calculating…"
        }
    }
    var detailKey: String {
        switch self {
        case .normal: "Battery usage is within the recent range."
        case .highEnergyUsage: "Power use is well above this session's recent baseline."
        case .batteryHot: "Battery temperature is elevated."
        case .charging: "The battery is receiving charge from the adapter."
        case .fullyCharged: "The battery is full and connected to power."
        case .calculating: "More samples are needed for a stable estimate."
        }
    }
}

enum BatteryMath {
    static func capacityHealth(fullCharge: Double?, design: Double?) -> Double? {
        guard let fullCharge, let design, fullCharge.isFinite, design.isFinite, fullCharge > 0, design > 0 else { return nil }
        return min(100, max(0, fullCharge / design * 100))
    }

    static func watts(voltage: Double?, current: Double?) -> Double? {
        guard let voltage, let current, voltage.isFinite, current.isFinite, voltage > 0 else { return nil }
        let value = voltage * current
        return value.isFinite ? value : nil
    }

    static func percentRatePerHour(oldLevel: Double?, newLevel: Double?, elapsed: TimeInterval) -> Double? {
        guard let oldLevel, let newLevel, oldLevel.isFinite, newLevel.isFinite, elapsed >= 10 else { return nil }
        let value = (newLevel - oldLevel) / elapsed * 3600
        return value.isFinite && abs(value) <= 1000 ? value : nil
    }

    static func smooth(previous: Double?, next: Double, alpha: Double = 0.2) -> Double {
        guard let previous, previous.isFinite else { return next }
        let clamped = min(1, max(0.01, alpha))
        return previous + (next - previous) * clamped
    }

    static func average(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    static func remainingHours(availableCapacityMilliampHours: Double?, voltage: Double?, powerWatts: Double?) -> Double? {
        guard let capacity = availableCapacityMilliampHours, let voltage, let powerWatts,
              capacity > 0, voltage > 0, powerWatts < -0.5,
              capacity.isFinite, voltage.isFinite, powerWatts.isFinite else { return nil }
        let hours = capacity * voltage / 1000 / abs(powerWatts)
        guard hours.isFinite, hours > 0 else { return nil }
        return min(24, max(0.1, hours))
    }

    static func timeToFullHours(level: Double?, chargeRatePercentPerHour: Double?) -> Double? {
        guard let level, let chargeRatePercentPerHour, level.isFinite, chargeRatePercentPerHour.isFinite,
              chargeRatePercentPerHour > 0.25, level < 100 else { return nil }
        let hours = (100 - level) / chargeRatePercentPerHour
        guard hours.isFinite, hours > 0 else { return nil }
        return min(12, max(0.05, hours))
    }

    static func highEnergy(powerWatts: Double?, baselineWatts: Double?, sustainedSamples: Int) -> Bool {
        guard let powerWatts, let baselineWatts, powerWatts.isFinite, baselineWatts.isFinite,
              powerWatts < -0.5, baselineWatts >= 2, sustainedSamples >= 3 else { return false }
        return abs(powerWatts) >= max(8, baselineWatts * 1.75)
    }
}

@MainActor final class BatteryIntelligence: ObservableObject {
    @Published private(set) var state: BatteryDisplayState = .unavailable
    @Published private(set) var level: Double?
    @Published private(set) var health: Double?
    @Published private(set) var designCapacity: Double?
    @Published private(set) var fullChargeCapacity: Double?
    @Published private(set) var currentCapacity: Double?
    @Published private(set) var cycles: Double?
    @Published private(set) var temperature: Double?
    @Published private(set) var voltage: Double?
    @Published private(set) var current: Double?
    @Published private(set) var power: Double?
    @Published private(set) var adapterRatedPower: Double?
    @Published private(set) var adapterVoltage: Double?
    @Published private(set) var adapterCurrent: Double?
    @Published private(set) var adapterInputPower: Double?
    @Published private(set) var chargeRate: Double?
    @Published private(set) var estimatedRemainingHours: Double?
    @Published private(set) var timeToFullHours: Double?
    @Published private(set) var insight: BatteryInsight = .calculating
    @Published private(set) var history: [BatteryHistoryPoint] = []

    private let historyLimit: Int
    private var smoothedRate: Double?
    private var highEnergySamples = 0

    init(historyLimit: Int = 5400) { self.historyLimit = historyLimit }

    func ingest(_ snapshot: Snapshot) {
        let date = snapshot.date
        let oldLevel = history.last?.level
        let oldDate = history.last?.date
        let level = nonNegative(snapshot[.battery])
        let power = finite(snapshot[.batteryPower])
        let temperature = nonNegative(snapshot[.batteryTemperature])
        let voltage = nonNegative(snapshot[.voltage])
        let current = finite(snapshot[.amperage])
        let rawRate = BatteryMath.percentRatePerHour(oldLevel: oldLevel, newLevel: level, elapsed: oldDate.map { date.timeIntervalSince($0) } ?? 0)
        if let rawRate { smoothedRate = BatteryMath.smooth(previous: smoothedRate, next: rawRate) }
        let rate = smoothedRate
        let point = BatteryHistoryPoint(date: date, level: level, power: power, temperature: temperature, chargeRate: rate)
        history.append(point)
        history.removeAll { $0.date < date.addingTimeInterval(-3 * 60 * 60) }
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }

        self.level = level
        self.power = power
        self.temperature = temperature
        self.voltage = voltage
        self.current = current
        self.designCapacity = nonNegative(snapshot.values["designCapacity"])
        self.fullChargeCapacity = nonNegative(snapshot.values["maxCapacity"])
        self.currentCapacity = nonNegative(snapshot.values["currentCapacity"])
        self.cycles = nonNegative(snapshot.values["cycles"])
        self.health = BatteryMath.capacityHealth(fullCharge: fullChargeCapacity, design: designCapacity)
        self.adapterRatedPower = nonNegative(snapshot.values["adapterRatedPower"])
        self.adapterVoltage = nonNegative(snapshot.values["adapterVoltage"])
        self.adapterCurrent = nonNegative(snapshot.values["adapterCurrent"])
        self.adapterInputPower = nonNegative(snapshot.values["adapterInputPower"])
        self.chargeRate = rate
        self.state = state(for: snapshot, level: level)
        self.estimatedRemainingHours = self.state == .discharging
            ? BatteryMath.remainingHours(availableCapacityMilliampHours: currentCapacity, voltage: voltage, powerWatts: power)
            : nil
        self.timeToFullHours = self.state == .charging
            ? BatteryMath.timeToFullHours(level: level, chargeRatePercentPerHour: rate)
                ?? nonNegative(snapshot.values["systemTimeRemainingMinutes"]).map { min(12, max(0.05, $0 / 60)) }
            : nil
        let baselineValues = history.dropLast().filter { $0.date >= date.addingTimeInterval(-5 * 60) }.suffix(150).compactMap { $0.power }.map(abs)
        let baseline = BatteryMath.average(Array(baselineValues))
        if BatteryMath.highEnergy(powerWatts: power, baselineWatts: baseline, sustainedSamples: highEnergySamples + 1) {
            highEnergySamples += 1
        } else if !((power ?? 0) < -0.5) {
            highEnergySamples = 0
        }
        if let power, BatteryMath.highEnergy(powerWatts: power, baselineWatts: baseline, sustainedSamples: highEnergySamples) {
            _ = power
            insight = temperature.map { $0 >= 40 } == true ? .batteryHot : .highEnergyUsage
        } else if temperature.map({ $0 >= 40 }) == true {
            insight = .batteryHot
        } else {
            switch state {
            case .fullyCharged: insight = .fullyCharged
            case .charging: insight = .charging
            case .discharging, .notCharging: insight = rate == nil ? .calculating : .normal
            case .unavailable: insight = .calculating
            }
        }
    }

    private func state(for snapshot: Snapshot, level: Double?) -> BatteryDisplayState {
        let external = snapshot.values["externalPower"] == 1
        let charging = snapshot.values["charging"] == 1
        let full = snapshot.values["fullyCharged"] == 1 || (external && (level ?? 0) >= 99 && !charging)
        if full { return .fullyCharged }
        if charging { return .charging }
        if external { return .notCharging }
        if level != nil { return .discharging }
        return .unavailable
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func nonNegative(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }
}
