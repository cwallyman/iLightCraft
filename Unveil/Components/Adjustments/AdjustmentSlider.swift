//
//  AdjustmentSlider.swift
//  Unveil
//

import SwiftUI

/// AdjustmentSlider is one develop control: its name, its current value, a slider over the kind's
/// range and a compact stepper (minus and plus) that moves the value by one step.
///
/// It knows nothing about the engine. The value comes in as a binding, the drag edges go out
/// through `onEditingChanged`, and every discrete change (a stepper press, a VoiceOver step, a
/// reset) goes out through `onCommit` as a whole edit, so the panel decides what each one means.
///
/// The stepper repeats while held (`buttonRepeatBehavior`), each repeat being one more step. A
/// double tap on the name or on the slider (or the VoiceOver action "Reset") resets the
/// value to the kind's default.
///
/// Haptics: a selection tick when a drag crosses or lands on the default and at every stepper
/// press, and a light impact on reset.
///
/// For VoiceOver the row is one element: the name and the value are read once, and a swipe up or
/// down moves the value by one step. The stepper buttons are not separate elements, the
/// adjustable action is the same thing.
struct AdjustmentSlider: View {

    let kind            : DevelopAdjustmentKind
    let value           : Binding<Double>
    let onEditingChanged: (Bool) -> Void
    let onCommit        : (Double) -> Void

    @Environment(\.isEnabled)
    private var isEnabled

    @State
    private var isDragging = false

    @State
    private var selectionTicks = 0

    @State
    private var resets = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {

            HStack(alignment: .firstTextBaseline) {

                Text(Self.title(of: kind))

                Spacer()

                Text(formattedValue)
                    .monospacedDigit()
                    .foregroundStyle(isAtDefault ? .secondary : .primary)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: reset)

            HStack(spacing: 0) {

                stepButton(direction: -1)

                Slider(
                    value            : value,
                    in               : kind.range,
                    step             : kind.step,
                    onEditingChanged : editingChanged
                )
                .tint(.primary)
                .simultaneousGesture(TapGesture(count: 2).onEnded(reset))

                stepButton(direction: 1)
            }
        }
        .onChange(of: value.wrappedValue) { oldValue, newValue in
            if isDragging, crossesDefault(from: oldValue, to: newValue) {
                selectionTicks += 1
            }
        }
        .sensoryFeedback(.selection, trigger: selectionTicks)
        .sensoryFeedback(.impact(weight: .light), trigger: resets)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title(of: kind))
        .accessibilityValue(formattedValue)
        .accessibilityAdjustableAction { direction in adjust(direction) }
        .accessibilityAction(named: "Reset", reset)
    }

    // MARK: - Stepper

    /// stepButton is the minus or plus of the stepper: a 44 pt target around a small symbol,
    /// disabled at the end of the range it moves toward.
    private func stepButton(direction: Double) -> some View {
        let isAtLimit = direction < 0
            ? value.wrappedValue <= kind.range.lowerBound
            : value.wrappedValue >= kind.range.upperBound

        return Button {
            step(by: direction * kind.step)
            selectionTicks += 1
        } label: {
            Image(systemName: direction < 0 ? "minus" : "plus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(.primary.opacity(0.75))
        .disabled(isAtLimit)
    }

    // MARK: - Edits

    private func editingChanged(_ isEditing: Bool) {
        isDragging = isEditing
        onEditingChanged(isEditing)
    }

    /// step(by:) commits the value moved by `delta`, clamped to the range. Rounding to the step
    /// keeps repeated presses on the grid (0.01 steps drift in binary floating point).
    private func step(by delta: Double) {
        guard isEnabled else { return }

        let stepped = ((value.wrappedValue + delta) / kind.step).rounded() * kind.step
        onCommit(min(max(stepped, kind.range.lowerBound), kind.range.upperBound))
    }

    private func reset() {
        guard isEnabled else { return }

        resets += 1
        onCommit(kind.defaultValue)
    }

    /// adjust moves the value one step in the VoiceOver direction. A disabled slider (no photo
    /// open) ignores it, as its touch gesture does.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
            case .increment:
                step(by: kind.step)

            case .decrement:
                step(by: -kind.step)

            @unknown default:
                return
        }
    }

    private func crossesDefault(from oldValue: Double, to newValue: Double) -> Bool {
        let before = oldValue - kind.defaultValue
        let after  = newValue - kind.defaultValue

        return before * after < 0 || (after == 0 && before != 0)
    }

    // MARK: - Text

    private var isAtDefault: Bool { value.wrappedValue == kind.defaultValue }

    /// formattedValue shows exposure in EV with a sign and two decimals, temperature in kelvin,
    /// and every other control as an integer, signed when its range goes below zero.
    private var formattedValue: String {
        let number = value.wrappedValue

        switch kind {
            case .exposure:
                let text = number.formatted(
                    .number
                        .precision(.fractionLength(2))
                        .sign(strategy: .always(includingZero: false))
                )
                return "\(text) EV"

            case .temperature:
                return "\(number.formatted(.number.precision(.fractionLength(0)).grouping(.never))) K"

            default:
                let sign: NumberFormatStyleConfiguration.SignDisplayStrategy = kind.range.lowerBound < 0
                    ? .always(includingZero: false)
                    : .automatic
                return number.formatted(.number.precision(.fractionLength(0)).sign(strategy: sign))
        }
    }

    /// title(of:) is the control's name in the panel and in VoiceOver.
    private static func title(of kind: DevelopAdjustmentKind) -> String {
        switch kind {
            case .exposure:       "Exposure"
            case .contrast:       "Contrast"
            case .highlights:     "Highlights"
            case .shadows:        "Shadows"
            case .whites:         "Whites"
            case .blacks:         "Blacks"
            case .temperature:    "Temperature"
            case .tint:           "Tint"
            case .vibrance:       "Vibrance"
            case .saturation:     "Saturation"
            case .texture:        "Texture"
            case .clarity:        "Clarity"
            case .dehaze:         "Dehaze"
            case .sharpening:     "Sharpening"
            case .noiseReduction: "Noise Reduction"
            case .colorNoise:     "Color Noise Reduction"
            case .vignette:       "Vignette"
            case .grain:          "Grain"
        }
    }
}
