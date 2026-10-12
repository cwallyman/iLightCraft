//
//  ExclusiveWindowTrait.swift
//  UnveilTests
//

import Synchronization
import Testing

/// ExclusiveWindowTrait runs each test of the suites that carry it alone among them, in the order
/// they ask. Those tests put a window on screen and wait on what a display link draws in it.
///
/// Swift Testing runs suites in parallel, and `.serialized` orders the tests of one suite only. In
/// F6's re-review a canvas glide test missed its wait in 2 of 2 full runs, both times next to
/// EditorViewTests' full-screen editor window and its screen snapshots, and passed alone every time.
/// With this trait a window test never shares the screen with another suite's window.
struct ExclusiveWindowTrait: TestTrait, SuiteTrait, TestScoping {

    let isRecursive = true

    /// Turn hands the screen to one test at a time: `take` waits until it is free, `pass` gives it
    /// to the next waiting test (or frees it).
    private final class Turn: Sendable {

        private struct State {

            var isTaken = false
            var waiting : [CheckedContinuation<Void, Never>] = []
        }

        private let state = Mutex(State())

        func take() async {
            await withCheckedContinuation { continuation in
                let isFree = state.withLock { state in
                    guard state.isTaken else {
                        state.isTaken = true
                        return true
                    }

                    state.waiting.append(continuation)

                    return false
                }

                if isFree {
                    continuation.resume()
                }
            }
        }

        func pass() {
            let next = state.withLock { state in
                guard !state.waiting.isEmpty else {
                    state.isTaken = false
                    return nil as CheckedContinuation<Void, Never>?
                }

                return state.waiting.removeFirst()
            }

            next?.resume()
        }
    }

    private static let turn = Turn()

    /// scopeProvider(for:testCase:) wraps each test case, never a whole suite, so a suite waiting
    /// for its turn cannot hold the screen its own tests then wait for.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    // @concurrent: Swift Testing's requirement, under this target's nonisolated(nonsending) default.
    @concurrent
    func provideScope(
        for test            : Test,
        testCase            : Test.Case?,
        performing function : @concurrent @Sendable () async throws -> Void
    ) async throws {
        await Self.turn.take()
        defer { Self.turn.pass() }

        try await function()
    }
}

extension Trait where Self == ExclusiveWindowTrait {

    /// exclusiveWindow runs each test of the suite alone among the suites with this trait.
    static var exclusiveWindow: Self {
        Self()
    }
}
