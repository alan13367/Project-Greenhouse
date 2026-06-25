import GreenhouseCore
import SwiftUI

struct AppLibraryTile: View {
    let app: AndroidApp
    let state: AppWindowState
    let canOpen: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: app.symbolName)
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(app.source.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                AppStatePill(state: state)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.packageName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Button(state == .visible ? "Focus" : "Open", action: open)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canOpen)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(state == .visible ? "Focus" : "Open", action: open)
                .disabled(!canOpen)
            Text(app.packageName)
        }
    }
}

private struct AppStatePill: View {
    let state: AppWindowState

    var body: some View {
        Text(state.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stateColor.opacity(0.14), in: Capsule())
            .foregroundStyle(stateColor)
    }

    private var stateColor: Color {
        switch state {
        case .visible: .green
        case .creatingDisplay, .launchingTask, .reconnecting: .blue
        case .failed: .red
        case .backgrounded: .orange
        case .closed: .secondary
        }
    }
}
