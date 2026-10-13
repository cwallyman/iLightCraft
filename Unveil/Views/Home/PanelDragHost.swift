//
//  PanelDragHost.swift
//  Unveil
//

import SwiftUI
import UIKit

/// PanelDragHost is the Photos panel itself (glass, fade and PhotosBrowser) hosted in UIKit, which
/// owns the panel's position the way a system sheet does. SwiftUI lays the host out once, at the
/// expanded position and at the panel's full size; PanelController then moves the panel with a
/// plain layer transform: in the pan's own callback while a finger drags it, and with a Core
/// Animation spring on release, which the render server runs by itself. No SwiftUI state changes
/// per touch event, so following the finger costs one transform per frame. SwiftUI hears only
/// where the panel settles, through `isExpanded`; setting it from SwiftUI (VoiceOver, launch
/// options) snaps the panel there.
///
/// The hosted content is rebuilt only when what it shows changes (expanded or not, importing or
/// not), never while the panel moves. The library is observed by the browser itself.
struct PanelDragHost: UIViewControllerRepresentable {

    @Binding
    var isExpanded: Bool

    let library      : PhotoLibraryStore
    let fader        : PickerFader
    let geometry     : HomePanelGeometry
    let contentHeight: CGFloat
    let fadeHeight   : CGFloat
    let isImporting  : Bool
    let onPick       : (String) -> Void

    func makeUIViewController(context: Context) -> PanelController {
        PanelController(isExpanded: isExpanded, geometry: geometry, fader: fader)
    }

    func updateUIViewController(
        _ controller: PanelController,
        context     : Context
    ) {
        controller.onSettle = { expanded in isExpanded = expanded }
        controller.onPick   = onPick
        controller.update(
            content    : PanelContent(
                library       : library,
                isExpanded    : isExpanded,
                isImporting   : isImporting,
                contentHeight : contentHeight,
                fadeHeight    : fadeHeight
            ),
            isExpanded : isExpanded,
            geometry   : geometry
        )
    }
}

/// PanelContent is what the panel shows, a value so the controller can tell when it changed.
struct PanelContent: Equatable {

    let library      : PhotoLibraryStore
    let isExpanded   : Bool
    let isImporting  : Bool
    let contentHeight: CGFloat
    let fadeHeight   : CGFloat

    static func == (lhs: PanelContent, rhs: PanelContent) -> Bool {
        lhs.library === rhs.library && lhs.isExpanded == rhs.isExpanded && lhs.isImporting == rhs.isImporting
            && lhs.contentHeight == rhs.contentHeight && lhs.fadeHeight == rhs.fadeHeight
    }
}

/// PanelController moves the panel and tells the source picker (PickerFader) when a drag starts
/// and where the panel settles. Its own view passes touches through wherever the panel is not,
/// so the picker above a resting panel stays reachable.
///
/// The pan follows the system sheet's rules:
/// - collapsed, or off the grid (the toolbar), a vertical drag moves the panel from the start;
/// - expanded, on the grid, the pan runs alongside the grid's own scrolling but stays passive
///   while the grid scrolls; once the grid shows its top and the finger goes down, even halfway
///   through the drag, the pan takes over: the grid's pan is cancelled, the grid held at its top,
///   and the panel follows the finger from that point. The grid never bounces, so there is no
///   rubber band to spring back against the finger;
/// - buttons still take taps, which a pan never claims; the window's own drags (moving or
///   minimizing the app) wait for this pan to fail, so a drag on the panel never moves the app;
/// - a drag that catches the panel mid-snap starts from where the panel is shown.
final class PanelController: UIViewController, UIGestureRecognizerDelegate {

    var onSettle: (Bool) -> Void   = { _ in }
    var onPick  : (String) -> Void = { _ in }

    private let hosting = UIHostingController(rootView: AnyView(EmptyView()))

    private let fader     : PickerFader
    private var isExpanded: Bool
    private var geometry  : HomePanelGeometry
    private var content   : PanelContent?

