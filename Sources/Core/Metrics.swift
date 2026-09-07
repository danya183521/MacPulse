import Foundation

// Единый каталог задаёт формат, источник и смысл каждой метрики.
enum Metric: String, CaseIterable, Codable, Identifiable {
    case cpu, cpuTemperature, cpuPower, gpu, gpuTemperature, gpuPower, gpuMemory
    case memory, memoryUsed, memoryAvailable, memoryTotal, wired, compressed, cached, swap, swapTotal
    case battery, batteryHealth, cycles, batteryTemperature, voltage, amperage, batteryPower, estimatedRemaining, designCapacity, currentCapacity, maxCapacity
    case anePower, computePower, systemPower, packagePower, download, upload, wifiSignal, wifiNoise, wifiLink
    case storage, storageTotal, storageUsed, storageAvailable, diskRead, diskWrite
    var id: String { rawValue }
    var title: String {
        L10n.text("metric.\(rawValue)")
    }
    var symbol: String {
        switch self {
        case .cpu, .cpuPower: "cpu"
        case .cpuTemperature, .gpuTemperature, .batteryTemperature: "thermometer.medium"
        case .gpu, .gpuMemory, .gpuPower: "square.3.layers.3d"
        case .memory, .memoryUsed, .memoryAvailable, .memoryTotal, .wired, .compressed, .cached, .swap, .swapTotal: "memorychip"
        case .battery, .batteryHealth, .cycles, .designCapacity, .currentCapacity, .maxCapacity: "battery.75percent"
        case .anePower, .computePower, .systemPower, .packagePower, .batteryPower, .voltage, .amperage: "bolt"
        case .estimatedRemaining: "hourglass"
        case .download: "arrow.down"; case .upload: "arrow.up"
        case .wifiSignal, .wifiNoise, .wifiLink: "wifi"
        default: "internaldrive"
        }
    }
    var unit: String {
        switch self {
        case .cpu, .gpu, .memory, .battery, .batteryHealth, .storage: "%"
        case .cpuTemperature, .gpuTemperature, .batteryTemperature: "°C"
        case .cpuPower, .gpuPower, .anePower, .computePower, .systemPower, .packagePower, .batteryPower: "W"
        case .download, .upload, .diskRead, .diskWrite: "B/s"
        case .wifiSignal, .wifiNoise: "dBm"; case .wifiLink: "Mbps"
        case .voltage: "V"; case .amperage: "A"; case .estimatedRemaining: "h"; case .cycles: "cycles"
        case .designCapacity, .currentCapacity, .maxCapacity: "mAh"
        default: "bytes"
        }
    }
    var source: String {
        L10n.text("source.\(sourceKey)")
    }
    private var sourceKey: String {
        switch self {
        case .systemPower, .packagePower: "smc"
        case .battery: "battery"
        case .cpu: "cpu"
        case .cpuTemperature, .gpuTemperature: "temperature"
        case .cpuPower, .gpuPower, .anePower, .computePower: "ioreport"
        case .gpu, .gpuMemory: "gpu"
        case .memory, .memoryUsed, .memoryAvailable, .memoryTotal, .wired, .compressed, .cached: "memory"
        case .swap, .swapTotal: "swap"
        case .download, .upload: "network"
        case .wifiSignal, .wifiNoise, .wifiLink: "wifi"
        case .storage, .storageTotal, .storageUsed, .storageAvailable: "storage"
        case .diskRead, .diskWrite: "disk"
        default: "batteryDetails"
        }
    }
    var menuPrefix: String {
        switch self {
        case .cpu, .cpuPower: "CPU"
        case .gpu, .gpuPower, .gpuMemory: "GPU"
        case .memory: "RAM"
        case .download: "↓"
        case .upload: "↑"
        case .battery, .batteryPower, .batteryHealth, .estimatedRemaining: "BAT"
        case .cpuTemperature: ""
        case .systemPower: "SYS"
        case .anePower: "ANE"
        case .computePower: "Σ"
        case .storage: "SSD"
        default: ""
        }
    }
    func format(_ value: Double?, compact: Bool = false) -> String {
        guard let v = value, v.isFinite else { return "—" }
        if unit == "bytes" { return ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .binary) }
        if unit == "B/s" {
            let divisor: Double = v >= 1_000_000_000 ? 1e9 : v >= 1_000_000 ? 1e6 : v >= 1_000 ? 1e3 : 1
            let suffix = divisor == 1e9 ? "G" : divisor == 1e6 ? "M" : divisor == 1e3 ? "K" : "B"
            let n = v / divisor
            let text = String(format: n < 10 && divisor > 1 ? "%.1f" : "%.0f", locale: Locale.current, n)
            return compact ? text + suffix : text + " " + suffix + (divisor == 1 ? "/s" : "B/s")
        }
        let decimals = ["W", "V", "A"].contains(unit) ? (unit == "A" ? 2 : 1) : 0
        let number = String(format: "%.*f", locale: Locale.current, decimals, v)
        if unit == "%" || unit == "°C" { return number + unit }
        return number + (compact ? "" : " ") + unit
    }
    static let menuChoices: [Metric] = [.cpu, .cpuTemperature, .gpu, .memory, .battery, .batteryTemperature, .download, .upload, .cpuPower, .gpuPower, .batteryPower, .estimatedRemaining, .systemPower, .anePower, .computePower, .storage]
}

