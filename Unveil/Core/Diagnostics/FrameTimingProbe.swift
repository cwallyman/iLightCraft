//
//  FrameTimingProbe.swift
//  Unveil
//

import Foundation
import os
import QuartzCore
import Synchronization

#if DEBUG

/// FrameTimingProbe is the Debug-only hitch meter of the measurements, built because Instruments
/// may not run on the iPad (its recordings filled the device's storage). It does three things.
///
/// It times the canvas's display link: it keeps the gap between two updates of a link that stayed
/// running, and at report time a gap over 1.5 times the phase's median gap (the link's actual
/// cadence, 60 or 120 Hz, whatever the screen's maximum) is a tick hitch, of the gap minus that
/// median. It times the drawables the same way, from their presented times, whenever the canvas
/// wanted to draw on the previous update too, so an update that skipped its draw (the last pass
/// still on the GPU, counted apart as `gpu-busy-skip`) shows as a present hitch as well. A drawable
/// never shown is counted as `present-dropped`, and the GPU's wait and run times of each pass too.
///
/// It wraps the main thread's known owners in OSSignposter intervals (category `Timing`) through
/// `measure`, and measures every main run loop iteration from wake to sleep (Core Animation's
/// commit included), so the time no owner claims is the SwiftUI and commit remainder. Each
/// interval's duration is also kept in memory: iOS does not store signposts in the process's own
/// log store (OSLogStore returned none of them on the iPad, only ordinary messages), so they
/// cannot be read back there; the signposts remain for Instruments on a Mac or a simulator.
///
/// `writeReport` splits everything by the phases `mark` opened and writes one CSV row per phase
/// and owner next to the FootprintSampler CSV. A Release build has the stub below instead: no
/// state, and calls the compiler folds away.
nonisolated final class FrameTimingProbe: Sendable {

    static let shared = FrameTimingProbe()

    static let signposter = OSSignposter(subsystem: "com.unveil", category: "Timing")

    /// hitchFactor is how many times the phase's median gap a gap must exceed to count as a hitch.
    static let hitchFactor = 1.5

    static let header = "phase,phase_s,owner,count,total_ms,median_ms,p95_ms,max_ms"

    private let state = Mutex(State())

    private struct Phase {

        let name     : String
        let mediaTime: CFTimeInterval
    }

    /// Sample is one timed event: when it ended (media time) and how long it took, in seconds.
    private struct Sample {

        let owner    : String
        let mediaTime: CFTimeInterval
        let duration : Double
    }

    private struct State {

        var isRecording: Bool = false
        var phases     : [Phase] = []
        var samples    : [Sample] = []
        var lastTick   : CFTimeInterval?
        var lastPresent: CFTimeInterval?
        var runLoopWake: CFTimeInterval?

        mutating func record(_ owner: String, at mediaTime: CFTimeInterval, lasting duration: Double = 0) {
            samples.append(Sample(
                owner     : owner,
                mediaTime : mediaTime,
                duration  : duration
            ))
        }
    }

    /// runLoopObservers are the two run loop meters `start` installs on main.
    @MainActor
    private static var runLoopObservers: [CFRunLoopObserver] = []

    /// isRecording is true between `start` and `writeReport`.
    var isRecording: Bool {
        state.withLock { $0.isRecording }
    }

    /// measure runs `body` inside a `Timing` signpost interval named `name` while recording.
    @discardableResult
    func measure<Result>(_ name: StaticString, _ body: () throws -> Result) rethrows -> Result {
        guard isRecording else { return try body() }

        let begin    = CACurrentMediaTime()
        let interval = Self.signposter.beginInterval(name, id: Self.signposter.makeSignpostID())

        defer {
            let end = CACurrentMediaTime()

            Self.signposter.endInterval(name, interval)
            state.withLock { $0.record("\(name)", at: end, lasting: end - begin) }
        }

        return try body()
    }

    /// start begins a recording with its first phase and installs the run loop meter. Main only.
    @MainActor
    func start(phase: String) {
        let wake = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.afterWaiting.rawValue,
            true,
            .min
        ) { _, _ in
            FrameTimingProbe.shared.state.withLock { $0.runLoopWake = CACurrentMediaTime() }
        }
        let sleep = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            .max
        ) { _, _ in
            FrameTimingProbe.shared.runLoopWillSleep()
        }

        state.withLock { current in
            current = State()
            current.isRecording = true
        }

        Self.runLoopObservers = [wake, sleep].compactMap { $0 }

        for observer in Self.runLoopObservers {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        mark(phase)
    }

    /// mark opens a new phase; everything recorded until the next mark belongs to it.
    func mark(_ phase: String) {
        state.withLock { current in
            guard current.isRecording else { return }

            current.phases.append(Phase(name: phase, mediaTime: CACurrentMediaTime()))
        }
    }

    /// tick records one display link update at `timestamp`. `isPaused` is whether the link pauses
    /// after it, so the next update follows an idle gap that is no hitch. Main only.
    func tick(at timestamp: CFTimeInterval, isPaused: Bool, skippedDraw: Bool) {
        state.withLock { current in
            guard current.isRecording else { return }

            if let last = current.lastTick {
                current.record("tick-gap", at: timestamp, lasting: timestamp - last)
            }

            current.record("ticks", at: timestamp)

            if skippedDraw {
                current.record("gpu-busy-skip", at: timestamp)
            }

            current.lastTick = isPaused ? nil : timestamp
        }
    }

    /// presented records a drawable's presented time (0: not shown). `isContinuation` says the canvas
    /// wanted to draw on the update before too, so the gap since the last present counts. Any thread.
    func presented(at time: CFTimeInterval, isContinuation: Bool) {
        state.withLock { current in
            guard current.isRecording else { return }

            // A drawable never shown is a frame lost on its own; the next gap measures from nothing.
            guard time > 0 else {
                current.record("present-dropped", at: CACurrentMediaTime())
                current.lastPresent = nil
                return
            }

            if isContinuation, let last = current.lastPresent {
                current.record("present-gap", at: time, lasting: time - last)
            }

            current.record("presents", at: time)
            current.lastPresent = time
        }
    }

    /// gpuPass records how long the canvas's pass waited on the GPU after its commit (other GPU work,
    /// the engine's renders among it, runs first) and how long it ran. Any thread; host-time seconds.
    func gpuPass(committedAt: CFTimeInterval, start: CFTimeInterval, end: CFTimeInterval) {
        state.withLock { current in
            guard current.isRecording, start > 0, end >= start else { return }

            current.record("gpu-wait", at: end, lasting: max(0, start - committedAt))
            current.record("gpu-run", at: end, lasting: end - start)
        }
    }

    private func runLoopWillSleep() {
        let now = CACurrentMediaTime()

        state.withLock { current in
            guard current.isRecording, let wake = current.runLoopWake else { return }

            current.record("runloop", at: now, lasting: now - wake)
            current.runLoopWake = nil
        }
    }

    /// writeReport ends the recording and writes the per-phase table to `fileURL`, printing each row
    /// too. Main only, for the run loop observers.
    @MainActor
    func writeReport(to fileURL: URL) async {
        let (phases, samples) = state.withLock { current in
            current.isRecording = false
            return (current.phases, current.samples)
        }

        for observer in Self.runLoopObservers {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        Self.runLoopObservers = []

        guard !phases.isEmpty else { return }

        let rows = await Task.detached(priority: .utility) {
            Self.rows(phases: phases, samples: samples)
        }.value

        let text = ([Self.header] + rows).joined(separator: "\n") + "\n"

        do {
            try FileManager.default.createDirectory(
                at                          : fileURL.deletingLastPathComponent(),
                withIntermediateDirectories : true
            )
            try Data(text.utf8).write(to: fileURL)
            print("timing csv \(fileURL.path(percentEncoded: false))")
        } catch {
            print("timing csv not written: \(error.localizedDescription)")
        }

        for row in rows {
            print("timing \(row)")
        }
    }

    /// rows groups the samples by phase and owner: count, total, median, p95 and max in ms. The
    /// gaps of a phase also give its hitch rows, against that phase's median gap (see the type doc).
    private static func rows(phases: [Phase], samples: [Sample]) -> [String] {
        var rows = [String]()

        for (index, phase) in phases.enumerated() {
            let end   = index + 1 < phases.count ? phases[index + 1].mediaTime : .infinity
            let mine  = samples.filter { $0.mediaTime >= phase.mediaTime && $0.mediaTime < end }
            let last  = mine.map(\.mediaTime).max() ?? phase.mediaTime
            let span  = (end.isFinite ? end : last) - phase.mediaTime
            var owned = Dictionary(grouping: mine.map { ($0.owner, $0.duration * 1000) }, by: \.0)
                .mapValues { $0.map(\.1).sorted() }

            for (gap, hitch) in [("tick-gap", "tick-hitch"), ("present-gap", "present-hitch")] {
                guard let gaps = owned[gap], !gaps.isEmpty else { continue }

                let cadence = gaps[gaps.count / 2]
                let extra   = gaps.filter { $0 > hitchFactor * cadence }.map { $0 - cadence }

                if !extra.isEmpty {
                    owned[hitch] = extra.sorted()
                }
            }

            for owner in owned.keys.sorted() {
                let durations = owned[owner] ?? []

                func percentile(_ fraction: Double) -> Double {
                    durations[min(durations.count - 1, Int(fraction * Double(durations.count)))]
                }

                rows.append(String(
                    format: "%@,%.2f,%@,%d,%.2f,%.3f,%.3f,%.3f",
                    phase.name,
                    span,
                    owner,
                    durations.count,
                    durations.reduce(0, +),
                    percentile(0.5),
                    percentile(0.95),
                    durations.last ?? 0
                ))
            }
        }

        return rows
    }
}

#else

/// FrameTimingProbe in Release keeps only the entry points, empty and inlined, so the call sites
/// need no conditionals and nothing is measured, kept or written.
nonisolated final class FrameTimingProbe: Sendable {

    static let shared = FrameTimingProbe()

    @inline(__always)
    @discardableResult
    func measure<Result>(_ name: StaticString, _ body: () throws -> Result) rethrows -> Result {
        try body()
    }

    @inline(__always)
    func start(phase: String) {}

    @inline(__always)
    func mark(_ phase: String) {}

    @inline(__always)
    func tick(at timestamp: CFTimeInterval, isPaused: Bool, skippedDraw: Bool) {}

    @inline(__always)
    func presented(at time: CFTimeInterval, isContinuation: Bool) {}

    @inline(__always)
    func writeReport(to fileURL: URL) async {}
}

#endif
