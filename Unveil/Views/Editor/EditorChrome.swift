//
//  EditorChrome.swift
//  Unveil
//

import CoreGraphics
import Observation

/// EditorChrome is the state of the floating controls: which adjustment panel is open, if any.
///
/// It is shared by the SwiftUI overlay, which opens and switches panels from the toolbar, and by
/// the editor's UIKit side, which closes the panel when the canvas is tapped. It also remembers
/// whether the last switch went right or left in the toolbar, so the new panel slides in from
/// the matching side.
///
/// `touchableFrames` is where the overlay draws something that takes touches, in window points,
/// one frame per Region, for OverlayPassthroughView. It changes on every layout pass and nothing
/// renders from it, so it stays out of observation.
@Observable
@MainActor
final class EditorChrome {

    /// Region names each part of the overlay that takes touches.
    enum Region: Hashable {

        case emptyState
        case leadingBar
        case toolbar
    }

    private(set) var openGroup      : AdjustmentGroup?
    private(set) var isMovingForward: Bool = true

    @ObservationIgnored
    var touchableFrames: [Region: CGRect] = [:]

    /// toggle(_:) opens `group`, switches to it from another panel, or closes it if it is open.
    func toggle(_ group: AdjustmentGroup) {
        guard group != openGroup else {
            openGroup = nil
            return
        }

        isMovingForward = group.rawValue > (openGroup?.rawValue ?? -1)
        openGroup       = group
    }

    func close() {
        openGroup = nil
    }
}
