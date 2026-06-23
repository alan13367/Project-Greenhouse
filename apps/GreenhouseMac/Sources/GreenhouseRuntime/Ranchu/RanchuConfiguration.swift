import Foundation

public struct RanchuConfiguration: Sendable, Equatable {
    public let avdName: String
    public let dataDirectory: URL
    public let systemImageDirectory: URL?
    public let emulatorPort: Int
    public let adbServerPort: Int
    public let firstAgentForwardPort: Int
    public let bootTimeout: Duration

    public init(
        avdName: String,
        dataDirectory: URL,
        systemImageDirectory: URL? = nil,
        emulatorPort: Int = 5554,
        adbServerPort: Int = 5038,
        firstAgentForwardPort: Int = 27_183,
        bootTimeout: Duration = .seconds(180)
    ) {
        self.avdName = avdName
        self.dataDirectory = dataDirectory
        self.systemImageDirectory = systemImageDirectory
        self.emulatorPort = emulatorPort
        self.adbServerPort = adbServerPort
        self.firstAgentForwardPort = firstAgentForwardPort
        self.bootTimeout = bootTimeout
    }

    public static func development(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> RanchuConfiguration {
        let support = homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("Greenhouse", isDirectory: true)
        return RanchuConfiguration(
            avdName: environment["GREENHOUSE_AVD_NAME"] ?? "GreenhousePhase3Arm64",
            dataDirectory: environment["GREENHOUSE_RUNTIME_DATA"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            } ?? support.appendingPathComponent("Runtime", isDirectory: true),
            systemImageDirectory: environment["GREENHOUSE_SYSTEM_IMAGE_DIR"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        )
    }

    public var serial: String {
        "emulator-\(emulatorPort)"
    }

    public var androidUserHome: URL {
        dataDirectory.appendingPathComponent("android-home", isDirectory: true)
    }

    public var avdHome: URL {
        dataDirectory.appendingPathComponent("avd", isDirectory: true)
    }

    public var adbHome: URL {
        dataDirectory.appendingPathComponent("adb-home", isDirectory: true)
    }

    public var logDirectory: URL {
        dataDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public var userDataDirectory: URL {
        dataDirectory.appendingPathComponent("userdata", isDirectory: true)
    }

    public var emulatorArguments: [String] {
        var arguments = [
            "-port", String(emulatorPort),
            "-accel", "on",
            "-gpu", "host",
            "-no-window",
            "-no-boot-anim",
            "-no-snapshot",
            "-netdelay", "none",
            "-netspeed", "full"
        ]
        if let systemImageDirectory {
            arguments += [
                "-sysdir", systemImageDirectory.path,
                "-data", userDataDirectory
                    .appendingPathComponent("userdata-qemu.img")
                    .path,
                "-initdata", systemImageDirectory
                    .appendingPathComponent("userdata.img")
                    .path
            ]
        } else {
            arguments = ["-avd", avdName] + arguments
        }
        return arguments
    }

    public var processEnvironment: [String: String] {
        [
            "ANDROID_USER_HOME": androidUserHome.path,
            "ANDROID_AVD_HOME": avdHome.path,
            "HOME": adbHome.path,
            "ANDROID_ADB_SERVER_PORT": String(adbServerPort),
            "ADB_SERVER_SOCKET": "tcp:127.0.0.1:\(adbServerPort)"
        ]
    }
}
