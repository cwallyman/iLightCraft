//
//  EditorTool.swift
//  Unveil
//

/// EditorTool names the tools of the trailing rail. Move is the canvas gestures alone and the
/// default; Adjust also shows the adjust card. The raw value names it in accessibility identifiers.
nonisolated enum EditorTool: String, Sendable {

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
            case .move  : "hand.raised"
            case .adjust: "Adjust"
        }
    }
}

/*
 button("Move", systemImage: "hand.raised", tool: .move)

 button("Adjust", systemImage: "slider.horizontal.3", tool: .adjust)
     .disabled(!isPhotoOpen)
 */
