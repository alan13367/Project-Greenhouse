import AppKit
import GreenhouseCore
import SwiftUI

@main
struct GreenhouseMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = GreenhouseAppModel(backend: FakeBackend())
    @State private var appWindowCoordinator = AppWindowCoordinator()

    var body: some Scene {
        WindowGroup("Greenhouse", id: "library") {
            LibraryRootView(
                model: model,
                appWindowCoordinator: appWindowCoordinator
            )
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            GreenhouseCommands(model: model)
        }

        WindowGroup("Android App", for: AndroidAppID.self) { $appID in
            if let appID, let app = model.app(for: appID) {
                FakeAppWindowView(
                    app: app,
                    model: model,
                    appWindowCoordinator: appWindowCoordinator
                )
            } else {
                ContentUnavailableView(
                    "App unavailable",
                    systemImage: "app.dashed",
                    description: Text("Return to the library and open the app again.")
                )
            }
        }
        .defaultSize(width: 720, height: 560)

        Window("Advanced Diagnostics", id: "diagnostics") {
            DiagnosticsView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 920, height: 680)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
