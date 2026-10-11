//
//  CanvasView.swift
//  Unveil
//

import Metal
import os
import QuartzCore
import Synchronization
import UIKit

/// CanvasView draws the newest ready frame of a FrameSink through its CAMetalLayer, with pinch to
/// zoom (from 5 % to 3200 % of the photo's real pixels, below fit included, rubber-banded past
/// both ends), pan with momentum and rubber-banded edges, and a double tap that toggles between
/// fit and 100 % at the tap point. A single tap is handed to `onSingleTap`.
///
/// The gestures write the transform directly while the fingers are down; when they lift, a
/// CanvasSpring carries it to where it should rest (see CanvasTransform.settled), with the flick's
/// velocity as momentum. The spring runs on the same display link as the redraw, so the link stays
/// awake only while something moves. `onZoomChange` reports the zoom percentage for the editor's pill.
///
/// There is no polling. A CADisplayLink runs only while something is dirty: a new frame, a
/// transform change or a new drawable size marks the view, the next tick draws once, and the link
/// pauses again. A view with nothing to draw costs no CPU and no GPU.
///
/// Above the preview's own resolution (more than one screen pixel per preview pixel) the canvas
/// asks, through `onVisibleWindowChange`, for the visible window of the photo rendered at the zoom
/// on screen, capped at the photo's real pixels (FrameWindow.visible): at most every 100 ms while
/// a gesture or a spring moves the view (a draft), and once at full quality when it rests. It
/// keeps drawing the preview and draws the window on top at its place, so a pan never shows a
/// hole. A window is drawn only while it belongs to the frame the canvas would ask for now (a
/// pinch to another zoom below 100 % hides it until the new one arrives) and only if it is newer
/// than `windowFloor`, which rises on every tick that wants no window and when the photo changes,
/// so a window of an earlier photo or of earlier settings never comes back, even one that lands
/// late. From 100 % the window holds the photo's real pixels and is sampled nearest-neighbour
/// (pixels as squares; at 100 % itself moved onto the screen's pixel grid, so 1:1 is exact), from
/// 800 % with a grid on the pixel edges. The real pixels are measured against the engine's
/// native size of the frame (cropped and straightened), which every frame carries.
///
/// New frames arrive on the engine thread through `frames.onFrame`. That callback never waits on
/// the main thread (a suspend in progress can hold main for up to 2 s, and the engine thread must
/// not stall behind it): it schedules at most one asynchronous hop, coalesced by an atomic flag,
/// and the hop only marks the view dirty. The pixels never cross threads: the tick reads
/// `frames.latest()` once, at encode time, and samples the buffer that snapshot names.
///
/// The textures are zero-copy views of the sink's shared buffers (`makeTexture(descriptor:offset:
/// bytesPerRow:)`), one cached per buffer and rebuilt only when the frame's geometry changes, so
/// steady drawing allocates no pixel memory. They are `rgba8Unorm`, the drawable is `bgra8Unorm`
/// and the layer's colorspace is sRGB: the engine's bytes are already display-encoded and travel
/// to the screen untouched (see Canvas.metal for the shader side).
///
/// The sink double-buffers each kind of frame, so a GPU pass that samples buffer A while the
/// engine publishes twice would read A as it is rewritten (a torn frame, visual only, gone on the
/// next frame). Two rules keep that rare and visible: at most one command buffer samples the sink
/// at a time (a tick that finds one in flight retries on the next tick), and the completed handler
/// counts the passes that may have torn, in `possibleTearCount`, so T13 can decide whether a
/// fourth buffer is needed.
final class CanvasView: UIView {

    nonisolated static let vertexFunctionName   = "canvasVertex"
    nonisolated static let fragmentFunctionName = "canvasFragment"

    private static let drawablePixelFormat = MTLPixelFormat.bgra8Unorm
    private static let logger              = Logger(subsystem: "com.eliorodr2104.unveil", category: "CanvasView")

    // any: Metal vends its objects only as protocol existentials, there is no concrete type to name.
    private let frames      : FrameSink
    private let commandQueue: any MTLCommandQueue
    private let pipeline    : (any MTLRenderPipelineState)?
    private let renderPass  = MTLRenderPassDescriptor()
    private let crossThread = CrossThreadState()

    private var displayLink   : CADisplayLink?
    private var isDirty       : Bool = false
    private var laidOutSize   : CGSize = .zero
    private var cachedTextures: InlineArray<3, CachedTexture?> = [nil, nil, nil]

    private let pinchRecognizer = UIPinchGestureRecognizer()
    private let panRecognizer   = UIPanGestureRecognizer()

    private var spring           : CanvasSpring?
    private var springStartTime  : CFTimeInterval = 0
    private var lastFullFrameSize: CGSize = .zero

    /// onSingleTap runs when the canvas is tapped once (the editor closes its panel with it).
    var onSingleTap: (() -> Void)?

    /// onTouchDown runs the moment a finger lands on the canvas, before any gesture is decided. The editor
    /// sets it only while its card is open, so the card closes without waiting for the double-tap window.
    var onTouchDown: (() -> Void)?

