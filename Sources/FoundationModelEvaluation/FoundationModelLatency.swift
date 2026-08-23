import Foundation

/// Wall-clock latency captured for one evaluated generation.
public struct FoundationModelLatency: Codable, Equatable, Sendable {
    public let total: TimeInterval
    public let timeToFirstToken: TimeInterval?

    public init(total: TimeInterval, timeToFirstToken: TimeInterval? = nil) {
        self.total = max(0, total)
        self.timeToFirstToken = timeToFirstToken.map { max(0, $0) }
    }
}
