/// How often and how long to retry a dropped connection: exponential backoff from `initialDelay`,
/// capped at `maxDelay`, for at most `maxAttempts` tries before the window shows can't-connect.
public struct ReconnectPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var initialDelay: Duration
    public var maxDelay: Duration

    public init(maxAttempts: Int, initialDelay: Duration, maxDelay: Duration) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
    }

    /// The wait before try number `attempt` (1-based), or nil once the tries are used up.
    public func delay(beforeAttempt attempt: Int) -> Duration? {
        guard attempt >= 1, attempt <= maxAttempts else { return nil }
        var delay = initialDelay
        for _ in 1..<attempt {
            delay = delay * 2
            if delay >= maxDelay { return maxDelay }
        }
        return min(delay, maxDelay)
    }
}
