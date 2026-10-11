//
//  EditorAlertPresenter.swift
//  Unveil
//

import SwiftUI

/// EditorAlertPresenter attaches the same alert contract to the active presentation surface.
/// In compact width the inspector is a sheet, so its content must own the visible alert.
struct EditorAlertPresenter: ViewModifier {

    let alert    : EditorAlert?
    let isActive : Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            alert?.title ?? "",
            isPresented: Binding(
                get: { isActive && alert != nil },
                set: { if !$0 && isActive { onDismiss() } }
            ),
            presenting: alert
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { alert in
            Text(alert.message)
        }
    }
}
