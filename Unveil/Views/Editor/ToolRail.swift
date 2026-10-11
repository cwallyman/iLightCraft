//
//  ToolRail.swift
//  Unveil
//

import SwiftUI

/// ToolRail is the trailing glass capsule of tools. Each tool is a toggle button, so the system
/// draws the selected one; the two bindings keep exactly one tool selected.
struct ToolRail: View {

    let tool       : EditorTool
    let isPhotoOpen: Bool
    let onSelect   : (EditorTool) -> Void

    var body: some View {
        VStack(spacing: 4) {

            button("Move", systemImage: "hand.raised", tool: .move)

            button("Adjust", systemImage: "slider.horizontal.3", tool: .adjust)
                .disabled(!isPhotoOpen)
        }
        .glassEffect(.regular, in: .capsule)
    }

    private func button(
        _ title    : LocalizedStringKey,
        systemImage: String,
        tool       : EditorTool
    ) -> some View {
        Toggle(isOn: Binding(
            get: { self.tool == tool },
            set: { onSelect($0 ? tool : .move) }
        )) {
            // The frame and shape sit on the label, so the whole 44 pt circle is drawn and hit-tested.
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .toggleStyle(.button)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier("tool-\(tool.rawValue)")
    }
}
