//
//  CapsulePicker.swift
//  Unveil
//

import SwiftUI

/// CapsulePicker is a segmented control drawn as one glass capsule with an inner pill that slides
/// to the chosen option, styled like the Files browser's own Recents / Shared / Browse switch: the
/// chosen title in the tint color on a lighter pill. The home uses it for its source and for the
/// Photos panel's Recents / Albums switch.
struct CapsulePicker<Value: Hashable>: View {

    let label  : String
    let options: [(title: String, value: Value)]

    @Binding
    var selection: Value

    @Namespace
    private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                segment(option.title, for: option.value)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ title: String, for value: Value) -> some View {
        let isSelected = selection == value

        return Button {
            withAnimation(.snappy(duration: 0.3)) { selection = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
