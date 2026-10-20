//
//  EngineDiagnosing.swift
//  Unveil
//

// Nonisolated: the diagnostics run on the engine's command queue, and the app default is MainActor.
/// EngineDiagnosing provides JSON command access for diagnostics and native photo output.
/// EditorViewModel orders native export and crop-preview commands after pending edits.
///
/// The result is the engine's JSON, untouched: the caller shows it or logs it, and decodes nothing.
nonisolated protocol EngineDiagnosing: AnyObject, Sendable {

    func diagnostic(_ command: String, params: some Encodable & Sendable) async throws(EngineError) -> String
}
