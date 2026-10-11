//
//  OpenPhotoButton.swift
//  Unveil
//

import SwiftUI

/// OpenPhotoButton makes the entire outlined card one menu target, with system text scaling
/// and the same import actions as the toolbar. The parent provides its available space.
struct OpenPhotoButton: View {

    let openPhotos: () -> Void
    let openFiles : () -> Void

    var body: some View {
        Menu {
            PhotoImportActions(openPhotos: openPhotos, openFiles: openFiles)
        } label: {
            VStack(spacing: 14) {
                
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 52, weight: .light))
                    .accessibilityHidden(true)

                Text("Open Photo")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect(cornerRadius: 36))
            .overlay {
                RoundedRectangle(cornerRadius: 36)
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Open Photo")
        .accessibilityHint("Choose from Photos or Files.")
        .accessibilityIdentifier("open-photo-card")
    }
}
