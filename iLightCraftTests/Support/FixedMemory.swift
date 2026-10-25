//
//  FixedMemory.swift
//  iLightCraftTests
//

@testable import iLightCraft

/// FixedMemory reports the same available memory every time, for tests.
struct FixedMemory: AvailableMemoryReading {

    let bytes: UInt64

    func availableBytes() -> UInt64 {
        bytes
    }
}
