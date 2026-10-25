import SwiftUI
import UIKit

/// A real custom toolbar view keeps UIKit hover tracking attached to the control.
/// Applying onHover/help directly to a SwiftUI toolbar Button can lose the interaction when
/// SwiftUI synthesizes a UIBarButtonItem instead of retaining the SwiftUI view.
struct ToolbarHoverLabel<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let label: String
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: hostedContent)
        // A toolbar custom view has no navigation/window safe area of its own.
        // Inheriting it pushes the hosted icon below the actual button background.
        host.safeAreaRegions = []
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        let hover = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hoverChanged(_:)))
        hover.cancelsTouchesInView = false
        host.view.addGestureRecognizer(hover)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<AnyView>, context: Context) {
        context.coordinator.parent = self
        host.rootView = hostedContent
    }

    private var hostedContent: AnyView {
        AnyView(content
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .toggleStyle(.button)
            .environment(\.isEnabled, isEnabled)
            .environment(\.colorScheme, colorScheme)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle()))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<AnyView>, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    static func dismantleUIViewController(_ host: UIHostingController<AnyView>, coordinator: Coordinator) {
        coordinator.hide()
    }

    final class Coordinator: NSObject {
        var parent: ToolbarHoverLabel
        private var bubble: UIVisualEffectView?
        private let text = UILabel()

        init(parent: ToolbarHoverLabel) {
            self.parent = parent
            text.font = .systemFont(ofSize: 13, weight: .semibold)
            text.textColor = .white
            text.numberOfLines = 2
            text.textAlignment = .center
        }

        @objc func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                if let target = recognizer.view { show(below: target) }
            default: hide()
            }
        }

        private func show(below target: UIView) {
            guard let window = target.window else { hide(); return }
            let anchor = target.convert(target.bounds, to: window)
            guard !anchor.isEmpty else { hide(); return }
            let panel: UIVisualEffectView
            if let bubble { panel = bubble }
            else {
                panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
                panel.layer.cornerRadius = 12
                panel.clipsToBounds = true
                panel.isUserInteractionEnabled = false
                panel.accessibilityElementsHidden = true
                panel.contentView.addSubview(text)
                bubble = panel
            }
            text.text = parent.label
            let maximumWidth = min(280, max(44, window.bounds.width - 40))
            let size = text.sizeThatFits(CGSize(width: maximumWidth - 24, height: 80))
            let width = min(maximumWidth, ceil(size.width) + 24)
            let height = ceil(size.height) + 14
            let x = min(max(8, anchor.midX - width / 2), max(8, window.bounds.width - width - 8))
            let y = min(anchor.maxY + 6, max(8, window.bounds.height - height - 8))
            panel.frame = CGRect(x: x, y: y, width: width, height: height)
            text.frame = panel.bounds.insetBy(dx: 12, dy: 7)
            if panel.superview !== window { window.addSubview(panel) }
            window.bringSubviewToFront(panel)
        }

        func hide() {
            bubble?.removeFromSuperview()
            bubble = nil
        }
    }
}

/// Keeps the bounded scrolling tool strip as one custom toolbar view. Without this hosting
/// boundary SwiftUI extracts only native bar items and drops the ScrollView content.
struct EditorToolbarStrip<Content: View>: UIViewControllerRepresentable {
    let width: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var root: some View {
        content
            .environment(\.colorScheme, colorScheme)
            .tint(Color(red: 242.0 / 255, green: 165.0 / 255, blue: 22.0 / 255))
            .frame(width: width, height: 44)
    }
    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: AnyView(root))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        return host
    }
    func updateUIViewController(_ host: UIHostingController<AnyView>, context: Context) {
        host.rootView = AnyView(root)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<AnyView>, context: Context) -> CGSize? {
        CGSize(width: width, height: 44)
    }
}
