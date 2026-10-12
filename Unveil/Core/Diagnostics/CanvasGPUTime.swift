//
//  CanvasGPUTime.swift
//  Unveil
//

import Foundation
import Synchronization

/// CanvasGPUTime adds up the GPU time of the canvas's command buffers (`gpuEndTime - gpuStartTime`)
/// while a cost measurement runs (`-UnveilCost`). The canvas asks `isActive` before each pass, so a
/// normal launch adds no completion handler and pays one atomic read.
nonisolated enum CanvasGPUTime {

    struct Totals: Sendable {

        var passes : Int    = 0
        var seconds: Double = 0
        var longest: Double = 0
    }

    private static let state        = Mutex(Totals())
    private static let isActiveFlag = Atomic<Bool>(false)

    static var isActive: Bool {
        get { isActiveFlag.load(ordering: .relaxed) }
        set { isActiveFlag.store(newValue, ordering: .relaxed) }
    }

    /// record adds one finished pass; a buffer the GPU never ran reports equal times and adds 0.
    static func record(start: CFTimeInterval, end: CFTimeInterval) {
        let seconds = max(0, end - start)

        state.withLock {
            $0.passes  += 1
            $0.seconds += seconds
            $0.longest  = max($0.longest, seconds)
        }
    }

    static func reset() {
        state.withLock { $0 = Totals() }
    }

    static func totals() -> Totals {
        state.withLock { $0 }
    }
}
