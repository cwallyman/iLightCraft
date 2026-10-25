import CoreGraphics
import Testing
@testable import iLightCraft

struct PhotoToolGeometryTests {
    @Test func toolCoordinatesUseImageContentRatherThanViewportOrDockSize() {
        #expect(PhotoToolGeometry.normalized(CGPoint(x: 150, y: 50), size: CGSize(width: 600, height: 200)) == CGPoint(x: 0.25, y: 0.25))
        #expect(PhotoToolGeometry.normalized(CGPoint(x: -40, y: 260), size: CGSize(width: 600, height: 200)) == CGPoint(x: 0, y: 1))
        #expect(PhotoToolGeometry.normalized(.zero, size: .zero) == nil)
        #expect(PhotoToolGeometry.normalized(CGPoint(x: CGFloat.nan, y: 2), size: CGSize(width: 20, height: 20)) == nil)
    }
    @Test func movingCropPreservesSizeAndStaysInImage() {
        let initial = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        let moved = PhotoToolGeometry.crop(initial, corner: nil, delta: CGPoint(x: 5, y: -5), ratio: nil, imageSize: CGSize(width: 1600, height: 900))
        #expect(moved == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        #expect(PhotoToolGeometry.crop(initial, corner: nil, delta: CGPoint(x: CGFloat.infinity, y: 0), ratio: nil, imageSize: .zero) == initial)
    }
    @Test func cornerResizeKeepsOppositeAnchorAndAspectAtEdges() {
        let initial = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        for corner in 0..<4 {
            let crop = PhotoToolGeometry.crop(initial, corner: corner, delta: CGPoint(x: 0.1, y: 0.1), ratio: 1, imageSize: CGSize(width: 1600, height: 900))
            #expect(crop.minX >= 0 && crop.minY >= 0 && crop.maxX <= 1 && crop.maxY <= 1)
            #expect(abs((crop.width * 1600) / (crop.height * 900) - 1) < 0.0001)
            if corner % 2 == 0 { #expect(abs(crop.maxX - initial.maxX) < 0.0001) }
            else { #expect(abs(crop.minX - initial.minX) < 0.0001) }
            if corner < 2 { #expect(abs(crop.maxY - initial.maxY) < 0.0001) }
            else { #expect(abs(crop.minY - initial.minY) < 0.0001) }
        }
    }
}
