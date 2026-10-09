//
//  EditorOverlay.swift
//  Unveil
//

import SwiftUI

/// EditorOverlay is everything that floats over the canvas: the empty-state placeholder while no
/// photo is open, the glass capsule on the top left (Apri, diagnostics) and, once a photo is open,
/// the glass toolbar on the top right whose segments open the adjustment panels.
///
/// The canvas stays canvas-first. With a photo open the only things on screen are the two small
/// glass bars and, on demand, one panel anchored under the toolbar; with no photo the placeholder
/// covers the (black) canvas with a neutral white or near-black surface. The hosting view is
/// transparent, and every part that takes touches reports its frame to `chrome` (see
/// `touchable(_:)`), so OverlayPassthroughView sends the touches anywhere else to the canvas.
///
/// Motion: the selection capsule slides between segments (matchedGeometryEffect), the panel grows
/// out of the toolbar's corner, and a new panel's content slides in from the side of the segment
/// it came from while the old one fades. The old content only fades because SwiftUI keeps the
/// removal transition a view had when it was last drawn, before the direction of the new switch
/// was known. With Reduce Motion every one of these becomes a cross-fade.
struct EditorOverlay<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel      : EditorViewModel<Engine, Importer>
    let chrome         : EditorChrome
    let diagnosticsMenu: UIMenu
    let onOpen         : () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.accessibilityReduceMotion)
    private var isReduceMotionOn

    @Namespace
    private var segmentNamespace

    private static var panelWidth  : CGFloat { 340 }
    private static var toolbarWidth: CGFloat { 500 }

    var body: some View {
        ZStack(alignment: .top) {

            if !viewModel.isPhotoOpen {
                emptyState
                    .touchable(.emptyState, in: chrome)
                    .transition(.opacity)
            }

            HStack(alignment: .top, spacing: 16) {

                leadingBar
                    .touchable(.leadingBar, in: chrome)

                Spacer(minLength: 0)

                if viewModel.isPhotoOpen {
                    trailingControls
                        .touchable(.toolbar, in: chrome)
                        .transition(appearTransition)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPhotoOpen)
    }

    /// motion is the one animation of the floating controls: a soft spring, or a short fade
    /// with Reduce Motion.
    private var motion: Animation {
        isReduceMotionOn ? .easeInOut(duration: 0.2) : .spring(duration: 0.42, bounce: 0.16)
    }

    private var appearTransition: AnyTransition {
        isReduceMotionOn ? .opacity : .scale(scale: 0.88, anchor: .topTrailing).combined(with: .opacity)
    }

    /// contentTransition slides a new panel's rows in from the side of the segment it was picked
    /// from, and fades the old ones out (see the type's comment).
    private var contentTransition: AnyTransition {
        guard !isReduceMotionOn else { return .opacity }

        let insertion = AnyTransition
            .offset(x: chrome.isMovingForward ? 64 : -64)
            .combined(with: .opacity)

        return .asymmetric(insertion: insertion, removal: .opacity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Button(action: onOpen) {
            VStack(spacing: 14) {

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Apri una foto")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("RAW, JPEG o HEIC dall'app File")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520, maxHeight: 380)
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
            }
            .padding(48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(white: 0.06) : Color.white)
        .ignoresSafeArea()
        .accessibilityLabel("Apri una foto")
        .accessibilityHint("RAW, JPEG o HEIC dall'app File")
    }

    // MARK: - Leading bar

    private var leadingBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {

                Button(action: onOpen) {
                    Image(systemName: "folder")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Apri")

                DiagnosticsMenuButton(menu: diagnosticsMenu)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Altro")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary)
            .padding(4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    // MARK: - Toolbar and panel

    private var trailingControls: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .trailing, spacing: 12) {

                segmentBar

                if let group = chrome.openGroup {
                    panel(group)
                        .transition(appearTransition)
                }
            }
        }
        .animation(motion, value: chrome.openGroup)
    }

    /// segmentBar is the toolbar: one segment per AdjustmentGroup in a horizontal scroll view,
    /// so more groups fit later without crowding, with the selection capsule behind the open one.
    private var segmentBar: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {

                    ForEach(AdjustmentGroup.allCases) { group in
                        segment(group)
                    }
                }
                .padding(4)
            }
            .contentMargins(.horizontal, 4, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChange(of: chrome.openGroup) { _, group in
                guard let group else { return }

                withAnimation(motion) { scroller.scrollTo(group.id, anchor: .center) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: Self.toolbarWidth)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: chrome.openGroup)
    }

    private func segment(_ group: AdjustmentGroup) -> some View {
        let isSelected = chrome.openGroup == group

        return Button {
            chrome.toggle(group)
        } label: {
            Text(group.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .opacity(isSelected ? 1 : 0.78)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary.opacity(0.14))
                            .matchedGeometryEffect(id: "selection", in: segmentNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(group.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Chiude il pannello" : "Apre il pannello")
    }

    /// panel is the open group's sliders on a glass card under the toolbar. The rows are keyed by
    /// group, so a switch is a removal and an insertion that `contentTransition` animates. The
    /// glass gets a light neutral tint (dark in dark mode) so text stays legible over busy photos.
    private func panel(_ group: AdjustmentGroup) -> some View {
        ZStack(alignment: .top) {

            AdjustmentPanel(viewModel: viewModel, group: group)
                .id(group)
                .transition(contentTransition)
        }
        .frame(width: Self.panelWidth, alignment: .top)
        .clipShape(.rect(cornerRadius: 28))
        .glassEffect(.regular.tint(Color(uiColor: .systemBackground).opacity(0.3)), in: .rect(cornerRadius: 28))
    }
}

private extension View {

    /// touchable(_:in:) keeps `chrome` told where this view is, in window points, and forgets it
    /// when the view goes away, so the pass-through never routes touches to something not there.
    func touchable(_ region: EditorChrome.Region, in chrome: EditorChrome) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            chrome.touchableFrames[region] = frame
        }
        .onDisappear {
            chrome.touchableFrames[region] = nil
        }
    }
}

/// DiagnosticsMenuButton shows the existing UIKit diagnostics menu from a SwiftUI control: a plain
/// UIButton whose menu opens on tap, with the "..." icon.
private struct DiagnosticsMenuButton: UIViewRepresentable {

    let menu: UIMenu

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.setPreferredSymbolConfiguration(.init(pointSize: 18, weight: .medium), forImageIn: .normal)
        button.tintColor = .label
        button.menu = menu
        button.showsMenuAsPrimaryAction = true

        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {}
}
