//
//  FakeEngine.swift
//  UnveilTests
//

import CoreGraphics
import Foundation
import Metal
import Synchronization
@testable import Unveil

/// FakeEngine stands in for the engine in tests: it records what it is told and renders nothing.
///
/// All recorded state lives in one `Mutex<State>`; the test-facing properties are computed over
/// it, because a settable stored property is illegal in a Sendable class.
final class FakeEngine: EngineDriving, EngineDiagnosing {

    private struct State {
        var budgets            : [UInt64]  = []
        var lifecycle          : [String]  = []
        var previewCounter     : UInt64    = 0
        var calls              : [String]  = []
        var failNextOpen       : EngineError?
        var failNextValues     : EngineError?
        var failNextSet        : EngineError?
        var setsBeforeFailure  : Int       = 0
        var asShotQueries      : Int       = 0
        var isAsShot           : Bool      = true
        var asShotPair         : [DevelopAdjustmentKind: Double] = [:]
        var failNextPreview    : EngineError?
        var failNextMerge      : EngineError?
        var openedPhotos       : UInt64    = 0
        var storedValues       : [DevelopAdjustmentKind: Double] = [:]
        var edited             : Bool      = false
        var editedReads        : Int       = 0
        var photoInfo          : PhotoInfo = .image
    }

    private let state = Mutex(State())

    let frames = FrameSink(device: MTLCreateSystemDefaultDevice()!, maxPixels: 64)

    var budgets  : [UInt64] { state.withLock { $0.budgets } }
    var lifecycle: [String] { state.withLock { $0.lifecycle } }

    /// Every openPhoto, select, set, reset and requestPreview in order, as "open <path>",
    /// "select <id>", "set <id> <value>", "reset <photo>", "merge <json>", "wb asShot" and
    /// "preview <pixels> draft|full" (and requestWindow's "window ..." lines, releaseWindows'
    /// "release windows").
    var calls: [String] { state.withLock { $0.calls } }

    /// The error the next openPhoto throws, once. It clears itself when thrown.
    var failNextOpen: EngineError? {
        get { state.withLock { $0.failNextOpen } }
        set { state.withLock { $0.failNextOpen = newValue } }
    }

    /// The error the next currentValues throws, once, like a read that times out after a good open.
    var failNextValues: EngineError? {
        get { state.withLock { $0.failNextValues } }
        set { state.withLock { $0.failNextValues = newValue } }
    }

    /// failNextSet makes one slider operation fail so presentation tests can exercise its alert.
    var failNextSet: EngineError? {
        get { state.withLock { $0.failNextSet } }
        set { state.withLock { $0.failNextSet = newValue } }
    }

    /// How many sets succeed before `failNextSet` fires, to fail an operation halfway.
    var setsBeforeFailure: Int {
        get { state.withLock { $0.setsBeforeFailure } }
        set { state.withLock { $0.setsBeforeFailure = newValue } }
    }

    /// How many times isWhiteBalanceAsShot() was called. It is not in `calls`, a query changes nothing.
    var asShotQueries: Int { state.withLock { $0.asShotQueries } }

    /// The white balance mode isWhiteBalanceAsShot() reports. A set of temperature or tint makes it
    /// Custom, like the engine; a white balance reset or a develop reset makes it As Shot again.
    var isAsShot: Bool {
        get { state.withLock { $0.isAsShot } }
        set { state.withLock { $0.isAsShot = newValue } }
    }

    /// The error the next requestPreview throws, once, like a render refused while the app is away.
    var failNextPreview: EngineError? {
        get { state.withLock { $0.failNextPreview } }
        set { state.withLock { $0.failNextPreview = newValue } }
    }

    /// The error resetDevelop's merge throws, once, after the reset has landed.
    var failNextMerge: EngineError? {
        get { state.withLock { $0.failNextMerge } }
        set { state.withLock { $0.failNextMerge = newValue } }
    }

    /// The values currentValues reports on top of the kind defaults, like a photo reopened with saved settings.
    var storedValues: [DevelopAdjustmentKind: Double] {
        get { state.withLock { $0.storedValues } }
        set { state.withLock { $0.storedValues = newValue } }
    }

    /// The engine's edited flag that isEdited(_:) reports. The fake never changes it by itself:
    /// a test sets it, so the status can only have come from the engine.
    var edited: Bool {
        get { state.withLock { $0.edited } }
        set { state.withLock { $0.edited = newValue } }
    }

    /// How many times isEdited(_:) was called.
    var editedReads: Int { state.withLock { $0.editedReads } }

    /// What photoInfo(of:) reports for every photo: a plain image unless a test makes it a raw.
    var photoInfo: PhotoInfo {
        get { state.withLock { $0.photoInfo } }
        set { state.withLock { $0.photoInfo = newValue } }
    }

    func isWhiteBalanceAsShot() async throws(EngineError) -> Bool {
        state.withLock {
            $0.asShotQueries += 1
            return $0.isAsShot
        }
    }

    func isEdited(_ photo: PhotoID) async throws(EngineError) -> Bool {
        state.withLock {
            $0.editedReads += 1
            return $0.edited
        }
    }

    func photoInfo(of photo: PhotoID) async throws(EngineError) -> PhotoInfo {
        photoInfo
    }

