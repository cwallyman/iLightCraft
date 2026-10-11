//
//  EditorViewModel.swift
//  Unveil
//

import CoreGraphics
import Foundation
import Observation
import os
import UniformTypeIdentifiers

/// EditorViewModel is the state of the editor: which photo is open, the slider values and the
/// last error to show. The view reads it, and it drives the engine through `EngineDriving`.
///
/// Every engine call goes through one chain, `pending`: each step awaits the one before it. That is
/// what makes a full preview on release safe. The engine's `set` is queued asynchronously while
/// `requestPreview` is immediate, so without the chain the release preview could overtake the last
/// drag's `set` and render a frame that lacks the final value. Values are clamped to the kind's
/// range here, so the slider and the engine never disagree. Errors never propagate: they land in
/// `errorMessage` for the view to show.
///
/// A slider at 120 Hz is faster than the engine's round trip, so drags are coalesced: each kind
/// keeps only its newest wanted value and at most one drag link waits in the chain. When the link
/// runs it sends the newest value (and its draft preview), or nothing if that value was already
/// sent, so the backlog never grows and the engine never sees an older value after a newer one.
@Observable
@MainActor
final class EditorViewModel<Engine: EngineDriving, Importer: PhotoImporting> {

    private(set) var values      : [DevelopAdjustmentKind: Double]
    private(set) var openPhoto   : PhotoID?
    private(set) var errorMessage: String?
    private(set) var photoTitle  : String = "Photo"
    private(set) var photoType   : String?

    /// isEdited is the editor's "Edited" status: the engine's own flag (`Photo::is_edited`, which
    /// compares with the photo's import look), read after open and after every committed change.
    /// A drag does not read it: the status catches up when the slider is released.
    private(set) var isEdited = false

    /// photoSize is the open photo's size in real pixels, `.zero` when unknown. The zoom pill
    /// measures against it, not against the preview.
    private(set) var photoSize: CGSize = .zero

    /// developDefaults is each control's value right after import for the open photo (see
    /// `PhotoInfo.developDefaults`): a raw starts with sharpening and color noise reduction.
    private(set) var developDefaults: [DevelopAdjustmentKind: Double]

    /// cameraDefaults is what Reset All merges back after `develop.reset` (see
    /// `PhotoInfo.cameraDefaultsMerge`).
    @ObservationIgnored
    private var cameraDefaults = DevelopMergeSettings.none

    private let engine          : Engine
    private let importer        : Importer
    private let previewPixels   : Int
    private let nudgeSettleDelay: Duration

    // Plain bookkeeping the view never reads, so it stays out of observation.
    @ObservationIgnored
    private var pending: Task<Bool, Never>?

    @ObservationIgnored
    private var wanted: [DevelopAdjustmentKind: Double] = [:]

    @ObservationIgnored
    private var sent: [DevelopAdjustmentKind: Double] = [:]

    @ObservationIgnored
    private var waitingDrags: Set<DevelopAdjustmentKind> = []

    /// nudgeSettle is the stepper burst waiting to be committed: its kind and the timer that
    /// commits it once the presses stop.
    @ObservationIgnored
    private var nudgeSettle: (kind: DevelopAdjustmentKind, timer: Task<Void, Never>)?

    /// isPhotoOpen is false until `open` succeeds: the view keeps the sliders disabled until then.
    var isPhotoOpen: Bool { openPhoto != nil }

    /// defaultValue(of:) is the open photo's own default for `kind`, what a single control's reset
    /// goes back to and what the slider styles as "at default".
    func defaultValue(of kind: DevelopAdjustmentKind) -> Double {
        developDefaults[kind] ?? kind.defaultValue
    }

    /// `nudgeSettleDelay` is how long after the last stepper press the burst is committed; tests
    /// shorten it.
    init(
        engine          : Engine,
        importer        : Importer,
        previewPixels   : Int,
        nudgeSettleDelay: Duration = .milliseconds(300)
    ) {
        self.engine           = engine
        self.importer         = importer
        self.previewPixels    = previewPixels
        self.nudgeSettleDelay = nudgeSettleDelay
        self.values           = Self.defaultValues
        self.developDefaults  = Self.defaultValues
    }

