import Testing
import CoreGraphics
@testable import iLightCraft

struct EditorControlsLayoutTests {
    @Test func portraitPhoneReservesEqualPhotoAndControlSpace() {
        let layout = EditorControlsLayout(size: CGSize(width: 393, height: 700), isPhone: true)
        #expect(layout.isBottom)
        let controls = EditorControlsLayout.bottomHeight(available: 700)
        #expect(controls * 2 + 8 == 700)
    }
    @Test func landscapePhoneUsesSidePanelEvenWithCompactSizeClass() {
        let layout = EditorControlsLayout(size: CGSize(width: 780, height: 320), isPhone: true)
        #expect(!layout.isBottom)
        #expect(layout.sideWidth == 280)
        #expect(layout.size.width - layout.sideWidth - 8 > layout.sideWidth)
    }
    @Test func padAndMacKeepSideControlsInTallWindows() {
        let layout = EditorControlsLayout(size: CGSize(width: 820, height: 1000), isPhone: false)
        #expect(!layout.isBottom)
        #expect(EditorControlsLayout(size: CGSize(width: 1600, height: 900), isPhone: false).sideWidth == 360)
        #expect(EditorControlsLayout.bottomHeight(available: 0) == 0)
    }
}
