//
//  EngineDriving.swift
//  Unveil
//

import CoreGraphics
import Foundation

/// EngineDriving is the whole surface the editor sees of the engine: open a photo, set a
/// develop control, ask for a preview, and hold the engine still while the app is in the background.
///
/// Callers never touch the FFI: the editor, the lifecycle observer and the memory monitor depend on this
/// protocol, so each can be tested against a fake. The pixels do not come back from these calls: a render
/// lands in `frames` on the engine thread, and `requestPreview` only returns the generation it will carry.
// Nonisolated: the engine thread and background tasks call it, and the app default is MainActor.
nonisolated protocol EngineDriving: AnyObject, Sendable {

    /// The shared buffers the engine fills. Fixed for the life of the engine.
    var frames: FrameSink { get }

    func openPhoto(at fileURL: URL) async throws(EngineError) -> PhotoID

    /// Makes a photo of the library the active one again, without importing anything.
    func select(_ photo: PhotoID) async throws(EngineError)

    func set(_ adjustment: DevelopAdjustmentKind, to value: Double) async throws(EngineError)

    /// The current value of each develop control of the active photo, as the engine holds it: the
    /// photo's saved settings, or the as-shot values for a first open.
    func currentValues() async throws(EngineError) -> [DevelopAdjustmentKind: Double]

    /// The engine's own "edited" flag for `photo`: its settings differ from what import gave it.
    func isEdited(_ photo: PhotoID) async throws(EngineError) -> Bool

    /// Whether the active photo's white balance mode is As Shot (`develop.get`'s `wb.mode`), as
    /// opposed to any other mode: Custom numbers can equal the as-shot pair, so values do not tell.
    func isWhiteBalanceAsShot() async throws(EngineError) -> Bool

    /// What the library records of the photo: its pixel size and what decides its develop defaults.
    func photoInfo(of photo: PhotoID) async throws(EngineError) -> PhotoInfo

    /// Puts every develop setting of `photo` back to the engine's reset look (As Shot white balance,
    /// the rest at control defaults), then applies `settings` in one `develop.merge` unless empty.
    /// A throw may come from the merge, after the reset already landed.
    func resetDevelop(
        _ photo            : PhotoID,
        restoring settings : DevelopMergeSettings
    ) async throws(EngineError)

    /// Puts the active photo's temperature and tint back to As Shot.
    func resetWhiteBalance() async throws(EngineError)

    /// Starts a render and returns its generation without waiting for it. That generation may never be
    /// delivered if a newer request overtakes it, so wait for a frame at or above it, not equal to it.
    ///
    /// With `before` the frame is the photo's unedited look (its crop kept) instead of the edited one.
    func requestPreview(maxPixels: Int, draft: Bool, before: Bool) throws(EngineError) -> UInt64

    /// Starts a render of one window of the zoomed frame (see FrameWindow), drawn over the preview,
    /// and returns its generation like `requestPreview`. A window never replaces a pending preview,
    /// while a newer preview replaces it. Its size must fit `frames`. `before` is as in `requestPreview`.
    func requestWindow(_ window: FrameWindow, draft: Bool, before: Bool) throws(EngineError) -> UInt64

    /// Frees what windows keep resident in the engine (their stages and the full-size source on the
    /// GPU) once the view no longer shows one. It never waits; the next window rebuilds them.
    func releaseWindows()

    func suspend() throws(EngineError)
    func resume() throws(EngineError)
    func setMemoryBudget(bytes: UInt64)
}