    /// onZoomChange gets the zoom as a percentage of the photo's real pixels on screen pixels, at
    /// most once per display frame and only when the pill's text (ZoomScale.label) changes.
    var onZoomChange: ((Double) -> Void)?

    /// onVisibleWindowChange gets the window of the zoomed frame to render over the preview (nil
    /// when the preview is enough) and whether a draft will do because the view is moving.
    var onVisibleWindowChange: ((FrameWindow?, _ isDraft: Bool) -> Void)?

    /// isMeasurementPanning makes `measurementPan(at:)` count as a gesture, so its windows are
    /// throttled drafts as under a finger. The launch runner sets it for the pan sweep only.
    var isMeasurementPanning = false {
        didSet {
            if !isMeasurementPanning {
                wakeForWindowUpdate()
            }
        }
    }

    /// photoSize is the open photo's size in real pixels (`.zero` when unknown), as the editor reads
    /// it. The zoom percentage is measured against it until a frame carries the engine's native
    /// size of the frame (see `nativeSize`), not against the smaller preview.
    var photoSize: CGSize = .zero {
        didSet {
            if photoSize != oldValue {
                reportedPercent = nil
                setNeedsRedraw()
            }
        }
    }

    /// clippingOverlay marks the clipped pixels of the preview and the window (Canvas.metal).
    var clippingOverlay: ClippingOverlay = [] {
        didSet {
            if clippingOverlay != oldValue {
                setNeedsRedraw()
            }
        }
    }

    private var reportedPercent: String?

    private lazy var haptics = TickHaptics(view: self)

    /// disarmedLandmark is the landmark zoom that ticked last and may not tick again until the
    /// pinch leaves the band around it (ZoomScale.landmarkTick).
    private var disarmedLandmark: Double?

    /// pinchCenter is the fingers' last centroid, where a zoom stretched past the range springs back.
    private var pinchCenter: CGPoint?

    /// windowRequestInterval is the least time between two window requests while the view moves.
    private static let windowRequestInterval: CFTimeInterval = 0.1

    /// gridPercent is the zoom from which a grid is drawn on the image pixels' edges, and
    /// gridOpacity how far its lines step toward mid grey.
    private static let gridPercent = 800.0
    private static let gridOpacity: Float = 0.3

    /// wantedWindow is the window the canvas needs for the current view (FrameWindow.visible),
    /// recomputed on each tick; sentWindow is the last one handed to `onVisibleWindowChange`.
    private var wantedWindow        : FrameWindow?
    private var sentWindow          : FrameWindow?
    private var isSentWindowDraft   : Bool = false
    private var lastWindowSendTime  : CFTimeInterval = 0
    private var isWindowUpdatePending = false

    /// windowFloor is the newest generation published on the last tick that wanted no window (or
    /// at the last photo change): a window at or below it is never drawn again.
    private var windowFloor: UInt64 = 0

    /// previewFloor is the newest generation already published when this canvas was made: a scene
    /// that connects later must not show a frame from before it (another scene's, or the one left
    /// by a photo it never opened), so the first frame drawn is one asked for after.
    private let previewFloor: UInt64

    /// canvasTransform is the gesture state (UIView already owns `transform`). Any real change to
    /// it asks for one redraw.
    private var canvasTransform = CanvasTransform() {
        didSet {
            if canvasTransform != oldValue {
                setNeedsRedraw()
            }
        }
    }

    /// CachedTexture is the zero-copy texture over one sink buffer, valid while the frame in that
    /// buffer keeps the geometry it was made for. The buffer index is the slot it is stored in.
    private struct CachedTexture {

        let width      : Int
        let height     : Int
        let bytesPerRow: Int
        let texture    : any MTLTexture

        func fits(_ frame: ReadyFrame) -> Bool {
            width == frame.width && height == frame.height && bytesPerRow == frame.bytesPerRow
        }
    }

    /// CanvasStyle mirrors Canvas.metal's struct of the same name: how one quad is sampled. Its
    /// layout (8 + 4 + 4 + 4 bytes, padded to 24 for the float2's alignment) matches the shader's.
    private struct CanvasStyle {

        var gridSize   : SIMD2<Float>
        var gridOpacity: Float
        var nearest    : UInt32
        var clipping   : UInt32
    }

    /// CrossThreadState is what the engine thread and Metal's completion thread touch: only atomics,
    /// so it is Sendable without a lock. It is a separate object so those closures hold it, never the
    /// view: a UIView must not be retained, and possibly freed, off the main thread.
    // Nonisolated: the engine thread and Metal's completion thread use it, the app default is MainActor.
    private nonisolated final class CrossThreadState: Sendable {

        let isHopPending            = Atomic<Bool>(false)
        let isCommandBufferInFlight = Atomic<Bool>(false)
        let possibleTears           = Atomic<Int>(0)
        let droppedFrames           = Mutex(DroppedFrameRetries())

        /// commandBufferCompleted(sampled:newest:) runs on Metal's completion thread when a pass ends,
        /// with the newest generation the pass sampled and the newest one published by then.
        ///
        /// Any newer generation published while the pass ran is a possible tear. One publish lands
        /// in the free buffer and frees a sampled one as the engine's next write target, so the
        /// engine may already be copying into it while the GPU still reads it; two or more publishes
        /// certainly rewrote it. The count is an upper bound: an exposed pass may still read clean.
        func commandBufferCompleted(sampled: UInt64?, newest: UInt64?) {
            if let sampled,
               let newest,
               newest > sampled {
                possibleTears.add(1, ordering: .relaxed)
            }

            isCommandBufferInFlight.store(false, ordering: .releasing)
        }
    }

