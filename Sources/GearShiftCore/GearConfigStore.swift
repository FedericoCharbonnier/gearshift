import Foundation

/// Loads and saves `GearConfig` as JSON.
public struct GearConfigStore {
    public let url: URL

    public init(url: URL = GearConfigStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GearShift", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// The stored config, or the defaults when the file is missing or unreadable.
    public func load() -> GearConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(GearConfig.self, from: data)
        else { return .defaults }
        return config.fillingMissingGears()
    }

    public func save(_ config: GearConfig) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
