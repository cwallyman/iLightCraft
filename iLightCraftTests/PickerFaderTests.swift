//
//  PickerFaderTests.swift
//  iLightCraftTests
//

import Testing
import UIKit
@testable import iLightCraft

@MainActor
struct PickerFaderTests {

    /// thePickerShowsOnlyOverARestingPanel catches a picker left over a dragged or expanded
    /// panel, or one hidden by the other panel's state: each panel's drag and detent count only
    /// while that panel is shown.
    @Test
    func thePickerShowsOnlyOverARestingPanel() {
        let fader      = PickerFader()
        let controller = SourcePickerHost.PickerController()
        controller.loadViewIfNeeded()
        fader.attach(controller.container)
        let pill = controller.container.pill

        fader.source = .photos
        #expect(pill?.alpha == 1)

        fader.setDragging(true, for: .photos)
        #expect(pill?.alpha == 0)

        fader.setDragging(false, for: .photos)
        fader.setExpanded(false, for: .photos)
        #expect(pill?.alpha == 1)

        fader.setExpanded(true, for: .files)
        #expect(pill?.alpha == 1)

        fader.source = .files
        #expect(pill?.alpha == 0)

        fader.setExpanded(false, for: .files)
        #expect(pill?.alpha == 1)
    }
}
