//
//  ComputationalToolsTests.swift
//  iLightCraftTests
//

import CoreVideo
import Foundation
import Testing
@testable import iLightCraft

struct ComputationalToolsTests {
    @Test
    func modelMaskCoverageAndInversionPreserveImageCoordinates() throws {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_OneComponent8, nil, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        #expect(CVPixelBufferLockBaseAddress(pixels, []) == kCVReturnSuccess)
        let base = try #require(CVPixelBufferGetBaseAddress(pixels))
        let row = CVPixelBufferGetBytesPerRow(pixels)
        base.storeBytes(of: UInt8(255), toByteOffset: 0, as: UInt8.self)
        base.storeBytes(of: UInt8(0), toByteOffset: 1, as: UInt8.self)
        base.storeBytes(of: UInt8(0), toByteOffset: row, as: UInt8.self)
        base.storeBytes(of: UInt8(255), toByteOffset: row + 1, as: UInt8.self)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let mask = try OnDeviceAnalysis.selection(from: pixels, inverted: false)
        let background = try OnDeviceAnalysis.selection(from: pixels, inverted: true)
        #expect(mask.side == 256)
        #expect(mask.alpha[0] == 255)
        #expect(mask.alpha[255] == 0)
        #expect(mask.alpha[255 * 256] == 0)
        #expect(mask.alpha[256 * 256 - 1] == 255)
        #expect(zip(mask.alpha, background.alpha).allSatisfy { Int($0.0) + Int($0.1) == 255 })
    }
    @Test
    func localSearchCombinesImageLabelsOCRAndPeopleWithoutAService() throws {
        var index = LocalAnalysisIndex()
        try index.record(id: 1, name: "coast", analysis: .init(labels: ["beach", "sunset"], text: [], faces: 0))
        try index.record(id: 2, name: "receipt", analysis: .init(labels: ["document"], text: ["Coffee 12.50"], faces: 0))
        try index.record(id: 3, name: "portrait", analysis: .init(labels: ["portrait"], text: [], faces: 1))
        #expect(index.search("show me photos of the beach at sunset").map(\.id) == [1])
        #expect(index.search("coffee").map(\.id) == [2])
        #expect(index.search("people").map(\.id) == [3])
        #expect(index.search("unknown content").isEmpty)
        let restored = try JSONDecoder().decode(LocalAnalysisIndex.self, from: JSONEncoder().encode(index))
        #expect(restored.search("text").map(\.id) == [2])
    }
    @Test
    func semanticRankingRejectsInvalidVectorsAndPreservesCosineOrder() {
        #expect(LocalSemanticSearch.similarity([1, 0], [1, 0]) == 1)
        #expect(LocalSemanticSearch.similarity([1, 0], [0, 1]) == 0)
        #expect(LocalSemanticSearch.similarity([0, 0], [1, 0]) == nil)
        #expect(LocalSemanticSearch.similarity([Double.nan], [1]) == nil)
        #expect(LocalSemanticSearch.similarity([1, 2], [1]) == nil)
    }
    @Test
    func mergeSourcesShowReadableNamesInsteadOfImportHashes() throws {
        typealias Photo = PhotoMergeSession<EngineManager, PhotoImporter>.Photo
        let encoded = """
        {"id":1,"fileName":"\(String(repeating: "a", count: 64))-vacation.png","width":1200,"height":800}
        """
        let photo = try JSONDecoder().decode(Photo.self, from: Data(encoded.utf8))
        #expect(photo.name == "vacation")
    }
    @Test
    func allOptionalModelsHaveFixedRevisionsAndArchiveHashes() {
        #expect(DepthModelStore.files.allSatisfy { $0.size > 0 && $0.sha256.count == 64 })
        #expect(EnhancementModel.allCases.allSatisfy { $0.size < 3_000_000 && $0.sha256.count == 64 })
        #expect(DepthModelStore.revision.count == 40)
        #expect(EnhancementModel.revision.count == 40)
    }
}