struct Volume: Codable, Identifiable { var name: String; var total: Double; var available: Double; var id: String { name } }
struct Snapshot: Codable {
    var date = Date()
    var values: [String: Double] = [:]
    var info: [String: String] = [:]
    var cores: [Double] = []
    var sensors: [String: Double] = [:]
    var energyChannels: [String: Double] = [:]
    var volumes: [Volume] = []
    subscript(_ metric: Metric) -> Double? { values[metric.rawValue] }
    func reason(for metric: Metric) -> String {
        switch metric {
        case .cpuTemperature, .gpuTemperature: L10n.text("reason.temperature")
        case .cpuPower, .gpuPower, .anePower, .computePower: L10n.text("reason.power")
        case .download, .upload: L10n.text("reason.network")
        case .gpu, .gpuMemory: L10n.text("reason.gpu")
        case .wifiSignal, .wifiNoise, .wifiLink: L10n.text("reason.wifi")
        case .cpu, .diskRead, .diskWrite: L10n.text("reason.counters")
        default: L10n.text("reason.source")
        }
    }
    var thermalLabel: String {
        switch Int(values["thermalState"] ?? -1) { case 0: L10n.text("status.nominal"); case 1: L10n.text("status.fair"); case 2: L10n.text("status.serious"); case 3: L10n.text("status.critical"); default: L10n.text("Unavailable") }
    }
    var pressureLabel: String {
        switch Int(values["pressure"] ?? -1) { case 1: L10n.text("status.normal"); case 2: L10n.text("status.warning"); case 4: L10n.text("status.critical"); default: L10n.text("Unavailable") }
    }
    var batteryState: String {
        guard let external = values["externalPower"] else { return L10n.text("Unavailable") }
        if values["fullyCharged"] == 1 || (external == 1 && values["battery"] ?? 0 >= 99 && values["charging"] != 1) { return L10n.text("status.fullyCharged") }
        if values["charging"] == 1 { return L10n.text("status.charging") }
        if external == 1 { return L10n.text("status.notCharging") }
        return L10n.text("status.discharging")
    }
}

struct HistoryPoint: Identifiable, Codable { var date: Date; var values: [String: Double]; var id: Date { date } }
struct HistoryStore {
    private(set) var points: [HistoryPoint] = []
    let limit: Int
    init(limit: Int = 900) { self.limit = limit }
    mutating func append(_ snapshot: Snapshot) {
        points.append(HistoryPoint(date: snapshot.date, values: snapshot.values))
        points.removeAll { $0.date < snapshot.date.addingTimeInterval(-1800) }
        if points.count > limit { points.removeFirst(points.count-limit) }
    }
}
