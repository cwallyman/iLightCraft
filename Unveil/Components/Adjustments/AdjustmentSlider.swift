//
//  AdjustmentSlider.swift
//  Unveil
//

import SwiftUI

/// AdjustmentSlider is one develop control: its name and value on top, and below them a thin
/// custom track between a minus and a plus stepper.
///
/// It knows nothing about the engine. The value comes in as a plain number and the photo's own
/// default as `defaultValue`. Out go every new drag value (`onDragValue`), the drag edges
/// (`onEditingChanged`), every whole edit (`onCommit`: a value typed in, a VoiceOver step), every
/// stepper press (`onNudge`, a delta; the owner commits the burst once the presses stop) and a
/// reset (`onReset`, since temperature and tint go back to As Shot rather than to a number).
///
/// The row is Equatable on what it draws (kind, value, default), closures left out, so the panel's
/// `.equatable()` re-evaluates only the row whose value changed during a drag, not all eighteen.
///
/// The track is relative: a drag anywhere on it moves the thumb by the finger's motion, it never
/// jumps to the touch point, and a tap (even a sloppy one) or a vertical swipe does nothing.
/// Moving the finger vertically away from the track slows the motion down (`SliderSpeed`), and a
/// capsule names the band while it is not full speed. The fill follows `SliderFill`: centred
/// controls fill from the default.
///
/// Haptics: a tick when a drag crosses or lands on the default or reaches either end of the range
/// (HapticsAnchor, so a trackpad drag clicks too), a selection tick when it changes speed band and
/// at every stepper press, and a light impact on reset. A double tap on the name or on the track
/// resets; a tap on the value opens a field to type it in.
///
/// For VoiceOver the row is one element: the name and the value are read once, a swipe up or
/// down moves the value by one step, and "Reset" resets it.
struct AdjustmentSlider: View {

    let kind            : DevelopAdjustmentKind
    let value           : Double
    let defaultValue    : Double
    let onDragValue     : (Double) -> Void
    let onEditingChanged: (Bool) -> Void
    let onCommit        : (Double) -> Void
    let onNudge         : (Double) -> Void
    let onReset         : () -> Void

    /// DragState is a drag in progress. `position` is the unrounded value the finger has reached,
    /// so slow motion below one step still accumulates; the binding gets it snapped to the step.
    private struct DragState {

        var position: Double
        var lastX   : CGFloat
        var speed   : SliderSpeed
    }

    private static let thumbSize   : CGFloat = 18
    private static let trackHeight : CGFloat = 4
    private static let dragSlop    : CGFloat = 8

    @Environment(\.isEnabled)
    private var isEnabled

    @GestureState
    private var isTrackTouched = false

    @State
    private var drag: DragState?

    /// isTrackSwipeIgnored is true for the rest of a track touch that started vertically: a page
    /// scroll that happens to begin on a track moves nothing.
    @State
    private var isTrackSwipeIgnored = false

    @State
    private var selectionTicks = 0

    /// alignmentTicks counts the default and range-end ticks; HapticsAnchor fires one per change,
    /// at `alignmentTickX` on the track.
    @State
    private var alignmentTicks = 0

    @State
    private var alignmentTickX: CGFloat = 0

    @State
    private var resets = 0

    @State
    private var isEntryShown = false

    @State
    private var entryText = ""

    @FocusState
    private var isEntryFocused: Bool

    #if DEBUG
    /// bodyRuns counts body evaluations per control in debug builds, so a test can check that a
    /// drag on one row leaves every other row alone.
    static var bodyRuns: [DevelopAdjustmentKind: Int] = [:]
    #endif

