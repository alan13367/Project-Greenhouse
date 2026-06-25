import GreenhouseCore
import SwiftUI

struct FakeAppWindowView: View {
    let app: AndroidApp
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator
    @Binding var controlsCollapsed: Bool
    @Binding var metricsVisible: Bool
    let focus: () -> Void
    let reconnect: () -> Void
    let toggleFullScreen: () -> Void
    let closeWindow: () -> Void

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    Image(systemName: app.symbolName)
                        .font(.system(size: 58))
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 6) {
                        Text(app.name)
                            .font(.largeTitle.weight(.semibold))
                        Text("Fake Android task surface")
                            .font(.headline)
                        Text(app.packageName)
                            .font(.caption.monospaced())
                            .opacity(0.75)
                    }

                    Divider()
                        .frame(maxWidth: 340)

                    HStack(spacing: 24) {
                        Label("Keyboard", systemImage: "keyboard")
                        Label("Pointer", systemImage: "cursorarrow.motionlines")
                        Label("Controller", systemImage: "gamecontroller")
                    }
                    .font(.caption)

                    Text("Window state: \(model.state(for: app).title)")
                        .font(.caption)
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(40)

                if metricsVisible {
                    FakeWindowMetricsOverlay(app: app, state: model.state(for: app))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if controlsCollapsed {
                    CollapsedAppWindowControlsButton(isCollapsed: $controlsCollapsed)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !controlsCollapsed {
                AppWindowControlsRail(
                    app: app,
                    session: nil,
                    canReconnect: model.snapshot.androidReadiness == .ready,
                    isCollapsed: $controlsCollapsed,
                    metricsVisible: $metricsVisible,
                    focus: focus,
                    reconnect: reconnect,
                    toggleFullScreen: toggleFullScreen,
                    close: closeWindow
                )
            }
        }
        .navigationTitle(app.name)
        .background {
            AppWindowRegistrationView(
                appID: app.id,
                coordinator: appWindowCoordinator
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: model.snapshot.vmLifecycle) { _, lifecycle in
            if lifecycle == .stopped || lifecycle == .crashed {
                dismissWindow(value: app.id)
            }
        }
        .onDisappear {
            Task { await model.closeApp(app) }
        }
    }

    private var gradientColors: [Color] {
        switch app.source {
        case .demo: [.indigo, .mint]
        case .communityStore: [.blue, .mint]
        case .systemService: [.green, .teal]
        case .localPackage: [.purple, .orange]
        }
    }
}

private struct FakeWindowMetricsOverlay: View {
    let app: AndroidApp
    let state: AppWindowState

    var body: some View {
        HStack(spacing: 10) {
            metric(title: "Surface", value: "Fake")
            metric(title: "State", value: state.title)
            metric(title: "Package", value: app.packageName)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }

    private func metric(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}
