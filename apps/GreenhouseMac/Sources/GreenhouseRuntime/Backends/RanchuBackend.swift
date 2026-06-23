import Foundation
import GreenhouseCore

@MainActor
public final class RanchuBackend: GreenhouseBackend {
    public let events: AsyncStream<DevelopmentEvent>

    public let streams: AppStreamRegistry
    private let runtime: RanchuRuntimeController?
    private let continuation: AsyncStream<DevelopmentEvent>.Continuation
    private var sequence = 0
    private var runtimeState: RuntimeInstallationState = .missing
    private var vmState: VMLifecycleState = .stopped
    private var androidState: AndroidReadinessState = .unavailable

    public init(
        sdk: AndroidSDK?,
        configuration: RanchuConfiguration = .development(),
        streams: AppStreamRegistry
    ) {
        self.streams = streams
        if let sdk {
            runtime = RanchuRuntimeController(
                sdk: sdk,
                configuration: configuration
            )
        } else {
            runtime = nil
        }
        let stream = AsyncStream<DevelopmentEvent>.makeStream()
        events = stream.stream
        continuation = stream.continuation
    }

    public func prepareRuntime() async {
        emit(
            name: "runtime.verification.started",
            message: "Verifying the managed ARM64 Android runtime",
            patch: StatePatch(
                runtimeInstallation: .verifying,
                currentOperation: .preparingRuntime(
                    OperationProgress(
                        fractionCompleted: 0.2,
                        detail: "Checking the Android Emulator and runtime image"
                    )
                )
            )
        )
        guard let runtime else {
            fail(
                code: .runtimeMissing,
                summary: "Android runtime tools are missing",
                detail: "The Android Emulator and platform tools were not found.",
                recovery: "Install the Android Emulator and platform tools, then prepare Android again.",
                patch: StatePatch(
                    runtimeInstallation: .missing,
                    currentOperation: .idle
                )
            )
            return
        }
        do {
            try runtime.prepare()
            emit(
                name: "runtime.ready",
                message: "The Ranchu runtime image and persistent userdata are ready",
                attributes: [
                    "virtualHardware": "goldfish-ranchu",
                    "graphics": "gfxstream-moltenvk"
                ],
                patch: StatePatch(
                    runtimeInstallation: .ready,
                    currentOperation: .idle
                )
            )
        } catch {
            fail(
                code: .runtimeMissing,
                summary: "Android runtime is not provisioned",
                detail: error.localizedDescription,
                recovery: "Install or select the managed Ranchu runtime images and try again.",
                patch: StatePatch(
                    runtimeInstallation: .missing,
                    currentOperation: .idle
                )
            )
        }
    }

    public func startAndroid() async {
        guard runtimeState == .ready, let runtime else {
            fail(
                code: .runtimeMissing,
                summary: "Android needs to be prepared",
                detail: "The managed Ranchu runtime is not ready.",
                recovery: "Choose Prepare Android first."
            )
            return
        }
        emit(
            name: "vm.starting",
            message: "Starting Android with HVF and host GPU acceleration",
            patch: StatePatch(
                vmLifecycle: .starting,
                androidReadiness: .booting,
                currentOperation: .startingAndroid
            )
        )
        do {
            let readiness = try await runtime.start()
            emit(
                name: "android.ready",
                message: "Android, graphics, package management, and app windows are ready",
                attributes: [
                    "renderer": readiness.renderer,
                    "vulkanLevel": readiness.vulkanLevel,
                    "vulkanDevice": readiness.vulkanDevice,
                    "adbTransport": "private-localhost",
                    "appWindowAgent": "responsive"
                ],
                patch: StatePatch(
                    vmLifecycle: .running,
                    androidReadiness: .ready,
                    googleServices: .signInRequired,
                    googleServicesProvider: .microG,
                    currentOperation: .idle
                )
            )
        } catch let error as RanchuRuntimeError {
            let graphicsFailure: Bool
            if case .graphicsAccelerationUnavailable = error {
                graphicsFailure = true
            } else {
                graphicsFailure = false
            }
            fail(
                code: graphicsFailure ? .graphicsAccelerationUnavailable : .androidBootTimeout,
                summary: graphicsFailure
                    ? "Accelerated graphics are unavailable"
                    : "Android could not start",
                detail: error.localizedDescription,
                recovery: graphicsFailure
                    ? "Verify that the AVD uses host graphics and MoltenVK."
                    : "Review diagnostics and retry the managed runtime.",
                patch: StatePatch(
                    vmLifecycle: .stopped,
                    androidReadiness: graphicsFailure ? .degraded : .unavailable,
                    currentOperation: .idle
                )
            )
        } catch {
            fail(
                code: .backendCrash,
                summary: "Android could not start",
                detail: error.localizedDescription,
                recovery: "Review diagnostics and retry the managed runtime.",
                patch: StatePatch(
                    vmLifecycle: .stopped,
                    androidReadiness: .unavailable,
                    currentOperation: .idle
                )
            )
        }
    }

