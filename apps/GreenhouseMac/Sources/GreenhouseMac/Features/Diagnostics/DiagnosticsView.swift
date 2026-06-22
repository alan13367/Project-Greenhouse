import AppKit
import GreenhouseCore
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    let model: GreenhouseAppModel
    @State private var selectedFailure: SimulatedFailure = .missingRuntime

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding()

            Divider()

            if model.events.isEmpty {
                ContentUnavailableView(
                    "No events yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Prepare Android or run a failure simulation to produce structured events.")
                )
            } else {
                List(model.events.reversed()) { event in
                    EventRow(event: event)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Advanced Diagnostics")
        .toolbar {
            ToolbarItemGroup {
                Button("Copy NDJSON") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnosticsNDJSON, forType: .string)
                }
                .disabled(model.events.isEmpty)

                Button("Export…") {
                    exportEvents()
                }
                .disabled(model.events.isEmpty)

                Button("Clear") {
                    model.clearEvents()
                }
                .disabled(model.events.isEmpty)
            }
        }
    }

    private var controls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fake Backend Controls")
                    .font(.headline)
                Text("Every scenario produces the same state transitions and structured events on each run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Failure", selection: $selectedFailure) {
                ForEach(SimulatedFailure.allCases) { failure in
                    Text(failure.title).tag(failure)
                }
            }
            .frame(width: 250)

            Button("Simulate") {
                Task { await model.simulate(selectedFailure) }
            }
            .buttonStyle(.borderedProminent)

            Button("Reset") {
                model.resetFakeBackend()
            }
        }
    }

    private func exportEvents() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "greenhouse-diagnostics.ndjson"
        panel.allowedContentTypes = [.json, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.diagnosticsNDJSON.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct EventRow: View {
    let event: DevelopmentEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.name)
                        .font(.body.monospaced().weight(.medium))
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(event.message)
                if !event.attributes.isEmpty {
                    Text(
                        event.attributes
                            .sorted(by: { $0.key < $1.key })
                            .map { "\($0.key)=\($0.value)" }
                            .joined(separator: "  ")
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var levelColor: Color {
        switch event.level {
        case .debug: .secondary
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
