import Foundation

public enum IssueSeverity: String, Codable, Sendable {
    case notice
    case warning
    case error
}

public enum IssueCode: String, Codable, CaseIterable, Sendable {
    case runtimeMissing = "runtime.missing"
    case runtimeCorrupt = "runtime.corrupt"
    case backendCrash = "backend.crash"
    case androidBootTimeout = "android.boot-timeout"
    case apkInstallationFailed = "package.installation-failed"
    case googleSignInFailed = "google.sign-in-failed"
    case communityStoreDownloadFailed = "community-store.download-failed"
    case appWindowCreationFailed = "window.creation-failed"
    case graphicsAccelerationUnavailable = "graphics.acceleration-unavailable"
    case controllerDisconnected = "controller.disconnected"
    case downloadInterrupted = "runtime.download-interrupted"
}

public struct GreenhouseIssue: Error, Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let code: IssueCode
    public let severity: IssueSeverity
    public let summary: String
    public let detail: String
    public let recoveryAction: String

    public init(
        id: UUID = UUID(),
        code: IssueCode,
        severity: IssueSeverity = .error,
        summary: String,
        detail: String,
        recoverySuggestion: String
    ) {
        self.id = id
        self.code = code
        self.severity = severity
        self.summary = summary
        self.detail = detail
        recoveryAction = recoverySuggestion
    }
}

extension GreenhouseIssue: LocalizedError {
    public var errorDescription: String? { summary }
    public var failureReason: String? { detail }
    public var recoverySuggestion: String? { recoveryAction }
}

public extension GreenhouseIssue {
    static func forSimulation(_ failure: SimulatedFailure) -> GreenhouseIssue {
        switch failure {
        case .missingRuntime:
            return GreenhouseIssue(
                code: .runtimeMissing,
                summary: "Android needs to be prepared",
                detail: "The managed Android runtime is not installed.",
                recoverySuggestion: "Choose Prepare Android to download and verify it."
            )
        case .corruptRuntime:
            return GreenhouseIssue(
                code: .runtimeCorrupt,
                summary: "Android runtime needs repair",
                detail: "The installed runtime did not pass integrity verification.",
                recoverySuggestion: "Repair the runtime before opening apps."
            )
        case .backendCrash:
            return GreenhouseIssue(
                code: .backendCrash,
                summary: "Android stopped unexpectedly",
                detail: "The backend exited while Android was running.",
                recoverySuggestion: "Restart Android. Export diagnostics if this repeats."
            )
        case .androidBootTimeout:
            return GreenhouseIssue(
                code: .androidBootTimeout,
                summary: "Android took too long to start",
                detail: "The guest did not report readiness before the boot deadline.",
                recoverySuggestion: "Try again or open diagnostics to inspect the boot events."
            )
        case .apkInstallationFailure:
            return GreenhouseIssue(
                code: .apkInstallationFailed,
                summary: "Package could not be installed",
                detail: "The simulated package installer rejected the selected package.",
                recoverySuggestion: "Check that the package contains an ARM64 or universal Android app."
            )
        case .googleSignInFailure:
            return GreenhouseIssue(
                code: .googleSignInFailed,
                summary: "Google sign-in did not complete",
                detail: "The simulated Google account flow returned an error.",
                recoverySuggestion: "Try signing in again and verify network access."
            )
        case .communityStoreDownloadFailure:
            return GreenhouseIssue(
                code: .communityStoreDownloadFailed,
                summary: "F-Droid download failed",
                detail: "The simulated community-store download stopped before installation.",
                recoverySuggestion: "Retry the download."
            )
        case .appWindowCreationFailure:
            return GreenhouseIssue(
                code: .appWindowCreationFailed,
                summary: "App window could not be created",
                detail: "The backend could not create a display for the Android task.",
                recoverySuggestion: "Close the app and try opening it again."
            )
        case .graphicsUnavailable:
            return GreenhouseIssue(
                code: .graphicsAccelerationUnavailable,
                summary: "Graphics acceleration is unavailable",
                detail: "Android is running with a degraded graphics path.",
                recoverySuggestion: "Some games may not run. Review graphics diagnostics."
            )
        case .controllerDisconnection:
            return GreenhouseIssue(
                code: .controllerDisconnected,
                severity: .warning,
                summary: "Game controller disconnected",
                detail: "The active controller is no longer available.",
                recoverySuggestion: "Reconnect the controller or continue with keyboard input."
            )
        case .interruptedDownload:
            return GreenhouseIssue(
                code: .downloadInterrupted,
                summary: "Runtime download was interrupted",
                detail: "The partial runtime was discarded safely.",
                recoverySuggestion: "Choose Prepare Android to resume with a fresh verified download."
            )
        }
    }
}
