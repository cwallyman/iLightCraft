//
//  PhotoMergePanel.swift
//  iLightCraft
//

import SwiftUI

/// PhotoMergePanel merges imported full-resolution sources into a new DNG without replacing them.
struct PhotoMergePanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: PhotoMergeSession<Engine, Importer>
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Merge", selection: $session.kind) {
                Text("HDR brackets").tag("hdr")
                Text("Panorama").tag("panorama")
                Text("HDR panorama").tag("hdrPanorama")
            }
            if session.kind != "panorama" {
                Text("Deghosting").font(.subheadline)
                Picker("Deghost", selection: $session.deghost) {
                    ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            if session.kind != "hdr" {
                Picker("Projection", selection: $session.projection) {
                    ForEach(["auto", "spherical", "cylindrical", "perspective"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Toggle("Auto crop", isOn: $session.autoCrop)
                Text("Panorama output limit: \(session.maxMegapixels, specifier: "%.0f") MP")
                Slider(value: $session.maxMegapixels, in: 1...40, step: 1)
            }
            Text("Select imported photos in capture order. HDR panoramas require exposure brackets at each view. Full-resolution jobs are refused when their memory estimate exceeds the current allowance.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(session.photos) { photo in
                Button { session.toggle(photo.id) } label: {
                    HStack {
                        Image(systemName: session.selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading) {
                            Text(photo.name).lineLimit(1)
                            Text("\(photo.width) × \(photo.height)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let order = session.selected.firstIndex(of: photo.id) { Text("\(order + 1)") }
                    }
                }.disabled(session.working)
            }
            if session.photos.count < session.total {
                Button("Load More Photos") { Task { await session.loadMore() } }.disabled(session.working)
            }
            if session.working {
                ProgressView(value: session.progress)
                Text(session.stage).font(.footnote)
                Button("Cancel Merge") { Task { await session.cancel() } }
            } else {
                Button("Create Merged Copy") { Task { await session.merge() } }
                    .buttonStyle(.borderedProminent).disabled(session.selected.count < 2)
                if !session.stage.isEmpty { Text(session.stage).font(.footnote) }
            }
            if let error = session.error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .task { if session.photos.isEmpty { await session.loadMore() } }
    }
}
