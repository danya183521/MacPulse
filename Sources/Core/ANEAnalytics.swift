import Foundation
import Combine

struct ANEHistoryPoint: Identifiable, Equatable {
    let date: Date
    let power: Double?
    var id: Date { date }
}

enum ANEActivityState: Equatable {
    case unavailable, idle, active

    var titleKey: String {
        switch self {
        case .unavailable: "Unavailable"
        case .idle: "Idle"
        case .active: "Active"
        }
    }
}

enum ANEMath {
    static let activePowerThreshold = 0.05

    static func validPower(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value < 1000 else { return nil }
        return value
    }

    static func state(power: Double?) -> ANEActivityState {
        guard let power = validPower(power) else { return .unavailable }
        return power >= activePowerThreshold ? .active : .idle
    }

    static func average(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite && $0 >= 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    static func peak(_ values: [Double]) -> Double? {
        values.filter { $0.isFinite && $0 >= 0 }.max()
    }
}

@MainActor final class ANEIntelligence: ObservableObject {
    @Published private(set) var power: Double?
    @Published private(set) var state: ANEActivityState = .unavailable
    @Published private(set) var recentAverage: Double?
    @Published private(set) var peak: Double?
    @Published private(set) var history: [ANEHistoryPoint] = []

    private let historyLimit: Int

    init(historyLimit: Int = 900) {
        self.historyLimit = max(1, historyLimit)
    }

    func ingest(_ snapshot: Snapshot) {
        let value = ANEMath.validPower(snapshot[.anePower])
        let date = snapshot.date
        history.append(ANEHistoryPoint(date: date, power: value))
        history.removeAll { $0.date < date.addingTimeInterval(-30 * 60) }
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }

        power = value
        state = ANEMath.state(power: value)
        let recent = history.suffix(150).compactMap(\.power)
        recentAverage = ANEMath.average(Array(recent))
        peak = ANEMath.peak(history.compactMap(\.power))
    }
}