    override class var layerClass: AnyClass { CAMetalLayer.self }

    /// possibleTearCount is the number of passes that ended with a newer frame published, so the
    /// engine may have rewritten the buffer they sampled (see CrossThreadState). A diagnostic for
    /// T13, not a correctness signal.
    var possibleTearCount: Int {
        crossThread.possibleTears.load(ordering: .relaxed)
    }

    // layerClass makes the backing layer a CAMetalLayer, so the downcast cannot fail.
    private var metalLayer: CAMetalLayer {
        unsafeDowncast(layer, to: CAMetalLayer.self)
    }

    /// init(frames:device:) builds the pipeline and wires the sink's wake-up to this view.
    ///
    /// The pipeline is built here from the app's default library (Canvas.metal), once per view. If
    /// it does not build, the error is logged and the canvas only clears to the surround: the editor
    /// stays usable, and CanvasTextureTests fails on the same error. A device that cannot make a
    /// command queue is out of resources at launch, with nothing to degrade to.
    init(frames: FrameSink, device: some MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("CanvasView: the device cannot make a command queue")
        }

        do {
            pipeline = try Self.makePipelineState(
                device      : device,
                pixelFormat : Self.drawablePixelFormat
            )
        } catch {
            Self.logger.error("The canvas shaders did not build: \(String(describing: error), privacy: .public)")
            pipeline = nil
        }

        self.frames       = frames
        self.commandQueue = commandQueue
        self.previewFloor = Self.newestGeneration(frames.published())

        super.init(frame: .zero)

        windowFloor = previewFloor

