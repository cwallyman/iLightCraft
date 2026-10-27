//
//  LightCraftNumberButton.swift
//  iLightCraft
//

import SwiftUI

/// LightCraftNumberButton presents a local ten-key editor without opening the full keyboard.
struct LightCraftNumberButton: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var decimals = 0
    var suffix = ""
    var display: String? = nil
    var isPresented: Binding<Bool>? = nil
    let onCommit: (Double) -> Void
    @State private var localPresented = false
    private var presentation: Binding<Bool> { isPresented ?? $localPresented }
    var body: some View {
        Button {
            presentation.wrappedValue = true
        } label: {
            Text(display ?? (value.formatted(.number.precision(.fractionLength(decimals))) + suffix))
                .monospacedDigit().frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + " value")
        .accessibilityValue(display ?? value.formatted())
        .accessibilityHint("Enter a value with the numeric keypad.")
        .popover(isPresented: presentation, arrowEdge: .trailing) {
            LightCraftTenKey(title: title, value: value, range: range, step: step) { number in
                presentation.wrappedValue = false
                if number != value { onCommit(number) }
            } cancel: { presentation.wrappedValue = false }
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// LightCraftTenKey validates a draft locally; only Done commits an edit.
struct LightCraftTenKey: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double?
    let commit: (Double) -> Void
    let cancel: () -> Void
    @State private var text: String
    @State private var replaceOnDigit = true
    @State private var didEdit = false
    @State private var error: String?
    init(title: String, value: Double, range: ClosedRange<Double>, step: Double?, commit: @escaping (Double) -> Void, cancel: @escaping () -> Void) {
        self.title = title; self.range = range; self.step = step; self.commit = commit; self.cancel = cancel
        _text = State(initialValue: value.formatted(.number.precision(.fractionLength(0...8)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))))
    }
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text.isEmpty ? "0" : text).font(.system(size: 28)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, minHeight: 40, alignment: .trailing)
                .padding(.horizontal, 10).background(LightCraftPanelStyle.inset, in: .rect(cornerRadius: 6))
                .accessibilityLabel("Entered value").accessibilityValue(text.isEmpty ? "0" : text)
            Text("\(range.lowerBound.formatted()) to \(range.upperBound.formatted())")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(1...9, id: \.self) { digit in key(String(digit)) { append(String(digit)) } }
                key(".") { append(".") }.disabled(step.map { $0 >= 1 } ?? false)
                key("0") { append("0") }
                key("⌫", accessibility: "Backspace") { didEdit = true; replaceOnDigit = false; if !text.isEmpty { text.removeLast() }; error = nil }
            }
            HStack {
                key("±", accessibility: "Change sign") {
                    didEdit = true; replaceOnDigit = false
                    if text.hasPrefix("-") { text.removeFirst() } else { text = "-" + text }
                    error = nil
                }.disabled(range.lowerBound >= 0)
                key("Clear") { text = "0"; didEdit = true; replaceOnDigit = true; error = nil }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel", action: cancel).frame(maxWidth: .infinity, minHeight: 40)
                Button("Done", action: accept).buttonStyle(.borderedProminent)
                    .tint(LightCraftPanelStyle.changed).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .padding(14).frame(width: 250)
        .foregroundStyle(LightCraftPanelStyle.label).background(LightCraftPanelStyle.background)
        .preferredColorScheme(.dark)
    }
    private func key(_ label: String, accessibility: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 44)
                .background(LightCraftPanelStyle.inset, in: .rect(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(accessibility ?? label)
    }
    private func append(_ digit: String) {
        error = nil
        if replaceOnDigit { text = ""; replaceOnDigit = false }
        guard text.count < 18, digit != "." || !text.contains(".") else { return }
        didEdit = true
        if digit != ".", text == "0" || text == "-0" { text = text.hasPrefix("-") ? "-" : "" }
        if digit == "." && (text.isEmpty || text == "-") { text += "0" }
        text += digit
    }
    private func accept() {
        guard didEdit else { cancel(); return }
        guard let value = Double(text.isEmpty ? "0" : text), value.isFinite, range.contains(value) else {
            error = "Enter a number within the shown range."
            return
        }
        let rounded = step.flatMap { $0.isFinite && $0 > 0 ? (value / $0).rounded() * $0 : nil } ?? value
        guard rounded.isFinite else { error = "Enter a valid number."; return }
        commit(min(range.upperBound, max(range.lowerBound, rounded)))
    }
}
