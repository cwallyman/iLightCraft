import SwiftUI
import UniformTypeIdentifiers

struct NativeBackupPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @State private var session: NativeBackupSession<Engine, Importer>
    @State private var choosingFolder = false
    @State private var restoring = false
    init(model: EditorViewModel<Engine, Importer>) { _session = State(initialValue: NativeBackupSession(model: model)) }
    var body: some View {
        LightCraftMenuSection("Library backup & recovery") {
            Button("Back Up Library to Folder…") { restoring = false; choosingFolder = true }.disabled(session.busy)
            Button("Restore Backup as Separate Library…") { restoring = true; choosingFolder = true }.disabled(session.busy)
            if session.busy {
                ProgressView(value: session.progress)
                Button("Cancel After Current File", action: session.cancel)
            }
            if !session.status.isEmpty { Text(session.status).font(.footnote) }
            if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                if restoring { session.restore(from: url) } else { session.create(at: url) }
            case .failure(let error): session.error = error.localizedDescription
            }
        }
        .interactiveDismissDisabled(session.busy)
        .modifier(EditorToolBusyReporter(busy: session.busy))
    }
}
