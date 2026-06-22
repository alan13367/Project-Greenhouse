import Foundation
import Observation

@MainActor
@Observable
public final class GreenhouseAppModel {
    public private(set) var snapshot = GreenhouseSnapshot()
    public private(set) var apps: [AndroidApp] = []
    public private(set) var issues: [GreenhouseIssue] = []
    public private(set) var events: [DevelopmentEvent] = []

    private let backend: any GreenhouseBackend
    private let logger: RedactingEventLogger
    private var observationTask: Task<Void, Never>?

    public init(
        backend: any GreenhouseBackend,
        logger: RedactingEventLogger = RedactingEventLogger()
    ) {
        self.backend = backend
        self.logger = logger

        let stream = backend.events
        observationTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                consume(event)
            }
        }
    }

    public var latestIssue: GreenhouseIssue? {
        issues.last
    }

    public func prepareRuntime() async {
        await backend.prepareRuntime()
    }

    public func startAndroid() async {
        await backend.startAndroid()
    }

    public func stopAndroid() async {
        await backend.requestShutdown()
    }

    public func installPackage(named displayName: String) async {
        guard let app = await backend.installPackage(named: displayName) else { return }
        upsert(app)
    }

    public func openGooglePlay() async -> AndroidApp? {
        guard let app = await backend.openGooglePlay() else { return nil }
        upsert(app)
        return app
    }

    public func openApp(_ app: AndroidApp) async -> Bool {
        await backend.openApp(app)
    }

    public func closeApp(_ app: AndroidApp) async {
        await backend.closeApp(app)
    }

    public func addDemoApps() {
        upsert(.demoNotes)
        upsert(.demoGame)
    }

    public func simulate(_ failure: SimulatedFailure) async {
        await backend.simulate(failure)
    }

    public func resetFakeBackend() {
        snapshot = GreenhouseSnapshot()
        apps = []
        issues = []
        backend.reset()
    }

    public func clearIssues() {
        issues = []
    }

    public func clearEvents() {
        events = []
    }

    public func app(for id: AndroidAppID) -> AndroidApp? {
        apps.first(where: { $0.id == id })
    }

    public func state(for app: AndroidApp) -> AppWindowState {
        snapshot.appWindows[app.id, default: .closed]
    }

    public var diagnosticsNDJSON: String {
        events.map(\.ndjson).joined(separator: "\n")
    }

    private func upsert(_ app: AndroidApp) {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index] = app
        } else {
            apps.append(app)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func consume(_ event: DevelopmentEvent) {
        let redacted = logger.record(event)
        events.append(redacted)
        if events.count > 500 {
            events.removeFirst(events.count - 500)
        }

        if let patch = redacted.statePatch {
            snapshot.apply(patch)
        }
        if let issue = redacted.issue {
            issues.append(issue)
        }
    }
}