    public func requestShutdown() async {
        guard vmState == .running || vmState == .crashed else { return }
        emit(
            name: "vm.stopping",
            message: "Stopping Android safely",
            patch: StatePatch(vmLifecycle: .stopping)
        )
        streams.removeAll()
        if let runtime {
            await runtime.stop()
        }
        emit(
            name: "vm.stopped",
            message: "Android stopped and persistent userdata was preserved",
            patch: StatePatch(
                vmLifecycle: .stopped,
                androidReadiness: .unavailable,
                currentOperation: .idle
            )
        )
    }

    public func installedApps() async -> [AndroidApp] {
        guard androidState == .ready, let runtime else { return [] }
        do {
            return try await runtime.installedThirdPartyPackages().map { packageName in
                AndroidApp(
                    id: AndroidAppID(rawValue: "package.\(packageName)"),
                    name: packageName,
                    packageName: packageName,
                    symbolName: "app.fill",
                    source: .localPackage
                )
            }
        } catch {
            emit(
                level: .warning,
                name: "package.catalog-refresh.failed",
                message: "Installed Android apps could not be refreshed",
                attributes: ["reason": error.localizedDescription]
            )
            return []
        }
    }

    public func installPackage(at url: URL) async -> AndroidApp? {
        guard androidState == .ready, let runtime else {
            fail(
                code: .androidBootTimeout,
                summary: "Android is not ready",
                detail: "Package installation requires a ready Android environment.",
                recovery: "Start Android and try again."
            )
            return nil
        }
        emit(
            name: "package.installation.started",
            message: "Installing an Android package through private ADB",
            attributes: ["fileName": url.lastPathComponent],
            patch: StatePatch(
                currentOperation: .installingApp(
                    OperationProgress(
                        fractionCompleted: 0.25,
                        detail: "Checking and installing the package"
                    )
                )
            )
        )
        do {
            guard let packageName = try await runtime.installPackage(at: url) else {
                throw PackageError.packageNameUnavailable
            }
            let stem = url.deletingPathExtension().lastPathComponent
            let app = AndroidApp(
                id: AndroidAppID(rawValue: "package.\(packageName)"),
                name: stem.isEmpty ? packageName : stem,
                packageName: packageName,
                symbolName: "shippingbox.fill",
                source: .localPackage
            )
            emit(
                name: "package.installation.completed",
                message: "Android package installed",
                attributes: ["packageName": packageName],
                patch: StatePatch(currentOperation: .idle)
            )
            return app
        } catch {
            fail(
                code: .apkInstallationFailed,
                summary: "Package could not be installed",
                detail: error.localizedDescription,
                recovery: "Verify that the package contains an ARM64 or universal app.",
                patch: StatePatch(currentOperation: .idle)
            )
            return nil
        }
    }

    public func openGoogleServices() async -> AndroidApp? {
        guard androidState == .ready else { return nil }
        return .microGSettings
    }

    public func openCommunityStore() async -> AndroidApp? {
        guard androidState == .ready else { return nil }
        return .fDroid
    }

