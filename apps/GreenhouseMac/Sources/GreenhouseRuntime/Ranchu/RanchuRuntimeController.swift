import Foundation

public enum RanchuRuntimeError: Error, LocalizedError {
    case sdkMissing
    case avdMissing(String)
    case emulatorExited(Int32)
    case bootTimedOut
    case graphicsAccelerationUnavailable(renderer: String, vulkan: String)
    case appWindowAgentUnavailable

    public var errorDescription: String? {
        switch self {
        case .sdkMissing:
            "The Android SDK emulator and platform tools are not installed."
        case let .avdMissing(name):
            "The ARM64 AVD \(name) is not installed in Greenhouse's runtime directory."
        case let .emulatorExited(status):
            "The Android Emulator exited before Android was ready (status \(status))."
        case .bootTimedOut:
            "Android did not become ready before the boot deadline."
        case let .graphicsAccelerationUnavailable(renderer, vulkan):
            "The guest did not report accelerated graphics (renderer: \(renderer), Vulkan: \(vulkan))."
        case .appWindowAgentUnavailable:
            "The Greenhouse app-window agent is not installed or responsive."
        }
    }
}

public struct RanchuReadiness: Sendable, Equatable {
    public let renderer: String
    public let vulkanLevel: String
    public let vulkanDevice: String
    public let bootCompleted: Bool
    public let packageManagerResponsive: Bool
    public let appWindowAgentResponsive: Bool

    public var acceleratedGraphicsAvailable: Bool {
        let graphics = renderer + " " + vulkanDevice
        return !renderer.isEmpty
            && !vulkanLevel.isEmpty
            && !vulkanDevice.isEmpty
            && !graphics.localizedCaseInsensitiveContains("swiftshader")
            && !graphics.localizedCaseInsensitiveContains("lavapipe")
            && !graphics.localizedCaseInsensitiveContains("software")
    }
}

@MainActor
public final class RanchuRuntimeController {
    public static let agentSocketName = "greenhouse-app-window"

    public let sdk: AndroidSDK
    public let configuration: RanchuConfiguration
    public let adb: PrivateADBClient

    private let executor: CommandExecutor
    private var emulatorProcess: Process?
    private var emulatorLog: FileHandle?

    public init(
        sdk: AndroidSDK,
        configuration: RanchuConfiguration,
        executor: CommandExecutor = CommandExecutor()
    ) {
        self.sdk = sdk
        self.configuration = configuration
        self.executor = executor
        adb = PrivateADBClient(
            sdk: sdk,
            configuration: configuration,
            executor: executor
        )
    }

    deinit {
        emulatorProcess?.terminate()
        try? emulatorLog?.close()
    }

