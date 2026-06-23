import Foundation
import GreenhouseCore

@MainActor
public struct GreenhouseRuntimeEnvironment {
    public let backend: any GreenhouseBackend
    public let streams: AppStreamRegistry

    public init(backend: any GreenhouseBackend, streams: AppStreamRegistry) {
        self.backend = backend
        self.streams = streams
    }

    public static func makeDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GreenhouseRuntimeEnvironment {
        let streams = AppStreamRegistry()
        guard environment["GREENHOUSE_BACKEND"]?.lowercased() == "ranchu" else {
            return GreenhouseRuntimeEnvironment(
                backend: FakeBackend(),
                streams: streams
            )
        }
        let backend = RanchuBackend(
            sdk: AndroidSDK.discover(environment: environment),
            configuration: .development(environment: environment),
            streams: streams
        )
        return GreenhouseRuntimeEnvironment(backend: backend, streams: streams)
    }
}