    public func openApp(_ app: AndroidApp) async -> Bool {
        guard androidState == .ready, let runtime else {
            return false
        }
        emit(
            name: "app-window.display-creating",
            message: "Creating a trusted app-specific Android display",
            attributes: ["packageName": app.packageName],
            patch: StatePatch(
                currentOperation: .openingAppWindow,
                appWindow: AppWindowPatch(
                    appID: app.id,
                    state: .creatingDisplay
                )
            )
        )

        if let existing = streams.session(for: app.id) {
            streams.removeSession(for: app.id)
            await runtime.removeAgentForward(localPort: existing.localPort)
        }
        let streamID = streams.reserveStreamID()
        let localPort = runtime.configuration.firstAgentForwardPort + Int(streamID)
        do {
            try await runtime.prepareAgentForward(localPort: localPort)
            let session = AppStreamSession(
                app: app,
                streamID: streamID,
                localPort: localPort
            )
            streams.register(session, for: app.id)
            emit(
                name: "app-window.task-launching",
                message: "Launching the Android task on its dedicated display",
                attributes: ["packageName": app.packageName],
                patch: StatePatch(
                    appWindow: AppWindowPatch(
                        appID: app.id,
                        state: .launchingTask
                    )
                )
            )
            try await session.start()
            emit(
                name: "app-window.visible",
                message: "The encoded Android display is attached to a Metal window",
                attributes: [
                    "packageName": app.packageName,
                    "streamID": String(streamID)
                ],
                patch: StatePatch(
                    currentOperation: .idle,
                    appWindow: AppWindowPatch(appID: app.id, state: .visible)
                )
            )
            return true
        } catch {
            streams.removeSession(for: app.id)
            await runtime.removeAgentForward(localPort: localPort)
            fail(
                code: .appWindowCreationFailed,
                summary: "App window could not be created",
                detail: error.localizedDescription,
                recovery: "Close the app and try opening it again.",
                patch: StatePatch(
                    currentOperation: .idle,
                    appWindow: AppWindowPatch(appID: app.id, state: .failed)
                )
            )
            return false
        }
    }

    public func closeApp(_ app: AndroidApp) async {
        guard let session = streams.session(for: app.id) else { return }
        let localPort = session.localPort
        streams.removeSession(for: app.id)
        if let runtime {
            await runtime.removeAgentForward(localPort: localPort)
        }
        emit(
            name: "app-window.closed",
            message: "Closed the app display without stopping Android",
            attributes: ["packageName": app.packageName],
            patch: StatePatch(
                appWindow: AppWindowPatch(appID: app.id, state: .closed)
            )
        )
    }

    public func simulate(_ failure: SimulatedFailure) async {
        fail(
            code: GreenhouseIssue.forSimulation(failure).code,
            summary: GreenhouseIssue.forSimulation(failure).summary,
            detail: "Simulation is only supported by the fake backend.",
            recovery: "Run Greenhouse with GREENHOUSE_BACKEND=fake for deterministic scenarios."
        )
    }

    public func reset() {
        streams.removeAll()
        if let runtime {
            Task { await runtime.stop() }
        }
        runtimeState = .missing
        vmState = .stopped
        androidState = .unavailable
        emit(
            name: "backend.reset",
            message: "Reset Ranchu backend state",
            patch: StatePatch(
                runtimeInstallation: .missing,
                vmLifecycle: .stopped,
                androidReadiness: .unavailable,
                googleServices: .notIncluded,
                googleServicesProvider: GoogleServicesProvider.none,
                currentOperation: .idle
            )
        )
    }

    private func fail(
        code: IssueCode,
        summary: String,
        detail: String,
        recovery: String,
        patch: StatePatch? = nil
    ) {
        let issue = GreenhouseIssue(
            code: code,
            summary: summary,
            detail: detail,
            recoverySuggestion: recovery
        )
        emit(
            level: .error,
            name: code.rawValue,
            message: summary,
            patch: patch,
            issue: issue
        )
    }

    private func emit(
        level: EventLevel = .info,
        name: String,
        message: String,
        attributes: [String: String] = [:],
        patch: StatePatch? = nil,
        issue: GreenhouseIssue? = nil
    ) {
        sequence += 1
        if let patch {
            if let runtimeInstallation = patch.runtimeInstallation {
                runtimeState = runtimeInstallation
            }
            if let vmLifecycle = patch.vmLifecycle {
                vmState = vmLifecycle
            }
            if let androidReadiness = patch.androidReadiness {
                androidState = androidReadiness
            }
        }
        continuation.yield(
            DevelopmentEvent(
                sequence: sequence,
                source: "ranchu-backend",
                level: level,
                name: name,
                message: message,
                attributes: attributes,
                statePatch: patch,
                issue: issue
            )
        )
    }

    private enum PackageError: Error, LocalizedError {
        case packageNameUnavailable

        var errorDescription: String? {
            "ADB installed the package but its application ID could not be identified."
        }
    }
}