    /// list is the grid's scroll view when the drag started on it while expanded.
    private weak var list: UIScrollView?

    /// takeOverTranslation is the drag's translation when the panel took the drag, nil while the
    /// grid still scrolls; startOffset is where the panel was shown then. The panel sits at
    /// startOffset moved by the translation since takeOverTranslation.
    private var takeOverTranslation: CGFloat?
    private var startOffset        : CGFloat = 0

    /// takesOverAtOnce is true for a drag the panel owns from its start (collapsed, or off the grid).
    private var takesOverAtOnce = false

    init(isExpanded: Bool, geometry: HomePanelGeometry, fader: PickerFader) {
        self.isExpanded = isExpanded
        self.geometry   = geometry
        self.fader      = fader
        super.init(nibName: nil, bundle: nil)
        fader.setExpanded(isExpanded, for: .photos)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanelController is built in code, not from a storyboard")
    }

    override func loadView() {
        view = PassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(hosting)
        hosting.view.backgroundColor  = .clear
        hosting.view.frame            = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        hosting.view.addGestureRecognizer(pan)

        show(offset: geometry.restingOffset(isExpanded: isExpanded))
    }

    /// update takes SwiftUI's latest values. A change of `isExpanded` that the panel did not make
    /// itself snaps the panel to that detent; a new geometry (rotation) moves a resting panel.
    func update(
        content   : PanelContent,
        isExpanded: Bool,
        geometry  : HomePanelGeometry
    ) {
        if content != self.content {
            self.content     = content
            hosting.rootView = AnyView(panelView(content))
        }

        let isDragging = takeOverTranslation != nil
        if geometry != self.geometry {
            self.geometry = geometry
            if !isDragging {
                show(offset: geometry.restingOffset(isExpanded: self.isExpanded))
            }
        }
        if isExpanded != self.isExpanded, !isDragging {
            settle(expanded: isExpanded, velocity: 0)
        }
    }

