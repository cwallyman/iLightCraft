//
//  CanvasSpringTests.swift
//  UnveilTests
//

import Testing
@testable import Unveil

struct CanvasSpringTests {

    @Test
    func theSpringStartsAtTheStartAndEndsExactlyOnTheTarget() {
        let start  = CanvasTransform(zoom: 1, offset: .zero)
        let target = CanvasTransform(zoom: 4, offset: SIMD2(120, -40))
        let spring = CanvasSpring(from: start, to: target)

        let first = spring.transform(at: 0.0001)

        #expect(abs(first.zoom - 1) < 0.01 && abs(first.offset.x) < 0.5)
        #expect(spring.isSettled(at: 3))
        #expect(spring.transform(at: 3) == target)
    }

    @Test
    func aCriticallyDampedSpringNeverOvershoots() {
        let start  = CanvasTransform(zoom: 2, offset: .zero)
        let target = CanvasTransform(zoom: 2, offset: SIMD2(300, 0))
        let spring = CanvasSpring(from: start, to: target, offsetVelocity: SIMD2(600, 0), frequency: CanvasSpring.momentumFrequency)

        let samples = stride(from: 0.0, through: 3, by: 1.0 / 120).map { spring.transform(at: $0).offset.x }

        #expect(samples.allSatisfy { $0 <= 300.0001 })
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
    }
}
