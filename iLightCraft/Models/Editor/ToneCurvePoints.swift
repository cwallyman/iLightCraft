import Foundation

/// Normalized points shared by the graph, precise controls and engine command payload.
nonisolated struct ToneCurvePoints: Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
    }
    static let identity = [Point(x: 0, y: 0), Point(x: 1, y: 1)]
    static let spacing = 1.0 / 1024
    private(set) var points: [Point]

    init(_ saved: [Point] = []) throws {
        guard saved.count <= 64, saved.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw CurveError.invalidPoints
        }
        var ordered = saved.sorted { $0.x < $1.x }
        if ordered.isEmpty { ordered = Self.identity }
        guard ordered.count >= 2, zip(ordered, ordered.dropFirst()).allSatisfy({ $1.x - $0.x >= Self.spacing }) else {
            throw CurveError.invalidPoints
        }
        points = ordered
    }

    @discardableResult
    mutating func insert(x: Double, y: Double) -> Int? {
        guard x.isFinite, y.isFinite, points.count < 64 else { return nil }
        let x = min(1, max(0, x)), y = min(1, max(0, y))
        guard points.allSatisfy({ abs($0.x - x) >= Self.spacing }) else { return nil }
        let index = points.firstIndex(where: { $0.x > x }) ?? points.count
        points.insert(Point(x: x, y: y), at: index)
        return index
    }

    mutating func move(_ index: Int, x: Double, y: Double) {
        guard points.indices.contains(index), x.isFinite, y.isFinite else { return }
        let old = points[index]
        let minimum = index > 0 ? points[index - 1].x + Self.spacing : 0
        let maximum = index + 1 < points.count ? points[index + 1].x - Self.spacing : 1
        // Keep the black/white anchors on their input boundaries; their output can still move.
        let locked = old.x == 0 || old.x == 1
        points[index] = Point(x: locked ? old.x : min(maximum, max(minimum, x)), y: min(1, max(0, y)))
    }

    mutating func remove(_ index: Int) {
        guard points.indices.contains(index), points.count > 2, index > 0, index < points.count - 1 else { return }
        points.remove(at: index)
    }

    /// Same Fritsch–Carlson interpolation used by the Rust renderer (color/src/spline.rs).
    /// Drawing the same curve avoids presenting a different interpolation from the saved edit.
    func value(at x: Double) -> Double {
        guard x.isFinite, let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        let n = points.count
        var slopes = [Double](repeating: 0, count: n - 1)
        for i in slopes.indices { slopes[i] = (points[i + 1].y - points[i].y) / (points[i + 1].x - points[i].x) }
        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = slopes[0]; tangents[n - 1] = slopes[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
            }
        }
        for i in slopes.indices {
            if slopes[i] == 0 { tangents[i] = 0; tangents[i + 1] = 0; continue }
            let a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i]
            let magnitude = a * a + b * b
            if magnitude > 9 {
                let gain = 3 / magnitude.squareRoot()
                tangents[i] = gain * a * slopes[i]; tangents[i + 1] = gain * b * slopes[i]
            }
        }
        let i = max(0, (points.firstIndex(where: { $0.x >= x }) ?? (n - 1)) - 1)
        let h = points[i + 1].x - points[i].x
        let t = (x - points[i].x) / h, t2 = t * t, t3 = t * t * t
        return min(1, max(0, (2 * t3 - 3 * t2 + 1) * points[i].y
            + (t3 - 2 * t2 + t) * h * tangents[i]
            + (-2 * t3 + 3 * t2) * points[i + 1].y
            + (t3 - t2) * h * tangents[i + 1]))
    }

    enum CurveError: Error, LocalizedError {
        case invalidPoints
        var errorDescription: String? { "This curve contains invalid, overlapping or too many points. Reset the channel to edit it." }
    }
}

nonisolated enum ToneCurveChannel: String, CaseIterable, Identifiable, Sendable {
    case master, red, green, blue
    var id: String { rawValue }
    var title: String { self == .master ? "RGB" : rawValue.capitalized }
}
