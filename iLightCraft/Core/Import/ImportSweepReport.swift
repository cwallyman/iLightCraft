//
//  ImportSweepReport.swift
//  iLightCraft
//

/// ImportSweepReport is what one orphan sweep removed: how many copies, and how many bytes.
nonisolated struct ImportSweepReport: Equatable, Sendable {

    let removedCount: Int
    let freedBytes  : Int64

    static let nothing = ImportSweepReport(removedCount: 0, freedBytes: 0)
}
