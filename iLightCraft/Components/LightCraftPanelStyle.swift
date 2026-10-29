//
//  LightCraftPanelStyle.swift
//  iLightCraft
//

import SwiftUI
import UIKit

/// LightCraftPanelStyle mirrors the desktop Charcoal panel tokens without importing artwork.
enum LightCraftPanelStyle {
    // On iPad the classic panel greys resolve to the inspector palette, so no tool shows a second grey.
    static var background: Color { isPad ? iPadBackground : Color(red: 45.0 / 255, green: 45.0 / 255, blue: 45.0 / 255) }
    static var inset: Color { isPad ? iPadInset : Color(red: 35.0 / 255, green: 35.0 / 255, blue: 35.0 / 255) }
    static let iPadBackground = Color(red: 24.0 / 255, green: 24.0 / 255, blue: 28.0 / 255)
    static let iPadInset = Color(red: 31.0 / 255, green: 31.0 / 255, blue: 35.0 / 255)
    static let text = Color(red: 226.0 / 255, green: 226.0 / 255, blue: 226.0 / 255)
    static let label = Color(red: 188.0 / 255, green: 188.0 / 255, blue: 188.0 / 255)
    static let divider = Color(red: 28.0 / 255, green: 28.0 / 255, blue: 28.0 / 255)
    static let changed = Color.accentColor
    static func isChanged(_ value: Double, from baseline: Double) -> Bool {
        value.isFinite && baseline.isFinite && abs(value - baseline) > max(0.000001, abs(baseline) * 0.000000001)
    }
    static let scrollGutter: CGFloat = 32
    // iPad inspector: grouped cards on a near-black panel, amber for selection and edits.
    static let iPadCard = Color(red: 36.0 / 255, green: 36.0 / 255, blue: 41.0 / 255)
    static let iPadCardTop = Color(red: 44.0 / 255, green: 44.0 / 255, blue: 50.0 / 255)
    static let iPadCardBorder = Color.white.opacity(0.07)
    static let iPadTrack = Color(red: 66.0 / 255, green: 66.0 / 255, blue: 72.0 / 255)
    static let highlight = Color(red: 242.0 / 255, green: 165.0 / 255, blue: 22.0 / 255)
    static let cardRadius: CGFloat = 16
    static var isPad: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}

extension View {
    /// lightCraftCard groups related controls the way the iPad inspector draws its sections.
    func lightCraftCard(padding: CGFloat = 14) -> some View {
        self.padding(padding).lightCraftCardSurface()
    }

    /// lightCraftCardSurface raises a card off the panel: a lit top edge, a soft drop shadow
    /// and a faint top-to-bottom shade, like the system's grouped inspector cards.
    func lightCraftCardSurface(cornerRadius: CGFloat = LightCraftPanelStyle.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background {
                shape.fill(LinearGradient(colors: [LightCraftPanelStyle.iPadCardTop, LightCraftPanelStyle.iPadCard], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }

    /// lightCraftGlassButton is the inspector's capsule action, such as Auto, Reset or Done.
    func lightCraftGlassButton(prominent: Bool = false) -> some View {
        self.font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.black : LightCraftPanelStyle.text)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.3), LightCraftPanelStyle.highlight], startPoint: .top, endPoint: .bottom))
                        .shadow(color: LightCraftPanelStyle.highlight.opacity(0.35), radius: 10)
                } else {
                    Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                }
            }
            .contentShape(.capsule)
    }
}

extension View {
    func lightCraftPanelContent(iPadStyle: Bool = false) -> some View {
        self
            .font(.system(size: 14))
            .tint(LightCraftPanelStyle.label)
            .foregroundStyle(LightCraftPanelStyle.label)
            .scrollContentBackground(.hidden)
            .lightCraftScrollGutter()
            .background(iPadStyle ? LightCraftPanelStyle.iPadBackground : LightCraftPanelStyle.background)
    }

    /// lightCraftFloatingGlass is glass over the panel grey, so capsules floating on the black photo
    /// surround match the glass buttons inside the panel.
    func lightCraftFloatingGlass<S: Shape>(_ shape: S) -> some View {
        glassEffect(.regular, in: shape).background(LightCraftPanelStyle.iPadBackground, in: shape)
    }

    /// lightCraftTextField is a rounded card field on iPad and the system rounded border elsewhere.
    @ViewBuilder func lightCraftTextField() -> some View {
        if LightCraftPanelStyle.isPad {
            textFieldStyle(.plain).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .lightCraftCardSurface(cornerRadius: 14)
        } else {
            textFieldStyle(.roundedBorder)
        }
    }

    /// lightCraftScrollGutter leaves a blank drag area inside each scroll view, beside its controls.
    func lightCraftScrollGutter() -> some View {
        // iPad sliders are wide enough to scroll beside; the gutter only wasted panel width.
        contentMargins(.trailing, LightCraftPanelStyle.isPad ? 0 : LightCraftPanelStyle.scrollGutter, for: .scrollContent)
    }
}

/// LightCraftMenuList uses Edit's flat layout instead of platform Form and List row backgrounds.
struct LightCraftMenuList<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LightCraftPanelStyle.isPad ? 12 : 18) { content() }
                .frame(maxWidth: .infinity, alignment: .leading).padding(LightCraftPanelStyle.isPad ? 14 : 20)
        }
        .lightCraftPanelContent(iPadStyle: LightCraftPanelStyle.isPad).preferredColorScheme(.dark)
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
        if LightCraftPanelStyle.isPad {
            VStack(alignment: .leading, spacing: 12) {
                if let title {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(LightCraftPanelStyle.text)
                }
                content
                footer.font(.system(size: 12)).foregroundStyle(LightCraftPanelStyle.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lightCraftCard()
        } else {
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
}
