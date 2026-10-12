//
//  FakeImportCatalog.swift
//  UnveilTests
//

import Foundation
@testable import Unveil

/// FakeImportCatalog answers the sweep with a fixed set of file names, or with a failure.
nonisolated struct FakeImportCatalog: ImportCatalogReading {

    let names  : Set<String>
    let failure: EngineError?

    init(names: Set<String> = [], failure: EngineError? = nil) {
        self.names   = names
        self.failure = failure
    }

    func referencedFileNames() async throws(EngineError) -> Set<String> {
        if let failure { throw failure }
        return names
    }
}
