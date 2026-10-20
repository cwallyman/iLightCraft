//
//  PhotoExportSheet.swift
//  Unveil
//

import SwiftUI

struct PhotoExportSheet<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {

    @State
    private var export: PhotoExportSession<Engine, Importer>

    @State
    private var showsShare = false

    @Environment(\.dismiss)
    private var dismiss

    init(model: EditorViewModel<Engine, Importer>) {
        _export = State(initialValue: PhotoExportSession(model: model))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    Picker("Format", selection: $export.options.format) {
                        Text("JPEG").tag("jpeg")
                        Text("PNG").tag("png")
                        Text("TIFF").tag("tiff")
                        if export.supportsHDR { Text("HEIC (HDR)").tag("heic") }
                    }
                    .onChange(of: export.options.format) { _, format in
                        if format == "jpeg" { export.options.bitDepth = 8 }
                        if format != "tiff" { export.options.hdr = format == "heic" }
                    }
                    if export.options.format == "jpeg" {
                        Stepper("Quality: \(export.options.quality)%", value: $export.options.quality, in: 1...100)
                    } else if export.options.format != "heic" && !export.options.hdr {
                        Picker("Bit depth", selection: $export.options.bitDepth) {
                            Text("8 bit").tag(8)
                            Text("16 bit").tag(16)
                        }
                    }
                    if export.supportsHDR && export.options.format == "tiff" {
                        Toggle("HDR (32-bit float)", isOn: $export.options.hdr)
                    }
                    Picker("Color space", selection: $export.options.colorSpace) {
                        Text("sRGB").tag("srgb")
                        Text("Display P3").tag("displayp3")
                        Text("Adobe RGB").tag("adobergb")
                        Text("ProPhoto RGB").tag("prophoto")
                        Text("Rec. 2020").tag("rec2020")
                    }
                    Toggle("Resize", isOn: Binding(
                        get: { export.options.longEdge > 0 },
                        set: { export.options.longEdge = $0 ? 2048 : 0 }
                    ))
                    if export.options.longEdge > 0 {
                        Stepper("Long edge: \(export.options.longEdge) px", value: $export.options.longEdge,
                                in: 256...16000, step: 256)
                    }
                }

                Section("Finishing") {
                    Picker("Output sharpening", selection: $export.options.sharpen) {
                        Text("None").tag("none")
                        Text("Screen").tag("screen")
                        Text("Matte paper").tag("matte")
                        Text("Glossy paper").tag("glossy")
                    }
                    if export.options.sharpen != "none" {
                        Picker("Amount", selection: $export.options.sharpenAmount) {
                            Text("Low").tag("low")
                            Text("Standard").tag("standard")
                            Text("High").tag("high")
                        }
                    }
                    TextField("Watermark text (optional)", text: $export.options.watermark)
                    Picker("Metadata", selection: $export.options.metadata) {
                        Text("All").tag("all")
                        Text("Except camera information").tag("allExceptCamera")
                        Text("Copyright only").tag("copyright")
                        Text("None").tag("none")
                    }
                    Toggle("Remove location", isOn: $export.options.removeLocation)
                }

                Section("Photos (\(export.selected.count) selected)") {
                    ForEach(export.photos) { photo in
                        Toggle(photo.name, isOn: Binding(
                            get: { export.selected.contains(photo.id) },
                            set: { if $0 { export.selected.insert(photo.id) } else { export.selected.remove(photo.id) } }
                        ))
                    }
                    if export.photos.count < export.total {
                        Button("Load more photos (\(export.photos.count) of \(export.total))") {
                            Task { await export.loadMore() }
                        }
                    }
                }

                if let error = export.error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if !export.files.isEmpty {
                    Section {
                        Button("Share \(export.files.count) exported photo(s)") { showsShare = true }
                    }
                }
            }
            .disabled(export.isWorking)
            .navigationTitle("Export Photos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(export.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        Task {
                            export.cleanUp()
                            await export.export()
                            if !export.files.isEmpty { showsShare = true }
                        }
                    }
                    .disabled(export.isWorking || export.selected.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if export.isWorking {
                    VStack(spacing: 10) {
                        ProgressView(export.requested > 0 ? "Exporting \(export.completed) of \(export.requested)…" : "Loading photos…")
                        if export.requested > 0 {
                            Button(export.stopRequested ? "Stopping after this photo…" : "Stop after this photo") {
                                export.stopRequested = true
                            }
                            .disabled(export.stopRequested)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
            .task { await export.loadMore() }
            .sheet(isPresented: $showsShare) { PhotoShareSheet(files: export.files) }
            .interactiveDismissDisabled(export.isWorking)
            .onDisappear { export.cleanUp() }
        }
    }
}
