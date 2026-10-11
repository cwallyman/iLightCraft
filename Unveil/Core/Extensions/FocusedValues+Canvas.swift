//
//  FocusedValues+Canvas.swift
//  Unveil
//

import SwiftUI

extension FocusedValues {

    /// zoomCanvas is the canvas of the active scene's editor while it shows a photo, so scene
    /// commands (ZoomCommands) reach it; nil otherwise (home shown, or no photo), which disables them.
    @Entry
    var zoomCanvas: CanvasView?
}
