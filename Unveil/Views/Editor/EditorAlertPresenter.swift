//
//  EditorAlertPresenter.swift
//  Unveil
//

import SwiftUI

/// EditorAlertPresenter attaches the editor's one alert contract: an alert value, an OK button.
struct EditorAlertPresenter: ViewModifier {

    let alert    : EditorAlert?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            alert?.title ?? "",
            isPresented: Binding(
                get: { alert != nil },
                set: { if !$0 { onDismiss() } }
            ),
            presenting: alert
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { alert in
            Text(alert.message)
        }
    }
}
