//
//  PhotoShareSheet.swift
//  Unveil
//

import SwiftUI
import UIKit

/// The system activity controller provides Save to Files, sharing and supported photo destinations.
struct PhotoShareSheet: UIViewControllerRepresentable {

    let files: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
