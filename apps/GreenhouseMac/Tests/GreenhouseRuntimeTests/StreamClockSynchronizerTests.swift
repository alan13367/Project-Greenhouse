import CoreMedia
import XCTest
@testable import GreenhouseRuntime

final class StreamClockSynchronizerTests: XCTestCase {
    func testEstimatesRoundTripAndGuestFrameLatency() throws {
        let synchronizer = StreamClockSynchronizer()

        synchronizer.acceptPong(
            hostSendNanos: 1_000_000_000,
            guestReceiveNanos: 6_010_000_000,
            guestSendNanos: 6_012_000_000,
            hostReceiveNanos: 1_022_000_000
        )

        XCTAssertEqual(
            try XCTUnwrap(synchronizer.roundTripMilliseconds),
            20,
            accuracy: 0.001
        )
        let latency = synchronizer.hostLatencyMilliseconds(
            forGuestPresentationTime: CMTime(
                value: 6_020_000,
                timescale: 1_000_000
            ),
            hostNowNanos: 1_045_000_000
        )
        XCTAssertEqual(try XCTUnwrap(latency), 25, accuracy: 0.001)
    }

    func testRejectsImplausibleUnsynchronizedPresentationTime() {
        let synchronizer = StreamClockSynchronizer()

        XCTAssertNil(
            synchronizer.hostLatencyMilliseconds(
                forGuestPresentationTime: .zero,
                hostNowNanos: 1_000
            )
        )
    }
}
