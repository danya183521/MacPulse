import AppKit
import Darwin
import Foundation

// Снимок процесса содержит только данные, полученные от публичных API macOS.
struct ProcessRecord: Identifiable, Equatable {
    let pid: Int32
    var name: String
    let executablePath: String?
    var bundleIdentifier: String?
    var isApplication: Bool
    var isUserProcess: Bool
    let parentPID: Int32
    let startDate: Date?
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let energyScore: Double?
    let networkDownload: Double?
    let networkUpload: Double?
    let diskReadRate: Double?
    let diskWriteRate: Double?
    let diskReadBytes: UInt64?
    let diskWriteBytes: UInt64?
    let threadCount: Int?
    let processState: String?

    var id: Int32 { pid }
    var networkTotalRate: Double? {
        guard let download = networkDownload, let upload = networkUpload else { return nil }
        return download + upload
    }
    var diskTotalRate: Double? {
        guard let read = diskReadRate, let write = diskWriteRate else { return nil }
        return read + write
    }
}

struct ProcessHistoryPoint: Identifiable, Equatable {
    let date: Date
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let networkRate: Double?
    let diskRate: Double?
    var id: Date { date }
}

enum ProcessScope: String, CaseIterable, Identifiable {
    case all
    case user

    var id: String { rawValue }
    var titleKey: String { self == .all ? "All Processes" : "User Processes" }
}

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case energy
    case network
    case disk
    case name

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .energy: "Energy Score"
        case .network: "Network"
        case .disk: "Disk I/O"
        case .name: "Process"
        }
    }
}

struct ProcessSample {
    let date: Date
    let records: [ProcessRecord]
}

// ProcessSampler выполняет один пакетный проход и хранит дельты между проходами.
final class ProcessSampler: @unchecked Sendable {
    private struct Counters {
        let startDate: Date?
        let userTime: UInt64
        let systemTime: UInt64
        let wakeups: UInt64
        let diskRead: UInt64
        let diskWrite: UInt64
        let date: Date
    }

    private var previous: [Int32: Counters] = [:]
    func reset() {
        previous.removeAll(keepingCapacity: true)
    }

