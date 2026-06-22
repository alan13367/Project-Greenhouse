import GreenhouseCore
import SwiftUI

struct GreenhouseCommands: Commands {
    let model: GreenhouseAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Android") {
            Button("Prepare Android") {
                Task { await model.prepareRuntime() }
            }
            .disabled(model.snapshot.runtimeInstallation == .ready)

            Button("Start Android") {
                Task { await model.startAndroid() }
            }
            .disabled(
                model.snapshot.runtimeInstallation != .ready ||
                model.snapshot.vmLifecycle != .stopped
            )

            Button("Stop Android") {
                Task { await model.stopAndroid() }
            }
            .disabled(model.snapshot.vmLifecycle != .running)

            Divider()

            Button("Add Demo Apps") {
                model.addDemoApps()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appInfo) {
            Button("Advanced Diagnostics…") {
                openWindow(id: "diagnostics")
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }
}
