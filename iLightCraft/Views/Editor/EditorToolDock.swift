import SwiftUI

/// One tool occupies the same reserved space beside the canvas at a time.
nonisolated enum EditorDockTool: Equatable, Hashable {
    case hsl, profiles, curves, pointColor, grading, optics, geometry, whiteBalance, presets, batch, versions, history, keywords, redEye, crop, export, info
    case computational(Int)
}

struct EditorToolEmbeddedKey: EnvironmentKey { static let defaultValue = false }

struct EditorToolDockedKey: EnvironmentKey { static let defaultValue = false }
struct EditorToolCloseKey: EnvironmentKey { static let defaultValue: (@MainActor () -> Void)? = nil }
struct EditorToolBusyKey: EnvironmentKey { static let defaultValue: Binding<Bool>? = nil }

extension EnvironmentValues {
    var editorToolEmbedded: Bool {
        get { self[EditorToolEmbeddedKey.self] }
        set { self[EditorToolEmbeddedKey.self] = newValue }
    }
    var editorToolDocked: Bool {
        get { self[EditorToolDockedKey.self] }
        set { self[EditorToolDockedKey.self] = newValue }
    }
    var editorToolClose: (@MainActor () -> Void)? {
        get { self[EditorToolCloseKey.self] }
        set { self[EditorToolCloseKey.self] = newValue }
    }
    var editorToolBusy: Binding<Bool>? {
        get { self[EditorToolBusyKey.self] }
        set { self[EditorToolBusyKey.self] = newValue }
    }
}

/// Reports operations that must finish before another toolbar tool can replace this panel.
struct EditorToolBusyReporter: ViewModifier {
    let busy: Bool
    @Environment(\.editorToolBusy) private var reportedBusy
    func body(content: Content) -> some View {
        content
            .onChange(of: busy, initial: true) { _, value in reportedBusy?.wrappedValue = value }
            .onDisappear { reportedBusy?.wrappedValue = false }
    }
}

/// A separate hosting boundary keeps each tool's navigation controls inside the dock.
/// Nested SwiftUI NavigationStacks otherwise merge their toolbar preferences into the editor.
struct EditorDockHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        return host
    }
    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
        host.rootView = content
    }
}

/// Docked tools have a local header, never a navigation toolbar that can join the main bar.
struct EditorToolPresentation<Header: View, Content: View>: View {
    @Environment(\.editorToolEmbedded) private var isEmbedded
    let title: String
    let header: Header
    let content: Content
    @Environment(\.editorToolDocked) private var isDocked

    init(title: String, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.title = title
        self.header = header()
        self.content = content()
    }

    var body: some View {
        presentation.lightCraftPanelContent().preferredColorScheme(.dark)
    }
    @ViewBuilder private var presentation: some View {
        if isEmbedded {
            content
        } else if isDocked {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(LightCraftPanelStyle.text).lineLimit(1)
                    Spacer(minLength: 4)
                    header.labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                .padding(.horizontal, 20).frame(minHeight: 46)
                Rectangle().fill(LightCraftPanelStyle.divider).frame(height: 1)
                content.frame(maxWidth: .infinity, maxHeight: .infinity).lightCraftPanelContent()
            }
            .background(LightCraftPanelStyle.background)
        } else {
            NavigationStack {
                content
                    .lightCraftScrollGutter()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LightCraftPanelStyle.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) { header }
                    }
            }
        }
    }
}

/// Layout uses available editor space, so landscape is independent of size-class changes.
nonisolated struct EditorControlsLayout {
    let size: CGSize
    let isPhone: Bool
    var isBottom: Bool { isPhone && size.height >= size.width }
    var sideWidth: CGFloat { min(360, max(280, size.width * 0.34)) }
    static func bottomHeight(available: CGFloat) -> CGFloat { max(0, (available - 8) * 0.5) }
}

/// EditorPanelScroll lets an expanded tool participate in Edit's single scrolling column.
struct EditorPanelScroll<Content: View>: View {
    @Environment(\.editorToolEmbedded) private var isEmbedded
    @ViewBuilder let content: () -> Content
    var body: some View {
        if isEmbedded { content() } else { ScrollView { content() } }
    }
}
