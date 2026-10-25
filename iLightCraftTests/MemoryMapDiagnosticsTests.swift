//
//  MemoryMapDiagnosticsTests.swift
//  iLightCraftTests
//

import Foundation
import Metal
import Testing
@testable import iLightCraft

struct MemoryMapDiagnosticsTests {

    @Test
    func theE0LaunchOptionsParse() {
        let options = MeasurementLaunchOptions(arguments: [
            "/app/iLightCraft",
            "-iLightCraftMemoryMap",
            "-iLightCraftTimeline",
            "-iLightCraftCost",
            "-iLightCraftSweepFull",
        ])

        #expect(options.reportsMemoryMap)
        #expect(options.reportsTimeline)
        #expect(options.reportsCost)
        #expect(options.releasesEveryTick)
        #expect(!MeasurementLaunchOptions(arguments: ["/app/iLightCraft"]).reportsCost)
    }

    @Test
    func theTimelineRecordsOnlyBetweenStartAndStop() {
        OpenTimeline.mark("before")
        OpenTimeline.start()
        OpenTimeline.mark("first")
        OpenTimeline.mark("second")

        let marks = OpenTimeline.stop()
        OpenTimeline.mark("after")

        // Other tests may run engine commands meanwhile and add their own marks: look at ours only.
        let ours = marks.filter { $0.name == "first" || $0.name == "second" }

        #expect(ours.map(\.name) == ["first", "second"])
        #expect(ours[0].nanoseconds <= ours[1].nanoseconds)
        #expect(!marks.contains { $0.name == "before" || $0.name == "after" })
    }

    @Test
    func theLatencyLogIgnoresIntervalsUntilItIsStarted() {
        SliderLatencyLog.record(quality: "draft", startedAtNs: 1, outcome: "presented")
        #expect(!SliderLatencyLog.isActive)

        SliderLatencyLog.start()
        #expect(SliderLatencyLog.isActive)
        SliderLatencyLog.record(quality: "draft", startedAtNs: ProcessCostProbe.uptimeNs(), outcome: "presented")

        let summary = SliderLatencyLog.stop()

        #expect(!SliderLatencyLog.isActive)
        #expect((summary["draft"] as? [String: Any])?["count"] as? Int == 1)
    }

    @Test
    func aMemoryMapLineIsJSONWithTheCountersOfTheProcess() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sink   = FrameSink(device: device, maxPixels: 64)
        let line   = MemoryMapReport.line(moment: "test", elapsed: 1.5, engineJSON: #"{"engineBytes":7}"#, frames: sink)

        #expect(line.hasPrefix("MM "))

        let object    = try #require(JSONSerialization.jsonObject(with: Data(line.dropFirst(3).utf8)) as? [String: Any])
        let footprint = try #require(object["footprint"] as? [String: Any])
        let engine    = try #require(object["engine"] as? [String: Any])

        #expect(object["moment"] as? String == "test")
        #expect((footprint["physFootprint"] as? UInt64 ?? 0) > 0)
        #expect(engine["engineBytes"] as? Int == 7)
        #expect(object["regions"] is [String: Any])
    }

    @Test
    func theProcessCostDeltaCountsCPUAndNamesTheThreads() {
        ProcessCostProbe.registerMainThread()

        let start = ProcessCostProbe.sample()
        var sum   = 0.0

        for step in 0 ..< 20_000_000 {
            sum += Double(step).squareRoot()
        }

        let end    = ProcessCostProbe.sample()
        let report = ProcessCostProbe.delta(from: start, to: end)

        #expect(sum > 0)
        #expect((report["cpuMs"] as? Double ?? 0) > 0)
        #expect((report["wallMs"] as? Double ?? 0) > 0)
        #expect(!end.threads.isEmpty)
    }

    @Test
    func theCanvasGPUTimeAddsPassesAndIgnoresAnInvertedInterval() {
        CanvasGPUTime.reset()
        CanvasGPUTime.record(start: 1.0, end: 1.004)
        CanvasGPUTime.record(start: 2.0, end: 1.0)

        let totals = CanvasGPUTime.totals()

        #expect(totals.passes == 2)
        #expect(abs(totals.seconds - 0.004) < 1e-9)
        #expect(abs(totals.longest - 0.004) < 1e-9)
        CanvasGPUTime.reset()
    }
}
