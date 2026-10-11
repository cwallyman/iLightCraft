//
//  FrameWindowTests.swift
//  UnveilTests
//

import CoreGraphics
import Testing
@testable import Unveil

/// FrameWindowTests checks the window the canvas asks for, on the iPad Air's view (1180 x 820 points
/// at 2x, a 2360 x 1573 preview) and the 24 MP RAF's size.
struct FrameWindowTests {

    let viewSize  = CGSize(width: 1180, height: 820)
    let imageSize = CGSize(width: 2360, height: 1573)
    let photoSize = CGSize(width: 6240, height: 4160)

    /// transform(atPercent:offset:) is the canvas zoomed to that real percentage.
    private func transform(atPercent percent: Double, offset: SIMD2<Double> = .zero) throws -> CanvasTransform {
        let scale = try #require(ZoomScale(
            viewSize    : viewSize,
            imageSize   : imageSize,
            screenScale : 2,
            photoScale  : CanvasTransform.photoScale(previewSize: imageSize, photoSize: photoSize)
        ))

        return CanvasTransform(zoom: scale.zoom(forPercent: percent), offset: offset)
    }

    private func window(
        _ transform: CanvasTransform,
        imageSize  : CGSize? = nil,
        photoSize  : CGSize? = nil,
        maxPixels  : Int = 2560
    ) -> FrameWindow? {
        FrameWindow.visible(
            transform   : transform,
            viewSize    : viewSize,
            imageSize   : imageSize ?? self.imageSize,
            photoSize   : photoSize ?? self.photoSize,
            screenScale : 2,
            maxPixels   : maxPixels
        )
    }

    @Test
    func atFitThePreviewIsEnough() throws {
        #expect(window(CanvasTransform()) == nil)
        #expect(window(try transform(atPercent: 37)) == nil)
    }

    @Test
    func anUnknownPhotoSizeAsksForNothing() throws {
        #expect(window(try transform(atPercent: 100), photoSize: .zero) == nil)
    }

    /// At 100 % the frame is the photo itself and the window is the screen plus the margin, centred.
    /// Both edges round outward, and the preview's rows (1573 for 1573.33) stretch over the frame's
    /// 4160, so the window can be two pixels over the screen plus the margin.
    @Test
    func atHundredPercentTheWindowIsTheScreenOfRealPixelsPlusTheMargin() throws {
        let shown = try #require(window(try transform(atPercent: 100)))

        #expect(shown.frameWidth == 6240 && shown.frameHeight == 4160)
        #expect(abs(shown.width - (2360 + 2 * FrameWindow.margin)) <= 2)
        #expect(abs(shown.height - (1640 + 2 * FrameWindow.margin)) <= 2)
        #expect(abs(shown.x + shown.width / 2 - 3120) <= 1)
        #expect(abs(shown.y + shown.height / 2 - 2080) <= 1)
    }

    /// A zoom a hair short of 100 % (where a spring may stop) still renders the real pixels.
    @Test
    func aZoomJustShortOfHundredPercentRendersTheRealPixels() throws {
        let shown = try #require(window(try transform(atPercent: 99.9)))

        #expect(shown.frameWidth == 6240)
    }

    /// Past 100 % the frame stays the photo's real pixels: only the window shrinks with the view.
    @Test
    func pastHundredPercentTheFrameStaysAtTheRealPixels() throws {
        let shown = try #require(window(try transform(atPercent: 800)))

        #expect(shown.frameWidth == 6240 && shown.frameHeight == 4160)
        #expect(abs(shown.width - (2360 / 8 + 2 * FrameWindow.margin)) <= 1)
    }

    @Test
    func belowHundredPercentTheFrameIsThePhotoAtTheZoom() throws {
        let shown = try #require(window(try transform(atPercent: 50)))

        #expect(shown.frameWidth == 3120 && shown.frameHeight == 2080)
        #expect(abs(shown.width - (2360 + 2 * FrameWindow.margin)) <= 1)
    }

    @Test
    func aWindowAtTheEdgeIsClampedIntoTheFrame() throws {
        let atEdge = try transform(atPercent: 100, offset: SIMD2(1e6, 1e6))
        let shown  = try #require(window(atEdge.settled(viewSize: viewSize, imageSize: imageSize)))

        #expect(shown.x == 0 && shown.y == 0)
        #expect(abs(shown.width - (2360 + FrameWindow.margin)) <= 1)
    }

    @Test
    func aWindowWiderThanTheBuffersKeepsTheMiddleOfTheView() throws {
        let shown = try #require(window(try transform(atPercent: 100), maxPixels: 2000))

        #expect(shown.width == 2000)
        #expect(abs(shown.x + 1000 - 3120) <= 1)
    }

    /// With a crop the engine's native size is the crop's own pixels: 100 % is that frame, with its
    /// aspect, not the uncropped photo resampled.
    @Test
    func aCroppedFrameAtHundredPercentIsTheCropsOwnPixels() throws {
        let crop  = CGSize(width: 3000, height: 1500)
        let image = CGSize(width: 2360, height: 1180)
        let scale = try #require(ZoomScale(
            viewSize    : viewSize,
            imageSize   : image,
            screenScale : 2,
            photoScale  : CanvasTransform.photoScale(previewSize: image, photoSize: crop)
        ))
        let shown = try #require(window(
            CanvasTransform(zoom: scale.zoom(forPercent: 100)),
            imageSize : image,
            photoSize : crop
        ))

        #expect(shown.frameWidth == 3000 && shown.frameHeight == 1500)
    }

    @Test
    func aPortraitPhotoGetsAPortraitFrame() throws {
        let portrait = CGSize(width: 1230, height: 1640)
        let photo    = CGSize(width: 3024, height: 4032)
        let scale    = try #require(ZoomScale(
            viewSize    : viewSize,
            imageSize   : portrait,
            screenScale : 2,
            photoScale  : CanvasTransform.photoScale(previewSize: portrait, photoSize: photo)
        ))
        let shown    = try #require(window(
            CanvasTransform(zoom: scale.zoom(forPercent: 100)),
            imageSize : portrait,
            photoSize : photo
        ))

        #expect(shown.frameWidth == 3024 && shown.frameHeight == 4032)
    }

    @Test
    func theQuadIsTheWindowsShareOfTheImage() {
        let shown = FrameWindow(
            frameWidth  : 400,
            frameHeight : 200,
            x           : 100,
            y           : 50,
            width       : 200,
            height      : 100
        )
        let quad  = shown.quad(in: (min: SIMD2(-1, -1), max: SIMD2(1, 1)))

        #expect(quad.min == SIMD2(-0.5, -0.5))
        #expect(quad.max == SIMD2(0.5, 0.5))
    }

    @Test
    func theSameLongEdgeIsTheSameFrame() {
        let asked = FrameWindow(
            frameWidth  : 6240,
            frameHeight : 4159,
            x           : 0,
            y           : 0,
            width       : 10,
            height      : 10
        )
        let back  = FrameWindow(
            frameWidth  : 6240,
            frameHeight : 4160,
            x           : 0,
            y           : 0,
            width       : 10,
            height      : 10
        )
        let other = FrameWindow(
            frameWidth  : 3120,
            frameHeight : 2080,
            x           : 0,
            y           : 0,
            width       : 10,
            height      : 10
        )

        let widerByOne = FrameWindow(
            frameWidth  : 6241,
            frameHeight : 4160,
            x           : 0,
            y           : 0,
            width       : 10,
            height      : 10
        )

        #expect(asked.hasSameFrame(as: back))
        #expect(!asked.hasSameFrame(as: other))
        #expect(!asked.hasSameFrame(as: widerByOne))
    }
}
