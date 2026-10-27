//
//  EditorAuxiliaryPanel.swift
//  iLightCraft
//

import SwiftUI

/// EditorAuxiliaryPanel exposes the catalog keywords and existing engine eye correction.
struct EditorAuxiliaryPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: EditorAuxiliarySession<Engine, Importer>
    @Environment(\.editorToolClose) private var close
    private var isWhiteBalance: Bool { session.mode == .whiteBalance }
    private var isEye: Bool { session.mode == .redEye }
    var body: some View {
        EditorToolPresentation(title: isEye ? "Red Eye" : (isWhiteBalance ? "White Balance" : "Keywords"), header: { EmptyView() }) {
            LightCraftMenuList {
                if isEye { eyeControls } else if isWhiteBalance {
                    LightCraftMenuSection("White Balance Selector") {
                        Text("Tap a neutral area on the main photo. Pinch to zoom and pan with two fingers.")
                        LabeledContent("Temp", value: String(format: "%.0f K", session.model.values[.temperature] ?? 6500))
                        LabeledContent("Tint", value: String(format: "%.0f", session.model.values[.tint] ?? 0))
                        Text("Use Edit to return to the sliders.").font(.caption).foregroundStyle(.secondary)
                    }
                } else { keywordControls }
                if session.busy { ProgressView("Working…") }
                if let error = session.error { Text(error).foregroundStyle(.red) }
            }
        }
        .task { await session.load(); if session.mode == .keywords { await session.suggest() } }
        .task(id: session.keyword) {
            guard session.mode == .keywords else { return }
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); await session.suggest() }
            catch {}
        }
        .modifier(EditorToolBusyReporter(busy: session.busy))
    }
    private var keywordControls: some View {
        Group {
            LightCraftMenuSection("Add keyword") {
                TextField("Keyword", text: $session.keyword).submitLabel(.done)
                    .onSubmit { Task { await session.addKeyword() } }
                Button("Add Keyword") { Task { await session.addKeyword() } }
                    .disabled(!session.loaded || session.busy || NativeKeywordInput.clean(session.keyword) == nil)
            }
            LightCraftMenuSection("Keywording") {
                Picker("View", selection: $session.keywordView) {
                    Text("Keywords").tag("keywords"); Text("& Containing").tag("containing"); Text("Will Export").tag("export")
                }.pickerStyle(.segmented)
                if session.keywords.isEmpty { Text("No keywords").foregroundStyle(.secondary) }
                ForEach(Array(session.displayedKeywords.enumerated()), id: \.offset) { _, keyword in
                    HStack {
                        Text(session.keywordView == "containing" ? keyword.replacingOccurrences(of: "|", with: " › ") : keyword)
                        Spacer()
                        if session.keywordView == "keywords" {
                        Button("Remove \(keyword)", lightCraftIcon: "LightCraft-Close") {
                            Task { await session.removeKeyword(keyword) }
                        }.labelStyle(.iconOnly).disabled(session.busy)
                        }
                    }
                }
                if session.keywordView == "export" {
                    Text("Export includes these keywords when metadata is retained. None and Copyright Only omit keywords.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Keywords are saved in the local catalog for this photo.").font(.footnote).foregroundStyle(.secondary)
            }
            LightCraftMenuSection("Keyword Suggestions") {
                ForEach(session.suggestions, id: \.self) { keyword in
                    Button(keyword) { Task { await session.applyKeyword(keyword) } }.disabled(session.busy)
                }
            }
            LightCraftMenuSection("Keyword Set") {
                Menu(session.currentSet) {
                    ForEach(session.keywordSets, id: \.self) { name in
                        Button(name) { Task { await session.useSet(name) } }
                    }
                }
                ForEach(session.setKeywords, id: \.self) { keyword in
                    Button(keyword) { Task { await session.applyKeyword(keyword) } }.disabled(session.busy)
                }
                TextField("New set name", text: $session.setName)
                Button("Save Current Keywords as Set") { Task { await session.saveSet() } }
                    .disabled(session.busy || NativeKeywordInput.clean(session.setName) == nil || session.keywords.isEmpty)
                Button("Delete Current Set", role: .destructive) { Task { await session.deleteSet() } }
                    .disabled(session.busy || session.currentSet == "Recent Keywords")
            }
            LightCraftMenuSection("Keyword List") {
                ForEach(session.keywordList, id: \.0) { path, count in
                    Button("\(path.replacingOccurrences(of: "|", with: " › ")) (\(count))") {
                        Task { await session.applyKeyword(path) }
                    }.disabled(session.busy)
                }
            }
        }
    }
    private var eyeControls: some View {
        Group {
            LightCraftMenuSection {
                Text("Tap the pupil on the main photo, then apply. Pinch to zoom and pan with two fingers. The selection preview shows the uncropped photo.")
                Button(session.picking ? "Select an eye on the photo" : "Choose Another Eye") { session.picking = true }
                Toggle("Pet Eye", isOn: $session.pet).foregroundStyle(session.pet ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                LightCraftSliderRow("Eye Radius", value: $session.radius, in: 0.002...0.1, defaultValue: 0.02, step: nil)
                LightCraftSliderRow("Pupil Size", value: $session.pupilSize, in: 0...100, defaultValue: 50, step: nil)
                LightCraftSliderRow("Darken", value: $session.darken, in: 0...100, defaultValue: 50, step: nil)
                Button("Apply Eye Correction") { Task { await session.addEye() } }
                    .disabled(!session.loaded || session.center == nil || session.busy)
            }.disabled(session.busy)
            LightCraftMenuSection("Corrections") {
                ForEach(Array(session.eyes.enumerated()), id: \.offset) { index, eye in
                    NativeEyeCorrectionRow(session: session, index: index, eye: eye)
                }
                if session.eyes.count > 1 { Button("Delete All", role: .destructive) { Task { await session.removeAllEyes() } }.disabled(session.busy) }
            }
        }
    }
}

private struct NativeEyeCorrectionRow<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    let session: EditorAuxiliarySession<Engine, Importer>
    let index: Int
    let eye: EditorAuxiliarySession<Engine, Importer>.Eye
    @State private var pupil: Double
    @State private var darken: Double
    init(session: EditorAuxiliarySession<Engine, Importer>, index: Int, eye: EditorAuxiliarySession<Engine, Importer>.Eye) {
        self.session = session; self.index = index; self.eye = eye
        _pupil = State(initialValue: eye.pupil_size); _darken = State(initialValue: eye.darken)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(eye.pet ? "Pet Eye" : "Red Eye") \(index + 1)")
                Spacer()
                Button("Delete", role: .destructive) { Task { await session.removeEye(index) } }
            }
                LightCraftSliderRow("Pupil Size", value: $pupil, in: 0...100, defaultValue: 50, step: 1) { editing in if !editing { apply() } }
                LightCraftSliderRow("Darken", value: $darken, in: 0...100, defaultValue: 50, step: 1) { editing in if !editing { apply() } }
            if eye.pet {
                Toggle("Add Catchlight", isOn: Binding(get: { eye.catchlight != nil }, set: { on in
                    Task { await session.catchlight(index, on: on) }
                }))
            }
        }
        .disabled(session.busy)
        .onChange(of: eye.pupil_size) { _, value in pupil = value }
        .onChange(of: eye.darken) { _, value in darken = value }
    }
    private func apply() { Task { await session.adjustEye(index, pupilSize: pupil, darken: darken) } }
}
