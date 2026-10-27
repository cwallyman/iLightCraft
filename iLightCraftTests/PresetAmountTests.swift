//
//  PresetAmountTests.swift
//  iLightCraftTests
//

import Foundation
import Testing
import UIKit
@testable import iLightCraft

/// Saved for user execution; no simulator or test run is performed for this change.
@Suite(.serialized)
@MainActor
struct PresetAmountTests {
    @Test func amountUsesOriginalBaselineAndResetKeepsEarlierEdits() async throws {
        let directory = URL.temporaryDirectory.appending(path: "preset-amount-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "photo.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        try #require(image.pngData()).write(to: file)
        let engine = try EngineManager(dataDirectory: directory.appending(path: "Library"), maxPixels: 128)
        let model = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 128)
        await model.open(pickedURL: file)
        _ = try await model.performPhotoEdit("develop.set", params: ["values": ["light.exposure": 0.35, "light.contrast": 12.0]])
        let session = PresetVersionSession(model: model, onOpen: { _, _ in })
        await session.load(includePhotos: false)
        let preset = try #require(session.presets.first { $0.id == "lc.vivid-pop" })
        await session.applyPreset(preset)
        #expect(session.appliedPresetID == preset.id)
        #expect(model.values[.contrast] == 18)
        session.amount = 50; await session.updatePresetAmount()
        #expect(model.values[.contrast] == 15)
        session.amount = 150; await session.updatePresetAmount()
        #expect(model.values[.contrast] == 21)
        session.amount = 50; await session.updatePresetAmount()
        #expect(model.values[.contrast] == 15)
        await session.resetPreset()
        #expect(model.values[.contrast] == 12)
        #expect(abs((model.values[.exposure] ?? 0) - 0.35) < 0.0001)
        #expect(session.appliedPresetID == nil && session.amount == 100)
        #expect(session.error == nil)

        // A different preset must discard values the previous preset alone introduced.
        await session.applyPreset(preset)
        let replacement = try #require(session.presets.first { $0.id == "lc.cool-morning" })
        let reopened = PresetVersionSession(model: model, onOpen: { _, _ in })
        await reopened.load(includePhotos: false)
        #expect(reopened.appliedPresetID == preset.id)
        await reopened.applyPreset(replacement)
        #expect(reopened.appliedPresetID == replacement.id)
        #expect(model.values[.contrast] == 12)
        #expect(model.values[.whites] == 0)
        #expect(model.values[.blacks] == 0)
        #expect(model.values[.clarity] == 0)
        #expect(model.values[.saturation] == 0)
        #expect(model.values[.highlights] == -20)
        #expect(abs((model.values[.exposure] ?? 0) - 0.35) < 0.0001)
        await reopened.resetPreset()
        #expect(model.values[.contrast] == 12 && model.values[.highlights] == 0)
        #expect(model.presetReplacementState == nil)

        await session.applyPreset(preset)
        _ = try await model.performPhotoEdit("develop.set", params: ["values": ["light.exposure": 1.0]])
        session.amount = 25; await session.updatePresetAmount()
        #expect(session.error != nil)
        #expect(model.values[.exposure] == 1)
    }
}
