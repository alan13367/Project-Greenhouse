import Foundation

public struct PrivateADBClient: Sendable {
    public let sdk: AndroidSDK
    public let configuration: RanchuConfiguration
    public let executor: CommandExecutor

    public init(
        sdk: AndroidSDK,
        configuration: RanchuConfiguration,
        executor: CommandExecutor = CommandExecutor()
    ) {
        self.sdk = sdk
        self.configuration = configuration
        self.executor = executor
    }

    public func startServer() async throws {
        _ = try await command(["start-server"], includeSerial: false)
    }

    public func killServer() async {
        _ = try? await command(
            ["kill-server"],
            includeSerial: false,
            allowingNonZeroExit: true
        )
    }

    public func waitForDevice() async throws {
        _ = try await command(["wait-for-device"])
    }

    public func shell(_ arguments: [String]) async throws -> String {
        try await command(["shell"] + arguments).standardOutput
    }

    public func shell(_ commandText: String) async throws -> String {
        try await shell(["sh", "-c", commandText])
    }

    public func install(packageAt url: URL) async throws {
        _ = try await command(["install", "-r", "-g", url.path])
    }

    public func thirdPartyPackages() async throws -> Set<String> {
        let output = try await shell(["cmd", "package", "list", "packages", "-3"])
        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .compactMap { line in
                    line.hasPrefix("package:") ? String(line.dropFirst(8)) : nil
                }
        )
    }

    public func thirdPartyPackageUpdateTimes() async throws -> [String: String] {
        let packages = try await thirdPartyPackages()
        let dump = try await shell(["dumpsys", "package", "packages"])
        return Self.packageUpdateTimes(
            from: dump,
            restrictingTo: packages
        )
    }

    static func packageUpdateTimes(
        from dump: String,
        restrictingTo packages: Set<String>
    ) -> [String: String] {
        var result: [String: String] = [:]
        var currentPackage: String?

        for rawLine in dump.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if let marker = line.range(of: "Package ["),
               let end = line[marker.upperBound...].firstIndex(of: "]") {
                let packageName = String(line[marker.upperBound..<end])
                currentPackage = packages.contains(packageName) ? packageName : nil
                continue
            }
            guard let currentPackage else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("lastUpdateTime=") else { continue }
            result[currentPackage] = String(
                trimmed.dropFirst("lastUpdateTime=".count)
            )
        }
        return result
    }

    public func forward(localPort: Int, socketName: String) async throws {
        _ = try await command([
            "forward",
            "tcp:\(localPort)",
            "localabstract:\(socketName)"
        ])
    }

    public func removeForward(localPort: Int) async {
        _ = try? await command(
            ["forward", "--remove", "tcp:\(localPort)"],
            allowingNonZeroExit: true
        )
    }

    public func stopEmulator() async {
        _ = try? await command(
            ["emu", "kill"],
            allowingNonZeroExit: true
        )
    }

    @discardableResult
    public func command(
        _ arguments: [String],
        includeSerial: Bool = true,
        allowingNonZeroExit: Bool = false
    ) async throws -> CommandResult {
        var adbArguments = ["-P", String(configuration.adbServerPort)]
        if includeSerial {
            adbArguments += ["-s", configuration.serial]
        }
        adbArguments += arguments
        return try await executor.run(
            executable: sdk.adb,
            arguments: adbArguments,
            environment: configuration.processEnvironment,
            allowingNonZeroExit: allowingNonZeroExit
        )
    }
}
