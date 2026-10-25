//
//  EditorAlert.swift
//  iLightCraft
//

/// EditorAlert carries presentation text without tying errors or diagnostics to a UI framework.
struct EditorAlert: Equatable {

    let title  : String
    let message: String
}
