import SwiftUI

struct LegalNoticesView: View {
    private let files = [
        ("Third-party notices", "ThirdPartyNotices"),
        ("Apache License 2.0", "Apache-2.0"),
        ("Engine MIT license", "Engine-MIT")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("iLightCraft").font(.title2.bold())
                ForEach(files, id: \.1) { title, resource in
                    DisclosureGroup(title) {
                        Text(contents(resource)).font(.footnote).textSelection(.enabled)
                    }
                }
            }.padding()
        }
        .navigationTitle("Licenses & Credits")
    }
    private func contents(_ resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt")
                ?? Bundle.main.url(forResource: resource, withExtension: "txt", subdirectory: "Legal"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The license file is unavailable in this build."
        }
        return text
    }
}
