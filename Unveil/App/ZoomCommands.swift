//
//  ZoomCommands.swift
//  Unveil
//

import SwiftUI

/// ZoomCommands puts Zoom In, Zoom Out, Zoom to Fit and Actual Size in the View menu with their
/// keyboard shortcuts (Cmd +, Cmd -, Cmd 0, Cmd 1).
///
/// They live at scene level because a toolbar Menu builds its items only while it is open, so
/// shortcuts on the zoom pill's items would never fire with the menu closed. Scene commands are
/// registered all the time, show in the iPadOS menu bar and in the shortcut overlay, and reach
/// the active editor's canvas through the focused scene value `zoomCanvas`. Cmd = for Zoom In
/// (US keyboards type plus with Shift) is a hidden alias in EditorView.
struct ZoomCommands: Commands {

    @FocusedValue(\.zoomCanvas)
    private var canvas

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { canvas?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(canvas == nil)

            Button("Zoom Out") { canvas?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(canvas == nil)

            Button("Zoom to Fit") { canvas?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(canvas == nil)

            Button("Actual Size") { canvas?.zoom(toPercent: 100) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(canvas == nil)
        }
    }
}
