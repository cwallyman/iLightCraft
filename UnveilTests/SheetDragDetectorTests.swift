//
//  SheetDragDetectorTests.swift
//  UnveilTests
//

import Testing
@testable import Unveil

struct SheetDragDetectorTests {

    /// aLayoutPassIsNotADrag catches a detector that reads the two or three resolver calls of an
    /// ordinary layout pass (appearing, rotating) as a finger on the sheet.
    @Test
    func aLayoutPassIsNotADrag() {
        var detector = SheetDragDetector()

        let starts = [1.000, 1.001, 1.013, 1.200].map { detector.noteResolve(at: $0) }

        #expect(!starts.contains(true))
        #expect(!detector.isDragging)
    }

    /// aStreamOfCallsStartsOneDrag is a finger: two calls a frame start a drag once, and the
    /// end reports it.
    @Test
    func aStreamOfCallsStartsOneDrag() {
        var detector = SheetDragDetector()
        let starts = (0 ..< 20).map { frame in
            detector.noteResolve(at: Double(frame / 2) * 0.019 + Double(frame % 2) * 0.0005)
        }

        let wasDragging = detector.isDragging
        let firstEnd    = detector.end()
        let secondEnd   = detector.end()

        #expect(starts.filter { $0 }.count == 1)
        #expect(wasDragging && firstEnd && !secondEnd)
    }

    /// theLayoutAfterAReleaseIsIgnored catches the release's own burst of calls starting a
    /// second drag right after the first one ended.
    @Test
    func theLayoutAfterAReleaseIsIgnored() {
        var detector = SheetDragDetector()
        detector.release(at: 5.0)
        _ = detector.end()

        let starts = [5.001, 5.002, 5.004, 5.008, 5.010].map { detector.noteResolve(at: $0) }

        #expect(!starts.contains(true))
        #expect(!detector.isDragging)
    }
}
