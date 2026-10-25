import Foundation
import Testing
@testable import iLightCraft

struct ToneCurveTests {
    @Test func hostilePointsAreRejectedWithoutProducingInvalidCommands() throws {
        #expect(throws: ToneCurvePoints.CurveError.self) { try ToneCurvePoints([.init(x: .nan, y: 0), .init(x: 1, y: 1)]) }
        #expect(throws: ToneCurvePoints.CurveError.self) { try ToneCurvePoints([.init(x: 0, y: 0), .init(x: 0, y: 1)]) }
        #expect(throws: ToneCurvePoints.CurveError.self) { try ToneCurvePoints([.init(x: 0, y: 0), .init(x: 1, y: 2)]) }
        var curve = try ToneCurvePoints()
        #expect(curve.insert(x: 0.5, y: 0.6) == 1)
        curve.move(1, x: 4, y: -1)
        #expect(curve.points[1].x < 1)
        #expect(curve.points[1].y == 0)
        #expect(curve.points[2].x == 1)
        curve.move(0, x: 0.5, y: 0.2)
        #expect(curve.points[0].x == 0)
        #expect(curve.points[0].y == 0.2)
    }

    @Test func drawingInterpolationPassesThroughKnotsAndDoesNotOvershoot() throws {
        let curve = try ToneCurvePoints([.init(x: 0, y: 0), .init(x: 0.25, y: 0.1), .init(x: 0.75, y: 0.9), .init(x: 1, y: 1)])
        for point in curve.points { #expect(abs(curve.value(at: point.x) - point.y) < 1e-9) }
        var previous = 0.0
        for step in 0...1024 {
            let value = curve.value(at: Double(step) / 1024)
            #expect(value >= previous && value <= 1)
            previous = value
        }
        let identity = try ToneCurvePoints()
        #expect(abs(identity.value(at: 0.37) - 0.37) < 1e-9)
    }

    @Test func nativeUndoIncludesEveryCurveChannelAndParametricSetting() throws {
        let text = #"{"curve":{"master":[{"x":0,"y":0},{"x":1,"y":0.8}],"red":[],"green":[],"blue":[],"lights":20},"masks":[],"light":{"exposure":1}}"#
        let snapshot = try EngineManager.nativeUndoSettings(from: text)
        let object = try #require(JSONSerialization.jsonObject(with: Data(snapshot.utf8)) as? [String: Any])
        let curve = try #require(object["curve"] as? [String: Any])
        #expect(curve["lights"] as? Int == 20)
        #expect((curve["master"] as? [[String: Double]])?.last?["y"] == 0.8)
        #expect(curve["red"] != nil && curve["green"] != nil && curve["blue"] != nil)
        #expect(object["masks"] != nil)
        #expect(object["light"] == nil)
    }
}
