//
//  ManualSettle.swift
//  UnveilTests
//

import Synchronization

/// ManualSettle is a stepper settle wait that ends only when the test calls `fire`, in place of
/// the view model's 0.3 s sleep: a burst then never splits because the main actor was slow
/// between two presses, which a wall-clock delay cannot promise under the full suite's load.
///
/// `fire` latches: every wait in progress and every later one returns. A burst's earlier timers,
/// cancelled by the next press, return too and see they were cancelled, as after a real sleep.
final class ManualSettle: Sendable {

    private let state = Mutex<(isFired: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, []))

    func wait() async {
        await withCheckedContinuation { waiter in
            let isFired = state.withLock { current -> Bool in
                if !current.isFired {
                    current.waiters.append(waiter)
                }

                return current.isFired
            }

            if isFired {
                waiter.resume()
            }
        }
    }

    func fire() {
        let waiters = state.withLock { current in
            current.isFired = true
            defer { current.waiters = [] }

            return current.waiters
        }

        waiters.forEach { $0.resume() }
    }
}
