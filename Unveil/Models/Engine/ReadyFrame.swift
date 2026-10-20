//
//  ReadyFrame.swift
//  Unveil
//

// nonisolated: FrameSink publishes it from the engine thread, and the canvas reads it on the main actor.
/// ReadyFrame describes a frame a FrameSink holds; the canvas reads it, never the pixels' owner.
/// The pixels stay in the sink's shared buffer, so a ReadyFrame is a few numbers, cheap to copy across threads.
/// A whole-frame preview has no `window`; a zoom window says where its pixels sit in the frame.
/// `nativeWidth x nativeHeight` is the whole frame at the photo's own resolution (cropped and
/// straightened), what 100 % means; 0 when the engine did not say.
nonisolated struct ReadyFrame: Equatable, Sendable {

    let bufferIndex : Int            // Which of the sink's shared MTLBuffers holds the pixels.
    let width       : Int
    let height      : Int
    let bytesPerRow : Int            // Row stride in bytes, aligned for rgba8Unorm textures.
    let generation  : UInt64         // Engine render counter: FrameSink drops anything at or below it.
    let isDraft     : Bool
    let window      : FrameWindow?   // Placement of a window frame; nil for a whole-frame preview.
    let nativeWidth : Int
    let nativeHeight: Int
    var isHDR: Bool = false
}
