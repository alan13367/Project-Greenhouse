import AppKit
import GreenhouseCore
import SwiftUI

@MainActor
final class AppWindowCoordinator {
    private final class WindowReference {
        weak var window: NSWindow?

        init(_ window: NSWindow) {
            self.window = window
        }
    }

    private var windows: [AndroidAppID: WindowReference] = [:]
    private var pendingAppIDs: Set<AndroidAppID> = []

    func presentWindow(for appID: AndroidAppID, open: () -> Void) {
        if focusWindow(for: appID) {
            return
        }
        guard pendingAppIDs.insert(appID).inserted else {
            return
        }

        open()

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.pendingAppIDs.remove(appID)
        }
    }

    @discardableResult
    func focusWindow(for appID: AndroidAppID) -> Bool {
        guard let window = windows[appID]?.window else {
            windows.removeValue(forKey: appID)
            return false
        }
        guard window.isVisible || window.isMiniaturized else {
            windows.removeValue(forKey: appID)
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func register(_ window: NSWindow, for appID: AndroidAppID) {
        windows[appID] = WindowReference(window)
        pendingAppIDs.remove(appID)
    }

    func unregister(_ window: NSWindow, for appID: AndroidAppID) {
        guard windows[appID]?.window === window else {
            return
        }
        windows.removeValue(forKey: appID)
    }
}

struct AppWindowRegistrationView: NSViewRepresentable {
    let appID: AndroidAppID
    let coordinator: AppWindowCoordinator

    func makeNSView(context: Context) -> AppWindowRegistrationNSView {
        AppWindowRegistrationNSView(appID: appID, coordinator: coordinator)
    }

    func updateNSView(_ nsView: AppWindowRegistrationNSView, context: Context) {}

    static func dismantleNSView(
        _ nsView: AppWindowRegistrationNSView,
        coordinator: ()
    ) {
        nsView.stopTracking()
    }
}

final class AppWindowRegistrationNSView: NSView {
    private let appID: AndroidAppID
    private let appWindowCoordinator: AppWindowCoordinator
    private weak var registeredWindow: NSWindow?

    init(appID: AndroidAppID, coordinator: AppWindowCoordinator) {
        self.appID = appID
        appWindowCoordinator = coordinator
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let registeredWindow, registeredWindow !== window {
            appWindowCoordinator.unregister(registeredWindow, for: appID)
        }
        registeredWindow = window
        if let window {
            appWindowCoordinator.register(window, for: appID)
        }
    }

    func stopTracking() {
        if let registeredWindow {
            appWindowCoordinator.unregister(registeredWindow, for: appID)
        }
        registeredWindow = nil
    }
}