    /// open copies the picked file off the main actor, opens it in the engine, loads the controls'
    /// current values into the sliders and shows a full preview. A photo already in the library
    /// reopens with its saved settings, so the sliders show what the engine holds, not the defaults.
    ///
    /// An open that fails, even halfway (the import worked, the select or the values read did not),
    /// leaves both sides on the previous state: the model keeps its photo and values, and the engine
    /// is told to select that photo again, which also undoes a select that timed out but still runs,
    /// because the engine takes commands in order. A copy made for this open is deleted. With no
    /// previous photo the model stays closed, so nothing acts on whatever the engine has selected.
    ///
    /// A successful open also sets `photoTitle` (the picked file's name without its extension, or
    /// `title` when the caller knows a better one), `photoType` and `photoSize` for the Info sheet,
    /// the photo's develop defaults and the engine's edited flag.
    ///
    /// It is the `OpenToFirstFrame` signpost's start; the interval ends when the canvas presents the
    /// preview asked for here, or at once as `failed` when no preview was asked for.
    ///
    /// It returns true once the new photo is open in both the model and the engine. A first preview
    /// refused after that does not undo the open: the editor shows the photo's alert, or nothing
    /// for `.suspended`, since `refreshPreview` draws the photo when the engine resumes.
    ///
    /// A stepper burst still waiting for its timer is committed first, on the photo it edited.
    @discardableResult
    func open(pickedURL: URL, title: String? = nil) async -> Bool {
        commitPendingNudge()

        let signpost = Signposts.beginOpen()
        let copy: (url: URL, isNew: Bool)

        do {
            copy = try await Self.importCopy(of: pickedURL, using: importer)
        } catch {
            Signposts.openRequestedPreview(signpost, generation: nil)
            errorMessage = Self.message(for: error)
            return false
        }

        return await enqueue { [engine, previewPixels] in
            var previewGeneration: UInt64?
            defer { Signposts.openRequestedPreview(signpost, generation: previewGeneration) }

            let previous = self.openPhoto
            let photo    : PhotoID
            let current  : [DevelopAdjustmentKind: Double]
            let info     : PhotoInfo
            let edited   : Bool

            do {
                photo   = try await engine.openPhoto(at: copy.url)
                current = try await engine.currentValues()
                info    = try await engine.photoInfo(of: photo)
                edited  = try await engine.isEdited(photo)
            } catch {
                await Self.rollBack(engine: engine, to: previous, discarding: copy)
                throw error
            }

            self.openPhoto       = photo
            self.values          = Self.defaultValues.merging(current) { _, engineValue in engineValue }
            self.sent            = self.values
            self.wanted          = [:]
            self.isEdited        = edited
            self.photoSize       = info.size
            self.developDefaults = info.developDefaults
            self.cameraDefaults  = info.cameraDefaultsMerge

            self.photoTitle = title ?? pickedURL.deletingPathExtension().lastPathComponent
            self.photoType  = UTType(filenameExtension: pickedURL.pathExtension)?.localizedDescription

            do throws(EngineError) {
                previewGeneration = try engine.requestPreview(maxPixels: previewPixels, draft: false)
            } catch .suspended {
                // The app left mid-open: refreshPreview redraws on resume, so there is nothing to say.
            } catch {
                self.errorMessage = error.message
            }
        }
    }

    /// beginDrag marks the start of a slider gesture (or of a whole edit such as a value entry).
    /// `drag` does the work; the only thing to prepare is committing a stepper burst still waiting
    /// for its timer, so the burst and the new edit stay two separate edits.
    func beginDrag(_ kind: DevelopAdjustmentKind) {
        commitPendingNudge()
    }

