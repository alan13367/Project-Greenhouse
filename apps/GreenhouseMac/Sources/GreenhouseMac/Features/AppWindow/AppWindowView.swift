import GreenhouseCore
import GreenhouseRuntime
import SwiftUI

struct AppWindowView: View {
    let app: AndroidApp
    let model: GreenhouseAppModel
    let streams: AppStreamRegistry
    let appWindowCoordinator: AppWindowCoordinator

    @Environment(\.dismissWindow) private var dismissWindow
    @SceneStorage("greenhouse.appWindow.controlsCollapsed") private var controlsCollapsed = false
    @SceneStorage("greenhouse.appWindow.metricsVisible") private var metricsVisible = true

    var body: some View {
        if let session = streams.session(for: app.id) {
            LiveAppWindowView(
                app: app,
                model: model,
                session: session,
                appWindowCoordinator: appWindowCoordinator,
                controlsCollapsed: $controlsCollapsed,
                metricsVisible: $metricsVisible,
                focus: {
                    _ = appWindowCoordinator.focusWindow(for: app.id)
                    session.focus()
                },
                reconnect: reconnect,
                toggleFullScreen: {
                    appWindowCoordinator.toggleFullScreen(for: app.id)
                },
                closeWindow: {
                    dismissWindow(value: app.id)
                }
            )
        } else {
            FakeAppWindowView(
                app: app,
                model: model,
                appWindowCoordinator: appWindowCoordinator,
                controlsCollapsed: $controlsCollapsed,
                metricsVisible: $metricsVisible,
                focus: {
                    _ = appWindowCoordinator.focusWindow(for: app.id)
                },
                reconnect: reconnect,
                toggleFullScreen: {
                    appWindowCoordinator.toggleFullScreen(for: app.id)
                },
                closeWindow: {
                    dismissWindow(value: app.id)
                }
            )
        }
    }

    private func reconnect() {
        Task {
            _ = await model.openApp(app)
        }
    }
}

private struct LiveAppWindowView: View {
    let app: AndroidApp
    let model: GreenhouseAppModel
    let session: AppStreamSession
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
                MetalAppSurface(session: session)
                    .ignoresSafeArea()

                if let error = session.model.errorMessage {
                    StreamErrorBadge(message: error)
                        .padding(.top, 12)
                        .padding(.trailing, controlsCollapsed ? 62 : 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if metricsVisible {
                    StreamMetricsOverlay(stream: session.model)
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
                    session: session,
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
        .modifier(
            AppWindowLifecycleModifier(
                app: app,
                model: model,
                dismissWindow: dismissWindow
            )
        )
    }
}

private struct StreamMetricsOverlay: View {
    let stream: AppStreamModel

    var body: some View {
        HStack(spacing: 10) {
            metric(
                title: "FPS",
                value: stream.measuredFramesPerSecond.formatted(
                    .number.precision(.fractionLength(1))
                )
            )
            metric(
                title: "Frame jitter",
                value: milliseconds(stream.frameJitterMilliseconds)
            )
            metric(
                title: "Decode p95",
                value: milliseconds(stream.decodeLatencyMilliseconds)
            )
            metric(
                title: "Present p95",
                value: milliseconds(stream.presentationLatencyMilliseconds)
            )
            metric(
                title: "Audio p95",
                value: milliseconds(stream.audioLatencyMilliseconds)
            )
            metric(
                title: "Control RTT",
                value: milliseconds(stream.controlRoundTripMilliseconds)
            )
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

    private func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1))) + " ms"
    }
}

private struct StreamErrorBadge: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }
}

private struct AppWindowLifecycleModifier: ViewModifier {
    let app: AndroidApp
    let model: GreenhouseAppModel
    let dismissWindow: DismissWindowAction

    func body(content: Content) -> some View {
        content
            .onChange(of: model.snapshot.vmLifecycle) { _, lifecycle in
                if lifecycle == .stopped || lifecycle == .crashed {
                    dismissWindow(value: app.id)
                }
            }
            .onDisappear {
                Task { await model.closeApp(app) }
            }
    }
}
