import Foundation

/// Reads the complete lines appended to a file since the last read.
public final class TranscriptTail {
    /// At most this much of an existing file is read the first time. Only the last minute of a
    /// transcript matters, and parsing a whole long one is slow (0.64 s and 310 MB for 35 MB).
    static let initialReadLimit: UInt64 = 4 << 20

    public let url: URL
    private var offset: UInt64 = 0
    private var partialLine = Data()
    /// Set when reading starts mid-file: the bytes up to the next newline end a line whose start
    /// was skipped.
    private var isSkippingToNextLine = false

    public init(url: URL) {
        self.url = url
    }

    /// With `startingAtEnd`, only lines appended after now are read. It reads from one byte before
    /// the end, so a line that was still being written now is skipped as a whole.
    public convenience init(url: URL, startingAtEnd: Bool) {
        self.init(url: url)
        guard startingAtEnd,
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.uint64Value > 0
        else { return }
        offset = size.uint64Value - 1
        isSkippingToNextLine = true
    }

    /// The complete lines in the last `maxBytes` of the file (the last one even without a newline).
    /// A line cut by the start of that range is dropped.
    public static func lastLines(of url: URL, maxBytes: UInt64) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let isCut = size > maxBytes
        // One byte early: if that byte is a newline, the first line read is complete.
        let start = isCut ? size - maxBytes - 1 : 0
        guard (try? handle.seek(toOffset: start)) != nil, var data = try? handle.readToEnd() else { return [] }
        if isCut {
            guard let firstNewline = data.firstIndex(of: UInt8(ascii: "\n")) else { return [] }
            data = Data(data[data.index(after: firstNewline)...])
        }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    public func readNewLines() -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            // Truncated or replaced: start over.
            offset = 0
            partialLine = Data()
            isSkippingToNextLine = false
        }
        if offset == 0, size > Self.initialReadLimit {
            // One byte early: if that byte is a newline, the first line read is complete.
            offset = size - Self.initialReadLimit - 1
            isSkippingToNextLine = true
        }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd()
        else { return [] }
        offset += UInt64(data.count)
        var buffer = partialLine + data
        if isSkippingToNextLine {
            guard let firstNewline = buffer.firstIndex(of: UInt8(ascii: "\n")) else {
                partialLine = Data()
                return []
            }
            buffer = Data(buffer[buffer.index(after: firstNewline)...])
            isSkippingToNextLine = false
        }
        guard let lastNewline = buffer.lastIndex(of: UInt8(ascii: "\n")) else {
            partialLine = buffer
            return []
        }
        partialLine = Data(buffer[buffer.index(after: lastNewline)...])
        return String(decoding: buffer[..<lastNewline], as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }
}
