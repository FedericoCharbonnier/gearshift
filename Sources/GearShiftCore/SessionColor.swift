import Foundation

/// A colour of the user's own per session: the same nickname (or, without one, the same session)
/// always gets the same colour, across launches.
public enum SessionColor {
    /// Hues that read on the dark card and stay clear of the VFD's mint green (`#8affc1`).
    public static let palette: [String] = [
        "#ff6b6b",  // coral
        "#ff9f43",  // tangerine
        "#f7d154",  // sun
        "#4cc9f0",  // sky
        "#7b8cff",  // periwinkle
        "#c77dff",  // orchid
        "#ff7eb6",  // pink
        "#e0c3a0",  // sand
    ]

    /// What the colour is picked by: the nickname, else the session id.
    public static func key(for session: SessionRecord) -> String {
        session.nickname ?? session.sessionId
    }

    public static func hex(for session: SessionRecord) -> String {
        palette[index(forKey: key(for: session))]
    }

    public static func index(forKey key: String) -> Int {
        Int(fnv1a(key) % UInt32(palette.count))
    }

    /// 32-bit FNV-1a over the UTF-8 bytes; unlike `hashValue`, the same in every process.
    public static func fnv1a(_ string: String) -> UInt32 {
        var hash: UInt32 = 0x811c_9dc5
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }
}
