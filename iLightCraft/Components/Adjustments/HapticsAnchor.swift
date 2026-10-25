//
//  HapticsAnchor.swift
//  iLightCraft
//

import SwiftUI

/// HapticsAnchor is an invisible UIView that a SwiftUI control places behind itself to fire
/// TickHaptics, which needs a view for the trackpad and Apple Pencil Pro feedback. Every change of
/// `ticks` fires one tick at `location`, in the control's own coordinates; the generators warm up
/// when `isDragging` turns on. The TickHaptics lives in the coordinator, so it is created once per
/// view and not on every re-creation of the control during a drag. The view takes no touches.
struct HapticsAnchor: UIViewRepresentable {

    let ticks     : Int
    let location  : CGPoint
    let isDragging: Bool

    /// Coordinator keeps the generators and the last tick count and drag state it has seen.
    final class Coordinator {

        var haptics   : TickHaptics?
        var ticks     : Int
        var isDragging: Bool = false

        init(ticks: Int) {
            self.ticks = ticks
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(ticks: ticks)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        view.isUserInteractionEnabled = false
        context.coordinator.haptics   = TickHaptics(view: view)

        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator

        if isDragging, !coordinator.isDragging {
            coordinator.haptics?.prepare()
        }

        if ticks != coordinator.ticks {
            coordinator.haptics?.tick(at: location)
        }

        coordinator.ticks      = ticks
        coordinator.isDragging = isDragging
    }
}
