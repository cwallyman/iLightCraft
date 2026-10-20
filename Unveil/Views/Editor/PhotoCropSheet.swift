//
//  PhotoCropSheet.swift
//  Unveil
//

import SwiftUI

struct PhotoCropSheet<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {

    @State
    private var crop: CropEditorSession<Engine, Importer>

    @State
    private var isApplying = false

    @Environment(\.dismiss)
    private var dismiss

    init(model: EditorViewModel<Engine, Importer>) {
        _crop = State(initialValue: CropEditorSession(model: model))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    preview
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)

                    Form {
                        Section {
                            HStack {
                                Button("Left", systemImage: "rotate.left") { Task { await crop.rotate(clockwise: false) } }
                                Spacer()
                                Button("Right", systemImage: "rotate.right") { Task { await crop.rotate(clockwise: true) } }
                                Spacer()
                                Menu("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                                    Button("Horizontal") { Task { await crop.flip(horizontal: true) } }
                                    Button("Vertical") { Task { await crop.flip(horizontal: false) } }
                                }
                            }
                            .buttonStyle(.borderless)
                            Picker("Aspect ratio", selection: $crop.aspect) {
                                Text("Free").tag("free")
                                if crop.aspect == "current" { Text("Current").tag("current") }
                                Text("Original").tag("original")
                                ForEach(["1x1", "4x5", "5x7", "2x3", "4x3", "16x9"], id: \.self) { name in
                                    Text(name.replacingOccurrences(of: "x", with: ":")).tag(name)
                                }
                            }
                            .onChange(of: crop.aspect) { _, _ in crop.chooseAspect() }
                            if crop.aspect != "free" && crop.aspect != "original" && crop.aspect != "current" {
                                Toggle("Portrait crop", isOn: $crop.portrait)
                                    .onChange(of: crop.portrait) { _, _ in crop.chooseAspect() }
                            }
                            VStack {
                                HStack {
                                    Text("Straighten")
                                    Spacer()
                                    Text(crop.draft.crop.geometry.angle, format: .number.precision(.fractionLength(1)))
                                    Text("°")
                                }
                                Slider(value: $crop.draft.crop.geometry.angle, in: -45...45, step: 0.1)
                                    .accessibilityLabel("Straighten angle")
                            }
                            Button("Reset Crop") {
                                crop.draft.crop.geometry = .init()
                                crop.draft.crop.aspect = nil
                                crop.aspect = "free"
                            }
                        } footer: {
                            Text("Drag the corners to crop, or drag inside to move. Done saves one undoable edit; Cancel keeps your previous crop.")
                        }
                        if let error = crop.error { Text(error).foregroundStyle(.red) }
                    }
                    .disabled(crop.isLoading)
                    .frame(height: min(350, geometry.size.height * 0.48))
                }
            }
            .navigationTitle("Crop & Rotate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isApplying) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            isApplying = true
                            if await crop.apply() { dismiss() }
                            isApplying = false
                        }
                    }
                    .disabled(crop.image == nil || crop.isLoading || isApplying)
                }
            }
            .disabled(isApplying)
            .interactiveDismissDisabled(isApplying)
            .task { await crop.loadPreview() }
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            if let image = crop.image {
                let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .rotationEffect(.degrees(crop.previewAngle))
                        .clipped()
                    CropSelection(rectangle: $crop.selection, imageSize: image.size, ratio: crop.ratio)
                        .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .disabled(crop.isLoading)
            }
            if crop.isLoading {
                ProgressView("Preparing photo…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
