import Foundation

@MainActor
public protocol GreenhouseBackend: AnyObject {
    var events: AsyncStream<DevelopmentEvent> { get }

    func prepareRuntime() async
    func startAndroid() async
    func requestShutdown() async
    func installPackage(named displayName: String) async -> AndroidApp?
    func openGooglePlay() async -> AndroidApp?
    func openApp(_ app: AndroidApp) async -> Bool
    func closeApp(_ app: AndroidApp) async
    func simulate(_ failure: SimulatedFailure) async
    func reset()
}

public enum SimulatedFailure: String, Codable, CaseIterable, Sendable, Identifiable {
    case missingRuntime
    case corruptRuntime
    case backendCrash
    case androidBootTimeout
    case apkInstallationFailure
    case googleSignInFailure
    case googlePlayDownloadFailure
    case appWindowCreationFailure
    case graphicsUnavailable
    case controllerDisconnection
    case interruptedDownload

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .missingRuntime: "Missing runtime"
        case .corruptRuntime: "Corrupt runtime"
        case .backendCrash: "Backend crash"
        case .androidBootTimeout: "Android boot timeout"
        case .apkInstallationFailure: "APK installation failure"
        case .googleSignInFailure: "Google sign-in failure"
        case .googlePlayDownloadFailure: "Google Play download failure"
        case .appWindowCreationFailure: "App-window creation failure"
        case .graphicsUnavailable: "Graphics unavailable"
        case .controllerDisconnection: "Controller disconnection"
        case .interruptedDownload: "Interrupted download"
        }
    }
}
