import GreenhouseCore
import Observation

@MainActor
@Observable
public final class AppStreamRegistry {
    private var sessions: [AndroidAppID: AppStreamSession] = [:]
    private var nextStreamID: UInt32 = 1

    public init() {}

    public func session(for appID: AndroidAppID) -> AppStreamSession? {
        sessions[appID]
    }

    func reserveStreamID() -> UInt32 {
        defer { nextStreamID &+= 1 }
        return nextStreamID
    }

    func register(_ session: AppStreamSession, for appID: AndroidAppID) {
        sessions[appID]?.close()
        sessions[appID] = session
    }

    func removeSession(for appID: AndroidAppID) {
        sessions.removeValue(forKey: appID)?.close()
    }

    func removeAll() {
        let active = sessions.values
        sessions = [:]
        for session in active {
            session.close()
        }
    }
}