    /// resetDevelop clears the stored values, then a non-empty merge (recorded as its sorted JSON)
    /// stores its detail values, or throws `failNextMerge` with the reset already applied.
    func resetDevelop(
        _ photo            : PhotoID,
        restoring settings : DevelopMergeSettings
    ) async throws(EngineError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(settings)).map { String(decoding: $0, as: UTF8.self) } ?? "?"

        let failure = state.withLock {
            $0.calls.append("reset \(photo.rawValue)")
            $0.storedValues = [:]
            $0.isAsShot     = true

            guard !settings.isEmpty else { return EngineError?.none }

            $0.calls.append("merge \(json)")

            let failure = $0.failNextMerge
            $0.failNextMerge = nil

            if failure == nil, let detail = settings.detail {
                $0.storedValues = [.sharpening: detail.sharpenAmount, .colorNoise: detail.nrColor]
            }
            return failure
        }

        if let failure {
            throw failure
        }
    }

    /// resetWhiteBalance puts back the temperature and tint a set replaced (the As Shot pair) and
    /// the As Shot mode.
    func resetWhiteBalance() async throws(EngineError) {
        state.withLock {
            $0.calls.append("wb asShot")
            $0.isAsShot = true

            for (kind, value) in $0.asShotPair {
                $0.storedValues[kind] = value
            }
        }
    }

    func currentValues() async throws(EngineError) -> [DevelopAdjustmentKind: Double] {
        let (stored, failure) = state.withLock {
            let failure = $0.failNextValues
            $0.failNextValues = nil
            return ($0.storedValues, failure)
        }

        if let failure {
            throw failure
        }

        return Dictionary(uniqueKeysWithValues: DevelopAdjustmentKind.allCases.map {
            ($0, stored[$0] ?? $0.defaultValue)
        })
    }

    /// openPhoto hands out ids 1, 2, 3... one per successful open, so a test can tell photos apart.
    func openPhoto(at fileURL: URL) async throws(EngineError) -> PhotoID {
        let (failure, id) = state.withLock {
            $0.calls.append("open \(fileURL.path)")

            let failure = $0.failNextOpen
            $0.failNextOpen = nil

            if failure == nil {
                $0.openedPhotos += 1
            }
            return (failure, $0.openedPhotos)
        }

        if let failure {
            throw failure
        }

        return PhotoID(rawValue: id)
    }

    func select(_ photo: PhotoID) async throws(EngineError) {
        state.withLock { $0.calls.append("select \(photo.rawValue)") }
    }

    /// Yields once after recording, like a real `set` that is still queued when the caller moves on:
    /// a view model that does not chain its calls shows up as a reordered `calls`. A set that lands
    /// is stored for currentValues, and one of temperature or tint makes the mode Custom.
    func set(_ adjustment: DevelopAdjustmentKind, to value: Double) async throws(EngineError) {
        let failure = state.withLock { locked -> EngineError? in
            locked.calls.append("set \(adjustment.rawValue) \(value)")

            if locked.setsBeforeFailure > 0 {
                locked.setsBeforeFailure -= 1
            } else if let failure = locked.failNextSet {
                locked.failNextSet = nil
                return failure
            }

            if adjustment.isWhiteBalance {
                if locked.isAsShot {
                    for kind in [DevelopAdjustmentKind.temperature, .tint] where locked.asShotPair[kind] == nil {
                        locked.asShotPair[kind] = locked.storedValues[kind] ?? kind.defaultValue
                    }
                }
                locked.isAsShot = false
            }

            locked.storedValues[adjustment] = value
            return nil
        }

        if let failure {
            throw failure
        }

        await Task.yield()
    }

    func requestPreview(maxPixels: Int, draft: Bool, before: Bool) throws(EngineError) -> UInt64 {
        let (failure, generation) = state.withLock {
            $0.calls.append("preview \(maxPixels) \(draft ? "draft" : "full")\(before ? " before" : "")")

            let failure = $0.failNextPreview
            $0.failNextPreview = nil

            if failure == nil {
                $0.previewCounter += 1
            }
            return (failure, $0.previewCounter)
        }

        if let failure {
            throw failure
        }

        return generation
    }

    /// requestWindow logs "window <x>,<y> <width>x<height> of <frameWidth>x<frameHeight> draft|full"
    /// and shares the preview's generations and `failNextPreview`.
    func requestWindow(_ window: FrameWindow, draft: Bool, before: Bool) throws(EngineError) -> UInt64 {
        let (failure, generation) = state.withLock {
            let place = "\(window.x),\(window.y) \(window.width)x\(window.height)"
            let frame = "\(window.frameWidth)x\(window.frameHeight)"
            $0.calls.append("window \(place) of \(frame) \(draft ? "draft" : "full")\(before ? " before" : "")")

            let failure = $0.failNextPreview
            $0.failNextPreview = nil

            if failure == nil {
                $0.previewCounter += 1
            }
            return (failure, $0.previewCounter)
        }

        if let failure {
            throw failure
        }

        return generation
    }

    func releaseWindows() {
        state.withLock { $0.calls.append("release windows") }
    }

    func suspend() throws(EngineError) {
        state.withLock { $0.lifecycle.append("suspend") }
    }

    func resume() throws(EngineError) {
        state.withLock { $0.lifecycle.append("resume") }
    }

    func setMemoryBudget(bytes: UInt64) {
        state.withLock { $0.budgets.append(bytes) }
    }

    func diagnostic(
        _ command: String,
        params   : some Encodable & Sendable
    ) async throws(EngineError) -> String {
        throw .unknownCommand(command)
    }
}
