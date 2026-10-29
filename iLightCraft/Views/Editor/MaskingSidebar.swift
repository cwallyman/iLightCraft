import SwiftUI

/// MaskTypeGrid is the Add Mask pop-out: one tile per mask type, each starting that mask.
struct MaskTypeGrid<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: ComputationalToolsSession<Engine, Importer>
    var onPick: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Mask").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                tile("Subject", icon: "Subject") { session.select(people: false, background: false) }
                tile("Sky", icon: "Sky", action: session.selectSky)
                tile("Background", icon: "Invert") { session.select(people: false, background: true) }
                tile("Brush", icon: "Brush") { session.beginManual("brush") }
                tile("Linear", icon: "Linear") { session.beginManual("linear") }
                tile("Radial", icon: "Radial") { session.beginManual("radial") }
                tile("Luminance", icon: "Sun") { session.beginManual("luminanceRange") }
                tile("Color", icon: "Picker") { session.beginManual("colorRange") }
                tile("Object", icon: "Target") {
                    let picking = !session.isPickingObject
                    session.beginManual("none"); session.isPickingObject = picking
                }
                tile("All People", icon: "FaceBox") { session.select(people: true, background: false) }
                tile("Each Person", icon: "Subject") { session.selectIndividuals(skin: false) }
                tile("Skin", icon: "FaceBox") { session.selectIndividuals(skin: true) }
                tile("Content-Aware", icon: "Eraser", action: session.beginContentAware)
            }
        }
        .buttonStyle(.plain)
        .disabled(session.busy || session.image == nil)
    }

    private func tile(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onPick()
        } label: {
            VStack(spacing: 6) {
                Image(lightCraftIcon: "LightCraft-\(icon)").resizable().scaledToFit().frame(width: 22, height: 22)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .foregroundStyle(.white)
            .lightCraftCardSurface(cornerRadius: 14)
            .contentShape(.rect)
        }.accessibilityLabel(title)
    }
}
