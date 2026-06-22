import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Foundation Build") {
                LabeledContent("Backend", value: "Deterministic fake backend")
                LabeledContent("Event format", value: "Schema v1 NDJSON")
                LabeledContent("Runtime", value: "No Android image included")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