    func sample() -> ProcessSample {
        let now = Date()
        let pids = processIDs()
        var current: [Int32: Counters] = [:]
        var records: [ProcessRecord] = []
        records.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let base = bsdInfo(pid), let usage = usageInfo(pid) else { continue }
            let task = taskInfo(pid)
            let path = executablePath(pid)
            let name = path?.split(separator: "/").last.map(String.init) ?? base.name
            let startDate = Date(timeIntervalSince1970: TimeInterval(base.startSeconds) + TimeInterval(base.startMicroseconds) / 1_000_000)
            let counters = Counters(startDate: startDate,
                                    userTime: usage.userTime,
                                    systemTime: usage.systemTime,
                                    wakeups: usage.wakeups,
                                    diskRead: usage.diskRead,
                                    diskWrite: usage.diskWrite,
                                    date: now)
            current[pid] = counters

            let old = previous[pid]
            let sameProcess = old?.startDate == startDate
            let elapsed = sameProcess ? now.timeIntervalSince(old!.date) : 0
            let cpu: Double?
            let wakeupsRate: Double?
            let diskReadRate: Double?
            let diskWriteRate: Double?
            if sameProcess, elapsed > 0 {
                cpu = max(0, Double(delta(counters.userTime, old!.userTime) + delta(counters.systemTime, old!.systemTime)) / 1_000_000_000 / elapsed * 100)
                wakeupsRate = Double(delta(counters.wakeups, old!.wakeups)) / elapsed
                diskReadRate = Double(delta(counters.diskRead, old!.diskRead)) / elapsed
                diskWriteRate = Double(delta(counters.diskWrite, old!.diskWrite)) / elapsed
            } else {
                cpu = nil
                wakeupsRate = nil
                diskReadRate = nil
                diskWriteRate = nil
            }
            let energy = energyScore(cpu: cpu, wakeupsRate: wakeupsRate, diskRate: (diskReadRate ?? 0) + (diskWriteRate ?? 0))
            let memory = usage.physicalFootprint > 0 ? usage.physicalFootprint : task?.residentSize
            records.append(ProcessRecord(pid: pid,
                                          name: name,
                                          executablePath: path,
                                          bundleIdentifier: nil,
                                          isApplication: false,
                                          isUserProcess: base.uid == getuid(),
                                          parentPID: base.parentPID,
                                          startDate: startDate,
                                          cpuPercent: cpu,
                                          memoryBytes: memory,
                                          energyScore: energy,
                                          networkDownload: nil,
                                          networkUpload: nil,
                                          diskReadRate: diskReadRate,
                                          diskWriteRate: diskWriteRate,
                                          diskReadBytes: usage.diskRead,
                                          diskWriteBytes: usage.diskWrite,
                                          threadCount: task?.threadCount,
                                          processState: processState(base.status)))
        }
        previous = current
        return ProcessSample(date: now, records: records)
    }

    private func processIDs() -> [Int32] {
        let requested = max(1, proc_listallpids(nil, 0))
        var pids = [Int32](repeating: 0, count: Int(requested) + 64)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [] }
        return Array(pids.prefix(Int(bytes)))
    }

    private struct BSDInfo {
        let parentPID: Int32
        let uid: uid_t
        let name: String
        let status: UInt32
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    private func bsdInfo(_ pid: Int32) -> BSDInfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return BSDInfo(parentPID: Int32(info.pbi_ppid), uid: info.pbi_uid, name: fixedString(info.pbi_name), status: info.pbi_status, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
    }

    private struct UsageInfo {
        let userTime: UInt64
        let systemTime: UInt64
        let wakeups: UInt64
        let physicalFootprint: UInt64
        let diskRead: UInt64
        let diskWrite: UInt64
    }

    private func usageInfo(_ pid: Int32) -> UsageInfo? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            let buffer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_V4, buffer)
        }
        guard result == 0 else { return nil }
        return UsageInfo(userTime: info.ri_user_time,
                         systemTime: info.ri_system_time,
                         wakeups: info.ri_pkg_idle_wkups + info.ri_interrupt_wkups,
                         physicalFootprint: info.ri_phys_footprint,
                         diskRead: info.ri_diskio_bytesread,
                         diskWrite: info.ri_diskio_byteswritten)
    }

    private struct TaskInfo {
        let residentSize: UInt64
        let threadCount: Int
    }

    private func taskInfo(_ pid: Int32) -> TaskInfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return TaskInfo(residentSize: info.pti_resident_size, threadCount: Int(info.pti_threadnum))
    }

    private func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func fixedString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private func delta(_ newer: UInt64, _ older: UInt64) -> UInt64 {
        newer >= older ? newer - older : 0
    }

    // Это понятный относительный балл активности, а не официальный Apple Energy Impact.
    private func energyScore(cpu: Double?, wakeupsRate: Double?, diskRate: Double) -> Double? {
        guard let cpu else { return nil }
        let cpuPart = min(100, max(0, cpu))
        let wakeupPart = min(100, max(0, (wakeupsRate ?? 0) / 500 * 100))
        let diskPart = min(100, max(0, diskRate / 50_000_000 * 100))
        return min(100, 0.7 * cpuPart + 0.2 * wakeupPart + 0.1 * diskPart)
    }

    private func processState(_ status: UInt32) -> String? {
        switch status {
        case 1: return "running"
        case 2: return "sleeping"
        case 3: return "stopped"
        case 4: return "zombie"
        default: return nil
        }
    }
}

// ProcessMonitor использует один timer: редкий фоновый режим для Health и быстрый режим открытого экрана.
@MainActor final class ProcessMonitor: ObservableObject {
    @Published private(set) var records: [ProcessRecord] = []
    @Published private(set) var history: [Int32: [ProcessHistoryPoint]] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isSampling = false
    @Published private(set) var sampleDurationMilliseconds = 0.0

