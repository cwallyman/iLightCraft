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
    @State private var phoneZoomEntry = false
    @State private var dockTool: EditorDockTool?
    @State private var dockIsBusy = false
    @State private var photoPanel: PhotoPanelSession<Engine, Importer>
    @State private var auxiliary: EditorAuxiliarySession<Engine, Importer>?
    @State private var presetVersions: PresetVersionSession<Engine, Importer>?
    @State private var advancedColor: AdvancedColorSession<Engine, Importer>?
    @State private var spatialCrop: CropEditorSession<Engine, Importer>?
    @State private var spatialSelection: ComputationalToolsSession<Engine, Importer>?
    @State private var mainPhotoInteracting = false
    @State private var toolZoomPercent: Double?
    @State private var toolZoomRequest: PhotoToolViewport.ZoomRequest?
    private var interactionLocked: Bool { dockIsBusy || mainPhotoInteracting }
    private var usesPhotoTools: Bool { (auxiliary?.mode == .redEye || auxiliary?.mode == .whiteBalance) || spatialCrop != nil || spatialSelection != nil || (advancedColor?.pointColor == true || advancedColor?.guiding == true) }

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
        _photoPanel = State(initialValue: PhotoPanelSession(model: session.viewModel))
        _dockTool = State(initialValue: initialDockTool)
        if initialDockTool == .keywords || initialDockTool == .redEye || initialDockTool == .whiteBalance {
            _auxiliary = State(initialValue: EditorAuxiliarySession(model: session.viewModel, mode: initialDockTool == .redEye ? .redEye : (initialDockTool == .whiteBalance ? .whiteBalance : .keywords)))
        }
        if initialDockTool == .presets || initialDockTool == .batch || initialDockTool == .versions || initialDockTool == .history {
            _presetVersions = State(initialValue: PresetVersionSession(model: session.viewModel, onOpen: { photo, source in
                _ = await session.openMergedCopy(photo, source: source, merged: false)
            }))
        }
        if initialDockTool == .pointColor || initialDockTool == .grading || initialDockTool == .optics || initialDockTool == .geometry || initialDockTool == .crop {
            _advancedColor = State(initialValue: AdvancedColorSession(model: session.viewModel, pointColor: initialDockTool == .pointColor, optics: initialDockTool == .optics || initialDockTool == .geometry || initialDockTool == .crop))
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
                    .overlay {
                        if photoPanel.mode == .beforeAfter {
                            BeforeEditedComparison(session: photoPanel, tool: dockTool, zoomRequest: toolZoomRequest,
                                                   onZoomPercent: { toolZoomPercent = $0 }, onInteraction: { mainPhotoInteracting = $0 })
                        } else if photoPanel.mode != .detail {
                            PhotoPanelGallery(session: photoPanel) { id in Task { await openPanelPhoto(id) } }
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        PhotoPanelControls(session: photoPanel, locked: interactionLocked || session.viewModel.isShowingBefore) { mode in
                            guard !interactionLocked else { return }
                            if mode == .beforeAfter && usesPhotoTools { closeTool(); session.select(.move) }
                            toolZoomPercent = nil; toolZoomRequest = .init(action: .fit)
                            Task { await photoPanel.choose(mode) }
                        }
                    }

                    controlsPanel(isBottom: isBottom, width: isBottom ? geometry.size.width : dockWidth, height: max(0, geometry.size.height - 52))
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
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { topToolbar }
            }
            .sheet(isPresented: $isSettingsShown) {
                NavigationStack {
                    LightCraftMenuList {
                        LightCraftMenuSection("About") {
                            NavigationLink("Licenses & Credits") { LegalNoticesView() }
                        }
                        NativeBackupPanel(model: session.viewModel)
                        LightCraftMenuSection("Editor layout") {
                            Picker("Controls side", selection: $controlsSide) {
                                Text("Left").tag("left")
                                Text("Right").tag("right")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .navigationTitle("Settings")
                    .toolbarBackground(LightCraftPanelStyle.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
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
        .onChange(of: usesPhotoTools) { _, active in
            if active && photoPanel.mode == .beforeAfter { photoPanel.mode = .detail; photoPanel.stopComparison() }
        }
        .focusedSceneValue(\.zoomCanvas, session.canZoom && !interactionLocked && !usesPhotoTools && photoPanel.mode != .beforeAfter ? canvas : nil)
        .modifier(EditorAlertPresenter(
            alert     : session.presentedAlert,
            onDismiss : session.dismiss
        ))
    }

    private func presentTool(_ tool: EditorDockTool) {
        guard !interactionLocked else { return }
        if dockTool == tool { closeTool(); return }
        session.select(.move)
        presetVersions = tool == .presets || tool == .batch || tool == .versions || tool == .history ? PresetVersionSession(model: session.viewModel, onOpen: { photo, source in
            if await session.openMergedCopy(photo, source: source, merged: false) { closeTool() }
        }) : nil
        advancedColor = tool == .pointColor || tool == .grading || tool == .optics || tool == .geometry || tool == .crop
            ? AdvancedColorSession(model: session.viewModel, pointColor: tool == .pointColor, optics: tool == .optics || tool == .geometry || tool == .crop) : nil
        spatialCrop = tool == .crop ? CropEditorSession(model: session.viewModel) : nil
        spatialSelection = tool == .computational(0) || tool == .computational(1)
            ? ComputationalToolsSession(model: session.viewModel, onIndexed: { _, _ in }) : nil
        auxiliary = tool == .redEye || tool == .keywords || tool == .whiteBalance ? EditorAuxiliarySession(model: session.viewModel, mode: tool == .redEye ? .redEye : (tool == .whiteBalance ? .whiteBalance : .keywords)) : nil
        toolZoomPercent = nil
        toolZoomRequest = nil
        dockTool = tool
    }

    private func closeTool() {
        dockTool = nil
        auxiliary = nil
        spatialCrop = nil; spatialSelection = nil; advancedColor = nil; presetVersions = nil
        mainPhotoInteracting = false; toolZoomRequest = nil
        dockIsBusy = false
    }

    private func zoomPhotoToFit() {
        if usesPhotoTools || photoPanel.mode == .beforeAfter { toolZoomRequest = .init(action: .fit) }
        else { canvas.zoomToFit() }
    }

    private func changeHistory(redo: Bool) async {
        if redo { await session.viewModel.redo() } else { await session.viewModel.undo() }
        await spatialSelection?.refreshAfterHistory()
        await spatialCrop?.refreshAfterHistory()
        await advancedColor?.load()
        await presetVersions?.load()
        await auxiliary?.load()
    }

    @ViewBuilder private var mainPhotoTools: some View {
        if let eye = auxiliary, eye.mode == .redEye || eye.mode == .whiteBalance {
            if let image = eye.image {
                PhotoToolViewport(image: image, mode: .masks, sourcePoint: eye.center,
                                  brushSize: eye.radius, picking: eye.picking, busy: eye.busy,
                                  zoomRequest: toolZoomRequest,
                                  onPick: { point in
                                      if eye.mode == .whiteBalance { Task { await eye.pickWhiteBalance(point) } }
                                      else { eye.center = point; eye.picking = false }
                                  },
                                  onInteraction: { mainPhotoInteracting = $0 },
                                  sourcePixelWidth: session.viewModel.photoSize.width, selectionRadius: eye.mode == .redEye ? eye.radius : nil,
                                  onZoomPercent: { toolZoomPercent = $0 })
                    .accessibilityIdentifier("main-photo-red-eye")
            } else {
                Rectangle().fill(EditorSurround.color).overlay { Text(eye.error ?? "Preparing Red Eye…") }
            }
        } else if let optics = advancedColor, optics.guiding {
            if let image = optics.image {
                PhotoToolViewport(image: image, mode: .guides, stroke: optics.guideStroke,
                                  guideLines: optics.guideLines, onGuideFinished: optics.finishGuide,
                                  busy: optics.busy, zoomRequest: toolZoomRequest,
                                  onStroke: { optics.guideStroke = $0 }, onInteraction: { mainPhotoInteracting = $0 },
                                  sourcePixelWidth: session.viewModel.photoSize.width,
                                  onZoomPercent: { toolZoomPercent = $0 })
            } else { Rectangle().fill(EditorSurround.color).overlay { ProgressView("Preparing guides…") } }
        } else if let color = advancedColor, color.pointColor {
            if let image = color.image {
                PhotoToolViewport(image: image, mode: .masks, picking: color.picking, busy: color.busy,
                                  zoomRequest: toolZoomRequest,
                                  onPick: { point in Task { await color.pick(point) } },
                                  onInteraction: { mainPhotoInteracting = $0 },
                                  sourcePixelWidth: session.viewModel.photoSize.width,
                                  onZoomPercent: { toolZoomPercent = $0 })
            } else {
                Rectangle().fill(EditorSurround.color).overlay { ProgressView(color.error ?? "Preparing photo…") }
            }
        } else if let crop = spatialCrop {
            if let image = crop.image {
                PhotoToolViewport(image: image, mode: crop.straightening ? .guides : .crop, stroke: crop.straightenStroke,
                                  onGuideFinished: crop.finishStraightening, crop: crop.selection, ratio: crop.ratio, angle: crop.previewAngle,
                                  busy: dockIsBusy, zoomRequest: toolZoomRequest,
                                  onStroke: { crop.straightenStroke = $0 }, onCrop: { crop.selection = $0 }, onInteraction: { mainPhotoInteracting = $0 },
                                  sourcePixelWidth: session.viewModel.photoSize.width,
                                  onZoomPercent: { toolZoomPercent = $0 }, cropOverlay: crop.overlay, cropOverlayFlipped: crop.flipOverlay)
                    .accessibilityIdentifier("main-photo-crop")
            } else {
                Rectangle().fill(EditorSurround.color).overlay { ProgressView(crop.error ?? "Preparing crop…") }
            }
        } else if let selection = spatialSelection {
            if let image = selection.displayedImage {
                PhotoToolViewport(image: image, mode: spatialMode(selection),
                                  mask: selection.showMaskOverlay && selection.tintedPreview == nil && dockTool == .computational(0) ? selection.maskOverlay : nil,
                                  sourcePoint: dockTool == .computational(1) && selection.removalMode != "fill" ? selection.sourcePoint : nil,
                                  maskPin: dockTool == .computational(0) && selection.showPins && !selection.maskingContentAware ? selection.selectedMaskPin : nil,
                                  stroke: dockTool == .computational(0) && !selection.maskingContentAware && selection.manualKind != "none" ? selection.manualPoints : selection.stroke,
                                  brushSize: selection.brushSize,
                                  picking: selection.isPickingObject || selection.isPickingSource || selection.manualKind == "colorRange", busy: selection.busy,
                                  zoomRequest: toolZoomRequest,
                                  onPick: { point in
                                      if dockTool == .computational(1) && selection.isPickingSource { selection.sourcePoint = point; selection.isPickingSource = false }
                                      else if selection.manualKind == "colorRange" { selection.manualPick(point) }
                                      else { selection.select(people: false, background: false, point: point) }
                                  },
                                  onStroke: { points in
                                      if dockTool == .computational(0) && !selection.maskingContentAware && selection.manualKind != "none" { selection.manualPoints = points }
                                      else { selection.stroke = points }
                                  }, onInteraction: { mainPhotoInteracting = $0 },
                                  sourcePixelWidth: session.viewModel.photoSize.width,
                                  onZoomPercent: { toolZoomPercent = $0 })
                    .accessibilityIdentifier("main-photo-mask-remove")
            } else {
                Rectangle().fill(EditorSurround.color).overlay { ProgressView(selection.error ?? "Preparing photo…") }
            }
        }
    }

    private func spatialMode(_ selection: ComputationalToolsSession<Engine, Importer>) -> PhotoToolViewport.Mode {
        if dockTool == .computational(1) && selection.isPickingSource { return .masks }
        if dockTool == .computational(1) || selection.maskingContentAware || selection.manualKind == "brush" { return .remove }
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
                        .background(LightCraftPanelStyle.background)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    LightCraftEditPanel(model: session.viewModel, group: session.selectedGroup, clipping: $session.clipping, openTool: presentTool, onColorPicker: { if dockTool == nil { auxiliary = nil; advancedColor = $0 } }, onWhiteBalancePicker: { if dockTool == nil { advancedColor = nil; auxiliary = $0 } })

                }
            }
            .environment(\.editorToolBusy, $dockIsBusy)
            .frame(width: width)
            .frame(height: isBottom ? EditorControlsLayout.bottomHeight(available: height) : height)
            .clipped()
            .accessibilityIdentifier("editor-controls-panel")
        }
    }

    @ViewBuilder
    private func dockContent(_ tool: EditorDockTool) -> some View {
        switch tool {
        case .presets, .batch, .versions, .history:
            if let presetVersions { PresetVersionPanel(session: presetVersions, versionsMode: tool == .versions || tool == .history, historyMode: tool == .history, appExtras: tool == .batch, openBatch: { presentTool(.batch) }) }
        case .redEye, .keywords, .whiteBalance:
            if let auxiliary { EditorAuxiliaryPanel(session: auxiliary) }
        case .optics, .geometry:
            if let advancedColor { OpticsPanel(session: advancedColor, geometryOnly: tool == .geometry) }
        case .pointColor, .grading:
            if let advancedColor { AdvancedColorPanel(session: advancedColor) }
        case .hsl: HSLMixerPanel(model: session.viewModel)
        case .profiles: ProfilesPanel(model: session.viewModel)
        case .curves: ToneCurveSheet(model: session.viewModel)
        case .crop: PhotoCropSheet(model: session.viewModel, sharedSession: spatialCrop, sharedGeometry: advancedColor)
        case .export: PhotoExportSheet(model: session.viewModel)
        case .info:
            LightCraftInfoPanel(model: session.viewModel, photoPanel: photoPanel)
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
        .disabled(!session.canZoom || interactionLocked || usesPhotoTools || photoPanel.mode == .beforeAfter)
    }

    /// beforeShortcut is the backslash key, before and after, as a toggle: the keyboard
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
        if isShowing && photoPanel.mode == .beforeAfter { photoPanel.mode = .detail; photoPanel.stopComparison() }
        Task.immediate { await session.viewModel.setShowingBefore(isShowing) }
    }

    private func toggleBefore() {
        setShowingBefore(!session.viewModel.isShowingBefore)
    }

    /// cardAnimation opens and closes the card: a short slide, or a cross-fade under Reduce Motion.
    private var cardAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.25)
    }

    /// usesCompactToolbar folds the editing modes into More when the editor is too narrow for the
    /// glass groups: on iPhone, and on iPad in a narrow window or in Split View.
    private var usesCompactToolbar: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || editorWidth < 720
    }

    /// showsModeNames writes each mode's name under its icon when the full row fits.
    private var showsModeNames: Bool { editorWidth >= 1000 }

    /// topToolbar floats the editor controls as Liquid Glass groups over the surround: back, title
    /// and zoom on the leading side, the editing modes in the middle, history and output on the
    /// trailing side. Tools used less often live in More, so nothing scrolls sideways.
    private var topToolbar: some View {
        HStack(spacing: 10) {
            backButton
                .glassEffect(.regular, in: .capsule)
            if usesCompactToolbar {
                photoTitle.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                photoTitle
                    .padding(.horizontal, 14)
                    .frame(maxWidth: 220, minHeight: 44, alignment: .leading)
                    .glassEffect(.regular, in: .capsule)
                toolbarZoom
                    .frame(minWidth: 58, minHeight: 44)
                    .padding(.horizontal, 6)
                    .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
                editingModes
                    .padding(3)
                    .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) { historyActions }
                .padding(.horizontal, 2)
                .glassEffect(.regular, in: .capsule)
            HStack(spacing: 0) {
                if !usesCompactToolbar {
                    toolbarTool("Export", icon: "Share", tool: .export).accessibilityIdentifier("export-button")
                }
                moreMenu
            }
            .padding(.horizontal, 2)
            .glassEffect(.regular, in: .capsule)
        }
        .labelStyle(.iconOnly).buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(height: 64)
        .background(EditorSurround.color)
        .accessibilityIdentifier("editor-top-toolbar")
    }
    private var backButton: some View {
        Button { if !interactionLocked { session.goHome() } } label: {
            Image(lightCraftIcon: "LightCraft-Back").resizable().scaledToFit()
                .frame(width: 26, height: 26).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Back")
        .accessibilityIdentifier("home-button").disabled(interactionLocked)
    }

    /// editingModes are the editor's main modes, named under their icons as iPadOS 27 toolbars do.
    /// Adjust toggles the Edit panel; the others open their tool in the same panel.
    private var editingModes: some View {
        HStack(spacing: 2) {
            modeButton("Adjust", lightCraftIcon: "LightCraft-Sliders", isSelected: isAdjusting) {
                closeTool()
                session.select(session.isCardOpen ? .move : .adjust)
            }
            .accessibilityIdentifier("adjust-button")
            .accessibilityValue(session.isCardOpen ? "Editing panel open" : "Editing panel closed")
            .disabled(!session.viewModel.isPhotoOpen || interactionLocked)
            modeButton("Crop", lightCraftIcon: "LightCraft-Crop", isSelected: dockTool == .crop || dockTool == .geometry) {
                presentTool(.crop)
            }
            .accessibilityIdentifier("toolbar-crop")
            .disabled(isToolUnavailable)
            ForEach([ComputationalTool.masks, .remove]) { tool in
                modeButton(tool == .masks ? "Masks" : tool.title, lightCraftIcon: tool.symbol, isSelected: dockTool == .computational(tool.rawValue)) {
                    presentTool(.computational(tool.rawValue))
                }
                .accessibilityIdentifier("tool-\(tool.rawValue)")
                .disabled(isToolUnavailable)
            }
            modeButton("Presets", lightCraftIcon: "LightCraft-Presets", isSelected: dockTool == .presets) {
                presentTool(.presets)
            }
            .accessibilityIdentifier("toolbar-presets")
            .disabled(isToolUnavailable)
        }
    }

    /// isAdjusting is true while the Edit panel, or a tool opened from inside it, is showing.
    private var isAdjusting: Bool {
        session.isCardOpen || [EditorDockTool.profiles, .curves, .hsl, .pointColor, .grading, .optics, .whiteBalance].contains { $0 == dockTool }
    }

    /// isToolUnavailable blocks the tools that edit the photo: none is open, a tool is busy, or the
    /// original is showing.
    private var isToolUnavailable: Bool {
        !session.viewModel.isPhotoOpen || interactionLocked || session.viewModel.isShowingBefore
    }

    private func modeButton(
        _ title       : String,
        lightCraftIcon: String,
        isSelected    : Bool,
        action        : @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            EditorModeLabel(
                title     : title,
                icon      : lightCraftIcon,
                isSelected: isSelected,
                showsTitle: showsModeNames
            )
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toolbarTool(_ title: String, icon: String, tool: EditorDockTool) -> some View {
        Button(title, lightCraftIcon: "LightCraft-\(icon)") { presentTool(tool) }
            .editorToolSelected(dockTool == tool || (tool == .crop && dockTool == .geometry)).editorHoverHelp(title)
            .accessibilityIdentifier("toolbar-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            .disabled(!session.viewModel.isPhotoOpen || interactionLocked || (tool != .info && tool != .export && session.viewModel.isShowingBefore))
    }

    /// menuTool is a tool as a plain menu item: menus draw their own items, so the hover and
    /// selection wrappers of the toolbar buttons stay out of them.
    private func menuTool(_ title: String, lightCraftIcon: String, tool: EditorDockTool) -> some View {
        Button(title, lightCraftIcon: lightCraftIcon) { presentTool(tool) }
            .accessibilityIdentifier("toolbar-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            .disabled(!session.viewModel.isPhotoOpen || interactionLocked || (tool != .info && tool != .export && session.viewModel.isShowingBefore))
    }

    @ViewBuilder private var toolbarZoom: some View {
        if usesPhotoTools || photoPanel.mode == .beforeAfter {
            LightCraftNumberButton(title: "Zoom Percent", value: toolZoomPercent ?? session.zoomPercent,
                                   range: ZoomScale.minimumPercent...ZoomScale.maximumPercent, step: 1, suffix: "%",
                                   display: "\(ZoomScale.label(forPercent: toolZoomPercent ?? session.zoomPercent))%") { percent in
                toolZoomRequest = .init(action: .percent(percent))
            }
            .contextMenu {
                Button("Zoom In") { toolZoomRequest = .init(action: .zoomIn) }
                Button("Zoom Out") { toolZoomRequest = .init(action: .zoomOut) }
                Button("Zoom to Fit", action: zoomPhotoToFit)
            }
            .accessibilityLabel("Zoom").accessibilityIdentifier("zoom-pill")
            .disabled(interactionLocked)
        } else {
            ZoomPill(session: session, canvas: canvas).disabled(interactionLocked)
        }
    }

    @ViewBuilder private var historyActions: some View {
        Button("Undo", lightCraftIcon: "LightCraft-Rotate") { Task { await changeHistory(redo: false) } }
            .keyboardShortcut("z", modifiers: .command)
            .frame(width: 44, height: 44)
            .accessibilityIdentifier("undo-button")
            .editorHoverHelp("Undo")
            .disabled(!session.viewModel.canUndo || session.viewModel.isShowingBefore || interactionLocked)
        Button("Redo", lightCraftIcon: "LightCraft-RotateClockwise") { Task { await changeHistory(redo: true) } }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .frame(width: 44, height: 44)
            .accessibilityIdentifier("redo-button")
            .editorHoverHelp("Redo")
            .disabled(!session.viewModel.canRedo || session.viewModel.isShowingBefore || interactionLocked)
    }

    private var photoName: some View {
        Text(session.viewModel.photoTitle)
            .font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            .accessibilityIdentifier("photo-name")
    }

    /// photoTitle is the open photo's name with its status under it ("Edited" when any control
    /// differs from its default, otherwise "Original"). Tapping it opens Info.
    private var photoTitle: some View {
        Button { presentTool(.info) } label: {
            VStack(alignment: .leading, spacing: 0) {
                photoName
                Text(session.viewModel.isEdited ? "Edited" : "Original")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(session.viewModel.isEdited ? Color.accentColor : Color.secondary)
                    .accessibilityIdentifier("photo-status")
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Shows the photo info")
        .disabled(!session.viewModel.isPhotoOpen || interactionLocked)
    }

    /// Native-only workflows stay outside the shared LightCraft tool panels.
    private var moreMenu: some View {
        Menu {
            if usesCompactToolbar {
                Section {
                    Button("Zoom (\(ZoomScale.label(forPercent: photoPanel.mode == .beforeAfter || usesPhotoTools ? toolZoomPercent ?? session.zoomPercent : session.zoomPercent))%)…") { phoneZoomEntry = true }
                        .disabled(!session.canZoom)
                    menuTool("Export", lightCraftIcon: "LightCraft-Share", tool: .export)
                }.labelStyle(.titleAndIcon)
                Section {
                    Button("Adjust", lightCraftIcon: "LightCraft-Sliders") {
                        closeTool()
                        session.select(session.isCardOpen ? .move : .adjust)
                    }
                    .disabled(!session.viewModel.isPhotoOpen || interactionLocked)
                    menuTool("Crop", lightCraftIcon: "LightCraft-Crop", tool: .crop)
                    menuTool("Masks", lightCraftIcon: ComputationalTool.masks.symbol, tool: .computational(ComputationalTool.masks.rawValue))
                    menuTool(ComputationalTool.remove.title, lightCraftIcon: ComputationalTool.remove.symbol, tool: .computational(ComputationalTool.remove.rawValue))
                    menuTool("Presets", lightCraftIcon: "LightCraft-Presets", tool: .presets)
                }.labelStyle(.titleAndIcon)
            }
            Section {
                menuTool("Red Eye", lightCraftIcon: "LightCraft-Eye", tool: .redEye)
                menuTool("Versions", lightCraftIcon: "LightCraft-Versions", tool: .versions)
                menuTool("History", lightCraftIcon: "LightCraft-Clock", tool: .history)
                menuTool("Keywords", lightCraftIcon: "LightCraft-Tag", tool: .keywords)
                menuTool("Info", lightCraftIcon: "LightCraft-Info", tool: .info)
            }.labelStyle(.titleAndIcon)
            if session.photoContext != nil {
                Button("Save to Apple Photos", lightCraftIcon: "LightCraft-Photos") { Task { await session.saveToPhotos() } }
                    .disabled(session.isSavingPhotos)
            }
            Section("Additional Tools") {
                ForEach([ComputationalTool.lensBlur, .enhancement, .analysis, .merge]) { tool in
                    computationalToolButton(tool)
                }
                Toggle("Show Original", isOn: Binding(get: { session.viewModel.isShowingBefore }, set: setShowingBefore))
                    .disabled(!session.canZoom || usesPhotoTools)
            }
            Button("Settings", lightCraftIcon: "LightCraft-Gear") { isSettingsShown = true }
        } label: {
            Image(lightCraftIcon: "LightCraft-More").resizable().scaledToFit()
                .frame(width: 26, height: 26).frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("more-menu").disabled(interactionLocked)
        .popover(isPresented: $phoneZoomEntry) {
            LightCraftTenKey(title: "Zoom Percent", value: usesPhotoTools || photoPanel.mode == .beforeAfter ? toolZoomPercent ?? session.zoomPercent : session.zoomPercent,
                             range: ZoomScale.minimumPercent...ZoomScale.maximumPercent, step: 1) { percent in
                phoneZoomEntry = false
                if usesPhotoTools || photoPanel.mode == .beforeAfter { toolZoomRequest = .init(action: .percent(percent)) }
                else { canvas.zoom(toPercent: percent) }
            } cancel: { phoneZoomEntry = false }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func openPanelPhoto(_ id: UInt64) async {
        guard !interactionLocked else { return }
        if session.viewModel.openPhoto?.rawValue == id { photoPanel.mode = .detail; return }
        do {
            let source = try await photoPanel.source(for: id)
            if session.photoContext != nil, !(await session.saveToPhotos()) { return }
            if await session.openMergedCopy(PhotoID(rawValue: id), source: source, merged: false) {
                closeTool(); session.select(.move)
                photoPanel.mode = .detail; photoPanel.selected = [id]
                await photoPanel.load()
            }
        } catch { photoPanel.error = error.localizedDescription }
    }

    private func computationalToolButton(_ tool: ComputationalTool) -> some View {
        Button(tool.title, lightCraftIcon: tool.symbol) { presentTool(.computational(tool.rawValue)) }
            .editorToolSelected(dockTool == .computational(tool.rawValue))
            .editorHoverHelp(tool.title)
            .accessibilityIdentifier("tool-\(tool.rawValue)")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
    }

    @ViewBuilder
    private var editingTools: some View {
        Button("Crop & Rotate", lightCraftIcon: "LightCraft-Crop") { presentTool(.crop) }
            .editorToolSelected(dockTool == .crop)
            .editorHoverHelp("Crop & Rotate")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        ForEach([ComputationalTool.remove, .masks]) { tool in
            computationalToolButton(tool)
        }
        Button("Presets & Batch", lightCraftIcon: "LightCraft-Presets") { presentTool(.presets) }
            .editorToolSelected(dockTool == .presets).editorHoverHelp("Presets & Batch")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Profiles", lightCraftIcon: "LightCraft-ProfileGrid") { presentTool(.profiles) }
            .editorToolSelected(dockTool == .profiles)
            .editorHoverHelp("Profiles")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Tone Curves", lightCraftIcon: "LightCraft-Curve") { presentTool(.curves) }
            .editorToolSelected(dockTool == .curves)
            .editorHoverHelp("Tone Curves")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("HSL Mixer", lightCraftIcon: "LightCraft-Sliders") { presentTool(.hsl) }
            .editorToolSelected(dockTool == .hsl)
            .editorHoverHelp("HSL Mixer")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Point Color", lightCraftIcon: "LightCraft-Picker") { presentTool(.pointColor) }
            .editorToolSelected(dockTool == .pointColor).editorHoverHelp("Point Color")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Color Grading", lightCraftIcon: "LightCraft-GradeAll") { presentTool(.grading) }
            .editorToolSelected(dockTool == .grading).editorHoverHelp("Color Grading")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Optics & Perspective", lightCraftIcon: "LightCraft-Target") { presentTool(.optics) }
            .editorToolSelected(dockTool == .optics).editorHoverHelp("Optics & Perspective")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Button("Versions & History", lightCraftIcon: "LightCraft-Versions") { presentTool(.versions) }
            .editorToolSelected(dockTool == .versions).editorHoverHelp("Versions & History")
            .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        ForEach([ComputationalTool.lensBlur, .enhancement, .analysis, .merge]) { tool in
            computationalToolButton(tool)
        }
        Toggle("HDR Editing", lightCraftIcon: "LightCraft-Sun", isOn: Binding(
            get: { session.viewModel.hdrEnabled },
            set: { value in Task { await session.viewModel.setHDR(value) } }
        ))
        .editorToolSelected(session.viewModel.hdrEnabled)
        .editorHoverHelp("HDR Editing")
        .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore || interactionLocked)
        Toggle(
            "Show Original",
            lightCraftIcon : "LightCraft-BeforeAfter",
            isOn        : Binding(
                get : { session.viewModel.isShowingBefore },
                set : setShowingBefore
            )
        )
        .editorToolSelected(session.viewModel.isShowingBefore)
        .editorHoverHelp("Show Original")
        .disabled(!session.canZoom || interactionLocked || usesPhotoTools)

        Button("Reset All", lightCraftIcon: "LightCraft-Rotate") {
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

/// EditorModeLabel draws one editing mode: its icon, its name when there is room, and an accent
/// capsule behind the selected mode. It dims itself when disabled, since explicit colors opt out of
/// the button's own dimming.
private struct EditorModeLabel: View {

    let title     : String
    let icon      : String
    let isSelected: Bool
    let showsTitle: Bool

    @Environment(\.isEnabled)
    private var isEnabled

    var body: some View {
        VStack(spacing: 2) {
            Image(lightCraftIcon: icon)
                .resizable().scaledToFit()
                .frame(width: 20, height: 20)
            if showsTitle {
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .opacity(isEnabled ? 1 : 0.35)
        .frame(width: showsTitle ? 64 : 44, height: showsTitle ? 46 : 38)
        .background {
            if isSelected { Capsule().fill(Color.accentColor.opacity(0.22)) }
        }
        .contentShape(Capsule())
    }
}
