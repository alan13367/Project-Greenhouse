import Foundation

public struct OperationProgress: Codable, Equatable, Sendable {
    public let fractionCompleted: Double
    public let detail: String

    public init(fractionCompleted: Double, detail: String) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.detail = detail
    }
}

public enum RuntimeInstallationState: String, Codable, CaseIterable, Sendable {
    case missing
    case downloading
    case verifying
    case installing
    case ready
    case invalid
    case repairing
    case updating
}

public enum VMLifecycleState: String, Codable, CaseIterable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case crashed
}

public enum AndroidReadinessState: String, Codable, CaseIterable, Sendable {
    case unavailable
    case booting
    case connecting
    case ready
    case degraded
}

public enum GoogleServicesState: String, Codable, CaseIterable, Sendable {
    case notIncluded
    case initializing
    case signInRequired
    case ready
    case certificationError
    case unavailable
}

public enum GoogleServicesProvider: String, Codable, CaseIterable, Sendable {
    case none
    case microG
    case licensedGMS
}

public enum AppWindowState: String, Codable, CaseIterable, Sendable {
    case closed
    case creatingDisplay
    case launchingTask
    case visible
    case backgrounded
    case reconnecting
    case failed
}

public enum CurrentOperation: Codable, Equatable, Sendable {
    case idle
    case preparingRuntime(OperationProgress)
    case startingAndroid
    case signingInToGoogle
    case installingFromCommunityStore(OperationProgress)
    case installingApp(OperationProgress)
    case openingAppWindow
    case updatingRuntime(OperationProgress)
    case repairingRuntime(OperationProgress)
    case exportingDiagnostics

    private enum CodingKeys: String, CodingKey {
        case kind
        case progress
    }

    private enum Kind: String, Codable {
        case idle
        case preparingRuntime
        case startingAndroid
        case signingInToGoogle
        case installingFromCommunityStore
        case installingApp
        case openingAppWindow
        case updatingRuntime
        case repairingRuntime
        case exportingDiagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .idle:
            self = .idle
        case .preparingRuntime:
            self = .preparingRuntime(try container.decode(OperationProgress.self, forKey: .progress))
        case .startingAndroid:
            self = .startingAndroid
        case .signingInToGoogle:
            self = .signingInToGoogle
        case .installingFromCommunityStore:
            self = .installingFromCommunityStore(
                try container.decode(OperationProgress.self, forKey: .progress)
            )
        case .installingApp:
            self = .installingApp(try container.decode(OperationProgress.self, forKey: .progress))
        case .openingAppWindow:
            self = .openingAppWindow
        case .updatingRuntime:
            self = .updatingRuntime(try container.decode(OperationProgress.self, forKey: .progress))
        case .repairingRuntime:
            self = .repairingRuntime(try container.decode(OperationProgress.self, forKey: .progress))
        case .exportingDiagnostics:
            self = .exportingDiagnostics
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case let .preparingRuntime(progress):
            try container.encode(Kind.preparingRuntime, forKey: .kind)
            try container.encode(progress, forKey: .progress)
        case .startingAndroid:
            try container.encode(Kind.startingAndroid, forKey: .kind)
        case .signingInToGoogle:
            try container.encode(Kind.signingInToGoogle, forKey: .kind)
        case let .installingFromCommunityStore(progress):
            try container.encode(Kind.installingFromCommunityStore, forKey: .kind)
            try container.encode(progress, forKey: .progress)
        case let .installingApp(progress):
            try container.encode(Kind.installingApp, forKey: .kind)
            try container.encode(progress, forKey: .progress)
        case .openingAppWindow:
            try container.encode(Kind.openingAppWindow, forKey: .kind)
        case let .updatingRuntime(progress):
            try container.encode(Kind.updatingRuntime, forKey: .kind)
            try container.encode(progress, forKey: .progress)
        case let .repairingRuntime(progress):
            try container.encode(Kind.repairingRuntime, forKey: .kind)
            try container.encode(progress, forKey: .progress)
        case .exportingDiagnostics:
            try container.encode(Kind.exportingDiagnostics, forKey: .kind)
        }
    }
}

