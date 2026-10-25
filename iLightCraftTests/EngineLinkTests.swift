//
//  EngineLinkTests.swift
//  iLightCraftTests
//

import Testing
import iLightCraftEngine

struct EngineLinkTests {

    @Test
    func abiVersionMatchesHeader() {
        #expect(uv_abi_version() == UInt32(UV_ABI_VERSION))
    }
}