    var body: some View {
        #if DEBUG
        let _ = Self.bodyRuns[kind, default: 0] += 1
        #endif

        VStack(alignment: .leading, spacing: 2) {

            HStack(alignment: .firstTextBaseline) {

                Text(Self.title(of: kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: reset)

                Button(formattedValue, action: openEntry)
                    .buttonStyle(.plain)
                    .monospacedDigit()
                    .foregroundStyle(isAtDefault ? .secondary : .primary)
                    .popover(isPresented: $isEntryShown) { entryField }
            }
            .font(.subheadline)

            HStack(spacing: 0) {

                stepButton(direction: -1)

                track

                stepButton(direction: 1)
            }
        }
        .overlay(alignment: .top) { speedLabel }
        .animation(.easeOut(duration: 0.15), value: drag?.speed)
        .onChange(of: value) { oldValue, newValue in
            if let drag, ticks(from: oldValue, to: newValue) {
                alignmentTickX  = drag.lastX
                alignmentTicks += 1
            }
        }
        .onChange(of: isTrackTouched) { _, isTouched in
            if !isTouched {
                endDrag()
            }
        }
        .onChange(of: isEntryShown) { _, isShown in
            if !isShown {
                commitEntry()
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

    // MARK: - Track

    /// track draws the line, the fill, the default's tick (centred controls) and the thumb, inset
    /// by half a thumb so the thumb stays inside at both ends. The whole 32 pt band takes the drag.
    private var track: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - Self.thumbSize, 1)
            let fill   = SliderFill(
                value        : value,
                range        : kind.range,
                defaultValue : defaultValue
            )

            ZStack(alignment: .leading) {

                Capsule()
                    .fill(.secondary)
                    .frame(width: usable, height: Self.trackHeight)
                    .offset(x: Self.thumbSize / 2)

                if kind.range.lowerBound < 0 {
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 2, height: 10)
                        .offset(x: Self.thumbSize / 2 + defaultFraction * usable - 1)
                }

                Capsule()
                    .fill(.primary)
                    .frame(width: (fill.end - fill.start) * usable, height: Self.trackHeight)
                    .offset(x: Self.thumbSize / 2 + fill.start * usable)

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .offset(x: fill.thumb * usable)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(trackDrag(usableWidth: usable, height: proxy.size.height))
            .simultaneousGesture(TapGesture(count: 2).onEnded(reset))
            .background {
                HapticsAnchor(
                    ticks      : alignmentTicks,
                    location   : CGPoint(x: alignmentTickX, y: proxy.size.height / 2),
                    isDragging : drag != nil
                )
            }
        }
        .frame(height: 32)
    }

    /// trackDrag moves the value by the finger's horizontal motion, scaled by the speed band of
    /// its vertical distance from the track. The 8 pt slop is a dead zone: a tap's jitter never
    /// starts a drag, and motion counts from where the drag was recognized, so the thumb never
    /// jumps. A touch that starts mostly vertical is a swipe, not a drag, and moves nothing.
    private func trackDrag(usableWidth: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: Self.dragSlop)
            .updating($isTrackTouched) { _, isTouched, _ in isTouched = true }
            .onChanged { gesture in
                guard isEnabled, !isTrackSwipeIgnored else { return }

                if drag == nil, abs(gesture.translation.height) > abs(gesture.translation.width) {
                    isTrackSwipeIgnored = true
                    return
                }

                let speed = SliderSpeed(distance: gesture.location.y - height / 2)
                var state = drag ?? DragState(
                    position : value,
                    lastX    : gesture.location.x,
                    speed    : speed
                )

                if drag == nil {
                    onEditingChanged(true)
                } else if speed != state.speed {
                    selectionTicks += 1
                }

                let span  = kind.range.upperBound - kind.range.lowerBound
                let moved = Double(gesture.location.x - state.lastX) / Double(usableWidth) * span

                state.position = min(
                    max(state.position + moved * speed.factor, kind.range.lowerBound),
                    kind.range.upperBound
                )
                state.lastX = gesture.location.x
                state.speed = speed
                drag        = state

                let snapped = kind.snapped(state.position)
                if snapped != value {
                    onDragValue(snapped)
                }
            }
    }

    /// endDrag runs when the track's gesture ends or is cancelled (the gesture state resets in
    /// both cases), and only if a drag actually started.
    private func endDrag() {
        isTrackSwipeIgnored = false

        guard drag != nil else { return }

        drag = nil
        onEditingChanged(false)
    }

