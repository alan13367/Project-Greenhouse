import XCTest
@testable import GreenhouseRuntime

final class GreenhouseWireProtocolTests: XCTestCase {
    func testParserAcceptsFragmentedPackets() throws {
        let first = GreenhousePacket(
            kind: .hello,
            streamID: 7,
            payload: Data("one".utf8)
        ).encoded()
        let second = GreenhousePacket(
            kind: .videoFrame,
            streamID: 7,
            payload: Data([1, 2, 3, 4])
        ).encoded()
        let combined = first + second

        var parser = GreenhousePacketParser()
        XCTAssertEqual(
            try parser.append(combined.prefix(9)),
            []
        )
        let packets = try parser.append(combined.dropFirst(9))
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(packets[0].kind, .hello)
        XCTAssertEqual(packets[0].streamID, 7)
        XCTAssertEqual(packets[0].payload, Data("one".utf8))
        XCTAssertEqual(packets[1].kind, .videoFrame)
        XCTAssertEqual(packets[1].payload, Data([1, 2, 3, 4]))
    }

    func testParserRejectsOversizedPayloadBeforeBufferingBody() {
        var header = Data()
        header.append(contentsOf: [0x47, 0x52, 0x48, 0x53])
        header.append(contentsOf: [0, 1, 0, 101])
        header.append(contentsOf: [1, 0, 0, 1])
        header.append(contentsOf: [0, 0, 0, 1])

        var parser = GreenhousePacketParser()
        XCTAssertThrowsError(try parser.append(header)) { error in
            XCTAssertEqual(
                error as? GreenhouseProtocolError,
                .payloadTooLarge(16_777_217)
            )
        }
    }

    func testHealthPacketRoundTrips() throws {
        let packet = GreenhousePacket(kind: .health, streamID: 42)
        var parser = GreenhousePacketParser()

        let parsed = try XCTUnwrap(parser.append(packet.encoded()).first)

        XCTAssertEqual(parsed.kind, .health)
        XCTAssertEqual(parsed.streamID, 42)
        XCTAssertTrue(parsed.payload.isEmpty)
    }
}
