import Foundation

// Единый каталог задаёт формат, источник и смысл каждой метрики.
enum Metric: String, CaseIterable, Codable, Identifiable {
    case cpu, cpuTemperature, cpuPower, gpu, gpuTemperature, gpuPower, gpuMemory
    case memory, memoryUsed, memoryAvailable, memoryTotal, wired, compressed, cached, swap, swapTotal
    case battery, batteryHealth, cycles, batteryTemperature, voltage, amperage, batteryPower, designCapacity, currentCapacity, maxCapacity
    case anePower, computePower, systemPower, packagePower, download, upload, wifiSignal, wifiNoise, wifiLink
    case storage, storageTotal, storageUsed, storageAvailable, diskRead, diskWrite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"; case .cpuTemperature: "CPU temperature"; case .cpuPower: "CPU power"
        case .gpu: "GPU"; case .gpuTemperature: "GPU temperature"; case .gpuPower: "GPU power"; case .gpuMemory: "GPU memory in use"
        case .memory: "Memory"; case .memoryUsed: "Used memory"; case .memoryAvailable: "Available memory"; case .memoryTotal: "Physical memory"
        case .wired: "Wired"; case .compressed: "Compressed"; case .cached: "Cached files"; case .swap: "Swap used"; case .swapTotal: "Swap allocated"
        case .battery: "Battery"; case .batteryHealth: "Capacity health"; case .cycles: "Charge cycles"; case .batteryTemperature: "Battery temperature"
        case .voltage: "Voltage"; case .amperage: "Current"; case .batteryPower: "Battery power"; case .designCapacity: "Design capacity"; case .currentCapacity: "Current capacity"; case .maxCapacity: "Full charge capacity"
        case .systemPower: "System power · SMC"; case .packagePower: "SMC PHPC power"; case .anePower: "Neural Engine power"; case .computePower: "CPU + GPU + ANE"
        case .download: "Download"; case .upload: "Upload"; case .wifiSignal: "Wi-Fi signal"; case .wifiNoise: "Wi-Fi noise"; case .wifiLink: "Wi-Fi transmit link"
        case .storage: "Storage"; case .storageTotal: "Total capacity"; case .storageUsed: "Used storage"; case .storageAvailable: "Free storage"; case .diskRead: "Disk read"; case .diskWrite: "Disk write"
        }
    }
    var symbol: String {
        switch self {
        case .cpu, .cpuPower: "cpu"
        case .cpuTemperature, .gpuTemperature, .batteryTemperature: "thermometer.medium"
        case .gpu, .gpuMemory, .gpuPower: "square.3.layers.3d"
        case .memory, .memoryUsed, .memoryAvailable, .memoryTotal, .wired, .compressed, .cached, .swap, .swapTotal: "memorychip"
        case .battery, .batteryHealth, .cycles, .designCapacity, .currentCapacity, .maxCapacity: "battery.75percent"
        case .anePower, .computePower, .systemPower, .packagePower, .batteryPower, .voltage, .amperage: "bolt"
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
        case .voltage: "V"; case .amperage: "A"; case .cycles: "cycles"
        case .designCapacity, .currentCapacity, .maxCapacity: "mAh"
        default: "bytes"
        }
    }
    var source: String {
        switch self {
        case .systemPower, .packagePower: "AppleSMC read-only float keys PSTR / PHPC • private ABI • experimental rail mapping"
        case .battery: "IOKit public Power Sources API • AppleSmartBattery fallback"
        case .cpu: "Mach host_processor_info • tick deltas"
        case .cpuTemperature, .gpuTemperature: "IOHID temperature events • private API • mean of named CPU/GPU sensors"
        case .cpuPower, .gpuPower, .anePower, .computePower: "IOReport Energy Model / PMP • private API • energy delta / elapsed time"
        case .gpu, .gpuMemory: "IOKit IOAccelerator • undocumented PerformanceStatistics"
        case .memory, .memoryUsed, .memoryAvailable, .memoryTotal, .wired, .compressed, .cached: "Mach host_statistics64 • VM pages × page size"
        case .swap, .swapTotal: "sysctl vm.swapusage"
        case .download, .upload: "sysctl IFMIB_IFDATA / IFDATA_GENERAL • primary-interface 64-bit byte-counter deltas"
        case .wifiSignal, .wifiNoise, .wifiLink: "CoreWLAN • link information"
        case .storage, .storageTotal, .storageUsed, .storageAvailable: "Foundation volume capacity • home volume • excludes purgeable space"
        case .diskRead, .diskWrite: "IOKit IOBlockStorageDriver • all physical drive byte-counter deltas"
        default: "IOKit AppleSmartBattery • undocumented registry properties"
        }
    }
    var menuPrefix: String {
        switch self { case .cpu: "CPU"; case .gpu: "GPU"; case .memory: "RAM"; case .download: "↓"; case .upload: "↑"; case .battery: "BAT"; case .cpuTemperature: ""; case .cpuPower: "CPU"; case .systemPower: "SYS"; case .anePower: "ANE"; case .computePower: "Σ"; default: title }
    }
    func format(_ value: Double?, compact: Bool = false) -> String {
        guard let v = value, v.isFinite else { return "—" }
        if unit == "bytes" { return ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .binary) }
        if unit == "B/s" {
            let divisor: Double = v >= 1_000_000_000 ? 1e9 : v >= 1_000_000 ? 1e6 : v >= 1_000 ? 1e3 : 1
            let suffix = divisor == 1e9 ? "G" : divisor == 1e6 ? "M" : divisor == 1e3 ? "K" : "B"
            let n = v / divisor
            let text = String(format: n < 10 && divisor > 1 ? "%.1f" : "%.0f", n)
            return compact ? text + suffix : text + " " + suffix + (divisor == 1 ? "/s" : "B/s")
        }
        let decimals = ["W", "V", "A"].contains(unit) ? (unit == "A" ? 2 : 1) : 0
        let number = String(format: "%.*f", decimals, v)
        if unit == "%" || unit == "°C" { return number + unit }
        return number + (compact ? "" : " ") + unit
    }
    static let menuChoices: [Metric] = [.cpu, .cpuTemperature, .gpu, .memory, .battery, .download, .upload, .cpuPower, .gpuPower, .batteryPower, .systemPower, .anePower, .computePower, .storage]
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
        case .cpuTemperature, .gpuTemperature: info["thermalReason"] ?? "Temperature service has no valid reading"
        case .cpuPower, .gpuPower, .anePower, .computePower: info["powerReason"] ?? "Energy channel or supported unit is absent"
        case .download, .upload: "Waiting for two samples on the active network interface"
        case .gpu, .gpuMemory: "IOAccelerator does not expose this statistic"
        case .wifiSignal, .wifiNoise, .wifiLink: "Wi-Fi is off, disconnected or access is restricted"
        case .cpu, .diskRead, .diskWrite: "Waiting for counter deltas, or counters are unavailable"
        default: "This system source does not expose the requested value"
        }
    }
    var thermalLabel: String {
        switch Int(values["thermalState"] ?? -1) { case 0: "Nominal"; case 1: "Fair"; case 2: "Serious"; case 3: "Critical"; default: "Unavailable" }
    }
    var pressureLabel: String {
        switch Int(values["pressure"] ?? -1) { case 1: "Normal"; case 2: "Warning"; case 4: "Critical"; default: "Unavailable" }
    }
    var batteryState: String {
        guard let charging = values["charging"], let external = values["externalPower"] else { return "Unavailable" }
        return charging == 1 ? "Charging" : external == 1 ? "On external power" : "Discharging"
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
