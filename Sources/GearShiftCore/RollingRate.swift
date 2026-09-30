import Foundation

public struct TokenSample: Equatable {
    public var timestamp: Date
    public var tokens: Int

    public init(timestamp: Date, tokens: Int) {
        self.timestamp = timestamp
        self.tokens = tokens
    }
}

/// Tokens seen in the last `window` seconds, scaled to tokens per minute.
public struct RollingRate {
    public let window: TimeInterval
    private var samples: [TokenSample] = []

    public init(window: TimeInterval = 60) {
        self.window = window
    }

    public mutating func add(_ sample: TokenSample) {
        samples.append(sample)
    }

    public mutating func tokensPerMinute(now: Date) -> Int {
        samples.removeAll { now.timeIntervalSince($0.timestamp) > window }
        let total = samples.reduce(0) { $0 + $1.tokens }
        return Int(Double(total) * 60 / window)
    }
}