        configureLayer(device: device)
        configureRenderPass()
        configureGestures()
        configureAccessibility()
        listenForFrames()
    }

    /// makePipelineState(device:pixelFormat:) looks the two canvas functions up in the
    /// default library and returns the render pipeline that draws into a drawable of `pixelFormat`.
    /// It throws CanvasShaderError when the library or a named function is missing.
    /// The whole build is the `ShaderCompile` signpost: it runs on main when the canvas is made.
    nonisolated static func makePipelineState(
        device     : some MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> any MTLRenderPipelineState {
        let signpost = Signposts.signposter.beginInterval(
            "ShaderCompile",
            id: Signposts.signposter.makeSignpostID()
        )
        defer { Signposts.signposter.endInterval("ShaderCompile", signpost) }

        guard let library = device.makeDefaultLibrary() else {
            throw CanvasShaderError.missingLibrary
        }

        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            throw CanvasShaderError.missingFunction(vertexFunctionName)
        }

        guard let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            throw CanvasShaderError.missingFunction(fragmentFunctionName)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction                  = vertexFunction
        descriptor.fragmentFunction                = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CanvasView is built in code, not from a storyboard")
    }

    /// resetZoom returns to fit at once, for a newly opened photo: the old zoom and pan belonged to
    /// the previous one, and so does any window published so far.
    func resetZoom() {
        spring = nil
        canvasTransform.reset()
        windowFloor = Self.newestGeneration(frames.published())
    }

    /// measurementPan(at:) moves the image along a circle through 90 % of its pan range, one turn
    /// every 4 s, `elapsed` seconds in: the pan sweep of the measurements, in place of a finger.
    func measurementPan(at elapsed: Double) {
        var edge = canvasTransform
        edge.offset = SIMD2(1e9, 1e9)

        let limits = edge.settled(viewSize: bounds.size, imageSize: imageSize).offset
        let angle  = 2 * Double.pi * elapsed / 4

        spring = nil
        canvasTransform.offset = limits * SIMD2(cos(angle), sin(angle)) * 0.9
    }

    /// zoomToFit animates back to aspect fit (a jump under Reduce Motion), like a double tap from zoomed in.
    func zoomToFit() {
        move(to: CanvasTransform())
    }

    /// zoomToFill animates to the zoom at which the photo covers the whole view, around the view center.
    func zoomToFill() {
        guard let scale = zoomScale else { return }

        zoomAroundCenter(to: scale.fillZoom(viewSize: bounds.size, imageSize: imageSize), scale: scale)
    }

    /// zoomIn animates to the next preset above the current zoom, around the view center.
    func zoomIn() {
        guard let scale = zoomScale else { return }

        zoomAroundCenter(to: scale.zoomIn(from: restingTransform.zoom), scale: scale)
    }

    /// zoomOut animates to the next preset below the current zoom, around the view center.
    func zoomOut() {
        guard let scale = zoomScale else { return }

        zoomAroundCenter(to: scale.zoomOut(from: restingTransform.zoom), scale: scale)
    }

    /// zoom(toPercent:) animates to that percentage of the photo's real pixels on screen pixels
    /// around the view center, clamped to the zoom range and settled inside the edges. Above the
    /// preview's own resolution the canvas asks for a window of the photo at that zoom.
    func zoom(toPercent percent: Double) {
        guard let scale = zoomScale else { return }

        zoomAroundCenter(to: scale.zoom(forPercent: percent), scale: scale)
    }

    /// setNeedsRedraw marks the canvas dirty: the next display link tick draws once, then the link
    /// pauses. Marks made before the next tick coalesce into that one draw.
    func setNeedsRedraw() {
        isDirty = true
        displayLink?.isPaused = false
    }

    // MARK: - View lifecycle

    /// didMoveToWindow owns the display link. CADisplayLink retains its target, so a link left
    /// alive after the view leaves its window would keep the view alive forever: it is invalidated
    /// on every move and made again only when there is a window to draw into.
    override func didMoveToWindow() {
        super.didMoveToWindow()

        displayLink?.invalidate()
        displayLink = nil

        guard let window else { return }

        contentScaleFactor = window.traitCollection.displayScale
        setNeedsLayout()

        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.isPaused                = !isDirty
        link.add(to: .main, forMode: .common)

        displayLink = link
    }

    /// layoutSubviews sizes the drawable to the view in pixels; a new size needs one redraw.
    ///
    /// The comparison is against the last size laid out here, not `metalLayer.drawableSize`, so
    /// the redraw does not depend on whether CAMetalLayer ever resizes its drawable by itself.
    override func layoutSubviews() {
        super.layoutSubviews()

        let pixelSize = CGSize(
            width  : bounds.width  * contentScaleFactor,
            height : bounds.height * contentScaleFactor
        )

        guard pixelSize != laidOutSize else { return }

        laidOutSize             = pixelSize
        metalLayer.drawableSize = pixelSize
        setNeedsRedraw()
    }

    // MARK: - Drawing

    /// displayLinkDidFire draws once if the view is dirty, then pauses the link.
    ///
    /// If the last command buffer is still on the GPU the tick returns with the link running, so
    /// the draw is retried on the next tick: that is the one-pass-in-flight rule. `isDirty` is
    /// cleared before `encodeFrame` reads the sink, so a frame published after that read marks the
    /// view again and gets its own draw instead of being lost.
    @objc
    private func displayLinkDidFire(_ link: CADisplayLink) {
        advanceSpring(to: link.targetTimestamp)
        reportZoom()
        updateVisibleWindow(at: link.timestamp)

        guard isDirty else {
            link.isPaused = spring == nil && !isWindowUpdatePending
            return
        }

        let claimed = crossThread.isCommandBufferInFlight.compareExchange(
            expected : false,
            desired  : true,
            ordering : .acquiring
        )

        guard claimed.exchanged else { return }

        isDirty = false

        if !encodeFrame() {
            crossThread.isCommandBufferInFlight.store(false, ordering: .releasing)
        }

        link.isPaused = !isDirty && spring == nil && !isWindowUpdatePending
    }

    /// encodeFrame clears the drawable and draws the sink's newest preview into it, then the window
    /// over it when it may be shown (see the type doc), returning false when nothing was committed
    /// (no drawable yet, or no command buffer).
    ///
    /// `frames.published()` is read exactly once, here, and the textures and the tear check come
    /// from that one snapshot, so the pass never mixes the geometry of one frame with another.
    ///
    /// A nil drawable drops the draw instead of marking the view dirty again. Before the first
    /// layout the size is zero, and `layoutSubviews` marks the view once it has a size. Otherwise
    /// `nextDrawable` has already blocked main for its 1 s timeout, and retrying on every tick
    /// would chain more of those stalls: the next frame or gesture draws instead.
    private func encodeFrame() -> Bool {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable      = metalLayer.nextDrawable()
        else {
            return false
        }

        let published = frames.published()
        let frame     = published.frame.flatMap { isCurrent($0) ? $0 : nil }

        // The encoder copies the descriptor, so the drawable is not kept past this pass.
        renderPass.colorAttachments[0].texture = drawable.texture
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        renderPass.colorAttachments[0].texture = nil

        guard let encoder else { return false }

        var sampledFrame : ReadyFrame? = nil
        var sampledWindow: ReadyFrame? = nil

        if let frame, !frame.isDraft {
            lastFullFrameSize = CGSize(width: frame.width, height: frame.height)
        }

        if let frame, let pipeline, let texture = texture(for: frame) {
            let quad    = canvasTransform.quad(
                viewSize  : bounds.size,
                imageSize : CGSize(width: frame.width, height: frame.height)
            )
            let percent = zoomScale?.percent(forZoom: canvasTransform.zoom) ?? 0

            encoder.setRenderPipelineState(pipeline)
            draw(
                texture,
                in      : quad,
                style   : previewStyle(percent: percent),
                encoder : encoder
            )
            sampledFrame = frame

            if let window = published.window,
               let placement = window.window,
               isShowable(window),
               let windowTexture = self.texture(for: window) {
                let windowQuad   = placement.quad(in: quad)
                let isOneToOne   = abs(percent - 100) <= 100 * FrameWindow.realPixelsTolerance
                let drawableSize = SIMD2<Float>(Float(laidOutSize.width), Float(laidOutSize.height))

                draw(
                    windowTexture,
                    in      : isOneToOne ? Self.pixelAligned(windowQuad, drawableSize: drawableSize) : windowQuad,
                    style   : windowStyle(for: placement, percent: percent),
                    encoder : encoder
                )
                sampledWindow = window
            }
        }

        encoder.endEncoding()

        let sampledGeneration = sampledWindow?.generation ?? sampledFrame?.generation

        // Added before present, as Metal requires: the handler ends the frames' signposts.
        // The simulator's Metal has no presented handler, so its frame intervals never end.
        #if !targetEnvironment(simulator)
        if let sampledFrame {
            drawable.addPresentedHandler(Self.presentedHandler(
                generation       : sampledFrame.generation,
                windowGeneration : sampledWindow?.generation,
                crossThread      : crossThread,
                drawAgain        : { [weak self] in
                    DispatchQueue.main.async { self?.setNeedsRedraw() }
                }
            ))
        }
        #endif

        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [crossThread, frames] _ in
            crossThread.commandBufferCompleted(
                sampled : sampledGeneration,
                newest  : Self.newestGeneration(frames.published())
            )
        }
        commandBuffer.commit()

        return true
    }

    /// draw encodes one textured quad (NDC corners) sampled with `style`.
    // any: Metal vends textures and encoders only as protocol existentials.
    private func draw(
        _ texture: any MTLTexture,
        in quad  : (min: SIMD2<Float>, max: SIMD2<Float>),
        style    : CanvasStyle,
        encoder  : any MTLRenderCommandEncoder
    ) {
        var corners = SIMD4<Float>(lowHalf: quad.min, highHalf: quad.max)
        var style   = style

        encoder.setVertexBytes(&corners, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&style, length: MemoryLayout<CanvasStyle>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// previewStyle samples the preview bilinearly. From `gridPercent` its grid follows the photo's
    /// real pixels (the frame of the window the canvas wants), so it lines up with the window's.
    private func previewStyle(percent: Double) -> CanvasStyle {
        let frame = wantedWindow.map { SIMD2<Float>(Float($0.frameWidth), Float($0.frameHeight)) }

        return CanvasStyle(
            gridSize    : frame ?? .one,
            gridOpacity : percent >= Self.gridPercent && frame != nil ? Self.gridOpacity : 0,
            nearest     : 0,
            clipping    : clippingOverlay.rawValue
        )
    }

    /// windowStyle samples a window nearest-neighbour from 100 % (its pixels are the photo's then:
    /// one per screen pixel at 100 %, squares above) and bilinearly below, with the grid on its
    /// pixels from `gridPercent`. A zoom within FrameWindow.realPixelsTolerance of 100 % counts.
    private func windowStyle(for placement: FrameWindow, percent: Double) -> CanvasStyle {
        CanvasStyle(
            gridSize    : SIMD2<Float>(Float(placement.width), Float(placement.height)),
            gridOpacity : percent >= Self.gridPercent ? Self.gridOpacity : 0,
            nearest     : percent >= 100 * (1 - FrameWindow.realPixelsTolerance) ? 1 : 0,
            clipping    : clippingOverlay.rawValue
        )
    }

    /// pixelAligned(_:drawableSize:) moves `quad` (NDC corners) by less than half a pixel, keeping
    /// its size, so its corner lands on a pixel edge of a `drawableSize` drawable. At 100 % a window
    /// texel is one pixel wide, so each pixel then samples exactly one texel: nearest sampling with
    /// a sub-pixel pan offset would pick its texels unevenly, a column now and then twice.
    nonisolated static func pixelAligned(
        _ quad      : (min: SIMD2<Float>, max: SIMD2<Float>),
        drawableSize: SIMD2<Float>
    ) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        let half  = drawableSize / 2
        let pixel = (quad.min + 1) * half
        let shift = (pixel.rounded(.toNearestOrAwayFromZero) - pixel) / half

        return (min: quad.min + shift, max: quad.max + shift)
    }

    /// isCurrent tells whether a published preview is one this canvas may draw (see `previewFloor`).
    func isCurrent(_ preview: ReadyFrame) -> Bool {
        preview.generation > previewFloor
    }

    /// isShowable tells whether a published window still belongs on screen: newer than the floor
    /// and of the frame the canvas would ask for now (see the type doc). Internal for the tests.
    func isShowable(_ window: ReadyFrame) -> Bool {
        guard let placement = window.window, let wantedWindow else { return false }

        return window.generation > windowFloor && placement.hasSameFrame(as: wantedWindow)
    }

    /// newestGeneration is the newest generation among the published frames, 0 before any.
    private nonisolated static func newestGeneration(_ published: (frame: ReadyFrame?, window: ReadyFrame?)) -> UInt64 {
        max(published.frame?.generation ?? 0, published.window?.generation ?? 0)
    }

    #if !targetEnvironment(simulator)
    /// presentedHandler ends the signposts waiting for the drawn preview's `generation`, then for the
    /// window drawn over it, once the drawable has left the display pipeline. It is built here,
    /// nonisolated, because Metal calls it on its own thread.
    ///
    /// A presented time of 0 means the frame was not shown, not that the measurement is wrong: a
    /// probe on the iPad (C1) saw every drawable drawn while the editor was still fading in report 0,
    /// and the first frame after an open can land there. The signposts stay open and `drawAgain`
    /// asks for the same frame on the next tick, until a drawable is presented (`DroppedFrameRetries`
    /// bounds it for a canvas that stays hidden, then the interval ends as `dropped`).
    private nonisolated static func presentedHandler(
        generation      : UInt64,
        windowGeneration: UInt64?,
        crossThread     : CrossThreadState,
        drawAgain       : @escaping @Sendable () -> Void
    ) -> @Sendable (any MTLDrawable) -> Void {
        { drawable in
            let isDropped = drawable.presentedTime == 0

            let isDrawnAgain = crossThread.droppedFrames.withLock { retries in
                retries.shouldDrawAgain(isDropped: isDropped, at: .now)
            }

            if isDrawnAgain {
                drawAgain()
                return
            }

            Signposts.framePresented(generation: generation, isDropped: isDropped)

            if let windowGeneration {
                Signposts.framePresented(generation: windowGeneration, isDropped: isDropped)
            }
        }
    }
    #endif

    /// texture(for:) returns the cached texture over the buffer holding `frame`, making a new one
    /// only when that buffer's frame changed size or stride.
    private func texture(for frame: ReadyFrame) -> (any MTLTexture)? {
        if let cached = cachedTextures[frame.bufferIndex], cached.fits(frame) {
            return cached.texture
        }

        guard let texture = Self.makeTexture(for: frame, in: frames) else {
            Self.logger.error("Cannot wrap buffer \(frame.bufferIndex) as a \(frame.width)x\(frame.height) texture")
            return nil
        }

        cachedTextures[frame.bufferIndex] = CachedTexture(
            width       : frame.width,
            height      : frame.height,
            bytesPerRow : frame.bytesPerRow,
            texture     : texture
        )

        return texture
    }

    /// makeTexture(for:in:) wraps the sink buffer that holds `frame` in an `rgba8Unorm` texture that
    /// shares its memory: no copy, and the texture sees every later write to that buffer.
    ///
    /// The bounds are the sink's contract: `bytesPerRow` is aligned to the device's linear texture
    /// alignment and `height * bytesPerRow` fits the buffer, because FrameSink only publishes frames
    /// within its `maxPixels` and sized the buffers for that worst case.
    nonisolated static func makeTexture(for frame: ReadyFrame, in frames: FrameSink) -> (any MTLTexture)? {
        let buffer     = frames.buffer(at: frame.bufferIndex)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat : .rgba8Unorm,
            width       : frame.width,
            height      : frame.height,
            mipmapped   : false
        )
        descriptor.storageMode = .shared
        descriptor.usage       = .shaderRead

        return buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: frame.bytesPerRow)
    }

    // MARK: - Gestures

    /// handlePinch zooms around the fingers; resetting `scale` makes each call a relative step. A
    /// trackpad pinch is damped (ZoomScale.indirectPinchFactor); fit and 100 % tick (TickHaptics).
    @objc
    private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
            case .began, .changed:
                spring = nil

                guard let scale = zoomScale else { return }

                let zoomBefore = canvasTransform.zoom
                let center     = recognizer.location(in: self)

                // A trackpad pinch arrives as a transform event, with no touches.
                let isIndirect = recognizer.numberOfTouches == 0
                let factor     = Double(recognizer.scale)

                canvasTransform.pinch(
                    by       : isIndirect ? ZoomScale.indirectPinchFactor(for: factor) : factor,
                    around   : center,
                    range    : scale.range,
                    viewSize : bounds.size
                )
                recognizer.scale = 1
                pinchCenter      = center

                let tick = scale.landmarkTick(
                    from     : zoomBefore,
                    to       : canvasTransform.zoom,
                    disarmed : disarmedLandmark
                )
                disarmedLandmark = tick.disarmed

                if tick.ticks {
                    haptics.tick(at: center)
                }

                haptics.prepare()

            case .ended, .cancelled, .failed:
                settle(velocity: .zero)

            default:
                break
        }
    }

    /// handlePan moves the image, rubber-banded past the edges; resetting the translation makes
    /// each call a relative step. On release the flick's velocity becomes momentum.
    @objc
    private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
            case .began, .changed:
                spring = nil
                canvasTransform.pan(
                    by        : recognizer.translation(in: self),
                    viewSize  : bounds.size,
                    imageSize : imageSize
                )
                recognizer.setTranslation(.zero, in: self)

            case .ended:
                let velocity = recognizer.velocity(in: self)
                settle(velocity: SIMD2<Double>(Double(velocity.x), Double(velocity.y)))

            case .cancelled, .failed:
                settle(velocity: .zero)

            default:
                break
        }
    }

    /// handleDoubleTap toggles fit and the photo's real 100 % around the tap (see
    /// CanvasTransform.toggledZoom).
    /// With Reduce Motion the zoom jumps instead of animating.
    @objc
    private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let target = canvasTransform.toggledZoom(
            at          : recognizer.location(in: self),
            viewSize    : bounds.size,
            imageSize   : imageSize,
            screenScale : Double(contentScaleFactor),
            photoScale  : CanvasTransform.photoScale(previewSize: imageSize, photoSize: nativeSize)
        )

        move(to: target)
    }

    /// move goes to `target` with the snap spring, or at once under Reduce Motion.
    private func move(to target: CanvasTransform) {
        if UIAccessibility.isReduceMotionEnabled {
            spring          = nil
            canvasTransform = target
        } else {
            animate(to: target, velocity: .zero, frequency: CanvasSpring.snapFrequency)
        }
    }

    @objc
    private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        onSingleTap?()
    }

    /// A finger landing on the canvas catches a gliding image, as in a scroll view, and tells
    /// `onTouchDown` at once so the editor can close its card.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        spring = nil
        onTouchDown?()
    }

    /// A touch that ends without becoming a gesture still lets a caught image settle.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        if spring == nil {
            settle(velocity: .zero)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)

        if spring == nil {
            settle(velocity: .zero)
        }
    }

    // MARK: - Motion

    /// imageSize is the size of the photo on screen, in preview pixels: the last full frame's,
    /// because drafts may be smaller, or the newest frame's before any full frame arrived.
    private var imageSize: CGSize {
        if lastFullFrameSize != .zero {
            return lastFullFrameSize
        }

        guard let frame = frames.latest() else { return .zero }

        return CGSize(width: frame.width, height: frame.height)
    }

    /// restingTransform is where the canvas is going: the running spring's target, or the current one.
    private var restingTransform: CanvasTransform {
        spring?.target ?? canvasTransform
    }

    /// nativeSize is what 100 % measures against: the whole frame at the photo's own resolution,
    /// cropped and straightened, as the newest frame reports it (the same for drafts), else the
    /// editor's `photoSize` (a frame without it, or none yet).
    private var nativeSize: CGSize {
        guard let frame = frames.latest(), frame.nativeWidth > 0, frame.nativeHeight > 0 else { return photoSize }

        return CGSize(width: frame.nativeWidth, height: frame.nativeHeight)
    }

    /// zoomScale is the zoom-to-percent conversion for the current view, photo and screen, or nil
    /// while any of them is unknown.
    private var zoomScale: ZoomScale? {
        ZoomScale(
            viewSize    : bounds.size,
            imageSize   : imageSize,
            screenScale : Double(contentScaleFactor),
            photoScale  : CanvasTransform.photoScale(previewSize: imageSize, photoSize: nativeSize)
        )
    }

    /// zoomAroundCenter moves to `zoom` keeping the view center fixed, settled inside the edges.
    private func zoomAroundCenter(to zoom: Double, scale: ZoomScale) {
        var target = restingTransform

        target.pinch(
            by       : zoom / target.zoom,
            around   : CGPoint(x: bounds.midX, y: bounds.midY),
            range    : scale.range,
            viewSize : bounds.size
        )

        move(to: target.settled(viewSize: bounds.size, imageSize: imageSize))
    }

    private var isGestureActive: Bool {
        [pinchRecognizer.state, panRecognizer.state].contains { $0 == .began || $0 == .changed }
    }

    /// settle springs the transform to where it should rest once no finger moves it. A flick
    /// (above 60 pt/s) glides with momentum toward its projected point, clamped to the edges;
    /// anything else snaps back quickly. A zoom resting within ZoomScale.realPixelsSnap of the real
    /// 100 % lands on it exactly (at once under Reduce Motion), where the window shows the photo
    /// 1:1 with nearest sampling: a scale a hair off 1 would double or skip a column now and then.
    private func settle(velocity: SIMD2<Double>) {
        guard !isGestureActive else { return }

        // The view rests where it is or springs there: either way the window catches up at rest.
        wakeForWindowUpdate()

        let isFlick = (velocity * velocity).sum() > 60 * 60
        var target  = canvasTransform

        if isFlick {
            target.offset += velocity * CanvasSpring.momentumProjection
        }

        var isSnappedToRealPixels = false

        if let scale = zoomScale {
            let center = pinchCenter ?? CGPoint(x: bounds.midX, y: bounds.midY)

            target = target.settled(
                viewSize  : bounds.size,
                imageSize : imageSize,
                range     : scale.range,
                around    : center
            )

            let resting = scale.restingZoom(for: target.zoom)

            if resting != target.zoom {
                target.pinch(
                    by       : resting / target.zoom,
                    around   : center,
                    range    : scale.range,
                    viewSize : bounds.size
                )
                target                = target.settled(viewSize: bounds.size, imageSize: imageSize)
                isSnappedToRealPixels = true
            }
        } else {
            target = target.settled(viewSize: bounds.size, imageSize: imageSize)
        }

        guard target != canvasTransform else { return }

        if isSnappedToRealPixels, UIAccessibility.isReduceMotionEnabled {
            spring          = nil
            canvasTransform = target
            return
        }

        // A zoom springing back from past a limit snaps; momentum is for a pan alone.
        let isMomentum = isFlick && target.zoom == canvasTransform.zoom

        animate(
            to        : target,
            velocity  : isMomentum ? velocity : .zero,
            frequency : isMomentum ? CanvasSpring.momentumFrequency : CanvasSpring.snapFrequency
        )
    }

    private func animate(
        to target: CanvasTransform,
        velocity : SIMD2<Double>,
        frequency: Double
    ) {
        spring = CanvasSpring(
            from           : canvasTransform,
            to             : target,
            offsetVelocity : velocity,
            frequency      : frequency
        )
        springStartTime = CACurrentMediaTime()
        displayLink?.isPaused = false
    }

    /// advanceSpring moves the transform to where the running spring is at `time`, and ends the
    /// spring once it has settled.
    private func advanceSpring(to time: CFTimeInterval) {
        guard let spring else { return }

        let elapsed = time - springStartTime
        canvasTransform = spring.transform(at: elapsed)

        if spring.isSettled(at: elapsed) {
            self.spring = nil
        }
    }

    /// visibleWindow is the window the current view needs (FrameWindow.visible), nil while the
    /// preview is enough.
    private var visibleWindow: FrameWindow? {
        FrameWindow.visible(
            transform   : canvasTransform,
            viewSize    : bounds.size,
            imageSize   : imageSize,
            photoSize   : nativeSize,
            screenScale : Double(contentScaleFactor),
            maxPixels   : frames.maxPixels
        )
    }

    /// updateVisibleWindow runs on each display tick: it recomputes the wanted window and hands it to
    /// `onVisibleWindowChange` when it changed. While the view moves (a gesture, a spring or the pan
    /// sweep) a new window waits at least `windowRequestInterval` after the last one and goes as a
    /// draft; at rest the window goes at once, at full quality, even if its draft already went.
    /// Losing the window (nil) goes at once. Every tick that wants no window raises `windowFloor`:
    /// a window still rendering when the view left it lands later, and wakes a tick of its own.
    private func updateVisibleWindow(at time: CFTimeInterval) {
        let wanted   = visibleWindow
        let isMoving = isGestureActive || spring != nil || isMeasurementPanning

        if wanted == nil {
            windowFloor = Self.newestGeneration(frames.published())
        }

        wantedWindow = wanted

        let isCurrent = wanted == sentWindow && (isMoving || !isSentWindowDraft)

        guard !isCurrent else {
            isWindowUpdatePending = false
            return
        }

        if wanted != nil, isMoving, time - lastWindowSendTime < Self.windowRequestInterval {
            isWindowUpdatePending = true
            return
        }

        sentWindow            = wanted
        isSentWindowDraft     = isMoving && wanted != nil
        lastWindowSendTime    = time
        isWindowUpdatePending = false

        onVisibleWindowChange?(wanted, isSentWindowDraft)
    }

    /// wakeForWindowUpdate runs the display link for at least one tick, so `updateVisibleWindow`
    /// sees a view that stopped moving without a redraw (a gesture ending where it rests).
    private func wakeForWindowUpdate() {
        isWindowUpdatePending = true
        displayLink?.isPaused = false
    }

    /// reportZoom runs on each display tick: it hands `onZoomChange` the percentage when its pill
    /// text differs from the last one, and gives VoiceOver the same text as the canvas's value.
    private func reportZoom() {
        guard let scale = zoomScale else { return }

        let percent = scale.percent(forZoom: canvasTransform.zoom)
        let label   = ZoomScale.label(forPercent: percent)

        guard label != reportedPercent else { return }

        reportedPercent    = label
        accessibilityValue = "\(label)%"
        onZoomChange?(percent)
    }

    // MARK: - Setup

    private func configureLayer(device: some MTLDevice) {
        isOpaque        = true
        backgroundColor = EditorSurround.uiColor

        metalLayer.device          = device
        metalLayer.pixelFormat     = Self.drawablePixelFormat
        metalLayer.colorspace      = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque        = true
    }

    private func configureRenderPass() {
        let attachment = renderPass.colorAttachments[0]
        attachment?.loadAction  = .clear
        attachment?.storeAction = .store
        attachment?.clearColor  = EditorSurround.metalClearColor
    }

    private func configureGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))

        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))

        doubleTap.numberOfTapsRequired = 2
        pinchRecognizer.delegate       = self
        panRecognizer.delegate         = self
        singleTap.require(toFail: doubleTap)

        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(singleTap)
    }

    private func configureAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel     = String(localized: "Photo")
        accessibilityTraits    = .image
    }

    /// listenForFrames sets the sink's wake-up. It runs on the engine thread, so it only flips an
    /// atomic and, if no hop is pending yet, schedules one asynchronous hop to main. The hop clears
    /// the flag before marking the view, so a frame that lands after it schedules a new hop.
    private func listenForFrames() {
        frames.onFrame = { [weak self, crossThread] in
            let claimed = crossThread.isHopPending.compareExchange(
                expected : false,
                desired  : true,
                ordering : .acquiringAndReleasing
            )

            guard claimed.exchanged else { return }

            DispatchQueue.main.async {
                crossThread.isHopPending.store(false, ordering: .releasing)
                self?.setNeedsRedraw()
            }
        }
    }
}

extension CanvasView: UIGestureRecognizerDelegate {

    /// Pinch and pan run together, so two fingers can zoom and move the image in one gesture.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
