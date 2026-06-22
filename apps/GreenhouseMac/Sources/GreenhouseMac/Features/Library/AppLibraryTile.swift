import GreenhouseCore
import SwiftUI

struct AppLibraryTile: View {
    let app: AndroidApp
    let state: AppWindowState
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: app.symbolName)
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Text(state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                Text(app.packageName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button("Open", action: open)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
