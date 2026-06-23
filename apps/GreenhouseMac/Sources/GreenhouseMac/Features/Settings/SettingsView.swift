import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Prototype") {
                LabeledContent("Backend", value: "Deterministic fake backend")
                LabeledContent("Event format", value: "Schema v2 NDJSON")
                LabeledContent("Guest target", value: "LineageOS 23.2 / ARM64")
            }

            Section("Community Runtime") {
                LabeledContent("Google compatibility", value: "microG")
                LabeledContent("App source", value: "F-Droid and local packages")
                LabeledContent("Official Google Play", value: "Not included")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
