//
//  EditorOverlay.swift
//  Unveil
//

import SwiftUI

/// EditorOverlay is everything that floats over the canvas: the empty-state placeholder while no
/// photo is open, the glass top bar and the glass adjustment panel.
///
/// The canvas stays canvas-first. When a photo is open the only things on screen are the small top
/// capsule and, on demand, the panel; with no photo the placeholder covers the (black) canvas with a
/// neutral white or near-black surface. The hosting view is transparent, so touches outside the
/// controls reach the canvas gestures below.
struct EditorOverlay<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel      : EditorViewModel<Engine, Importer>
    let diagnosticsMenu: UIMenu
    let onOpen         : () -> Void

    @State
    private var isPanelVisible = false

    @Environment(\.colorScheme)
    private var colorScheme

    private static var panelWidth: CGFloat { 320 }

    var body: some View {
        ZStack(alignment: .topTrailing) {

            if !viewModel.isPhotoOpen {
                emptyState
                    .transition(.opacity)
            }

            panel

            VStack {
                topBar

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPhotoOpen)
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

    // MARK: - Top bar

    private var topBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {

                Button(action: onOpen) {
                    Image(systemName: "folder")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Apri")

                Button {
                    withAnimation(.spring(duration: 0.45, bounce: 0.2)) { isPanelVisible.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 44, height: 44)
                        .symbolVariant(isPanelVisible ? .fill : .none)
                }
                .disabled(!viewModel.isPhotoOpen)
                .accessibilityLabel("Regolazioni")
                .accessibilityAddTraits(isPanelVisible ? .isSelected : [])

                DiagnosticsMenuButton(menu: diagnosticsMenu)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Altro")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary)
            .padding(4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    // MARK: - Adjustments

    private var panel: some View {
        AdjustmentPanel(viewModel: viewModel)
            .frame(width: Self.panelWidth)
            .frame(maxHeight: 640)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(.trailing, 16)
            .padding(.top, 8)
            .offset(x: isPanelVisible && viewModel.isPhotoOpen ? 0 : Self.panelWidth + 32)
            .opacity(isPanelVisible && viewModel.isPhotoOpen ? 1 : 0)
            .allowsHitTesting(isPanelVisible && viewModel.isPhotoOpen)
            .accessibilityHidden(!isPanelVisible || !viewModel.isPhotoOpen)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: isPanelVisible)
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
