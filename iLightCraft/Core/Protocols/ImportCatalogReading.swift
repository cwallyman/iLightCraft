//
//  ImportCatalogReading.swift
//  iLightCraft
//

/// ImportCatalogReading tells which files the engine's catalog still points at, by file name. The
/// import store deletes only copies this answer does not name, so a throw must mean "unknown",
/// never "none", and a partial answer must throw too.
///
/// Names, not paths: iOS moves the data container to a new folder on an update, and the catalog
/// keeps the old absolute path until the photo is reopened. Copy names start with the file's
/// SHA-256, so a name alone identifies a copy wherever the folder now lives.
// Nonisolated: the sweep runs off the main actor, and the app default is MainActor.
nonisolated protocol ImportCatalogReading: Sendable {

    /// The file name of every photo the catalog holds, trashed ones included.
    func referencedFileNames() async throws(EngineError) -> Set<String>
}
