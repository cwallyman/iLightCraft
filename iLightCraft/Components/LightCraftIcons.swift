//
//  LightCraftIcons.swift
//  iLightCraft
//

import SwiftUI

/// LightCraft icon labels use the desktop program's original 20-point vector drawings.
/// Asset catalogs preserve PDF paths and apply the current tint, including disabled states.
extension Image {
    init(lightCraftIcon name: String) {
        self = Image(name).renderingMode(.template)
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: String, lightCraftIcon name: String) {
        self.init { Text(title) } icon: { Image(lightCraftIcon: name) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, lightCraftIcon name: String, action: @escaping () -> Void) {
        self.init(action: action) { SwiftUI.Label(title, lightCraftIcon: name) }
    }
}

extension Menu where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, lightCraftIcon name: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUI.Label(title, lightCraftIcon: name) }
    }
}

extension Toggle where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, lightCraftIcon name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUI.Label(title, lightCraftIcon: name) }
    }
}
