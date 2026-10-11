//
//  EditorSurround.swift
//  Unveil
//

import Metal
import SwiftUI
import UIKit

/// EditorSurround is the editor's neutral surround: the dark grey around and behind the photo, on
/// the canvas and under the SwiftUI shell, so colors are judged against a neutral field and not
/// against pure black (which makes every tone look lighter). One constant, sRGB-encoded.
nonisolated enum EditorSurround {

    /// gray is the surround's sRGB value (0 to 1), written to the drawable as is.
    static let gray = 0.11

    static let metalClearColor = MTLClearColor(red: gray, green: gray, blue: gray, alpha: 1)

    static let uiColor = UIColor(red: gray, green: gray, blue: gray, alpha: 1)

    static let color = Color(.sRGB, white: gray, opacity: 1)
}
