import Testing

@testable import PaneCore

@Suite struct ReconnectPolicyTests {
    private let policy = ReconnectPolicy(maxAttempts: 5, initialDelay: .milliseconds(500), maxDelay: .seconds(4))

    @Test func doublesUpToTheCap() {
        let delays = (1...5).map { policy.delay(beforeAttempt: $0) }
        #expect(delays == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(4)])
    }

    @Test func givesUpAfterTheLastAttempt() {
        #expect(policy.delay(beforeAttempt: 6) == nil)
        #expect(policy.delay(beforeAttempt: 0) == nil)
    }
}
