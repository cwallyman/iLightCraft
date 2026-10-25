//
//  OpenTimeline.swift
//  iLightCraft
//

import Foundation
import Synchronization

/// OpenTimeline records named instants while a measurement run asks for it (`-iLightCraftTimeline`): the
/// start of the open, the copy and its hash, each engine command, the preview request and the first
/// presented frame. The clock is the one the engine's own events use (`CLOCK_UPTIME_RAW`), so the
/// runner can merge both into one table.
///
/// It records only between `start()` and `stop()`; outside a measurement `mark` is one atomic read:
/// no clock, no lock.
nonisolated enum OpenTimeline {

    struct Mark: Sendable {

        let nanoseconds: UInt64
        let name       : String
    }

    private struct State {

        var isRecording = false
        var list        = [Mark]()
    }

    private static let state       = Mutex(State())
    private static let isRecording = Atomic<Bool>(false)

    static func start() {
        state.withLock { $0 = State(isRecording: true) }
        isRecording.store(true, ordering: .relaxed)
    }

    /// stop ends the recording and returns what it saw, in order.
    static func stop() -> [Mark] {
        isRecording.store(false, ordering: .relaxed)

        return state.withLock { current in
            current.isRecording = false
            return current.list
        }
    }

    static func mark(_ name: @autoclosure () -> String) {
        guard isRecording.load(ordering: .relaxed) else { return }

        let now = ProcessCostProbe.uptimeNs()

        state.withLock { current in
            guard current.isRecording else { return }

            current.list.append(Mark(nanoseconds: now, name: name()))
        }
    }
}