    /// nudge moves `kind` by `delta` from a stepper press, snapped to the step and the range. Every
    /// press of a burst (a hold repeats it) sends a draft through `drag`; the burst is committed
    /// once, `nudgeSettleDelay` after the last press, by one `endDrag`: the burst's commit point.
    /// A press on another control first commits the burst in progress.
    func nudge(_ kind: DevelopAdjustmentKind, by delta: Double) async {
        if let pending = nudgeSettle, pending.kind != kind {
            commitPendingNudge()
        }

        nudgeSettle?.timer.cancel()

        let timer = Task { [weak self, nudgeSettleDelay] in
            do {
                try await Task.sleep(for: nudgeSettleDelay)
            } catch {
                return
            }

            // A press that lands after the sleep ended but before this resumes still cancels it.
            guard !Task.isCancelled, let self else { return }

            self.nudgeSettle = nil
            await self.endDrag(kind)
        }
        nudgeSettle = (kind, timer)

        await drag(kind, to: kind.snapped((values[kind] ?? kind.defaultValue) + delta))
    }

    /// drag clamps the value, shows it at once and records it as the newest wanted value for its
    /// kind. If a drag link for that kind is already waiting in the chain it will pick this value up
    /// and there is nothing more to queue; otherwise one link is queued behind whatever is in flight.
    func drag(_ kind: DevelopAdjustmentKind, to value: Double) async {
        let clamped = min(max(value, kind.range.lowerBound), kind.range.upperBound)
        values[kind] = clamped
        wanted[kind] = clamped

        guard waitingDrags.insert(kind).inserted else { return }

        await enqueue { [engine, previewPixels] in
            self.waitingDrags.remove(kind)

            guard let newest = self.wanted[kind], self.sent[kind] != newest else { return }

            try await engine.set(kind, to: newest)
            self.sent[kind] = newest

            _ = try engine.requestPreview(maxPixels: previewPixels, draft: true)
        }
    }

    /// endDrag queues the final `set` (only if the engine has not got that value yet) and then the
    /// full-quality preview, behind every earlier link, so the final frame carries the final value.
    /// The edited flag is read after the preview is asked for, so the render starts first.
    func endDrag(_ kind: DevelopAdjustmentKind) async {
        await enqueue { [engine, previewPixels] in
            if let newest = self.wanted[kind], self.sent[kind] != newest {
                try await engine.set(kind, to: newest)
                self.sent[kind] = newest
            }

            _ = try engine.requestPreview(maxPixels: previewPixels, draft: false)
            try await self.reloadEdited()
        }
    }

    /// resetAll puts the open photo back to its import look: `develop.reset` (white balance As Shot,
    /// every other control at its default), then one `develop.merge` of what `camera_defaults` adds
    /// (raw detail, embedded lens corrections). The reread runs even when the merge failed, since
    /// the reset has landed by then, and so does the one full preview; the merge's error follows.
    /// Wanted drag values are dropped, so a drag link still waiting in the chain sends nothing
    /// stale after the reset. A waiting stepper burst is committed first, as its own edit.
    func resetAll() async {
        commitPendingNudge()

        guard isEdited, let photo = openPhoto else { return }

        wanted = [:]

        await enqueue { [engine, previewPixels, cameraDefaults] in
            var resetError: EngineError?

            do throws(EngineError) {
                try await engine.resetDevelop(photo, restoring: cameraDefaults)
            } catch {
                resetError = error
            }

            try await self.reloadValues()
            _ = try engine.requestPreview(maxPixels: previewPixels, draft: false)

            if let resetError {
                throw resetError
            }
        }
    }

    /// reset(_:) puts one control back to its default as a whole edit. Temperature and tint go back
    /// to As Shot together (`develop.wb`), since their default is the photo's, not a constant.
    /// Either way a waiting stepper burst is committed first (`beginDrag` does it for the others).
    func reset(_ kind: DevelopAdjustmentKind) async {
        guard kind.isWhiteBalance else {
            beginDrag(kind)
            await drag(kind, to: defaultValue(of: kind))
            await endDrag(kind)
            return
        }

        commitPendingNudge()

        wanted[.temperature] = nil
        wanted[.tint]        = nil

        await enqueue { [engine, previewPixels] in
            try await engine.resetWhiteBalance()
            try await self.reloadValues()

            _ = try engine.requestPreview(maxPixels: previewPixels, draft: false)
        }
    }

