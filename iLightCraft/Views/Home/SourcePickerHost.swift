//
//  SourcePickerHost.swift
//  iLightCraft
//

import SwiftUI
import UIKit

/// PickerFader shows the source picker only while the panel the home shows rests at half height,
/// the same way for both panels: the picker fades out where it is the moment a drag on the panel
/// starts, stays out while the panel is expanded, and fades back in, settling from just above,
/// when the panel comes back to rest.
///
/// Photos reports its drags and detents from PanelController. Files reports what this process
/// can know of a sheet the system browser drags in its own process: the start of a drag and the
/// detent a release lands on (DocumentLaunch).
@MainActor
final class PickerFader {

    /// source is the panel shown, whose state the picker follows.
    var source: HomeView.Source = .files {
        didSet {
            if source != oldValue {
                picker?.setShown(!isHidden(source))
            }
        }
    }

    private weak var picker: PickerContainerView?

    /// attach gives the fader the picker to fade, shown or not as the panel shown is now.
    func attach(_ picker: PickerContainerView) {
        self.picker = picker
        picker.setShown(!isHidden(source))
    }

    private var isExpanded: Set<HomeView.Source> = []
    private var isDragging: Set<HomeView.Source> = []

    /// setExpanded takes the detent a panel rests or lands on.
    func setExpanded(_ expanded: Bool, for panel: HomeView.Source) {
        update(panel) { if expanded { isExpanded.insert(panel) } else { isExpanded.remove(panel) } }
    }

    /// setDragging hears a drag on a panel start and end.
    func setDragging(_ dragging: Bool, for panel: HomeView.Source) {
        update(panel) { if dragging { isDragging.insert(panel) } else { isDragging.remove(panel) } }
    }

    private func isHidden(_ panel: HomeView.Source) -> Bool {
        isExpanded.contains(panel) || isDragging.contains(panel)
    }

    /// update applies a change to a panel's state and fades the picker if that panel is shown
    /// and the change hides or shows it.
    private func update(_ panel: HomeView.Source, change: () -> Void) {
        let wasHidden = isHidden(panel)
        change()

        let hidden = isHidden(panel)
        if panel == source, hidden != wasHidden {
            picker?.fade(shown: !hidden)
        }
    }
}

/// SourcePickerHost is the home's Files / Photos picker (CapsulePicker) hosted in UIKit, so that
/// PickerFader can fade it from the panels' gesture callbacks. SwiftUI lays it out at rest, sized
/// to the capsule.
struct SourcePickerHost: UIViewControllerRepresentable {

    @Binding
    var source: HomeView.Source

    let fader: PickerFader

    func makeUIViewController(context: Context) -> PickerController {
        let controller = PickerController()
        fader.attach(controller.container)
        return controller
    }

    func updateUIViewController(
        _ controller: PickerController,
        context     : Context
    ) {
        controller.hosting.rootView = AnyView(
            CapsulePicker(
                label     : "Source",
                options   : [("Files", HomeView.Source.files), ("Photos", .photos)],
                selection : $source
            )
            .environment(\.colorScheme, .dark)
        )
        fader.source = source
    }

    func sizeThatFits(
        _ proposal       : ProposedViewSize,
        uiViewController : PickerController,
        context          : Context
    ) -> CGSize? {
        uiViewController.hosting.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
    }

    final class PickerController: UIViewController {

        let hosting   = UIHostingController(rootView: AnyView(EmptyView()))
        let container = PickerContainerView()

        override func loadView() {
            view = container
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            addChild(hosting)
            hosting.view.backgroundColor = .clear
            container.addPill(hosting.view)
            hosting.didMove(toParent: self)
        }
    }
}

/// PickerContainerView stays where SwiftUI put the picker; the pill inside it fades.
final class PickerContainerView: UIView {

    /// entryDrop is how far above its place the pill starts when it fades back in.
    private static let entryDrop: CGFloat = 12

    private(set) weak var pill: UIView?

    func addPill(_ view: UIView) {
        pill = view
        view.frame            = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }

    /// fade hides the pill where it is, quickly, or brings it back from `entryDrop` above,
    /// fading in as it settles, top to bottom.
    func fade(shown: Bool) {
        guard let pill else { return }

        if shown {
            if pill.alpha < 0.01 {
                pill.transform = CGAffineTransform(translationX: 0, y: -Self.entryDrop)
            }
            UIView.animate(
                springDuration : 0.45,
                bounce         : 0,
                options        : [.allowUserInteraction, .beginFromCurrentState]
            ) {
                pill.alpha     = 1
                pill.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                pill.alpha = 0
            }
        }
    }

    /// setShown shows or hides the pill at once (switching panels, first layout).
    func setShown(_ shown: Bool) {
        guard let pill else { return }

        pill.layer.removeAllAnimations()
        pill.alpha     = shown ? 1 : 0
        pill.transform = .identity
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
