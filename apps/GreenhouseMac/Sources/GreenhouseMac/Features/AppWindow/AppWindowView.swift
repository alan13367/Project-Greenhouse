import GreenhouseCore
import GreenhouseRuntime
import SwiftUI

struct AppWindowView: View {
    let app: AndroidApp
    let model: GreenhouseAppModel
    let streams: AppStreamRegistry
    let appWindowCoordinator: AppWindowCoordinator

    var body: some View {
        if let session = streams.session(for: app.id) {
            LiveAppWindowView(
                app: app,
                model: model,
                session: session,
                appWindowCoordinator: appWindowCoordinator
            )
        } else {
            FakeAppWindowView(
                app: app,
                model: model,
                appWindowCoordinator: appWindowCoordinator
            )
        }
    }
}

private struct LiveAppWindowView: View {
    let app: AndroidApp
    let model: GreenhouseAppModel
    let session: AppStreamSession
    let appWindowCoordinator: AppWindowCoordinator

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MetalAppSurface(session: session)
                .ignoresSafeArea()

            if let error = session.model.errorMessage {
                StreamErrorBadge(message: error)
                    .padding(12)
            }

            VStack {
                Spacer()
                StreamMetricsOverlay(stream: session.model)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
