import CoreGraphics
import Darwin
import Foundation
import GreenhouseCore
import GreenhouseRuntime

@main
struct GreenhouseRuntimeProbe {
    @MainActor
    static func main() async {
        do {
            let report = try await run()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(
                Data("Community Runtime proof failed: \(error)\n".utf8)
            )
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws -> Report {
        guard let sdk = AndroidSDK.discover() else {
            throw ProbeError.androidSDKMissing
        }
        let configuration = RanchuConfiguration.development()
        guard configuration.systemImageDirectory != nil else {
            throw ProbeError.communityImageDirectoryMissing
        }
        let runtime = RanchuRuntimeController(
            sdk: sdk,
            configuration: configuration
        )
        let readiness = try await runtime.start()

        let requiredPackages = [
            "com.google.android.gms",
            "com.android.vending",
            "com.google.android.gsf",
            "org.fdroid.fdroid",
            "org.fdroid.fdroid.privileged"
        ]
        for packageName in requiredPackages {
            let packagePath = try await runtime.adb.shell(
                ["cmd", "package", "path", packageName]
            )
            guard packagePath.hasPrefix("package:") else {
                throw ProbeError.requiredPackageMissing(packageName)
            }
        }

        let apps = [
            AndroidApp.fDroid,
            AndroidApp.microGSettings
        ]
        var sessions: [AppStreamSession] = []
        defer {
            for session in sessions {
                session.close()
            }
        }

        for (index, app) in apps.enumerated() {
            let port = configuration.firstAgentForwardPort + index + 1
            try await runtime.prepareAgentForward(localPort: port)
            let session = AppStreamSession(
                app: app,
                streamID: UInt32(index + 1),
                localPort: port
            )
            try await session.start(audioEnabled: false)
            sessions.append(session)
        }

        try await waitForFrames(sessions, minimum: 30, timeout: .seconds(30))
        let streamReports = sessions.map { session in
            StreamReport(
                packageName: session.app.packageName,
                displayID: session.model.displayID,
                framesDecoded: session.model.frameSequence,
                framesPerSecond: session.model.measuredFramesPerSecond,
                frameJitterMilliseconds: session.model.frameJitterMilliseconds,
                decodeLatencyP95Milliseconds: session.model.decodeLatencyMilliseconds,
                controlRoundTripMilliseconds: session.model.controlRoundTripMilliseconds
            )
        }
        guard Set(streamReports.compactMap(\.displayID)).count == 2 else {
            throw ProbeError.distinctDisplaysNotObserved
        }

        for session in sessions {
            let port = session.localPort
            session.close()
            await runtime.removeAgentForward(localPort: port)
        }
        sessions.removeAll()

        let marker = "greenhouse-community-\(UUID().uuidString)"
        _ = try await runtime.adb.shell(
            "printf '\(marker)' > /data/local/tmp/greenhouse-community-marker"
        )
        await runtime.stop()
        let restarted = try await runtime.start()
        let persistedMarker = try await runtime.adb.shell(
            ["cat", "/data/local/tmp/greenhouse-community-marker"]
        )
        await runtime.stop()

        return Report(
            schemaVersion: 1,
            engine: "Android Emulator",
            virtualHardware: "goldfish-ranchu",
            graphicsTransport: "gfxstream-moltenvk",
            renderer: readiness.renderer,
            vulkanLevel: readiness.vulkanLevel,
            vulkanDevice: readiness.vulkanDevice,
            appWindowAgentResponsive: readiness.appWindowAgentResponsive,
            requiredPackagesPresent: true,
            privateADBPort: configuration.adbServerPort,
            streams: streamReports,
            persistenceVerified: persistedMarker == marker,
            restartRenderer: restarted.renderer,
            restartVulkanDevice: restarted.vulkanDevice
        )
    }

    @MainActor
    private static func waitForFrames(
        _ sessions: [AppStreamSession],
        minimum: Int,
        timeout: Duration
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if sessions.allSatisfy({ $0.model.frameSequence >= minimum }) {
                return
            }
            if let error = sessions.compactMap({ $0.model.errorMessage }).first {
                throw ProbeError.streamFailed(error)
            }
            for (index, session) in sessions.enumerated() {
                session.pointer(
                    action: 7,
                    point: CGPoint(
                        x: 120 + ((session.model.frameSequence + index * 17) % 500),
                        y: 180 + ((session.model.frameSequence + index * 23) % 300)
                    ),
                    buttons: 0
                )
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ProbeError.frameTimeout
    }

    private struct Report: Codable {
        let schemaVersion: Int
        let engine: String
        let virtualHardware: String
        let graphicsTransport: String
        let renderer: String
        let vulkanLevel: String
        let vulkanDevice: String
        let appWindowAgentResponsive: Bool
        let requiredPackagesPresent: Bool
        let privateADBPort: Int
        let streams: [StreamReport]
        let persistenceVerified: Bool
        let restartRenderer: String
        let restartVulkanDevice: String
    }

    private struct StreamReport: Codable {
        let packageName: String
        let displayID: Int?
        let framesDecoded: Int
        let framesPerSecond: Double
        let frameJitterMilliseconds: Double
        let decodeLatencyP95Milliseconds: Double?
        let controlRoundTripMilliseconds: Double?
    }

    private enum ProbeError: Error {
        case androidSDKMissing
        case communityImageDirectoryMissing
        case requiredPackageMissing(String)
        case distinctDisplaysNotObserved
        case streamFailed(String)
        case frameTimeout
    }
}