    /// refreshPreview asks for one full preview of the open photo, behind any queued work. The app
    /// calls it when the engine resumes: a render refused while suspended would otherwise leave the
    /// canvas on a draft frame until the next slider move.
    func refreshPreview() async {
        guard isPhotoOpen else { return }

        await enqueue { [engine, previewPixels] in
            _ = try engine.requestPreview(maxPixels: previewPixels, draft: false)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Chain

    /// enqueue appends `step` to the chain and waits for it. The task is created before the first
    /// suspension, so steps run in the order the callers reached this point. It returns whether
    /// the step finished without throwing.
    @discardableResult
    private func enqueue(_ step: @escaping @MainActor () async throws -> Void) async -> Bool {
        let previous = pending

        let task = Task {
            _ = await previous?.value

            do {
                try await step()
                return true
            } catch EngineError.suspended {
                // Expected when the app resigns active mid-drag: refreshPreview redraws on resume.
            } catch let error as EngineError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }

            return false
        }

        pending = task
        return await task.value
    }

    // MARK: - Helpers

    /// commitPendingNudge commits a stepper burst now instead of when its timer fires. The
    /// `endDrag` link enters the chain before this returns, ahead of whatever the caller queues.
    /// Every action that reaches the engine (a new edit, open, Reset All, a white balance reset,
    /// and undo and redo when they come) calls it first, so the burst always ends as its own edit.
    private func commitPendingNudge() {
        guard let pending = nudgeSettle else { return }

        pending.timer.cancel()
        nudgeSettle = nil

        Task.immediate { await self.endDrag(pending.kind) }
    }

    /// reloadValues reads the engine's values and edited flag after a change the model did not
    /// make value by value. Called from inside a chain link only.
    private func reloadValues() async throws(EngineError) {
        let current = try await engine.currentValues()

        values = Self.defaultValues.merging(current) { _, engineValue in engineValue }
        sent   = values

        try await reloadEdited()
    }

    /// reloadEdited reads the engine's edited flag of the open photo. Called from inside a chain
    /// link only, after a committed change.
    private func reloadEdited() async throws(EngineError) {
        guard let openPhoto else { return }

        isEdited = try await engine.isEdited(openPhoto)
    }

    /// rollBack puts the engine back on `previous` and deletes `copy` if this open made it. Its own
    /// failures are only logged: the open's error is the one the user sees.
    private static func rollBack(
        engine          : Engine,
        to previous     : PhotoID?,
        discarding copy : (url: URL, isNew: Bool)
    ) async {
        let logger = Logger(subsystem: "com.eliorodr2104.unveil", category: "EditorViewModel")

        if let previous {
            do {
                try await engine.select(previous)
            } catch {
                logger.error("Re-selecting the previous photo failed: \(error.message, privacy: .public)")
            }
        }

        if copy.isNew {
            do {
                try FileManager.default.removeItem(at: copy.url)
            } catch {
                logger.error("Deleting a failed import failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static var defaultValues: [DevelopAdjustmentKind: Double] {
        Dictionary(uniqueKeysWithValues: DevelopAdjustmentKind.allCases.map { ($0, $0.defaultValue) })
    }

    /// importCopy runs the importer off the main actor: copying a 50 to 100 MB RAW would stall the UI.
    /// The copy is the `ImportCopy` signpost.
    @concurrent
    private static func importCopy(
        of pickedURL   : URL,
        using importer : Importer
    ) async throws(PhotoImportError) -> (url: URL, isNew: Bool) {
        let signpost = Signposts.signposter.beginInterval(
            "ImportCopy",
            id: Signposts.signposter.makeSignpostID()
        )
        defer { Signposts.signposter.endInterval("ImportCopy", signpost) }

        return try importer.importCopy(of: pickedURL)
    }

    private static func message(for error: PhotoImportError) -> String {
        switch error {
            case .accessDenied(let url):
                return "Cannot read \(url.lastPathComponent)."

            case .copyFailed(let text):
                return "Could not copy the file: \(text)"
        }
    }
}
