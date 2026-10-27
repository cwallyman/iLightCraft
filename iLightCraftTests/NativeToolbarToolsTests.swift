//
//  NativeToolbarToolsTests.swift
//  iLightCraftTests
//

import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import iLightCraft

struct NativeToolbarToolsTests {
    @Test func keywordsKeepUnicodeAndRejectEmptyOversizedOrMultilineValues() {
        #expect(NativeKeywordInput.clean("  Café | 秋  ") == "Café | 秋")
        #expect(NativeKeywordInput.clean("   ") == nil)
        #expect(NativeKeywordInput.clean("one\ntwo") == nil)
        #expect(NativeKeywordInput.clean(String(repeating: "a", count: 257)) == nil)
        #expect(NativeKeywordInput.clean(String(repeating: "秋", count: 256)) != nil)
    }
    @Test func eyeRequestsEncodeNormalizedCoordinatesAndEngineParameterNames() throws {
        let request = try #require(NativeEyeRequest(center: CGPoint(x: 0.25, y: 0.75), radius: 0.03, pupilSize: 60, darken: 40, pet: true))
        let value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(value["center"] as? [Double] == [0.25, 0.75])
        #expect(value["rx"] as? Double == 0.03)
        #expect(value["ry"] as? Double == 0.03)
        #expect(value["pupilSize"] as? Double == 60)
        #expect(value["darken"] as? Double == 40)
        #expect(value["pet"] as? Bool == true)
    }
    @Test @MainActor func cropGuidesHandleEmptyBoundsAndProduceFiniteGeometry() {
        for name in ["thirds", "grid", "golden", "diagonal", "triangle", "spiral", "none"] {
            #expect(NativeCropGuides.path(in: .zero, kind: name, flipped: false).isEmpty)
            let path = NativeCropGuides.path(in: CGRect(x: 10, y: 20, width: 480, height: 320), kind: name, flipped: true)
            if name == "none" { #expect(path.isEmpty) }
            else {
                let bounds = path.cgPath.boundingBoxOfPath
                #expect(!path.isEmpty && bounds.width.isFinite && bounds.height.isFinite)
                #expect(bounds.width > 0 && bounds.height > 0)
            }
        }
    }
    @Test func invalidEyeCoordinatesAndAmountsCannotProduceCommands() {
        #expect(NativeEyeRequest(center: CGPoint(x: -0.1, y: 0.5), radius: 0.02, pupilSize: 50, darken: 50, pet: false) == nil)
        #expect(NativeEyeRequest(center: CGPoint(x: .nan, y: 0.5), radius: 0.02, pupilSize: 50, darken: 50, pet: false) == nil)
        #expect(NativeEyeRequest(center: CGPoint(x: 0.5, y: 0.5), radius: .infinity, pupilSize: 50, darken: 50, pet: false) == nil)
        #expect(NativeEyeRequest(center: CGPoint(x: 0.5, y: 0.5), radius: 0.02, pupilSize: 101, darken: 50, pet: false) == nil)
    }
}

@Suite(.serialized)
@MainActor
struct NativePhotoPanelWorkflowTests {
    @Test func cullingCopyKeywordsAndEyeCorrectionsUseTheRealEngine() async throws {
        let directory = URL.temporaryDirectory.appending(path: "native-toolbar-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "photo.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.red.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 24, y: 24, width: 16, height: 16))
        }
        try #require(image.pngData()).write(to: file)
        let engine = try EngineManager(dataDirectory: directory.appending(path: "Library"), maxPixels: 128)
        let model = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 128)
        await model.open(pickedURL: file)
        #expect(model.isPhotoOpen)

        let panel = PhotoPanelSession(model: model)
        await panel.load()
        #expect(panel.error == nil)
        await panel.setRating(4); await panel.setFlag("pick")
        #expect(panel.rating == 4); #expect(panel.flag == "pick")
        await panel.sort("fileName", ascending: true, group: "none")
        #expect(panel.sortKey == "fileName"); #expect(panel.ascending); #expect(panel.groupBy == "none")
        _ = try await model.performPhotoEdit("develop.set", params: ["values": ["light.exposure": 1.0]])
        await panel.copyOrPaste(copyOnly: true)
        #expect(panel.hasClipboard)
        _ = try await model.performPhotoEdit("develop.set", params: ["values": ["light.exposure": 2.0]])
        await panel.copyOrPaste()
        #expect(model.values[.exposure] == 1.0)

        let keywords = EditorAuxiliarySession(model: model, mode: .keywords)
        await keywords.load(); #expect(keywords.error == nil)
        keywords.keyword = "Places|Café"
        await keywords.addKeyword()
        #expect(keywords.keywords.contains("Places|Café"))
        keywords.setName = "My Set"; await keywords.saveSet()
        #expect(keywords.keywordSets.contains("My Set"))
        await keywords.removeKeyword("Places|Café")
        #expect(!keywords.keywords.contains("Places|Café"))

        let eye = EditorAuxiliarySession(model: model, mode: .redEye)
        await eye.load(); #expect(eye.image != nil)
        eye.center = CGPoint(x: 0.5, y: 0.5); eye.radius = 0.1; eye.pet = true
        await eye.addEye(); #expect(eye.eyes.count == 1)
        await eye.adjustEye(0, pupilSize: 60, darken: 40)
        #expect(eye.eyes.first?.pupil_size == 60)
        await eye.catchlight(0, on: true)
        #expect(eye.eyes.first?.catchlight != nil)
        await eye.removeEye(0); #expect(eye.eyes.isEmpty)

        let edit = LightCraftEditSession(model: model)
        await edit.load(); #expect(edit.error == nil)
        #expect(edit.matching(["calibration"]).count == 7)
        #expect(edit.matching(["detail"]).count >= 10)
        let preview = try await panel.thumbnail(try #require(model.openPhoto).rawValue)
        #expect(preview.size.width > 0)
        await panel.choose(.photoGrid)
        #expect(panel.photos.contains { $0.id == model.openPhoto?.rawValue })
        await panel.choose(.detail)
        let crop = CropEditorSession(model: model)
        await crop.loadPreview()
        crop.setCustomAspect(3, 2)
        #expect(crop.ratio == 1.5)
        crop.swapAspect()
        #expect(abs(Double(crop.ratio ?? 0) - 2.0/3.0) < 0.001)
        crop.lockAspect(false)
        #expect(crop.ratio == nil)
        #expect(panel.error == nil); #expect(keywords.error == nil); #expect(eye.error == nil)
    }
}
