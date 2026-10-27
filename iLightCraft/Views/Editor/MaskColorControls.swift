import SwiftUI

struct MaskColorControls: View {
    @Binding var values: MaskColorAdjustments
    let busy: Bool
    let apply: () -> Void
    let colorize: (Double) -> Void
    let reset: () -> Void
    let onEditingChanged: (Bool) -> Void

    private let swatches: [(String, Double)] = [
        ("Red", 0), ("Orange", 30), ("Yellow", 60), ("Green", 120),
        ("Cyan", 180), ("Blue", 240), ("Purple", 270), ("Magenta", 300)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider("Temp", value: $values.temperature)
            slider("Tint", value: $values.tint)
            slider("Exposure", value: $values.exposure, range: -4...4, step: 0.01)
            Group {
                VStack(spacing: 14) {
                    slider("Contrast", value: $values.contrast)
                    slider("Highlights", value: $values.highlights)
                    slider("Shadows", value: $values.shadows)
                    slider("Whites", value: $values.whites)
                    slider("Blacks", value: $values.blacks)
                    slider("Texture", value: $values.texture)
                    slider("Clarity", value: $values.clarity)
                    slider("Dehaze", value: $values.dehaze)
                    slider("Sharpness", value: $values.sharpness)
                    slider("Noise", value: $values.noise)
                    slider("Moiré", value: $values.moire)
                    slider("Defringe", value: $values.defringe)
                }
            }
            Text("Color").font(.subheadline.weight(.semibold))
            slider("Hue shift", value: $values.hue)
            slider("Saturation", value: $values.saturation)
            Text("Colorize").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(swatches, id: \.0) { name, hue in
                    Button {
                        colorize(hue)
                    } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(hue: hue / 360, saturation: 1, brightness: 1))
                                .frame(width: 20, height: 20)
                            Text(name).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(values.colorAmount > 0 && values.colorHue == hue ? Color.accentColor.opacity(0.18) : .clear,
                                    in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colorize mask \(name)")
                }
            }
            slider("Target hue", value: $values.colorHue, range: 0...360, suffix: "°")
            slider("Color amount", value: $values.colorAmount, range: 0...100, suffix: "%")
            Text("Swatches replace the mask’s original color while retaining shading. For natural skin, use Temperature, Tint, Hue shift and Saturation. Release sliders to apply.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Apply Mask Adjustments", action: apply).buttonStyle(.borderedProminent)
            Button("Reset Mask Color", action: reset)
            Text("Use separate Subject and Background masks for different colors, such as a red subject and blue background.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(busy)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = -100...100,
                        step: Double = 1, suffix: String = "") -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                LightCraftNumberButton(title: title, value: value.wrappedValue, range: range, step: step, decimals: step < 0.1 ? 2 : step < 1 ? 1 : 0) { number in
                    value.wrappedValue = number; apply()
                }
                if !suffix.isEmpty { Text(suffix) }
            }.foregroundStyle(LightCraftPanelStyle.isChanged(value.wrappedValue, from: 0) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
            LightCraftSlider(value: value, in: range, step: step, controlID: title == "Temp" ? "mask.temp" : title == "Tint" ? "mask.tint" : title == "Saturation" ? "color.saturation" : title == "Hue shift" || title == "Target hue" ? "mask.hue" : "") { editing in
                onEditingChanged(editing)
                if !editing { apply() }
            }
            .accessibilityLabel("Mask \(title)")
        }
    }
}
