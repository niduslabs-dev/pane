import CoreVideo
import Foundation
import IOSurface
import Synchronization
import Testing

@testable import PaneCore

/// The stream pool frees its spare buffers once the screen has been still for
/// `idleTrimDelay`. A hand-driven timer stands in for the dispatch one, so nothing here waits.
@Suite struct PoolIdleTrimTests {
    /// An `IdleTrimTimer` on a pretend clock: `advance(by:)` runs the action once its deadline
    /// has passed.
    final class ManualTimer: IdleTrimTimer {
        private struct State {
            var now: Duration = .zero
            var deadline: Duration?
            var action: (@Sendable () -> Void)?
            var delays: [Duration] = []
            var fired = 0
        }
        private let state = Mutex(State())

        var delays: [Duration] { state.withLock { $0.delays } }
        var fired: Int { state.withLock { $0.fired } }

        func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) {
            state.withLock {
                $0.deadline = $0.now + delay
                $0.action = action
                $0.delays.append(delay)
            }
        }

        func cancel() { state.withLock { $0.deadline = nil } }

        func advance(by step: Duration) {
            let due: (@Sendable () -> Void)? = state.withLock {
                $0.now += step
                guard let deadline = $0.deadline, deadline <= $0.now else { return nil }
                $0.deadline = nil
                $0.fired += 1
                return $0.action
            }
            due?()
        }
    }

    static let size = PixelSize(width: 8, height: 8)
    static let delay = FramePixelBufferPool.defaultIdleTrimDelay
    static let underDelay = Duration.milliseconds(1_500)

    /// The surface behind a buffer, retained, so its identity can be compared after the pool
    /// lets go of it.
    static func surface(_ buffer: CVPixelBuffer) throws -> IOSurfaceRef {
        try #require(CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue())
    }

    static func isOneOf(_ surface: IOSurfaceRef, _ others: [IOSurfaceRef]) -> Bool {
        others.contains { $0 === surface }
    }

    /// Three buffers out, as after a burst; two released, the one on screen kept.
    static func afterBurst(_ pool: FramePixelBufferPool) throws -> (onScreen: CVPixelBuffer, spares: [IOSurfaceRef]) {
        var out = [CVPixelBuffer]()
        for _ in 0..<3 { out.append(try #require(pool.buffer(size: size))) }
        let spares = try out.dropLast().map(surface)
        let onScreen = out.removeLast()
        out.removeAll()
        return (onScreen, spares)
    }

    @Test func withoutATrimTheSparesAreReused() throws {
        let timer = ManualTimer()
        let pool = FramePixelBufferPool(idleTrimTimer: timer)
        let (onScreen, spares) = try Self.afterBurst(pool)
        let next = try #require(pool.buffer(size: Self.size))
        #expect(Self.isOneOf(try Self.surface(next), spares))
        withExtendedLifetime(onScreen) {}
    }

    @Test func sparesAreFreedAfterTheDelay() throws {
        let timer = ManualTimer()
        let pool = FramePixelBufferPool(idleTrimTimer: timer)
        let (onScreen, spares) = try Self.afterBurst(pool)
        #expect(timer.delays.allSatisfy { $0 == Self.delay })

        timer.advance(by: Self.delay)
        #expect(timer.fired == 1)
        let next = try #require(pool.buffer(size: Self.size))
        #expect(!Self.isOneOf(try Self.surface(next), spares))
        withExtendedLifetime(onScreen) {}
    }

    /// The trim frees only buffers no frame holds: the one on screen survives it and goes back
    /// into the pool when its frame is released.
    @Test func theBufferOnScreenIsKept() throws {
        let timer = ManualTimer()
        let pool = FramePixelBufferPool(idleTrimTimer: timer)
        var onScreen: CVPixelBuffer? = try Self.afterBurst(pool).onScreen
        let heldSurface = try Self.surface(try #require(onScreen))
        let marker: UInt8 = 0x5A
        try Self.withBytes(of: try #require(onScreen)) { $0.storeBytes(of: marker, as: UInt8.self) }

        timer.advance(by: Self.delay)
        #expect(timer.fired == 1)
        try Self.withBytes(of: try #require(onScreen)) { #expect($0.load(as: UInt8.self) == marker) }

        // Released after the trim, it goes back into the pool and is the next one handed out.
        onScreen = nil
        let next = try #require(pool.buffer(size: Self.size))
        #expect(try Self.surface(next) === heldSurface)
    }

    static func withBytes(of buffer: CVPixelBuffer, _ body: (UnsafeMutableRawPointer) -> Void) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        body(try #require(CVPixelBufferGetBaseAddress(buffer)))
    }

    @Test func noTrimWhileFramesKeepComing() throws {
        let timer = ManualTimer()
        let pool = FramePixelBufferPool(idleTrimTimer: timer)
        let (onScreen, spares) = try Self.afterBurst(pool)
        var latest = onScreen
        for _ in 0..<5 {
            timer.advance(by: Self.underDelay)
            latest = try #require(pool.buffer(size: Self.size))
        }
        #expect(timer.fired == 0)
        // Every frame reused a spare: nothing was freed and allocated again.
        #expect(Self.isOneOf(try Self.surface(latest), spares + [try Self.surface(onScreen)]))

        timer.advance(by: Self.delay)
        #expect(timer.fired == 1)
    }

    @Test func thePoolIsReusedAfterATrim() throws {
        let timer = ManualTimer()
        let pool = FramePixelBufferPool(idleTrimTimer: timer)
        let (onScreen, _) = try Self.afterBurst(pool)
        timer.advance(by: Self.delay)

        var fresh = pool.buffer(size: Self.size)
        let freshSurface = try Self.surface(try #require(fresh))
        fresh = nil
        let again = try #require(pool.buffer(size: Self.size))
        #expect(try Self.surface(again) === freshSurface)
        // And the trim is scheduled again for the next stillness.
        timer.advance(by: Self.delay)
        #expect(timer.fired == 2)
        withExtendedLifetime(onScreen) {}
    }

    /// The real timer, wired up: a short delay fires on its own queue. Polls with
    /// `Task.sleep`, which never blocks a thread of the cooperative pool.
    @Test(.timeLimit(.minutes(1))) func theDispatchTimerFires() async throws {
        let timer = DispatchIdleTrimTimer()
        let fired = Mutex(0)
        timer.schedule(after: .milliseconds(10)) { fired.withLock { $0 += 1 } }
        for _ in 0..<500 where fired.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(fired.withLock { $0 } == 1)

        timer.schedule(after: .seconds(60)) { fired.withLock { $0 += 1 } }
        timer.cancel()
        #expect(fired.withLock { $0 } == 1)
    }
}