public struct AndroidAppID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: String

    public var id: AndroidAppID { self }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AndroidApp: Identifiable, Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case demo
        case communityStore
        case systemService
        case localPackage
    }

    public let id: AndroidAppID
    public let name: String
    public let packageName: String
    public let symbolName: String
    public let source: Source

    public init(
        id: AndroidAppID,
        name: String,
        packageName: String,
        symbolName: String,
        source: Source
    ) {
        self.id = id
        self.name = name
        self.packageName = packageName
        self.symbolName = symbolName
        self.source = source
    }

    public static let demoNotes = AndroidApp(
        id: AndroidAppID(rawValue: "demo.notes"),
        name: "Pocket Notes",
        packageName: "dev.greenhouse.demo.notes",
        symbolName: "note.text",
        source: .demo
    )

    public static let demoGame = AndroidApp(
        id: AndroidAppID(rawValue: "demo.game"),
        name: "Orbit Runner",
        packageName: "dev.greenhouse.demo.game",
        symbolName: "gamecontroller.fill",
        source: .demo
    )

    public static let microGSettings = AndroidApp(
        id: AndroidAppID(rawValue: "system.microg-settings"),
        name: "microG Services",
        packageName: "com.google.android.gms",
        symbolName: "person.crop.circle.badge.checkmark",
        source: .systemService
    )

    public static let fDroid = AndroidApp(
        id: AndroidAppID(rawValue: "store.fdroid"),
        name: "F-Droid",
        packageName: "org.fdroid.fdroid",
        symbolName: "shippingbox.circle.fill",
        source: .communityStore
    )
}

public struct GreenhouseSnapshot: Codable, Equatable, Sendable {
    public var runtimeInstallation: RuntimeInstallationState
    public var vmLifecycle: VMLifecycleState
    public var androidReadiness: AndroidReadinessState
    public var googleServices: GoogleServicesState
    public var googleServicesProvider: GoogleServicesProvider
    public var currentOperation: CurrentOperation
    public var appWindows: [AndroidAppID: AppWindowState]

    public init(
        runtimeInstallation: RuntimeInstallationState = .missing,
        vmLifecycle: VMLifecycleState = .stopped,
        androidReadiness: AndroidReadinessState = .unavailable,
        googleServices: GoogleServicesState = .notIncluded,
        googleServicesProvider: GoogleServicesProvider = .none,
        currentOperation: CurrentOperation = .idle,
        appWindows: [AndroidAppID: AppWindowState] = [:]
    ) {
        self.runtimeInstallation = runtimeInstallation
        self.vmLifecycle = vmLifecycle
        self.androidReadiness = androidReadiness
        self.googleServices = googleServices
        self.googleServicesProvider = googleServicesProvider
        self.currentOperation = currentOperation
        self.appWindows = appWindows
    }
}

public struct AppWindowPatch: Codable, Equatable, Sendable {
    public let appID: AndroidAppID
    public let state: AppWindowState

    public init(appID: AndroidAppID, state: AppWindowState) {
        self.appID = appID
        self.state = state
    }
}

public struct StatePatch: Codable, Equatable, Sendable {
    public var runtimeInstallation: RuntimeInstallationState?
    public var vmLifecycle: VMLifecycleState?
    public var androidReadiness: AndroidReadinessState?
    public var googleServices: GoogleServicesState?
    public var googleServicesProvider: GoogleServicesProvider?
    public var currentOperation: CurrentOperation?
    public var appWindow: AppWindowPatch?

    public init(
        runtimeInstallation: RuntimeInstallationState? = nil,
        vmLifecycle: VMLifecycleState? = nil,
        androidReadiness: AndroidReadinessState? = nil,
        googleServices: GoogleServicesState? = nil,
        googleServicesProvider: GoogleServicesProvider? = nil,
        currentOperation: CurrentOperation? = nil,
        appWindow: AppWindowPatch? = nil
    ) {
        self.runtimeInstallation = runtimeInstallation
        self.vmLifecycle = vmLifecycle
        self.androidReadiness = androidReadiness
        self.googleServices = googleServices
        self.googleServicesProvider = googleServicesProvider
        self.currentOperation = currentOperation
        self.appWindow = appWindow
    }
}

public extension GreenhouseSnapshot {
    mutating func apply(_ patch: StatePatch) {
        if let runtimeInstallation = patch.runtimeInstallation {
            self.runtimeInstallation = runtimeInstallation
        }
        if let vmLifecycle = patch.vmLifecycle {
            self.vmLifecycle = vmLifecycle
        }
        if let androidReadiness = patch.androidReadiness {
            self.androidReadiness = androidReadiness
        }
        if let googleServices = patch.googleServices {
            self.googleServices = googleServices
        }
        if let googleServicesProvider = patch.googleServicesProvider {
            self.googleServicesProvider = googleServicesProvider
        }
        if let currentOperation = patch.currentOperation {
            self.currentOperation = currentOperation
        }
        if let appWindow = patch.appWindow {
            appWindows[appWindow.appID] = appWindow.state
        }
    }
}
