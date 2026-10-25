//
//  EditorTool.swift
//  iLightCraft
//

/// EditorTool names the tools of the trailing rail. Move is the canvas gestures alone and the
/// default; Adjust also shows the adjust card. The raw value names it in accessibility identifiers.
nonisolated enum EditorTool: String, Sendable, CaseIterable {

    case move
    case adjust
    
    var title: String {
        switch self {
            case .move  : "Move"
            case .adjust: "Adjust"
        }
    }
    
    var systemImage: String {
        switch self {
            case .move  : "pointer.arrow"
            case .adjust: "slider.horizontal.3"
        }
    }
}
