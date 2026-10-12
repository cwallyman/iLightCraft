//
//  FrameTimingProbeTests.swift
//  UnveilTests
//

import Foundation
import QuartzCore
import Testing
@testable import Unveil

/// FrameTimingProbeTests checks that the hitch meter reports what it measured.
@Suite(.serialized)
@MainActor
struct FrameTimingProbeTests {

    /// An interval measured while recording, and an update gap over 1.5 times the phase's median gap,
    /// land in the report's row of their phase with their durations; after a pause no gap counts,
    /// and nothing is measured once the report is written.
    @Test
    func measuredIntervalsAndHitchesAreReportedByPhase() async throws {
        let probe = FrameTimingProbe.shared
        let file  = URL.temporaryDirectory.appending(path: "probe-test.csv")
        let frame = 1.0 / 60
        defer { try? FileManager.default.removeItem(at: file) }

        probe.start(phase: "test")
        probe.measure("ProbeTest") { usleep(20_000) }

        let now = CACurrentMediaTime() + 1

        // Gaps of 1, 1, 1 and 3 frames: the cadence is 1 frame, one hitch of 2 frames.
        for (index, offset) in [0.0, 1, 2, 3, 6].enumerated() {
            probe.tick(at: now + offset * frame, isPaused: index == 4, skippedDraw: index == 4)
        }

        probe.tick(at: now + 600 * frame, isPaused: false, skippedDraw: false)
        await probe.writeReport(to: file)
        probe.measure("ProbeTest") { }

        let text     = try String(contentsOf: file, encoding: .utf8)
        let rows     = text.split(separator: "\n").map { $0.split(separator: ",") }
        let measured = try #require(rows.first { $0.count == 8 && $0[2] == "ProbeTest" })
        let hitch    = try #require(rows.first { $0.count == 8 && $0[2] == "tick-hitch" })
        let skipped  = try #require(rows.first { $0.count == 8 && $0[2] == "gpu-busy-skip" })

        #expect(measured[0] == "test" && measured[3] == "1")
        #expect((Double(measured[4]) ?? 0) >= 19 && (Double(measured[4]) ?? 0) < 1000)
        #expect(hitch[3] == "1" && abs((Double(hitch[4]) ?? 0) - 2000 * frame) < 0.01)
        #expect(skipped[3] == "1")
    }
}
