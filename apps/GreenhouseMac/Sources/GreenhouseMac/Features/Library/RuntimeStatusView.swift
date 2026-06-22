import GreenhouseCore
import SwiftUI

struct RuntimeStatusView: View {
    let model: GreenhouseAppModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: statusSymbol)
                .font(.system(size: 26))
                .foregroundStyle(statusColor)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusDetail)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            action
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var action: some View {
        switch (model.snapshot.runtimeInstallation, model.snapshot.vmLifecycle) {
        case (.ready, .stopped), (.ready, .crashed):
            Button("Start Android") {
                Task { await model.startAndroid() }
            }
            .buttonStyle(.borderedProminent)
        case (.ready, .running):
            Button("Stop") {
                Task { await model.stopAndroid() }
            }
        case (.downloading, _), (.verifying, _), (.installing, _), (.repairing, _), (.updating, _):
            EmptyView()
        default:
            Button("Prepare Android") {
                Task { await model.prepareRuntime() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statusTitle: String {
        if model.snapshot.androidReadiness == .ready {
            return "Android is ready"
        }
        if model.snapshot.androidReadiness == .degraded {
            return "Android is running with limited capabilities"
        }
        if model.snapshot.vmLifecycle == .starting {
            return "Android is starting"
        }
        if model.snapshot.runtimeInstallation == .ready {
            return "Android is prepared"
        }
        return "Prepare Android to begin"
    }

    private var statusDetail: String {
        switch model.snapshot.androidReadiness {
        case .ready:
            "Install a package, open Google Play, or launch an app."
        case .degraded:
            "Apps may open, but graphics or another service needs attention."
        case .booting, .connecting:
            "Greenhouse is waiting for the managed environment to become ready."
        case .unavailable:
            model.snapshot.runtimeInstallation == .ready
                ? "The runtime is installed and currently stopped."
                : "Greenhouse will download, verify, and install its managed runtime."
        }
    }

    private var statusSymbol: String {
        switch model.snapshot.androidReadiness {
        case .ready: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .booting, .connecting: "hourglass.circle.fill"
        case .unavailable: "leaf.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.snapshot.androidReadiness {
        case .ready: .green
        case .degraded: .orange
        case .booting, .connecting: .blue
        case .unavailable: .accentColor
        }
    }
}
