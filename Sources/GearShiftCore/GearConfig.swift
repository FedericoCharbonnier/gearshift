import Foundation

/// Claude Code's `/effort` levels. No effort (nil) means `auto`.
public enum Effort: String, Codable, CaseIterable {
    case low, medium, high, xhigh, max
}

/// What one gear switches the session to.
public struct GearSetting: Codable, Equatable {
    /// Short name under the gear number on the shifter, e.g. "Sonnet · med".
    public var label: String
    /// Name in the readout, e.g. "SONNET 5 · MED".
    public var displayName: String
    /// Alias passed to `/model`, e.g. "sonnet" or "default".
    public var model: String
    public var effort: Effort?

    public init(label: String, displayName: String, model: String, effort: Effort? = nil) {
        self.label = label
        self.displayName = displayName
        self.model = model
        self.effort = effort
    }
}

public struct GearConfig: Codable, Equatable {
    public var gears: [Gear: GearSetting]
    public var isMuted: Bool
    /// Float above other windows, so the shifter stays visible after a shift brings the terminal
    /// to the front.
    public var keepsOnTop: Bool
    /// After a shift that had to bring the terminal to the front (Warp, Terminal), bring back the
    /// app, window and tab that were in front before. iTerm2 is typed into without coming forward.
    public var returnsToPreviousApp: Bool

    public init(gears: [Gear: GearSetting], isMuted: Bool, keepsOnTop: Bool = true, returnsToPreviousApp: Bool = true) {
        self.gears = gears
        self.isMuted = isMuted
        self.keepsOnTop = keepsOnTop
        self.returnsToPreviousApp = returnsToPreviousApp
    }

    public static let defaults = GearConfig(
        gears: [
            .reverse: GearSetting(label: "Haiku", displayName: "HAIKU 4.5", model: "haiku"),
            .neutral: GearSetting(label: "Default", displayName: "DEFAULT", model: "default"),
            .one: GearSetting(label: "Sonnet · med", displayName: "SONNET 5 · MED", model: "sonnet", effort: .medium),
            .two: GearSetting(label: "Sonnet · high", displayName: "SONNET 5 · HIGH", model: "sonnet", effort: .high),
            .three: GearSetting(label: "Opus · med", displayName: "OPUS 5.5 · MED", model: "opus", effort: .medium),
            .four: GearSetting(label: "Opus · max", displayName: "OPUS 5.5 · MAX", model: "opus", effort: .max),
            .five: GearSetting(label: "Fable", displayName: "FABLE 5.1", model: "fable"),
        ],
        isMuted: false
    )

    /// The config with any gear missing from storage filled in from the defaults.
    func fillingMissingGears() -> GearConfig {
        var config = self
        for (gear, setting) in Self.defaults.gears where config.gears[gear] == nil {
            config.gears[gear] = setting
        }
        return config
    }
}

extension GearConfig {
    enum CodingKeys: String, CodingKey {
        case gears, isMuted, keepsOnTop, returnsToPreviousApp
    }

    /// Lenient so that schema drift keeps the rest of the file: each field falls back on its own,
    /// and a gear that doesn't decode is left out for the store to fill from the defaults. Unknown
    /// keys, such as v1's `recentProjects` and `sessionIDs`, are ignored. Encoding stays
    /// synthesized: `gears` is written keyed by raw value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedGears = (try? container.decodeIfPresent([String: StoredSetting].self, forKey: .gears)) ?? [:]
        self.init(
            gears: Dictionary(uniqueKeysWithValues: storedGears.compactMap { key, stored in
                guard let gear = Gear(rawValue: key), let setting = stored.setting else { return nil }
                return (gear, setting)
            }),
            isMuted: (try? container.decodeIfPresent(Bool.self, forKey: .isMuted)) ?? false,
            keepsOnTop: (try? container.decodeIfPresent(Bool.self, forKey: .keepsOnTop)) ?? true,
            returnsToPreviousApp: (try? container.decodeIfPresent(Bool.self, forKey: .returnsToPreviousApp)) ?? true
        )
    }

    /// One stored gear; nil when it doesn't decode. A v1 setting (it has an `agent`) is dropped as
    /// well: v1 put other models on each gear, including Codex ones that `/model` would reject.
    private struct StoredSetting: Decodable {
        let setting: GearSetting?

        private enum V1Keys: String, CodingKey {
            case agent
        }

        init(from decoder: Decoder) throws {
            let isV1 = (try? decoder.container(keyedBy: V1Keys.self).contains(.agent)) ?? false
            setting = isV1 ? nil : try? GearSetting(from: decoder)
        }
    }
}
