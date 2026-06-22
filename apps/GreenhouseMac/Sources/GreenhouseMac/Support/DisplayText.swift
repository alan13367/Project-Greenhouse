import GreenhouseCore

extension RuntimeInstallationState {
    var title: String {
        switch self {
        case .missing: "Not installed"
        case .downloading: "Downloading"
        case .verifying: "Verifying"
        case .installing: "Installing"
        case .ready: "Ready"
        case .invalid: "Needs repair"
        case .repairing: "Repairing"
        case .updating: "Updating"
        }
    }
}

extension VMLifecycleState {
    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .crashed: "Stopped unexpectedly"
        }
    }
}

extension AndroidReadinessState {
    var title: String {
        switch self {
        case .unavailable: "Unavailable"
        case .booting: "Booting"
        case .connecting: "Connecting"
        case .ready: "Ready"
        case .degraded: "Degraded"
        }
    }
}

extension AppWindowState {
    var title: String {
        switch self {
        case .closed: "Closed"
        case .creatingDisplay: "Creating display"
        case .launchingTask: "Launching"
        case .visible: "Open"
        case .backgrounded: "Background"
        case .reconnecting: "Reconnecting"
        case .failed: "Failed"
        }
    }
}

extension CurrentOperation {
    var title: String {
        switch self {
        case .idle: "Idle"
        case .preparingRuntime: "Preparing Android"
        case .startingAndroid: "Starting Android"
        case .signingInToGoogle: "Signing in to Google"
        case .installingFromPlay: "Installing from Google Play"
        case .installingApp: "Installing package"
        case .openingAppWindow: "Opening app window"
        case .updatingRuntime: "Updating Android"
        case .repairingRuntime: "Repairing Android"
        case .exportingDiagnostics: "Exporting diagnostics"
        }
    }

    var progress: OperationProgress? {
        switch self {
        case let .preparingRuntime(progress),
             let .installingFromPlay(progress),
             let .installingApp(progress),
             let .updatingRuntime(progress),
             let .repairingRuntime(progress):
            progress
        default:
            nil
        }
    }
}
