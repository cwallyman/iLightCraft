//
//  AdjustmentInspectorState.swift
//  Unveil
//

import Observation

/// AdjustmentInspectorState shares the selected group between the SwiftUI panel and UIKit's
/// launch commands. UIKit owns inspector visibility, including dismissal of its compact sheet.
@Observable
@MainActor
final class AdjustmentInspectorState {

    var selectedGroup: AdjustmentGroup = .light
}
