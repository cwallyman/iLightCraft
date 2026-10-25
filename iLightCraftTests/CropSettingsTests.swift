//
//  CropSettingsTests.swift
//  iLightCraftTests
//

import Foundation
import Testing
@testable import iLightCraft

struct CropSettingsTests {

    @Test
    func fourQuarterTurnsRestoreTheOrientation() {
        for initial in ["Normal", "FlipH", "Transpose", "Rotate270"] {
            var settings = CropSettings()
            settings.orientation = initial
            for _ in 0..<4 { settings.rotate(clockwise: true) }
            #expect(settings.orientation == initial)
        }
    }

    @Test
    func settingsDecodeAndEncodeTheEngineGeometry() throws {
        let json = #"{"orientation":"Rotate90","crop":{"geometry":{"rect":{"x0":0.1,"y0":0.2,"x1":0.8,"y1":0.9},"angle":4.5},"aspect":[4,5],"flip_h":true,"flip_v":false}}"#
        let decoded = try JSONDecoder().decode(CropSettings.self, from: Data(json.utf8))
        #expect(decoded.crop.geometry.angle == 4.5)
        #expect(decoded.crop.flip_h)
        #expect(decoded.crop.geometry.rect.x0 == 0.1)
        #expect(try JSONDecoder().decode(CropSettings.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test
    func aFreeCropExplicitlyClearsThePreviousAspectLock() throws {
        let bytes = try JSONEncoder().encode(CropSettings())
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let crop = try #require(object["crop"] as? [String: Any])
        #expect(crop["aspect"] is NSNull)
    }
}