    private let sampler = ProcessSampler()
    private let queue = DispatchQueue(label: "local.macpulse.processes", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval = 2.0
    private var backgroundInterval = 5.0
    private var backgroundEnabled = false
    private var interactiveInterval: Double?
    private var applicationMetadata: [Int32: (startDate: Date?, name: String?, bundleIdentifier: String?)] = [:]

    func start(interval: Double) {
        interactiveInterval = max(1, interval)
        applyDesiredInterval()
    }

    func startBackground(interval: Double = 5) {
        backgroundEnabled = true
        backgroundInterval = max(2, interval)
        applyDesiredInterval()
    }

    func stopBackground() {
        backgroundEnabled = false
        applyDesiredInterval()
    }

    func stop() {
        interactiveInterval = nil
        applyDesiredInterval()
    }

    func restartIfNeeded(interval: Double) {
        guard interactiveInterval != nil else { return }
        interactiveInterval = max(1, interval)
        applyDesiredInterval()
    }

    private func applyDesiredInterval() {
        let desired = interactiveInterval ?? (backgroundEnabled ? backgroundInterval : nil)
        guard let desired else {
            timer?.cancel()
            timer = nil
            isSampling = false
            return
        }
        guard timer == nil || abs(interval - desired) > 0.01 else { return }
        timer?.cancel()
        timer = nil
        interval = desired
        isSampling = true
        sampler.reset()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: desired, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self, sampler] in
            let started = ProcessInfo.processInfo.systemUptime
            let sample = sampler.sample()
            let duration = (ProcessInfo.processInfo.systemUptime - started) * 1000
            Task { @MainActor [weak self] in self?.receive(sample, duration: duration) }
        }
        self.timer = timer
        timer.resume()
    }

    func history(for pid: Int32) -> [ProcessHistoryPoint] {
        history[pid] ?? []
    }

    private func receive(_ sample: ProcessSample, duration: Double) {
        let knownPIDs = Set(sample.records.map(\.pid))
        applicationMetadata = applicationMetadata.filter { knownPIDs.contains($0.key) }
        let missingMetadata = sample.records.contains { record in
            applicationMetadata[record.pid]?.startDate != record.startDate
        }
        if missingMetadata {
            let applications = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { application -> (Int32, NSRunningApplication)? in
                let pid = application.processIdentifier
                guard pid > 0 else { return nil }
                return (pid, application)
            })
            for record in sample.records where applicationMetadata[record.pid]?.startDate != record.startDate {
                let application = applications[record.pid]
                applicationMetadata[record.pid] = (record.startDate, application?.localizedName, application?.bundleIdentifier)
            }
        }
        records = sample.records.map { record in
            guard let metadata = applicationMetadata[record.pid], metadata.startDate == record.startDate else { return record }
            var enriched = record
            if let name = metadata.name, !name.isEmpty { enriched.name = name }
            enriched.bundleIdentifier = metadata.bundleIdentifier
            enriched.isApplication = metadata.bundleIdentifier != nil
            enriched.isUserProcess = enriched.isUserProcess || enriched.isApplication
            return enriched
        }
        lastUpdated = sample.date
        sampleDurationMilliseconds = duration
        for record in sample.records {
            let point = ProcessHistoryPoint(date: sample.date,
                                             cpuPercent: record.cpuPercent,
                                             memoryBytes: record.memoryBytes,
                                             networkRate: record.networkTotalRate,
                                             diskRate: record.diskTotalRate)
            var points = history[record.pid, default: []]
            points.append(point)
            if points.count > 120 { points.removeFirst(points.count - 120) }
            history[record.pid] = points
        }
        let active = Set(sample.records.map(\.pid))
        history = history.filter { active.contains($0.key) }
    }

    deinit {
        timer?.cancel()
    }
}

@MainActor final class ProcessIconCache: ObservableObject {
    private var cache: [String: NSImage] = [:]

    func icon(for record: ProcessRecord) -> NSImage {
        let key = record.bundleIdentifier ?? record.executablePath ?? record.name
        if let cached = cache[key] { return cached }
        let image: NSImage
        if let application = NSRunningApplication(processIdentifier: record.pid), let icon = application.icon {
            image = icon
        } else if let path = record.executablePath {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: L10n.text("Process")) ?? NSImage()
        }
        image.size = NSSize(width: 20, height: 20)
        cache[key] = image
        return image
    }
}