    public func prepare() throws {
        let fileManager = FileManager.default
        for directory in [
            configuration.dataDirectory,
            configuration.androidUserHome,
            configuration.avdHome,
            configuration.adbHome,
            configuration.userDataDirectory,
            configuration.logDirectory
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        if let systemImageDirectory = configuration.systemImageDirectory {
            for file in [
                "system.img",
                "userdata.img",
                "kernel-ranchu",
                "ramdisk.img",
                "vendor.img"
            ] {
                let image = systemImageDirectory.appendingPathComponent(file)
                guard fileManager.fileExists(atPath: image.path) else {
                    throw RanchuRuntimeError.avdMissing(
                        "Community image missing \(file) in \(systemImageDirectory.path)"
                    )
                }
            }
        } else {
            let avdConfig = configuration.avdHome
                .appendingPathComponent("\(configuration.avdName).avd", isDirectory: true)
                .appendingPathComponent("config.ini")
            guard fileManager.fileExists(atPath: avdConfig.path) else {
                throw RanchuRuntimeError.avdMissing(configuration.avdName)
            }
        }
    }

    public func start() async throws -> RanchuReadiness {
        do {
            if emulatorProcess?.isRunning != true {
                try prepare()
                try await adb.startServer()

                try? emulatorLog?.close()
                let logURL = configuration.logDirectory
                    .appendingPathComponent("emulator.log")
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                let log = try FileHandle(forWritingTo: logURL)
                try log.seekToEnd()
                emulatorLog = log
                emulatorProcess = try executor.launch(
                    executable: sdk.emulator,
                    arguments: configuration.emulatorArguments,
                    environment: configuration.processEnvironment,
                    standardOutput: log,
                    standardError: log
                )
            }

            let readiness = try await waitForReadiness()
            guard readiness.acceleratedGraphicsAvailable else {
                throw RanchuRuntimeError.graphicsAccelerationUnavailable(
                    renderer: readiness.renderer,
                    vulkan: readiness.vulkanDevice.isEmpty
                        ? readiness.vulkanLevel
                        : readiness.vulkanDevice
                )
            }
            guard readiness.appWindowAgentResponsive else {
                throw RanchuRuntimeError.appWindowAgentUnavailable
            }
            return readiness
        } catch {
            await cleanUpFailedStart()
            throw error
        }
    }

    private func cleanUpFailedStart() async {
        await adb.stopEmulator()
        if let process = emulatorProcess, process.isRunning {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning {
                process.terminate()
            }
        }
        emulatorProcess = nil
        try? emulatorLog?.close()
        emulatorLog = nil
        await adb.killServer()
    }

    public func stop() async {
        await adb.stopEmulator()
        if let process = emulatorProcess, process.isRunning {
            try? await Task.sleep(for: .seconds(3))
            if process.isRunning {
                process.terminate()
            }
        }
        emulatorProcess = nil
        try? emulatorLog?.close()
        emulatorLog = nil
        await adb.killServer()
    }

    public func installPackage(at url: URL) async throws -> String? {
        let before = try await adb.thirdPartyPackages()
        let beforeUpdateTimes = try await adb.thirdPartyPackageUpdateTimes()
        try await adb.install(packageAt: url)
        let after = try await adb.thirdPartyPackages()
        if let installed = after.subtracting(before).sorted().first {
            return installed
        }
        let afterUpdateTimes = try await adb.thirdPartyPackageUpdateTimes()
        return after
            .filter { beforeUpdateTimes[$0] != afterUpdateTimes[$0] }
            .sorted()
            .first
    }

    public func installedThirdPartyPackages() async throws -> [String] {
        try await adb.thirdPartyPackages().sorted()
    }

    public func prepareAgentForward(localPort: Int) async throws {
        try await adb.forward(
            localPort: localPort,
            socketName: Self.agentSocketName
        )
    }

    public func removeAgentForward(localPort: Int) async {
        await adb.removeForward(localPort: localPort)
    }

    private func waitForReadiness() async throws -> RanchuReadiness {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: configuration.bootTimeout)
        var discoveryAttempts = 0

        while clock.now < deadline {
            if let process = emulatorProcess, !process.isRunning {
                throw RanchuRuntimeError.emulatorExited(process.terminationStatus)
            }

            do {
                let state = try await adb.command(
                    ["get-state"],
                    allowingNonZeroExit: true
                )
                guard state.exitCode == 0, state.standardOutput == "device" else {
                    discoveryAttempts += 1
                    if discoveryAttempts.isMultiple(of: 5) {
                        await adb.killServer()
                        try await adb.startServer()
                    }
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                let boot = try await adb.shell(["getprop", "sys.boot_completed"])
                guard boot == "1" else {
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                let packageManager = try await adb.shell(
                    ["cmd", "package", "path", "android"]
                )
                let renderer = try await adb.shell(
                    "dumpsys SurfaceFlinger | grep -m 1 'GLES:'"
                )
                let vulkan = try await adb.shell(
                    "pm list features | grep 'android.hardware.vulkan.level'"
                )
                let vulkanJSON = try await adb.shell(["cmd", "gpu", "vkjson"])
                let vulkanDevice = Self.vulkanSummary(from: vulkanJSON)
                let agent = try await agentIsResponsive()
                return RanchuReadiness(
                    renderer: renderer,
                    vulkanLevel: vulkan,
                    vulkanDevice: vulkanDevice,
                    bootCompleted: true,
                    packageManagerResponsive: !packageManager.isEmpty,
                    appWindowAgentResponsive: agent
                )
            } catch {
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw RanchuRuntimeError.bootTimedOut
    }

    nonisolated static func vulkanSummary(from jsonText: String) -> String {
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return ""
        }
        let interestingKeys = Set([
            "deviceName",
            "driverName",
            "driverInfo"
        ])
        var values: [String] = []

        func collect(_ value: Any) {
            if let object = value as? [String: Any] {
                for key in interestingKeys {
                    if let text = object[key] as? String,
                       !text.isEmpty,
                       !values.contains(text) {
                        values.append(text)
                    }
                }
                for nested in object.values {
                    collect(nested)
                }
            } else if let array = value as? [Any] {
                for nested in array {
                    collect(nested)
                }
            }
        }

        collect(root)
        return values.prefix(4).joined(separator: " · ")
    }

    private func agentIsResponsive() async throws -> Bool {
        let package = try await adb.shell([
            "cmd", "package", "list", "packages", "dev.greenhouse.agent"
        ])
        guard package.contains("dev.greenhouse.agent") else {
            return false
        }
        let probePort = configuration.firstAgentForwardPort - 1
        try await adb.forward(
            localPort: probePort,
            socketName: Self.agentSocketName
        )
        do {
            let healthy = try await AgentHealthProbe.probe(port: probePort)
            await adb.removeForward(localPort: probePort)
            return healthy
        } catch {
            await adb.removeForward(localPort: probePort)
            return false
        }
    }
}
