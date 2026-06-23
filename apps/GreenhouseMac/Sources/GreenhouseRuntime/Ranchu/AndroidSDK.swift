import Foundation

public struct AndroidSDK: Sendable, Equatable {
    public let root: URL
    public let emulator: URL
    public let adb: URL
    public let avdManager: URL?
    public let sdkManager: URL?

    public init(
        root: URL,
        emulator: URL,
        adb: URL,
        avdManager: URL?,
        sdkManager: URL?
    ) {
        self.root = root
        self.emulator = emulator
        self.adb = adb
        self.avdManager = avdManager
        self.sdkManager = sdkManager
    }

    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> AndroidSDK? {
        var candidates: [URL] = []
        for key in ["GREENHOUSE_ANDROID_SDK_ROOT", "ANDROID_SDK_ROOT", "ANDROID_HOME"] {
            if let path = environment[key], !path.isEmpty {
                candidates.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        candidates.append(
            homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Android", isDirectory: true)
                .appendingPathComponent("sdk", isDirectory: true)
        )
        candidates.append(
            URL(
                fileURLWithPath: "/opt/homebrew/share/android-commandlinetools",
                isDirectory: true
            )
        )
        candidates.append(
            URL(
                fileURLWithPath: "/usr/local/share/android-commandlinetools",
                isDirectory: true
            )
        )

        for root in candidates.uniquedByStandardizedPath() {
            let emulator = root.appendingPathComponent("emulator/emulator")
            let adb = root.appendingPathComponent("platform-tools/adb")
            guard fileManager.isExecutableFile(atPath: emulator.path),
                  fileManager.isExecutableFile(atPath: adb.path) else {
                continue
            }
            return AndroidSDK(
                root: root,
                emulator: emulator,
                adb: adb,
                avdManager: commandLineTool(
                    named: "avdmanager",
                    root: root,
                    fileManager: fileManager
                ),
                sdkManager: commandLineTool(
                    named: "sdkmanager",
                    root: root,
                    fileManager: fileManager
                )
            )
        }
        return nil
    }

    private static func commandLineTool(
        named name: String,
        root: URL,
        fileManager: FileManager
    ) -> URL? {
        let commandLineTools = root.appendingPathComponent(
            "cmdline-tools",
            isDirectory: true
        )
        let preferred = [
            commandLineTools.appendingPathComponent("latest/bin/\(name)"),
            commandLineTools.appendingPathComponent("bin/\(name)")
        ]
        if let match = preferred.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) {
            return match
        }

        guard let versions = try? fileManager.contentsOfDirectory(
            at: commandLineTools,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return versions
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { $0.appendingPathComponent("bin/\(name)") }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

private extension Array where Element == URL {
    func uniquedByStandardizedPath() -> [URL] {
        var seen = Set<String>()
        return filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
    }
}
