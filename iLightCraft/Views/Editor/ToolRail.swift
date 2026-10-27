//
//  ToolRail.swift
//  iLightCraft
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
            
            ForEach(EditorTool.allCases, id: \.title) { item in
                
                button(
                    item.title,
                    lightCraftIcon : item.lightCraftIcon,
                    tool        : item
                )
                
            }

        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    private func button(
        _ title    : String,
        lightCraftIcon: String,
        tool       : EditorTool
    ) -> some View {
        
        Toggle(
            isOn: Binding(
                get: { self.tool == tool },
                set: { onSelect($0 ? tool : .move) }
            )
        ) {
            // A 32 pt label with the small control size keeps the rail compact; the frame and shape
            // sit on the label, so the whole circle is hit-tested.
            Label(title, lightCraftIcon: lightCraftIcon)
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(.circle)
        }
        .toggleStyle(.button)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .accessibilityIdentifier("tool-\(tool.rawValue)")
        .tint(.primary)
    }
}
