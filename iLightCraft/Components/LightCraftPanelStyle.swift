//
//  LightCraftPanelStyle.swift
//  iLightCraft
//

import SwiftUI

/// LightCraftPanelStyle mirrors the desktop Charcoal panel tokens without importing artwork.
enum LightCraftPanelStyle {
    static let background = Color(red: 45.0 / 255, green: 45.0 / 255, blue: 45.0 / 255)
    static let inset = Color(red: 35.0 / 255, green: 35.0 / 255, blue: 35.0 / 255)
    static let text = Color(red: 226.0 / 255, green: 226.0 / 255, blue: 226.0 / 255)
    static let label = Color(red: 188.0 / 255, green: 188.0 / 255, blue: 188.0 / 255)
    static let divider = Color(red: 28.0 / 255, green: 28.0 / 255, blue: 28.0 / 255)
    static let changed = Color.accentColor
    static func isChanged(_ value: Double, from baseline: Double) -> Bool {
        value.isFinite && baseline.isFinite && abs(value - baseline) > max(0.000001, abs(baseline) * 0.000000001)
    }
    static let scrollGutter: CGFloat = 32
}

extension View {
    func lightCraftPanelContent() -> some View {
        self
            .font(.system(size: 14))
            .tint(LightCraftPanelStyle.label)
            .foregroundStyle(LightCraftPanelStyle.label)
            .scrollContentBackground(.hidden)
            .lightCraftScrollGutter()
            .background(LightCraftPanelStyle.background)
    }

    /// lightCraftScrollGutter leaves a blank drag area inside each scroll view, beside its controls.
    func lightCraftScrollGutter() -> some View {
        contentMargins(.trailing, LightCraftPanelStyle.scrollGutter, for: .scrollContent)
    }
}

/// LightCraftMenuList uses Edit's flat layout instead of platform Form and List row backgrounds.
struct LightCraftMenuList<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content() }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .lightCraftPanelContent().preferredColorScheme(.dark)
        .pickerStyle(.menu)
        .textFieldStyle(.plain)
    }
}

/// LightCraftMenuSection shares Edit's section type, spacing and divider colors.
struct LightCraftMenuSection<Content: View, Footer: View>: View {
    let title: String?
    let content: Content
    let footer: Footer
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.title = title; self.content = content(); self.footer = EmptyView()
    }
    init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title; self.content = content(); self.footer = footer()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(LightCraftPanelStyle.text)
            }
            content
            footer.font(.system(size: 12)).foregroundStyle(LightCraftPanelStyle.label)
            Rectangle().fill(LightCraftPanelStyle.divider).frame(height: 1).padding(.top, 4)
        }
    }
}
