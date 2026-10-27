//
//  LightCraftSlider.swift
//  iLightCraft
//

import SwiftUI

/// LightCraftSliderPalette uses the retained LightCraft control track colors.
enum LightCraftSliderPalette {
    static let gradients: [String: [UInt32]] = [
        "curve.refineSaturation": [0x7a7a7a, 0xd85a3a],
        "color.vibrance": [0x7a7a7a, 0xd8406a],
        "color.saturation": [0x7a7a7a, 0xe04a3a],
        "vignette.amount": [0x101010, 0xf0f0f0],
        "optics.defringePurple": [0x7a7a7a, 0xa040d0],
        "optics.defringePurpleHueLo": [0x6040e0, 0xd040b0],
        "optics.defringePurpleHueHi": [0x6040e0, 0xd040b0],
        "optics.defringeGreen": [0x7a7a7a, 0x40c040],
        "optics.defringeGreenHueLo": [0xc0d030, 0x30c0b0],
        "optics.defringeGreenHueHi": [0xc0d030, 0x30c0b0],
        "optics.caRed": [0x30c0c0, 0xe04040],
        "optics.caBlue": [0xd0c030, 0x4060e0],
        "calibration.redHue": [0xe0306a, 0xe08a30],
        "calibration.redSat": [0x7a7a7a, 0xe03a3a],
        "calibration.greenHue": [0xb0c030, 0x30c08a],
        "calibration.greenSat": [0x7a7a7a, 0x40b050],
        "calibration.blueHue": [0x30a0d0, 0x8040d0],
        "calibration.blueSat": [0x7a7a7a, 0x3a60e0],
    ]
    static let bands = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
    static let bandColors: [UInt32] = [0xaa0000, 0xbb6600, 0xaaaa00, 0x009900, 0x00aaaa, 0x0044cc, 0x7722aa, 0xaa0077]
    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    static func colors(_ id: String) -> [Color] {
        if id == "wb.temp" || id == "mask.temp" {
            return [0x193961, 0x47566a, 0x60666d, 0x70705b, 0x737339, 0x75742a].map(color)
        }
        if id == "wb.tint" || id == "mask.tint" || id == "calibration.shadowsTint" {
            return [0x246123, 0x2c552c, 0x394739, 0x4a3d4c, 0x6b336b, 0x872c87].map(color)
        }
        if let stops = gradients[id] { return stops.map(color) }
        let parts = id.split(separator: ".").map(String.init)
        if parts.count >= 2, (parts[0] == "mixer" || parts[0] == "bw"), let i = bands.firstIndex(of: parts[1]) {
            let c = color(bandColors[i])
            if parts.last == "hue" { return [color(bandColors[(i + 7) % 8]), c, color(bandColors[(i + 1) % 8])] }
            if parts.last == "sat" { return [color(0x7a7a7a), c] }
            return [color(0x101010), c, color(0xf0f0f0)]
        }
        if id.hasSuffix(".hue") || id == "mask.hue" { return [.red, .yellow, .green, .cyan, .blue, .purple, .red] }
        if id.hasSuffix(".sat") || id == "mask.saturation" { return [color(0x7a7a7a), color(0xe04a3a)] }
        return [color(0x656565), color(0x656565)]
    }
}

/// LightCraftSliderTrack shares the thin gradient line and hollow thumb across slider implementations.
struct LightCraftSliderTrack: View {
    let fraction: Double
    let controlID: String
    var isChanged = false
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 20)
            ZStack(alignment: .leading) {
                Rectangle().fill(LinearGradient(colors: LightCraftSliderPalette.colors(controlID), startPoint: .leading, endPoint: .trailing))
                    .frame(width: width, height: 2).offset(x: 10)
                Circle().fill(isChanged ? LightCraftPanelStyle.changed : LightCraftPanelStyle.background)
                    .overlay(Circle().stroke(isChanged ? LightCraftPanelStyle.changed : LightCraftSliderPalette.color(0x999999), lineWidth: 2))
                    .frame(width: 18, height: 18).offset(x: 1 + min(1, max(0, fraction)) * width)
            }
            .frame(height: geometry.size.height)
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// LightCraftSlider keeps vertical swipes available for scrolling and commits one edit per horizontal drag.
struct LightCraftSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let controlID: String
    let defaultValue: Double
    let onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var startValue: Double?
    @State private var ignoringSwipe = false
    @GestureState private var touching = false
    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil, controlID: String = "", defaultValue: Double? = nil, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.defaultValue = defaultValue ?? (range.contains(0) ? 0 : range.lowerBound)
        _value = value; self.range = range; self.step = step; self.controlID = controlID; self.onEditingChanged = onEditingChanged
    }
    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            LightCraftSliderTrack(fraction: span > 0 ? (value - range.lowerBound) / span : 0, controlID: controlID, isChanged: LightCraftPanelStyle.isChanged(value, from: defaultValue))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 8)
                    .updating($touching) { _, active, _ in active = true }
                    .onChanged { gesture in
                        guard isEnabled, !ignoringSwipe else { return }
                        if startValue == nil {
                            guard abs(gesture.translation.width) > abs(gesture.translation.height) else { ignoringSwipe = true; return }
                            startValue = value; onEditingChanged(true)
                        }
                        guard let startValue else { return }
                        set(startValue + Double(gesture.translation.width / max(1, geometry.size.width - 20)) * span)
                    }
                    .onEnded { _ in finish() })
        }
        .frame(height: 32)
        .onChange(of: touching) { _, active in if !active { finish() } }
        .accessibilityElement()
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(0...2))))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = step ?? (range.upperBound - range.lowerBound) / 100
            onEditingChanged(true)
            set(value + (direction == .increment ? delta : -delta))
            onEditingChanged(false)
        }
    }
    private func set(_ newValue: Double) {
        guard newValue.isFinite else { return }
        let rounded = step.flatMap { $0 > 0 ? (newValue / $0).rounded() * $0 : nil } ?? newValue
        value = min(range.upperBound, max(range.lowerBound, rounded))
    }
    private func finish() {
        let edited = startValue != nil
        startValue = nil; ignoringSwipe = false
        if edited { onEditingChanged(false) }
    }
}

/// LightCraftSliderRow keeps each slider's changed label, value and handle in sync.
struct LightCraftSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let step: Double?
    let controlID: String
    let onEditingChanged: (Bool) -> Void
    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, defaultValue: Double, step: Double? = nil, controlID: String = "", onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title; _value = value; self.range = range; self.defaultValue = defaultValue
        self.step = step; self.controlID = controlID; self.onEditingChanged = onEditingChanged
    }
    private var decimals: Int {
        if let step { return step < 0.01 ? 3 : step < 0.1 ? 2 : step < 1 ? 1 : 0 }
        let span = range.upperBound - range.lowerBound
        return span < 1 ? 3 : span <= 2 ? 2 : 0
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title); Spacer()
                LightCraftNumberButton(title: title, value: value, range: range, step: step, decimals: decimals) { number in
                    onEditingChanged(true); value = number; onEditingChanged(false)
                }
            }
            .foregroundStyle(LightCraftPanelStyle.isChanged(value, from: defaultValue) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
            LightCraftSlider(value: $value, in: range, step: step, controlID: controlID, defaultValue: defaultValue, onEditingChanged: onEditingChanged)
                .accessibilityLabel(title)
        }
    }
}
