import Foundation
import XCTest
@testable import GreenhouseCore

final class DevelopmentEventTests: XCTestCase {
    func testEventRoundTripsAsOneJSONLine() throws {
        let event = DevelopmentEvent(
            id: UUID(uuidString: "5D17699B-205B-44CF-A1CB-4A3DC05EAAC7")!,
            sequence: 42,
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            source: "tests",
            level: .info,
            name: "android.ready",
            message: "Android is ready",
            attributes: ["transport": "private"],
            statePatch: StatePatch(androidReadiness: .ready)
        )

        XCTAssertFalse(event.ndjson.contains("\n"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            DevelopmentEvent.self,
            from: Data(event.ndjson.utf8)
        )
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testRedactionCoversSensitiveKeysEmailsAndHomePaths() {
        let event = DevelopmentEvent(
            sequence: 1,
            source: "tests",
            level: .error,
            name: "redaction.test",
            message: "Read /Users/example/Downloads/app.apk for person@example.com",
            attributes: [
                "accessToken": "super-secret-token",
                "path": "/Users/example/Downloads/app.apk",
                "owner": "person@example.com"
            ]
        )

        let redacted = event.redacted(homeDirectory: "/Users/example")

        XCTAssertEqual(redacted.attributes["accessToken"], "<redacted>")
        XCTAssertEqual(redacted.attributes["path"], "~/Downloads/app.apk")
        XCTAssertEqual(redacted.attributes["owner"], "<redacted-email>")
        XCTAssertEqual(
            redacted.message,
            "Read ~/Downloads/app.apk for <redacted-email>"
        )
    }

    func testRedactionCoversNestedStatePatchStrings() {
        let event = DevelopmentEvent(
            sequence: 1,
            source: "tests",
            level: .info,
            name: "redaction.patch",
            message: "State update",
            statePatch: StatePatch(
                currentOperation: .preparingRuntime(
                    OperationProgress(
                        fractionCompleted: 0.5,
                        detail: "Reading /Users/example/person@example.com"
                    )
                ),
                appWindow: AppWindowPatch(
                    appID: AndroidAppID(
                        rawValue: "/Users/example/person@example.com"
                    ),
                    state: .creatingDisplay
                )
            )
        )

        let redacted = event.redacted(homeDirectory: "/Users/example")

        guard case let .preparingRuntime(progress) = redacted.statePatch?.currentOperation else {
            return XCTFail("Expected preparing runtime progress")
        }
        XCTAssertEqual(progress.detail, "Reading ~/<redacted-email>")
        XCTAssertEqual(
            redacted.statePatch?.appWindow?.appID.rawValue,
            "~/<redacted-email>"
        )
    }

    func testProgressIsClampedToValidRange() {
        XCTAssertEqual(
            OperationProgress(fractionCompleted: -1, detail: "low").fractionCompleted,
            0
        )
        XCTAssertEqual(
            OperationProgress(fractionCompleted: 4, detail: "high").fractionCompleted,
            1
        )
    }

    func testWireFormatUsesStableOperationKindAndStringAppID() throws {
        let event = DevelopmentEvent(
            sequence: 7,
            source: "tests",
            level: .info,
            name: "wire-format.test",
            message: "Stable shape",
            statePatch: StatePatch(
                currentOperation: .preparingRuntime(
                    OperationProgress(fractionCompleted: 0.5, detail: "Halfway")
                ),
                appWindow: AppWindowPatch(
                    appID: AndroidApp.demoNotes.id,
                    state: .creatingDisplay
                )
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(event.ndjson.utf8)) as? [String: Any]
        )
        let patch = try XCTUnwrap(object["statePatch"] as? [String: Any])
        let operation = try XCTUnwrap(patch["currentOperation"] as? [String: Any])
        let appWindow = try XCTUnwrap(patch["appWindow"] as? [String: Any])

        XCTAssertEqual(operation["kind"] as? String, "preparingRuntime")
        XCTAssertEqual(appWindow["appID"] as? String, "demo.notes")
    }
}