    private func panelView(_ content: PanelContent) -> some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)

        return PhotosBrowser(
            library         : content.library,
            isScrollEnabled : content.isExpanded,
            onPick          : { [weak self] identifier in self?.onPick(identifier) }
        )
        .frame(height: content.contentHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(!content.isImporting)
        .clipShape(shape)
        .background {
            GeometryReader { proxy in
                ZStack {
                    Color.clear
                        .glassEffect(.regular, in: shape)

                    // The fade spans the resting panel's visible height; below it, dark.
                    LinearGradient(
                        stops      : PhotosPanel.darkening,
                        startPoint : .top,
                        endPoint   : UnitPoint(x: 0.5, y: content.fadeHeight / max(proxy.size.height, 1))
                    )
                    .clipShape(shape)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Moving

    /// shownOffset is where the panel is on screen right now, mid-animation included.
    private var shownOffset: CGFloat {
        hosting.view.layer.presentation()?.affineTransform().ty ?? hosting.view.transform.ty
    }

    private func show(offset: CGFloat) {
        hosting.view.transform = CGAffineTransform(translationX: 0, y: offset)
    }

    /// stopMoving ends any snap under way, leaving the panel where it is shown.
    private func stopMoving() -> CGFloat {
        let shown = shownOffset
        hosting.view.layer.removeAllAnimations()
        show(offset: shown)
        return shown
    }

    /// settle snaps the panel to a detent with a critically damped spring whose start matches the
    /// release velocity (points per second, positive downward), and tells SwiftUI where it went.
    private func settle(expanded: Bool, velocity: CGFloat) {
        let released = stopMoving()
        let target   = geometry.restingOffset(isExpanded: expanded)
        let start    = geometry.snapVelocity(from: released, to: target, velocity: velocity)

        UIView.animate(
            springDuration        : HomePanelGeometry.snapDuration,
            bounce                : 0,
            initialSpringVelocity : start,
            options               : [.allowUserInteraction]
        ) {
            self.show(offset: target)
        }

        fader.setExpanded(expanded, for: .photos)
        fader.setDragging(false, for: .photos)

        if expanded != isExpanded {
            isExpanded = expanded
            onSettle(expanded)
        }
    }

    @objc
    private func panned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: nil).y

        switch pan.state {
            case .began, .changed:
                if pan.state == .began, takesOverAtOnce {
                    takeOver(at: translation)
                }
                takeOverIfListIsAtTop(pan)

                if let start = takeOverTranslation {
                    list?.holdAtTop()
                    show(offset: geometry.offset(from: startOffset, translation: translation - start))
                }

            case .ended, .cancelled:
                if takeOverTranslation != nil {
                    let velocity = pan.velocity(in: nil).y
                    settle(
                        expanded : geometry.settlesExpanded(released: shownOffset, velocity: velocity),
                        velocity : velocity
                    )
                }
                list                = nil
                takeOverTranslation = nil

            default:
                break
        }
    }

    /// takeOver gives the drag to the panel: it stops any snap under way where the panel is shown
    /// and moves from there.
    private func takeOver(at translation: CGFloat) {
        startOffset         = stopMoving()
        takeOverTranslation = translation
        fader.setDragging(true, for: .photos)
    }

    /// takeOverIfListIsAtTop gives the drag to the panel once the grid shows its top and the
    /// finger is going down; the grid's pan is cancelled by switching it off and on.
    private func takeOverIfListIsAtTop(_ pan: UIPanGestureRecognizer) {
        guard takeOverTranslation == nil, let list, list.isAtTop, pan.velocity(in: nil).y > 0 else { return }

        list.holdAtTop()
        list.panGestureRecognizer.isEnabled = false
        list.panGestureRecognizer.isEnabled = true
        takeOver(at: pan.translation(in: nil).y)
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }

        let velocity = pan.velocity(in: nil)
        guard abs(velocity.y) > abs(velocity.x) else { return false }

        list                = isExpanded ? Self.scrollingList(under: pan) : nil
        takesOverAtOnce     = list == nil
        takeOverTranslation = nil

        // The grid never bounces: at its top a pull down belongs to the panel, and a grid pulled
        // past its top would spring back while the panel moves, the photos jumping against the
        // finger. Set here, on the first drag that finds it, before it can bounce.
        list?.bounces = false
        return true
    }

    /// The grid's pan, the buttons' and the glass controls' run alongside this one; it takes over
    /// from the grid when it must, and a moving finger fails the taps by itself.
    func gestureRecognizer(
        _ recognizer                                     : UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherRecognizer: UIGestureRecognizer
    ) -> Bool {
        !(otherRecognizer.view is UIWindow)
    }

    /// The window's own drags (moving, resizing or minimizing the app) wait for this pan to fail,
    /// so a drag on the panel never moves the app.
    func gestureRecognizer(
        _ recognizer                            : UIGestureRecognizer,
        shouldBeRequiredToFailBy otherRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherRecognizer.view is UIWindow
    }

    /// scrollingList is the scrollable list under the finger, if the drag started on one.
    private static func scrollingList(under pan: UIPanGestureRecognizer) -> UIScrollView? {
        guard let view = pan.view else { return nil }

        var candidate = view.hitTest(pan.location(in: view), with: nil)
        while let current = candidate, current !== view {
            if let list = current as? UIScrollView, list.isScrollEnabled {
                return list
            }
            candidate = current.superview
        }
        return nil
    }

    /// PassthroughView takes no touches itself: only the panel inside it does.
    private final class PassthroughView: UIView {

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? nil : hit
        }
    }
}

private extension UIScrollView {

    /// isAtTop is true when the list shows its first row, give or take a point of rounding.
    var isAtTop: Bool {
        contentOffset.y <= -adjustedContentInset.top + 1
    }

    /// holdAtTop keeps the list at its top, stopping any scrolling it had under way.
    func holdAtTop() {
        guard contentOffset.y != -adjustedContentInset.top else { return }

        setContentOffset(CGPoint(x: contentOffset.x, y: -adjustedContentInset.top), animated: false)
    }
}
