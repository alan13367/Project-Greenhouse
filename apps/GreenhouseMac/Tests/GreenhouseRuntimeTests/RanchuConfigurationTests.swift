import Foundation
import XCTest
@testable import GreenhouseRuntime

final class RanchuConfigurationTests: XCTestCase {
    func testEmulatorArgumentsRequireHVFCompatibleAccelerationAndHostGPU() {
        let configuration = RanchuConfiguration(
            avdName: "GreenhouseTest",
            dataDirectory: URL(fileURLWithPath: "/tmp/greenhouse-test")
        )

        XCTAssertTrue(configuration.emulatorArguments.contains("on"))
        XCTAssertEqual(
            argumentValue(after: "-gpu", in: configuration.emulatorArguments),
            "host"
        )
        XCTAssertTrue(configuration.emulatorArguments.contains("-no-window"))
        XCTAssertTrue(configuration.emulatorArguments.contains("-no-snapshot"))
        XCTAssertEqual(configuration.serial, "emulator-5554")
        XCTAssertEqual(
            configuration.processEnvironment["ADB_SERVER_SOCKET"],
            "tcp:127.0.0.1:5038"
        )
        XCTAssertEqual(
            configuration.processEnvironment["ANDROID_ADB_SERVER_PORT"],
            "5038"
        )
    }

    func testAndroidSDKDiscoveryUsesExplicitRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let emulator = root.appendingPathComponent("emulator/emulator")
        let adb = root.appendingPathComponent("platform-tools/adb")
        try FileManager.default.createDirectory(
            at: emulator.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: adb.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: emulator.path, contents: Data())
        FileManager.default.createFile(atPath: adb.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: emulator.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: adb.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sdk = AndroidSDK.discover(
            environment: ["GREENHOUSE_ANDROID_SDK_ROOT": root.path],
            homeDirectory: URL(fileURLWithPath: "/nonexistent")
        )

        XCTAssertEqual(sdk?.root.standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(sdk?.emulator.standardizedFileURL, emulator.standardizedFileURL)
        XCTAssertEqual(sdk?.adb.standardizedFileURL, adb.standardizedFileURL)
    }

    func testAndroidSDKDiscoveryDeduplicatesEquivalentExplicitRoots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let emulator = root.appendingPathComponent("emulator/emulator")
        let adb = root.appendingPathComponent("platform-tools/adb")
        try FileManager.default.createDirectory(
            at: emulator.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: adb.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: emulator.path, contents: Data())
        FileManager.default.createFile(atPath: adb.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: emulator.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: adb.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sdk = AndroidSDK.discover(
            environment: [
                "GREENHOUSE_ANDROID_SDK_ROOT": root.path,
                "ANDROID_HOME": root.appendingPathComponent(".").path
            ],
            homeDirectory: URL(fileURLWithPath: "/nonexistent")
        )

        XCTAssertEqual(sdk?.root.standardizedFileURL, root.standardizedFileURL)
    }

    func testCommunityImageUsesSeparatePersistentUserdata() {
        let configuration = RanchuConfiguration(
            avdName: "unused",
            dataDirectory: URL(fileURLWithPath: "/tmp/greenhouse-runtime"),
            systemImageDirectory: URL(fileURLWithPath: "/tmp/greenhouse-images")
        )

        XCTAssertFalse(configuration.emulatorArguments.contains("-avd"))
        XCTAssertEqual(
            argumentValue(after: "-sysdir", in: configuration.emulatorArguments),
            "/tmp/greenhouse-images"
        )
        XCTAssertEqual(
            argumentValue(after: "-initdata", in: configuration.emulatorArguments),
            "/tmp/greenhouse-images/userdata.img"
        )
        XCTAssertEqual(
            argumentValue(after: "-data", in: configuration.emulatorArguments),
            "/tmp/greenhouse-runtime/userdata/userdata-qemu.img"
        )
    }

    func testVulkanSummaryExtractsDeviceAndDriver() {
        let summary = RanchuRuntimeController.vulkanSummary(
            from: """
            {
              "devices": [{
                "properties": {
                  "deviceName": "Android Emulator Vulkan (Apple M3)",
                  "driverName": "gfxstream",
                  "driverInfo": "MoltenVK"
                }
              }]
            }
            """
        )

        XCTAssertTrue(summary.contains("Android Emulator Vulkan (Apple M3)"))
        XCTAssertTrue(summary.contains("gfxstream"))
        XCTAssertTrue(summary.contains("MoltenVK"))
    }

    func testAcceleratedGraphicsRejectsSoftwareVulkan() {
        let readiness = RanchuReadiness(
            renderer: "GLES: Apple M3",
            vulkanLevel: "android.hardware.vulkan.level=1",
            vulkanDevice: "llvmpipe · lavapipe",
            bootCompleted: true,
            packageManagerResponsive: true,
            appWindowAgentResponsive: true
        )

        XCTAssertFalse(readiness.acceleratedGraphicsAvailable)
    }

    func testCommandExecutorDrainsLargeOutputWithoutDeadlocking() async throws {
        let result = try await CommandExecutor().run(
            executable: URL(fileURLWithPath: "/bin/dd"),
            arguments: ["if=/dev/zero", "bs=1024", "count=256"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.utf8.count, 256 * 1024)
    }

    func testPackageUpdateTimeParserRestrictsAndExtractsPackages() {
        let parsed = PrivateADBClient.packageUpdateTimes(
            from: """
              Package [dev.greenhouse.first] (abc):
                userId=10123
                lastUpdateTime=2026-06-23 10:00:00
              Package [android] (def):
                userId=1000
                lastUpdateTime=2026-01-01 00:00:00
              Package [dev.greenhouse.second] (ghi):
                userId=10124
                lastUpdateTime=2026-06-23 10:00:01
            """,
            restrictingTo: [
                "dev.greenhouse.first",
                "dev.greenhouse.second"
            ]
        )

        XCTAssertEqual(
            parsed,
            [
                "dev.greenhouse.first": "2026-06-23 10:00:00",
                "dev.greenhouse.second": "2026-06-23 10:00:01"
            ]
        )
    }

    private func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
