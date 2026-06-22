import Foundation

@MainActor
public final class FakeBackend: GreenhouseBackend {
    public struct Configuration: Sendable {
        public let stepDelay: Duration

        public init(stepDelay: Duration = .milliseconds(220)) {
            self.stepDelay = stepDelay
        }

        public static let tests = Configuration(stepDelay: .zero)
    }

    public let events: AsyncStream<DevelopmentEvent>

    private let configuration: Configuration
    private let continuation: AsyncStream<DevelopmentEvent>.Continuation
    private var sequence = 0
    private var runtimeState: RuntimeInstallationState = .missing
    private var vmState: VMLifecycleState = .stopped
    private var androidState: AndroidReadinessState = .unavailable
    private var installedPackageCount = 0
    private var activeAppIDs: Set<AndroidAppID> = []
    private var generation = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let eventStream = AsyncStream<DevelopmentEvent>.makeStream()
        events = eventStream.stream
        continuation = eventStream.continuation
    }

    public func prepareRuntime() async {
        let operationGeneration = generation

        emit(
            name: "runtime.download.started",
            message: "Downloading the managed Android runtime",
            patch: StatePatch(
                runtimeInstallation: .downloading,
                currentOperation: .preparingRuntime(
                    OperationProgress(fractionCompleted: 0, detail: "Starting download")
                )
            )
        )

        for progress in [0.25, 0.60, 1.0] {
            guard await pause(generation: operationGeneration) else { return }
            emit(
                name: "runtime.download.progress",
                message: "Runtime download progressed",
                attributes: ["fractionCompleted": String(progress)],
                patch: StatePatch(
                    currentOperation: .preparingRuntime(
                        OperationProgress(
                            fractionCompleted: progress,
                            detail: progress == 1 ? "Download complete" : "Downloading"
                        )
                    )
                )
            )
        }

        guard await pause(generation: operationGeneration) else { return }
        emit(
            name: "runtime.verification.started",
            message: "Verifying runtime signature and manifest",
            patch: StatePatch(runtimeInstallation: .verifying)
        )

        guard await pause(generation: operationGeneration) else { return }
        emit(
            name: "runtime.installation.started",
            message: "Installing runtime atomically",
            patch: StatePatch(runtimeInstallation: .installing)
        )

        guard await pause(generation: operationGeneration) else { return }
        emit(
            name: "runtime.ready",
            message: "The Android runtime is ready",
            patch: StatePatch(runtimeInstallation: .ready, currentOperation: .idle)
        )
    }

    public func startAndroid() async {
        let operationGeneration = generation

        guard runtimeState == .ready else {
            emitIssue(.missingRuntime, patch: StatePatch(currentOperation: .idle))
            return
        }

        emit(
            name: "vm.starting",
            message: "Starting the managed Android environment",
            patch: StatePatch(
                vmLifecycle: .starting,
                androidReadiness: .booting,
                currentOperation: .startingAndroid
            )
        )

        guard await pause(generation: operationGeneration) else { return }
        emit(
            name: "vm.running",
            message: "The backend is running",
            patch: StatePatch(vmLifecycle: .running, androidReadiness: .connecting)
        )

        guard await pause(generation: operationGeneration) else { return }
        emit(
            name: "android.ready",
            message: "Android is ready for apps",
            patch: StatePatch(
                androidReadiness: .ready,
                googleServices: .signInRequired,
                currentOperation: .idle
            )
        )
    }

    public func requestShutdown() async {
        let operationGeneration = generation

        guard vmState == .running || vmState == .crashed else { return }

        emit(
            name: "vm.stopping",
            message: "Stopping Android safely",
            patch: StatePatch(vmLifecycle: .stopping)
        )
        guard await pause(generation: operationGeneration) else { return }
        closeActiveAppWindows(
            eventName: "app-window.closed",
            message: "Closed app window because Android stopped"
        )
        emit(
            name: "vm.stopped",
            message: "Android stopped",
            patch: StatePatch(
                vmLifecycle: .stopped,
                androidReadiness: .unavailable,
                currentOperation: .idle
            )
        )
    }

    public func installPackage(named displayName: String) async -> AndroidApp? {
        let operationGeneration = generation

        guard androidState == .ready || androidState == .degraded else {
            emitIssue(.androidBootTimeout)
            return nil
        }

        emit(
            name: "package.installation.started",
            message: "Installing a user-provided Android package",
            attributes: ["fileName": displayName],
            patch: StatePatch(
                currentOperation: .installingApp(
                    OperationProgress(fractionCompleted: 0.1, detail: "Reading package")
                )
            )
        )
        guard await pause(generation: operationGeneration) else { return nil }
        emit(
            name: "package.installation.progress",
            message: "Package installation progressed",
            attributes: ["fileName": displayName],
            patch: StatePatch(
                currentOperation: .installingApp(
                    OperationProgress(fractionCompleted: 0.75, detail: "Installing")
                )
            )
        )
        guard await pause(generation: operationGeneration) else { return nil }

        installedPackageCount += 1
        let stem = URL(fileURLWithPath: displayName).deletingPathExtension().lastPathComponent
        let safeName = stem.isEmpty ? "Installed App" : stem
        let app = AndroidApp(
            id: AndroidAppID(rawValue: "local.\(installedPackageCount)"),
            name: safeName,
            packageName: "local.greenhouse.app\(installedPackageCount)",
            symbolName: "shippingbox.fill",
            source: .localPackage
        )

        emit(
            name: "package.installation.completed",
            message: "Package installed",
            attributes: ["packageName": app.packageName],
            patch: StatePatch(currentOperation: .idle)
        )
        return app
    }

    public func openGooglePlay() async -> AndroidApp? {
        let operationGeneration = generation

        guard androidState == .ready || androidState == .degraded else {
            emitIssue(.androidBootTimeout)
            return nil
        }

        emit(
            name: "google.sign-in.started",
            message: "Starting the simulated Google sign-in flow",
            patch: StatePatch(
                googleServices: .initializing,
                currentOperation: .signingInToGoogle
            )
        )
        guard await pause(generation: operationGeneration) else { return nil }
        emit(
            name: "google.services.ready",
            message: "Simulated Google services are ready",
            patch: StatePatch(googleServices: .ready, currentOperation: .idle)
        )
        return .googlePlay
    }

    public func openApp(_ app: AndroidApp) async -> Bool {
        let operationGeneration = generation

        guard androidState == .ready || androidState == .degraded else {
            emitIssue(.androidBootTimeout)
            return false
        }

        emit(
            name: "app-window.display-creating",
            message: "Creating an app-specific display",
            attributes: ["packageName": app.packageName],
            patch: StatePatch(
                currentOperation: .openingAppWindow,
                appWindow: AppWindowPatch(appID: app.id, state: .creatingDisplay)
            )
        )
        guard await pause(generation: operationGeneration) else { return false }
        emit(
            name: "app-window.task-launching",
            message: "Launching Android task",
            attributes: ["packageName": app.packageName],
            patch: StatePatch(
                appWindow: AppWindowPatch(appID: app.id, state: .launchingTask)
            )
        )
        guard await pause(generation: operationGeneration) else { return false }
        emit(
            name: "app-window.visible",
            message: "Android task is visible in its Mac window",
            attributes: ["packageName": app.packageName],
            patch: StatePatch(
                currentOperation: .idle,
                appWindow: AppWindowPatch(appID: app.id, state: .visible)
            )
        )
        return true
    }

    public func closeApp(_ app: AndroidApp) async {
        emit(
            name: "app-window.closed",
            message: "Closed app window",
            attributes: ["packageName": app.packageName],
            patch: StatePatch(appWindow: AppWindowPatch(appID: app.id, state: .closed))
        )
    }

    public func simulate(_ failure: SimulatedFailure) async {
        let operationGeneration = generation

        switch failure {
        case .missingRuntime:
            closeActiveAppWindows(
                eventName: "app-window.closed",
                message: "Closed app window because the runtime is missing"
            )
            emitIssue(
                failure,
                patch: StatePatch(
                    runtimeInstallation: .missing,
                    vmLifecycle: .stopped,
                    androidReadiness: .unavailable,
                    currentOperation: .idle
                )
            )
        case .corruptRuntime:
            emitIssue(
                failure,
                patch: StatePatch(runtimeInstallation: .invalid, currentOperation: .idle)
            )
        case .backendCrash:
            closeActiveAppWindows(
                eventName: "app-window.closed",
                message: "Closed app window because Android stopped unexpectedly"
            )
            emitIssue(
                failure,
                patch: StatePatch(
                    vmLifecycle: .crashed,
                    androidReadiness: .unavailable,
                    currentOperation: .idle
                )
            )
        case .androidBootTimeout:
            emit(
                name: "vm.starting",
                message: "Starting timeout simulation",
                patch: StatePatch(
                    vmLifecycle: .starting,
                    androidReadiness: .booting,
                    currentOperation: .startingAndroid
                )
            )
            guard await pause(generation: operationGeneration) else { return }
            emitIssue(
                failure,
                patch: StatePatch(
                    vmLifecycle: .stopped,
                    androidReadiness: .unavailable,
                    currentOperation: .idle
                )
            )
        case .apkInstallationFailure:
            emit(
                name: "package.installation.started",
                message: "Starting failed package installation simulation",
                patch: StatePatch(
                    currentOperation: .installingApp(
                        OperationProgress(fractionCompleted: 0.35, detail: "Validating package")
                    )
                )
            )
            guard await pause(generation: operationGeneration) else { return }
            emitIssue(failure, patch: StatePatch(currentOperation: .idle))
        case .googleSignInFailure:
            emit(
                name: "google.sign-in.started",
                message: "Starting failed sign-in simulation",
                patch: StatePatch(
                    googleServices: .initializing,
                    currentOperation: .signingInToGoogle
                )
            )
            guard await pause(generation: operationGeneration) else { return }
            emitIssue(
                failure,
                patch: StatePatch(
                    googleServices: .signInRequired,
                    currentOperation: .idle
                )
            )
        case .googlePlayDownloadFailure:
            emit(
                name: "google.play-download.started",
                message: "Starting failed Play download simulation",
                patch: StatePatch(
                    currentOperation: .installingFromPlay(
                        OperationProgress(fractionCompleted: 0.4, detail: "Downloading from Google Play")
                    )
                )
            )
            guard await pause(generation: operationGeneration) else { return }
            emitIssue(failure, patch: StatePatch(currentOperation: .idle))
        case .appWindowCreationFailure:
            let appID = AndroidApp.demoNotes.id
            emit(
                name: "app-window.display-creating",
                message: "Starting failed app-window simulation",
                patch: StatePatch(
                    currentOperation: .openingAppWindow,
                    appWindow: AppWindowPatch(appID: appID, state: .creatingDisplay)
                )
            )
            guard await pause(generation: operationGeneration) else { return }
            emitIssue(
                failure,
                patch: StatePatch(
                    currentOperation: .idle,
                    appWindow: AppWindowPatch(appID: appID, state: .failed)
                )
            )
        case .graphicsUnavailable:
            emitIssue(
                failure,
                patch: StatePatch(androidReadiness: .degraded, currentOperation: .idle)
            )
        case .controllerDisconnection:
            emitIssue(failure)
        case .interruptedDownload:
            emit(
                name: "runtime.download.progress",
                message: "Starting interrupted download simulation",
                patch: StatePatch(
                    runtimeInstallation: .downloading,
                    currentOperation: .preparingRuntime(
                        OperationProgress(fractionCompleted: 0.48, detail: "Downloading")
                    )
                )
            )
            guard await pause(generation: operationGeneration) else { return }
            emitIssue(
                failure,
                patch: StatePatch(
                    runtimeInstallation: .missing,
                    currentOperation: .idle
                )
            )
        }
    }

    public func reset() {
        generation += 1
        runtimeState = .missing
        vmState = .stopped
        androidState = .unavailable
        installedPackageCount = 0
        activeAppIDs = []
        emit(
            name: "backend.reset",
            message: "Reset fake backend state",
            patch: StatePatch(
                runtimeInstallation: .missing,
                vmLifecycle: .stopped,
                androidReadiness: .unavailable,
                googleServices: .notIncluded,
                currentOperation: .idle
            )
        )
    }

    private func pause(generation operationGeneration: Int) async -> Bool {
        do {
            try await Task.sleep(for: configuration.stepDelay)
        } catch {
            return false
        }
        return operationGeneration == generation && !Task.isCancelled
    }

    private func closeActiveAppWindows(eventName: String, message: String) {
        for appID in activeAppIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            emit(
                name: eventName,
                message: message,
                patch: StatePatch(
                    appWindow: AppWindowPatch(appID: appID, state: .closed)
                )
            )
        }
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
            if let appWindow = patch.appWindow {
                switch appWindow.state {
                case .closed, .failed:
                    activeAppIDs.remove(appWindow.appID)
                case .creatingDisplay, .launchingTask, .visible, .backgrounded, .reconnecting:
                    activeAppIDs.insert(appWindow.appID)
                }
            }
        }

        continuation.yield(
            DevelopmentEvent(
                sequence: sequence,
                source: "fake-backend",
                level: level,
                name: name,
                message: message,
                attributes: attributes,
                statePatch: patch,
                issue: issue
            )
        )
    }

    private func emitIssue(_ failure: SimulatedFailure, patch: StatePatch? = nil) {
        let issue = GreenhouseIssue.forSimulation(failure)
        emit(
            level: issue.severity == .warning ? .warning : .error,
            name: issue.code.rawValue,
            message: issue.summary,
            patch: patch,
            issue: issue
        )
    }
}
