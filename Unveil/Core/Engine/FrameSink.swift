//
//  FrameSink.swift
//  Unveil
//

import Metal
import os
import Synchronization

/// FrameSink holds three shared MTLBuffers for two published frames: the newest whole-frame
/// preview and the newest zoom window, which the canvas draws over it. The engine thread copies a
/// finished frame into the one buffer that holds neither, then publishes it in its kind's slot,
/// and the buffer it replaces becomes the next one written (the same double buffering per kind as
/// two buffers gave a single frame, with one buffer shared between the kinds).
///
/// `receive(...)` runs on the engine thread, `latest()`, `published()` and `buffer(at:)` are read
/// by the canvas, and the only state they share (the two published frames, the wake-up callback)
/// sits behind one Mutex. The pixel copy runs outside it, so the canvas never waits on a memcpy,
/// and `onFrame` is called after the unlock for the same reason: it may re-enter `latest()`.
///
/// `maxPixels` is the long edge, as in the engine's preview request: a frame is accepted when both
/// its width and its height fit, and every buffer is sized once for the worst case, a square
/// `maxPixels` frame with aligned rows. A window is the visible part of the zoomed frame plus a
/// margin, which can exceed the drawable, so the canvas caps it at `maxPixels` on each side
/// (FrameWindow.visible) and it fits the same buffers. Nothing is allocated after init.
///
/// Rows are padded to `minimumLinearTextureAlignment(for: .rgba8Unorm)`, so the canvas can wrap a
/// buffer in a texture with no copy. The engine's own stride is `width * 4` and may not be aligned,
/// which is why the copy goes row by row.
///
/// Sendable is asserted, not inferred: MTLBuffer is not Sendable, but `buffers` are immutable
/// references and the only shared mutable state is inside the Mutex. The pixel bytes are not
/// guarded: one producer writes an unpublished buffer, and readers sample the published ones.
/// They can overlap once, when two publishes land inside one in-flight GPU pass that still
/// samples the buffer being rewritten. That stays in bounds, is visual only (a torn frame) and
/// corrects itself on the next frame.
// Nonisolated: the engine thread calls it, and the app default is MainActor.
nonisolated final class FrameSink: @unchecked Sendable {

    static let bufferCount = 3

    let buffers: (any MTLBuffer, any MTLBuffer, any MTLBuffer)

    /// maxPixels is the most a frame may measure on either side: the long edge the buffers fit.
    let maxPixels: Int

    private let rowAlignment: Int
    private let state       : Mutex<State>
    private let logger      = Logger(subsystem: "com.eliorodr2104.unveil", category: "FrameSink")

    private struct State {

        var latestFrame : ReadyFrame?             = nil
        var latestWindow: ReadyFrame?             = nil
        var onFrame     : (@Sendable () -> Void)? = nil

        /// freeBufferIndex is the buffer neither published frame is in, the next one to write.
        var freeBufferIndex: Int {
            (0 ..< FrameSink.bufferCount).first {
                $0 != latestFrame?.bufferIndex && $0 != latestWindow?.bufferIndex
            } ?? 0
        }

        var newestGeneration: UInt64 {
            max(latestFrame?.generation ?? 0, latestWindow?.generation ?? 0)
        }
    }

    /// onFrame wakes the canvas after each published frame. Set it once at startup.
    var onFrame: (@Sendable () -> Void)? {
        get { state.withLock { $0.onFrame } }
        set { state.withLock { $0.onFrame = newValue } }
    }

    /// init(device:maxPixels:) allocates the three buffers for the largest frame, a square of
    /// `maxPixels` (the long edge). A failed allocation here is out of memory at launch: there is
    /// nothing to degrade to.
    init(device: some MTLDevice, maxPixels: Int) {
        precondition(maxPixels > 0, "FrameSink: maxPixels must be positive")

        let alignment = device.minimumLinearTextureAlignment(for: .rgba8Unorm)
        let length    = Self.alignUp(maxPixels * 4, to: alignment) * maxPixels

        guard let first  = device.makeBuffer(length: length, options: .storageModeShared),
              let second = device.makeBuffer(length: length, options: .storageModeShared),
              let third  = device.makeBuffer(length: length, options: .storageModeShared)
        else {
            fatalError("FrameSink: cannot allocate three shared buffers of \(length) bytes")
        }

        self.buffers      = (first, second, third)
        self.maxPixels    = maxPixels
        self.rowAlignment = alignment
        self.state        = Mutex(State())
    }

    /// latest returns the newest published whole-frame preview, or nil before the first one.
    func latest() -> ReadyFrame? {
        state.withLock { $0.latestFrame }
    }

    /// published returns the newest preview and the newest zoom window from one lock, so a pass
    /// never mixes two snapshots. The window may be older than the preview; the canvas decides
    /// whether it still belongs on screen.
    func published() -> (frame: ReadyFrame?, window: ReadyFrame?) {
        state.withLock { ($0.latestFrame, $0.latestWindow) }
    }

    /// buffer(at:) is the shared buffer a ReadyFrame's `bufferIndex` names.
    func buffer(at index: Int) -> any MTLBuffer {
        switch index {
            case 0 : buffers.0
            case 1 : buffers.1
            default: buffers.2
        }
    }

    /// receive copies one engine frame into the buffer no published frame is in, then publishes it
    /// as the newest preview, or as the newest window when `window` is set. Called on the engine
    /// thread. A frame at or below the last published generation of either kind, or larger than
    /// `maxPixels` on either edge, is dropped: the first because a newer one already won, the second
    /// because it would overrun the buffer (it is logged, since it means a request outgrew the sink).
    /// A preview that `replacesWindow` (the engine's whole-frame answer to a window it could not
    /// render alone) also unpublishes the window, which is older and may hold older settings.
    ///
    /// `rgba` must point to `height` rows of `stride` bytes, each holding at least `width * 4`.
    /// The pointer is only read during the call. The native size is passed through to the frame.
    func receive(
        rgba          : UnsafeRawPointer,
        width         : Int,
        height        : Int,
        stride        : Int,
        generation    : UInt64,
        isDraft       : Bool,
        window        : FrameWindow? = nil,
        replacesWindow: Bool = false,
        nativeWidth   : Int = 0,
        nativeHeight  : Int = 0
    ) {
        guard width > 0, height > 0, stride >= width * 4 else {
            logger.error("Dropped a malformed frame: \(width)x\(height), stride \(stride)")
            return
        }

        guard width <= maxPixels, height <= maxPixels else {
            logger.error("Dropped an oversized frame: \(width)x\(height), long edge limit \(self.maxPixels)")
            return
        }

        // ponytail: two publishes inside one in-flight GPU pass can tear the buffer it samples;
        // upgrade is a fourth buffer plus an in-use pin, if T13 measures it.
        let target = state.withLock { current -> Int? in
            guard generation > current.newestGeneration else { return nil }
            return current.freeBufferIndex
        }

        guard let target else { return }

        let bytesPerRow = Self.alignUp(width * 4, to: rowAlignment)

        copyRows(
            from        : rgba,
            to          : target,
            width       : width,
            height      : height,
            stride      : stride,
            bytesPerRow : bytesPerRow
        )

        let frame = ReadyFrame(
            bufferIndex : target,
            width       : width,
            height      : height,
            bytesPerRow : bytesPerRow,
            generation  : generation,
            isDraft     : isDraft,
            window      : window,
            nativeWidth : nativeWidth,
            nativeHeight: nativeHeight
        )

        let wake = state.withLock { current -> (@Sendable () -> Void)? in
            guard generation > current.newestGeneration else { return nil }

            if window == nil {
                current.latestFrame = frame

                if replacesWindow {
                    current.latestWindow = nil
                }
            } else {
                current.latestWindow = frame
            }

            return current.onFrame
        }

        wake?()
    }

    /// copyRows copies `height` rows of `width * 4` bytes, one memcpy each, into the buffer at `index`.
    ///
    /// The destination is the buffer's CPU mapping, owned by the buffer and alive as long as `self`.
    /// Row `r` ends at `r * bytesPerRow + width * 4`, which never exceeds the length set in `init`,
    /// because the caller checked `width` and `height` against `maxPixels` and `bytesPerRow` grows
    /// monotonically with `width`. The padding at the end of each row is left untouched.
    private func copyRows(
        from source : UnsafeRawPointer,
        to index    : Int,
        width       : Int,
        height      : Int,
        stride      : Int,
        bytesPerRow : Int
    ) {
        let destination = buffer(at: index).contents()
        let rowBytes    = width * 4

        for row in 0 ..< height {
            (destination + row * bytesPerRow).copyMemory(from: source + row * stride, byteCount: rowBytes)
        }
    }

    private static func alignUp(_ value: Int, to alignment: Int) -> Int {
        (value + alignment - 1) / alignment * alignment
    }
}
