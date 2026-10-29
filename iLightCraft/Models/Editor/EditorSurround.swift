//
//  EditorSurround.swift
//  iLightCraft
//

import Metal
import SwiftUI
import UIKit

/// EditorSurround is the editor's surround: the black around and behind the photo, on the canvas
/// and under the SwiftUI shell. One constant, sRGB-encoded.
nonisolated enum EditorSurround {

    /// gray is the surround's sRGB value (0 to 1), written to the drawable as is.
    static let gray = 0.0

    private static let linearGray = pow((gray + 0.055) / 1.055, 2.4)
    static let metalClearColor = MTLClearColor(red: linearGray, green: linearGray, blue: linearGray, alpha: 1)

    static let uiColor = UIColor(red: gray, green: gray, blue: gray, alpha: 1)

    static let color = Color(.sRGB, white: gray, opacity: 1)
}