    @ViewBuilder
    private var speedLabel: some View {
        if let label = drag?.speed.label {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Stepper

    /// stepButton is the minus or plus of the stepper, disabled at the end of the range it moves
    /// toward. Holding it repeats (`buttonRepeatBehavior`), each repeat being one more press.
    private func stepButton(direction: Double) -> some View {
        let isAtLimit = direction < 0
            ? value <= kind.range.lowerBound
            : value >= kind.range.upperBound

        return Button {
            guard isEnabled else { return }

            selectionTicks += 1
            onNudge(direction * kind.step)
        } label: {
            Image(systemName: direction < 0 ? "minus" : "plus")
                .font(.footnote.weight(.semibold))
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(.secondary)
        .disabled(isAtLimit)
    }

    // MARK: - Value entry

    /// entryField asks for the full keyboard's number layout on centred controls: the decimal pad
    /// of the floating (phone layout) keyboard has no minus key.
    private var entryField: some View {
        TextField(Self.title(of: kind), text: $entryText)
            .keyboardType(kind.range.lowerBound < 0 ? .numbersAndPunctuation : .decimalPad)
            .submitLabel(.done)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .focused($isEntryFocused)
            .onSubmit { isEntryShown = false }
            .frame(width: 160)
            .padding(16)
            .presentationCompactAdaptation(.popover)
            .onAppear { isEntryFocused = true }
    }

    /// openEntry fills the field with the plain number (no plus sign, unit or grouping) in the
    /// locale's decimal separator, as the row shows it, so it can be edited as typed.
    private func openEntry() {
        guard isEnabled else { return }

        let number = value
        entryText = kind.step < 1
            ? number.formatted(.number.precision(.fractionLength(2)).grouping(.never))
            : String(Int(number.rounded()))
        isEntryShown = true
    }

    /// commitEntry sends the typed number, snapped to the step and the range, as one whole edit.
    /// A comma counts as the decimal point and a typographic minus (U+2212) or en dash as a minus;
    /// text that is not a number, or no change, sends nothing.
    private func commitEntry() {
        let text = entryText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")

        guard let number = Double(text) else { return }

        let snapped = kind.snapped(number)
        if snapped != value {
            onCommit(snapped)
        }
    }

    // MARK: - Edits

    private func reset() {
        guard isEnabled else { return }

        resets += 1
        onReset()
    }

    /// adjust moves the value one step in the VoiceOver direction, as one whole edit. A disabled
    /// slider (no photo open) ignores it, as its touch gestures do.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard isEnabled else { return }

        switch direction {
            case .increment:
                onCommit(kind.snapped(value + kind.step))

            case .decrement:
                onCommit(kind.snapped(value - kind.step))

            @unknown default:
                return
        }
    }

    /// ticks(from:to:) is true when a drag's value change deserves a selection tick: it crosses or
    /// lands on the default, or it reaches either end of the range.
    private func ticks(from oldValue: Double, to newValue: Double) -> Bool {
        let before = oldValue - defaultValue
        let after  = newValue - defaultValue

        let crossesDefault = before * after < 0 || (after == 0 && before != 0)
        let reachesEnd     = newValue != oldValue
            && (newValue == kind.range.lowerBound || newValue == kind.range.upperBound)

        return crossesDefault || reachesEnd
    }

    // MARK: - Text

    private var isAtDefault: Bool { value == defaultValue }

    private var defaultFraction: Double { SliderFill.fraction(of: defaultValue, in: kind.range) }

    /// formattedValue shows exposure in EV with a sign and two decimals, temperature in kelvin,
    /// and every other control as an integer, signed when its range goes below zero.
    private var formattedValue: String {
        let number = value

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

extension AdjustmentSlider: Equatable {

    /// Two rows are equal when they draw the same. The closures are left out: the panel makes new
    /// ones on every pass, with the same behavior, and comparing them would never say equal.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.defaultValue == rhs.defaultValue
    }
}
