import Foundation

// Виджет получает только выбранные значения без имени компьютера и адресов сети.
struct WidgetSnapshot: Codable {
    var date: Date
    var cpu: Double?
    var memory: Double?
    var battery: Double?
    var temperature: Double?
    static let group = "group.local.macpulse.shared"
    static var isConfigured: Bool {
        #if MACPULSE_SIGNED
        true
        #else
        false
        #endif
    }
    static var fileURL: URL? {
        guard isConfigured else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("snapshot.json")
    }
    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func write() throws {
        guard let url = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
