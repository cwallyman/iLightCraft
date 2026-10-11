//
//  EditorAlertPresenter.swift
//  Unveil
//

import SwiftUI

/// EditorAlertPresenter attaches the editor's one alert contract: an alert value, an OK button.
///
/// `shown` is the alert that is up, and it stays as it is until the user dismisses it: UIKit would
/// keep showing the old text if it changed in place. The next one, already waiting when the first
/// is dismissed, is presented `dismissalGap` later, because SwiftUI never shows a presentation that
/// stays on across the dismissal.
struct EditorAlertPresenter: ViewModifier {

    let alert    : EditorAlert?
    let onDismiss: (EditorAlert) -> Void

    @State
    private var shown: EditorAlert?

    @State
    private var lastDismissal: ContinuousClock.Instant?

    private static let dismissalGap: Duration = .milliseconds(450)

    func body(content: Content) -> some View {
        content
            .alert(
                shown?.title ?? "",
                isPresented: Binding(
                    get: { shown != nil },
                    set: { isPresented in
                        guard !isPresented, let dismissed = shown else { return }

                        dismissShown()
                        onDismiss(dismissed)
                    }
                ),
                presenting: shown
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { alert in
                Text(alert.message)
            }
            // shown is part of the id: an alert that arrived while another was up (so `follow`
            // left it waiting) is presented once that one goes, even if `alert` did not change.
            .task(id: [alert, shown]) { await follow(alert) }
    }

    private func follow(_ next: EditorAlert?) async {
        // Nothing left to show: take the alert down (the session dismissed it, not the user).
        if shown != nil, next == nil {
            dismissShown()
        }

        guard shown == nil, let next else { return }

        if let lastDismissal {
            let wait = Self.dismissalGap - (ContinuousClock.now - lastDismissal)

            if wait > .zero {
                try? await Task.sleep(for: wait)
            }
        }

        // A newer alert, or none, cancelled this task while it waited.
        guard !Task.isCancelled else { return }

        shown = next
    }

    /// dismissShown takes the alert down. SwiftUI also reports a dismissal it was told to make
    /// (the setter then runs with `shown` nil), which must not acknowledge another alert.
    private func dismissShown() {
        shown         = nil
        lastDismissal = .now
    }
}
