//
//  SliderLatencyLog.swift
//  Unveil
//

import Foundation
import Synchronization

/// SliderLatencyLog keeps the length of every `SliderToFrame` interval that ends while a cost
/// measurement runs (`-UnveilCost`), by quality (`draft`, `full`, `window-draft`, `window-full`)
/// and outcome, so a run prints its own median and p95 with no trace attached. Outside a run it
/// is one atomic read per interval: no clock, no lock.
nonisolated enum SliderLatencyLog {

    private struct Row {

        let quality     : String
        let milliseconds: Double
        let outcome     : String
    }

    private struct State {

        var isActive = false
        var rows     = [Row]()
    }

    private static let state        = Mutex(State())
    private static let isActiveFlag = Atomic<Bool>(false)

    static var isActive: Bool { isActiveFlag.load(ordering: .relaxed) }

    static func start() {
        state.withLock { $0 = State(isActive: true) }
        isActiveFlag.store(true, ordering: .relaxed)
    }

    static func record(quality: String, startedAtNs: UInt64, outcome: String) {
        guard isActive else { return }

        let milliseconds = Double(ProcessCostProbe.uptimeNs() &- startedAtNs) / 1_000_000

        state.withLock { current in
            guard current.isActive else { return }

            current.rows.append(Row(quality: quality, milliseconds: milliseconds, outcome: outcome))
        }
    }

    /// stop ends the recording and summarises it per quality: the count, median and p95 of every
    /// interval that ended (`all`), of those that ended as `presented`, and the outcome counts.
    static func stop() -> [String: Any] {
        isActiveFlag.store(false, ordering: .relaxed)

        let rows = state.withLock { current in
            current.isActive = false
            return current.rows
        }

        var summary = [String: Any]()

        for quality in Set(rows.map(\.quality)) {
            let mine      = rows.filter { $0.quality == quality }
            let presented = mine.filter { $0.outcome == "presented" }
            var outcomes  = [String: Int]()

            for row in mine {
                outcomes[row.outcome, default: 0] += 1
            }

            summary[quality] = [
                "count"             : mine.count,
                "allMedianMs"       : percentile(0.5, of: mine.map(\.milliseconds)),
                "allP95Ms"          : percentile(0.95, of: mine.map(\.milliseconds)),
                "presentedMedianMs" : percentile(0.5, of: presented.map(\.milliseconds)),
                "presentedP95Ms"    : percentile(0.95, of: presented.map(\.milliseconds)),
                "outcomes"          : outcomes,
            ] as [String: Any]
        }

        return summary
    }

    /// percentile is linear between ranks, like the baseline's statistics; 0 for no data.
    private static func percentile(_ fraction: Double, of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        let sorted   = values.sorted()
        let position = fraction * Double(sorted.count - 1)
        let lower    = Int(position.rounded(.down))
        let upper    = min(lower + 1, sorted.count - 1)

        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
}
