//
//  EditorView.swift
//  iLightCraft
//

import SwiftUI
import UIKit

/// EditorView owns the editor layout and system presentations. Its dependencies are composed
/// once per scene; no observable adjustment value or preview frame constructs a new canvas.
struct EditorView<
    Engine       : EngineDriving & EngineDiagnosing,
    Importer     : PhotoImporting,
    LibraryLoader: PhotoLibraryLoading
>: View {

    @Bindable
    private var session: EditorSession<Engine, Importer, LibraryLoader>

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @AppStorage("editor.controlsSide") private var controlsSide = "right"
    @State private var isSettingsShown = false
    @State private var dockTool: EditorDockTool?
    @State private var dockIsBusy = false
    @State private var presetVersions: PresetVersionSession<Engine, Importer>?
    @State private var advancedColor: AdvancedColorSession<Engine, Importer>?
    @State private var spatialCrop: CropEditorSession<Engine, Importer>?
    @State private var spatialSelection: ComputationalToolsSession<Engine, Importer>?
    @State private var mainPhotoInteracting = false
    @State private var toolZoomRequest: PhotoToolViewport.ZoomRequest?
    private var interactionLocked: Bool { dockIsBusy || mainPhotoInteracting }
    private var usesPhotoTools: Bool { spatialCrop != nil || spatialSelection != nil || (advancedColor?.pointColor == true || advancedColor?.guiding == true) }

    @Environment(\.layoutDirection) private var contentLayoutDirection
    @State private var editorWidth: CGFloat = 1024

    private let canvas     : CanvasView
    private let diagnostics: EditorDiagnostics<Engine, Importer>

    init(
        session    : EditorSession<Engine, Importer, LibraryLoader>,
        canvas     : CanvasView,
        diagnostics: EditorDiagnostics<Engine, Importer>,
        initialDockTool: EditorDockTool? = nil
    ) {
        self.session     = session
        self.canvas      = canvas
        self.diagnostics = diagnostics
        _dockTool = State(initialValue: initialDockTool)
        if initialDockTool == .presets || initialDockTool == .versions {
            _presetVersions = State(initialValue: PresetVersionSession(model: session.viewModel, onOpen: { photo, source in
                _ = await session.openMergedCopy(photo, source: source, merged: false)
            }))
        }
        if initialDockTool == .pointColor || initialDockTool == .grading || initialDockTool == .optics {
            _advancedColor = State(initialValue: AdvancedColorSession(model: session.viewModel, pointColor: initialDockTool == .pointColor, optics: initialDockTool == .optics))
        }
        if initialDockTool == .crop {
            _spatialCrop = State(initialValue: CropEditorSession(model: session.viewModel))
        }
        if initialDockTool == .computational(0) || initialDockTool == .computational(1) {
            _spatialSelection = State(initialValue: ComputationalToolsSession(model: session.viewModel, onIndexed: { _, _ in }))
        }
    }

    var body: some View {

        NavigationStack {

            GeometryReader { geometry in
                let placement = EditorControlsLayout(size: geometry.size, isPhone: UIDevice.current.userInterfaceIdiom == .phone)
                let isBottom = placement.isBottom
                let dockWidth = placement.sideWidth
                let layout = isBottom
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))

                layout {
                    HStack(spacing: 8) {
                        if let reference = presetVersions?.referenceImage {
                            VStack(spacing: 4) {
                                Text("Reference: \(presetVersions?.referenceName ?? "")").font(.caption).lineLimit(1)
                                PhotoToolViewport(image: reference, mode: .masks,
                                                  onInteraction: { mainPhotoInteracting = $0 })
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    EditorCanvas(
                        canvas         : canvas,
                        photo          : session.viewModel.openPhoto,
                        photoSize      : session.viewModel.photoSize,
                        clipping       : session.clippingOverlay,
                        isShowingBefore: session.viewModel.isShowingBefore,
                        onSingleTap    : {},
                        onTouchDown    : nil,
                        onHoldChange   : { session.holdChanged($0) },
                        onToggleBefore : toggleBefore,
                        onZoomChange   : { session.zoomPercent = $0 },
                        onWindowChange : { window, isDraft in
                            Task.immediate { await session.viewModel.showWindow(window, draft: isDraft) }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(!interactionLocked && !usesPhotoTools)
                    .overlay { mainPhotoTools }
                    .clipped()
                    .environment(\.layoutDirection, contentLayoutDirection)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    controlsPanel(isBottom: isBottom, width: isBottom ? geometry.size.width : dockWidth, height: geometry.size.height)
                        .environment(\.layoutDirection, contentLayoutDirection)
                }
                // Reverse only the layout order, preserving canvas and tool identities/drafts.
                .environment(\.layoutDirection, !isBottom && controlsSide == "left" ? .rightToLeft : .leftToRight)

                .overlay(alignment: .top) {
                    if session.viewModel.isShowingBefore {
                        BeforeCapsule()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: session.viewModel.isShowingBefore)
                .sensoryFeedback(trigger: session.viewModel.isShowingBefore) { _, isShowing in
                    isShowing ? .impact(weight: .light) : nil
                }
                .overlay(alignment: .bottom) {
                    if let message = session.viewModel.renderErrorMessage {
                        RenderErrorBanner(
                            message   : message,
                            onDismiss : session.viewModel.dismissRenderError
                        )
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(cardAnimation, value: session.viewModel.renderErrorMessage)
                .background(EditorSurround.color.ignoresSafeArea())
                .background { zoomInAliases }
                .background { beforeShortcut }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editorWidth = $0 }
                .toolbar { toolbar }
            }
            .sheet(isPresented: $isSettingsShown) {
                NavigationStack {
                    Form {
                        Section("About") {
                            NavigationLink("Licenses & Credits") { LegalNoticesView() }
                        }
                        NativeBackupPanel(model: session.viewModel)
                        Section("Editor layout") {
                            Picker("Controls side", selection: $controlsSide) {
                                Text("Left").tag("left")
                                Text("Right").tag("right")
                            }
                            .pickerStyle(.segmented)
                            Text("Controls use this side on Mac, iPad and iPhone in landscape. On iPhone in portrait, controls stay in the lower half.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isSettingsShown = false }.disabled(dockIsBusy)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .environment(\.editorToolBusy, $dockIsBusy)
            }
            .onChange(of: session.isEditorPresented) { _, shown in
                if !shown { closeTool() }
                #if DEBUG
                if shown {
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("-iLightCraftShowComputational") {
                        let selected = UserDefaults.standard.string(forKey: "iLightCraftComputationalTool").flatMap(Int.init) ?? 0
                        presentTool(.computational(selected))
                    }
                    if arguments.contains("-iLightCraftShowCrop") { presentTool(.crop) }
                    if arguments.contains("-iLightCraftShowCurve") { presentTool(.curves) }
                    if arguments.contains("-iLightCraftShowHSL") { presentTool(.hsl) }
                    if arguments.contains("-iLightCraftShowProfiles") { presentTool(.profiles) }
                    if arguments.contains("-iLightCraftShowExport") { presentTool(.export) }
                }
                #endif
            }
            .onChange(of: session.isCardOpen) { _, open in
                if open { closeTool() }
            }

        }
        .preferredColorScheme(.dark)
        .disabled(session.isSavingPhotos || session.isReturningHome)
        .overlay {
            if session.isSavingPhotos {
                ProgressView(session.photosStatus ?? "Saving…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = session.photosStatus, !session.isSavingPhotos {
                Text(message)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .onTapGesture { session.photosStatus = nil }
            }
        }
        .focusedSceneValue(\.zoomCanvas, session.canZoom && !interactionLocked && !usesPhotoTools ? canvas : nil)
        .modifier(EditorAlertPresenter(
            alert     : session.presentedAlert,
            onDismiss : session.dismiss
        ))
    }

    private func presentTool(_ tool: EditorDockTool) {
        guard !interactionLocked else { return }
        if dockTool == tool { closeTool(); return }
        session.select(.move)
        presetVersions = tool == .presets || tool == .versions ? PresetVersionSession(model: session.viewModel, onOpen: { photo, source in
            if await session.openMergedCopy(photo, source: source, merged: false) { closeTool() }
        }) : nil
        advancedColor = tool == .pointColor || tool == .grading || tool == .optics
            ? AdvancedColorSession(model: session.viewModel, pointColor: tool == .pointColor, optics: tool == .optics) : nil
        spatialCrop = tool == .crop ? CropEditorSession(model: session.viewModel) : nil
        spatialSelection = tool == .computational(0) || tool == .computational(1)
            ? ComputationalToolsSession(model: session.viewModel, onIndexed: { _, _ in }) : nil
        toolZoomRequest = nil
        dockTool = tool
    }

    private func closeTool() {
        dockTool = nil
        spatialCrop = nil; spatialSelection = nil; advancedColor = nil; presetVersions = nil
        mainPhotoInteracting = false; toolZoomRequest = nil
        dockIsBusy = false
    }

    private func zoomPhotoToFit() {
        if usesPhotoTools { toolZoomRequest = .init(action: .fit) }
        else { canvas.zoomToFit() }
    }

    private func changeHistory(redo: Bool) async {
        if redo { await session.viewModel.redo() } else { await session.viewModel.undo() }
        await spatialSelection?.refreshAfterHistory()
        await spatialCrop?.refreshAfterHistory()
        await advancedColor?.load()
        await presetVersions?.load()
    }

    @ViewBuilder private var mainPhotoTools: some View {
        if let optics = advancedColor, optics.guiding {
            if let image = optics.image {
                PhotoToolViewport(image: image, mode: .guides, stroke: optics.guideStroke,
                                  guideLines: optics.guideLines, onGuideFinished: optics.finishGuide,
                                  busy: optics.busy, zoomRequest: toolZoomRequest,
                                  onStroke: { optics.guideStroke = $0 }, onInteraction: { mainPhotoInteracting = $0 })
            } else { Rectangle().fill(EditorSurround.color).overlay { ProgressView("Preparing guides…") } }
        } else if let color = advancedColor, color.pointColor {
            if let image = color.image {
                PhotoToolViewport(image: image, mode: .masks, picking: color.picking, busy: color.busy,
                                  zoomRequest: toolZoomRequest,
                                  onPick: { point in Task { await color.pick(point) } },
                                  onInteraction: { mainPhotoInteracting = $0 })
            } else {
                Rectangle().fill(EditorSurround.color).overlay { ProgressView(color.error ?? "Preparing photo…") }
            }
        } else if let crop = spatialCrop {
            if let image = crop.image {
                PhotoToolViewport(image: image, mode: .crop,
                                  crop: crop.selection, ratio: crop.ratio, angle: crop.previewAngle,
                                  busy: dockIsBusy, zoomRequest: toolZoomRequest,
                                  onCrop: { crop.selection = $0 }, onInteraction: { mainPhotoInteracting = $0 })
                    .accessibilityIdentifier("main-photo-crop")
            } else {
                Rectangle().fill(EditorSurround.color).overlay { ProgressView(crop.error ?? "Preparing crop…") }
            }
        } else if let selection = spatialSelection {
            if let image = selection.displayedImage {
                PhotoToolViewport(image: image, mode: spatialMode(selection),
                                  mask: selection.showMaskOverlay && selection.tintedPreview == nil && dockTool == .computational(0) ? selection.maskOverlay : nil,
                                  sourcePoint: dockTool == .computational(1) ? selection.sourcePoint : nil,
                                  stroke: dockTool == .computational(0) && selection.manualKind != "none" ? selection.manualPoints : selection.stroke,
                                  brushSize: selection.brushSize,
                                  picking: selection.isPickingObject || selection.isPickingSource || selection.manualKind == "colorRange", busy: selection.busy,
                                  zoomRequest: toolZoomRequest,
                                  onPick: { point in
                                      if dockTool == .computational(1) && selection.isPickingSource { selection.sourcePoint = point; selection.isPickingSource = false }
                                      else if selection.manualKind == "colorRange" { selection.manualPick(point) }
                                      else { selection.select(people: false, background: false, point: point) }
                                  },
                                  onStroke: { points in
                                      if dockTool == .computational(0) && selection.manualKind != "none" { selection.manualPoints = points }
                                      else { selection.stroke = points }
                                  }, onInteraction: { mainPhotoInteracting = $0 })
                    .accessibilityIdentifier("main-photo-mask-remove")
            } else {
                Rectangle().fill(EditorSurround.color).overlay { ProgressView(selection.error ?? "Preparing photo…") }
            }
        }
    }

    private func spatialMode(_ selection: ComputationalToolsSession<Engine, Importer>) -> PhotoToolViewport.Mode {
        if dockTool == .computational(1) && selection.isPickingSource { return .masks }
        if dockTool == .computational(1) || selection.manualKind == "brush" { return .remove }
        if selection.manualKind == "linear" { return .guides }
        if selection.manualKind == "radial" { return .radial }
        return .masks
    }

    @ViewBuilder
    private func controlsPanel(isBottom: Bool, width: CGFloat, height: CGFloat) -> some View {
        if dockTool != nil || session.isCardOpen {
            Group {
                if let dockTool {
                    EditorDockHost(content: dockContent(dockTool)
                        .id(dockTool)
                        .environment(\.editorToolDocked, true)
                        .environment(\.editorToolClose, { closeTool() })
                        .environment(\.editorToolBusy, $dockIsBusy)
                        .environment(\.colorScheme, .dark))
                        .background(.regularMaterial, in: .rect(cornerRadius: 20))
                        .clipShape(.rect(cornerRadius: 20))
                } else {
                    AdjustCard(viewModel: session.viewModel,
                               group: $session.selectedGroup,
                               clipping: $session.clipping,
                               width: max(0, width - 16),
                               isCompact: true,
                               histogramHeight: isBottom ? 48 : 68)
                }
            }
            .frame(width: width)
            .frame(height: isBottom ? EditorControlsLayout.bottomHeight(available: height) : height)
            .clipped()
            .accessibilityIdentifier("editor-controls-panel")
        }
    }

    @ViewBuilder
    private func dockContent(_ tool: EditorDockTool) -> some View {
        switch tool {
        case .presets, .versions:
            if let presetVersions { PresetVersionPanel(session: presetVersions, versionsMode: tool == .versions) }
        case .optics:
            if let advancedColor { OpticsPanel(session: advancedColor) }
        case .pointColor, .grading:
            if let advancedColor { AdvancedColorPanel(session: advancedColor) }
        case .hsl: HSLMixerPanel(model: session.viewModel)
        case .profiles: ProfilesPanel(model: session.viewModel)
        case .curves: ToneCurveSheet(model: session.viewModel)
        case .crop: PhotoCropSheet(model: session.viewModel, sharedSession: spatialCrop)
        case .export: PhotoExportSheet(model: session.viewModel)
        case .info:
            PhotoInfoSheet(name: session.viewModel.photoTitle, type: session.viewModel.photoType, size: session.viewModel.photoSize)
        case .computational(let section): computationalContent(section: section)
        }
    }

    private func computationalContent(section: Int) -> some View {
        ComputationalToolsSheet(model: session.viewModel, initialSection: section, sharedSession: spatialSelection, onMerged: { photo, source in
            if await session.openMergedCopy(photo, source: source) { closeTool() }
        }, onRendered: { source in
            await session.open(pickedURL: source)
            closeTool()
        }, onIndexed: { photo, source in
            if await session.openMergedCopy(photo, source: source, merged: false) { closeTool() }
        })
    }

    /// zoomInAliases add Cmd = and Cmd Shift = to Zoom In, next to ZoomCommands' Cmd +: plus needs
    /// Shift on a US keyboard and "=" needs it on an Italian one. They are invisible, zero-size
    /// buttons, kept out of the View menu so it lists Zoom In once.
    private var zoomInAliases: some View {
        Group {
            Button("Zoom In", action: canvas.zoomIn)
                .keyboardShortcut("=", modifiers: .command)

            Button("Zoom In", action: canvas.zoomIn)
                .keyboardShortcut("=", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .disabled(!session.canZoom || interactionLocked || usesPhotoTools)
    }

    /// beforeShortcut is the backslash key, Lightroom's before and after, as a toggle: the keyboard
    /// reports no key release to SwiftUI, so a hold would need a UIKit key handler. Invisible and
    /// zero-size like zoomInAliases; the More menu has the same toggle for touch.
    private var beforeShortcut: some View {
        Button("Show Original", action: toggleBefore)
            .keyboardShortcut("\\", modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .disabled(!session.canZoom || interactionLocked || usesPhotoTools)
    }

    /// setShowingBefore turns the before look on or off for the viewmodel, in order with the edits.
    private func setShowingBefore(_ isShowing: Bool) {
        Task.immediate { await session.viewModel.setShowingBefore(isShowing) }
    }

    private func toggleBefore() {
        setShowingBefore(!session.viewModel.isShowingBefore)
    }

    /// cardAnimation opens and closes the card: a short slide, or a cross-fade under Reduce Motion.
    private var cardAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.25)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            Button(
                "Home",
                systemImage : "chevron.backward",
                action      : { if !interactionLocked { session.goHome() } }
            )
            .editorHoverHelp("Back — save changes to Apple Photos")
            .accessibilityIdentifier("home-button")
            .disabled(interactionLocked)
        }

        ToolbarSpacer(.fixed, placement: .topBarLeading)

        if horizontalSizeClass != .compact {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Info", systemImage: "info.circle") { presentTool(.info) }

                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.viewModel.photoTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 180, alignment: .leading)

                        Text((session.viewModel.hdrEnabled ? "HDR · " : "") + (session.viewModel.isEdited ? "Edited" : "Original"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("title-menu")
                .disabled(interactionLocked)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .topBarLeading)

            ToolbarItem(placement: .topBarLeading) {
                if usesPhotoTools {
                    Menu("Zoom", systemImage: "magnifyingglass") {
                        Button("Zoom In") { toolZoomRequest = .init(action: .zoomIn) }
                        Button("Zoom Out") { toolZoomRequest = .init(action: .zoomOut) }
                        Button("Zoom to Fit", action: zoomPhotoToFit)
                    }
                    .labelStyle(.iconOnly).disabled(interactionLocked)
                } else {
                    ZoomPill(session: session, canvas: canvas)
                        .editorHoverHelp("Zoom")
                        .disabled(interactionLocked)
                }
            }
        }

        if UIDevice.current.userInterfaceIdiom == .phone {
            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarActions.labelStyle(.iconOnly)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                EditorToolbarStrip(width: min(880, max(88, editorWidth - 440))) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) { toolbarActions.labelStyle(.iconOnly) }
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: min(880, max(88, editorWidth - 440)), height: 44)
            }
        }
        ToolbarItem(placement: .topBarTrailing) { moreMenu }
    }

    @ViewBuilder
    private var toolbarActions: some View {
            Button(session.isCardOpen ? "Done Editing" : "Edit", systemImage: "slider.horizontal.3") {
                closeTool()
                session.select(session.isCardOpen ? .move : .adjust)
            }
            .labelStyle(.iconOnly)
            .editorToolSelected(session.isCardOpen)
            .disabled(!session.viewModel.isPhotoOpen || interactionLocked)
            .accessibilityValue(session.isCardOpen ? "Editing panel open" : "Editing panel closed")
            .editorHoverHelp(session.isCardOpen ? "Done Editing" : "Edit")
            .accessibilityIdentifier("adjust-button")
        if UIDevice.current.userInterfaceIdiom != .phone {
            editingTools.labelStyle(.iconOnly).toggleStyle(.button)
        }
            Button("Undo", systemImage: "arrow.uturn.backward") {
                Task { await changeHistory(redo: false) }
            }
            .keyboardShortcut("z", modifiers: .command)
            .editorHoverHelp("Undo")
            .disabled(!session.viewModel.canUndo || session.viewModel.isShowingBefore || interactionLocked)

            Button("Redo", systemImage: "arrow.uturn.forward") {
                Task { await changeHistory(redo: true) }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .editorHoverHelp("Redo")
            .disabled(!session.viewModel.canRedo || session.viewModel.isShowingBefore || interactionLocked)
            Button("Export", systemImage: "square.and.arrow.up") { presentTool(.export) }
                .disabled(!session.viewModel.isPhotoOpen || interactionLocked)
                .editorToolSelected(dockTool == .export)
                .editorHoverHelp("Export")
                .accessibilityIdentifier("export-button")
    }

    private var moreMenu: some View {
            Menu("More", systemImage: "ellipsis") {
                if session.photoContext != nil {
                    Button("Save to Apple Photos", systemImage: "photo.badge.checkmark") {
                        Task { await session.saveToPhotos() }
                    }
                    .disabled(!session.viewModel.isPhotoOpen || session.isSavingPhotos)
                }
                if UIDevice.current.userInterfaceIdiom == .phone {
                    editingTools
                }
                if horizontalSizeClass == .compact {
                    Text(session.viewModel.photoTitle + (session.viewModel.hdrEnabled ? " · HDR" : ""))
                }
                Button("Info", systemImage: "info.circle") { presentTool(.info) }
                Button("Fit Photo", action: zoomPhotoToFit)
                Button("Settings", systemImage: "gearshape") { isSettingsShown = true }

                #if DEBUG
                DiagnosticsMenuItems(diagnostics: diagnostics, isPhotoOpen: session.viewModel.isPhotoOpen)
                #endif
            }
            .help("More")
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("more-menu")
            .disabled(interactionLocked)
    }

    private func computationalToolButton(_ tool: ComputationalTool) -> some View {
        Button(tool.title, systemImage: tool.symbol) { presentTool(.computational(tool.rawValue)) }
            .editorToolSelected(dockTool == .computational(tool.rawValue))
            .editorHoverHelp(tool.title)
            .accessibilityIdentifier("tool-\(tool.rawValue)")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
    }

    @ViewBuilder
    private var editingTools: some View {
        Button("Crop & Rotate", systemImage: "crop.rotate") { presentTool(.crop) }
            .editorToolSelected(dockTool == .crop)
            .editorHoverHelp("Crop & Rotate")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        ForEach([ComputationalTool.remove, .masks]) { tool in
            computationalToolButton(tool)
        }
        Button("Presets & Batch", systemImage: "square.stack") { presentTool(.presets) }
            .editorToolSelected(dockTool == .presets).editorHoverHelp("Presets & Batch")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Profiles", systemImage: "camera.filters") { presentTool(.profiles) }
            .editorToolSelected(dockTool == .profiles)
            .editorHoverHelp("Profiles")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Tone Curves", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { presentTool(.curves) }
            .editorToolSelected(dockTool == .curves)
            .editorHoverHelp("Tone Curves")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("HSL Mixer", systemImage: "paintpalette") { presentTool(.hsl) }
            .editorToolSelected(dockTool == .hsl)
            .editorHoverHelp("HSL Mixer")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Point Color", systemImage: "eyedropper") { presentTool(.pointColor) }
            .editorToolSelected(dockTool == .pointColor).editorHoverHelp("Point Color")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Color Grading", systemImage: "circle.lefthalf.filled") { presentTool(.grading) }
            .editorToolSelected(dockTool == .grading).editorHoverHelp("Color Grading")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Optics & Perspective", systemImage: "camera.metering.center.weighted") { presentTool(.optics) }
            .editorToolSelected(dockTool == .optics).editorHoverHelp("Optics & Perspective")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Versions & History", systemImage: "clock.arrow.circlepath") { presentTool(.versions) }
            .editorToolSelected(dockTool == .versions).editorHoverHelp("Versions & History")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        ForEach([ComputationalTool.lensBlur, .enhancement, .analysis, .merge]) { tool in
            computationalToolButton(tool)
        }
        Toggle("HDR Editing", systemImage: "sun.max", isOn: Binding(
            get: { session.viewModel.hdrEnabled },
            set: { value in Task { await session.viewModel.setHDR(value) } }
        ))
        .editorToolSelected(session.viewModel.hdrEnabled)
        .editorHoverHelp("HDR Editing")
        .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Toggle(
            "Show Original",
            systemImage : "circle.lefthalf.filled",
            isOn        : Binding(
                get : { session.viewModel.isShowingBefore },
                set : setShowingBefore
            )
        )
        .editorToolSelected(session.viewModel.isShowingBefore)
        .editorHoverHelp("Show Original")
        .disabled(!session.canZoom || interactionLocked || usesPhotoTools)

        Button("Reset All", systemImage: "arrow.counterclockwise") {
            Task { await session.viewModel.resetAll(); await spatialSelection?.refreshAfterHistory(); await advancedColor?.load() }
        }
        .editorHoverHelp("Reset All")
        .disabled(!session.viewModel.isEdited || session.viewModel.isShowingBefore || interactionLocked || spatialCrop != nil)
    }
}

private extension View {
    /// Explicit styling survives the custom toolbar hosting boundary, unlike inherited tint.
    func editorToolSelected(_ selected: Bool) -> some View {
        let highlight = Color(red: 242.0 / 255, green: 165.0 / 255, blue: 22.0 / 255)
        return self
            .foregroundStyle(selected ? highlight : Color.primary)
            .frame(minWidth: 36, minHeight: 36)
            .background {
                if selected, UIDevice.current.userInterfaceIdiom != .phone {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(highlight.opacity(0.22))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(highlight.opacity(0.65), lineWidth: 1)
                        }
                }
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    func editorHoverHelp(_ label: String) -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            help(label)
        } else {
            ToolbarHoverLabel(content: self, label: label)
                .frame(width: 44, height: 44)
        }
    }
}
