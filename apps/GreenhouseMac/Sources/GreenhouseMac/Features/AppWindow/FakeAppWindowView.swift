import GreenhouseCore
import SwiftUI

struct FakeAppWindowView: View {
    let app: AndroidApp
    let model: GreenhouseAppModel
    let appWindowCoordinator: AppWindowCoordinator

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
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
