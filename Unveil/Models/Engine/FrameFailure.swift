//
//  FrameFailure.swift
//  Unveil
//

// nonisolated: the engine thread builds it, and the editor reads it on the main actor.
/// FrameFailure is a render the engine could not finish: the request's generation, whether it was
/// a zoom window (not a whole-frame preview), and the engine's message.
nonisolated struct FrameFailure: Equatable, Sendable {

    let generation: UInt64
    let isWindow  : Bool
    let message   : String
}
