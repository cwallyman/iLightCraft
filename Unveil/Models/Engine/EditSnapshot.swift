//
//  EditSnapshot.swift
//  Unveil
//

/// EditSnapshot is what an undo step restores: the shown control values and whether the engine's
/// white balance mode was As Shot. The mode is part of it because Custom numbers can equal the
/// as-shot pair, and only the mode tells the Edited/Original status apart.
struct EditSnapshot: Equatable {

    let values              : [DevelopAdjustmentKind: Double]
    let isWhiteBalanceAsShot: Bool
}
