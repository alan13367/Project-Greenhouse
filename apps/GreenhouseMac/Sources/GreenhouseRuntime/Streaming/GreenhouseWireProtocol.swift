import Foundation

public enum GreenhousePacketKind: UInt16, Sendable {
    case create = 1
    case resize = 2
    case focus = 3
    case pointer = 4
    case key = 5
    case text = 6
    case controller = 7
    case close = 8
    case ping = 9
    case health = 10

    case hello = 101
    case videoConfig = 102
    case videoFrame = 103
    case audioConfig = 104
    case audioFrame = 105
    case metrics = 106
    case pong = 109
    case healthy = 110
    case error = 199
}

public struct GreenhousePacket: Sendable, Equatable {
    public static let magic: UInt32 = 0x4752_4853
    public static let version: UInt16 = 1
    public static let headerSize = 16
    public static let maximumPayloadSize = 16 * 1024 * 1024

    public let kind: GreenhousePacketKind
    public let streamID: UInt32
    public let payload: Data

    public init(kind: GreenhousePacketKind, streamID: UInt32, payload: Data = Data()) {
        self.kind = kind
        self.streamID = streamID
        self.payload = payload
    }

    public func encoded() -> Data {
        var data = Data(capacity: Self.headerSize + payload.count)
        data.appendInteger(Self.magic)
        data.appendInteger(Self.version)
        data.appendInteger(kind.rawValue)
        data.appendInteger(UInt32(payload.count))
        data.appendInteger(streamID)
        data.append(payload)
        return data
    }

    public static func json(
        kind: GreenhousePacketKind,
        streamID: UInt32,
        object: [String: Any]
    ) throws -> GreenhousePacket {
        GreenhousePacket(
            kind: kind,
            streamID: streamID,
            payload: try JSONSerialization.data(withJSONObject: object)
        )
    }
}

public enum GreenhouseProtocolError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case unknownPacketKind(UInt16)
    case payloadTooLarge(Int)
}

public struct GreenhousePacketParser: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [GreenhousePacket] {
        buffer.append(data)
        var packets: [GreenhousePacket] = []

        while buffer.count >= GreenhousePacket.headerSize {
            let magic: UInt32 = buffer.integer(at: 0)
            guard magic == GreenhousePacket.magic else {
                throw GreenhouseProtocolError.invalidMagic
            }
            let version: UInt16 = buffer.integer(at: 4)
            guard version == GreenhousePacket.version else {
                throw GreenhouseProtocolError.unsupportedVersion(version)
            }
            let rawKind: UInt16 = buffer.integer(at: 6)
            guard let kind = GreenhousePacketKind(rawValue: rawKind) else {
                throw GreenhouseProtocolError.unknownPacketKind(rawKind)
            }
            let length = Int(buffer.integer(at: 8) as UInt32)
            guard length <= GreenhousePacket.maximumPayloadSize else {
                throw GreenhouseProtocolError.payloadTooLarge(length)
            }
            let packetLength = GreenhousePacket.headerSize + length
            guard buffer.count >= packetLength else {
                break
            }
            let streamID: UInt32 = buffer.integer(at: 12)
            let payload = buffer.subdata(
                in: GreenhousePacket.headerSize..<packetLength
            )
            packets.append(
                GreenhousePacket(kind: kind, streamID: streamID, payload: payload)
            )
            buffer.removeSubrange(0..<packetLength)
        }
        return packets
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    func integer<T: FixedWidthInteger>(at offset: Int) -> T {
        let size = MemoryLayout<T>.size
        return subdata(in: offset..<(offset + size)).withUnsafeBytes { bytes in
            T(bigEndian: bytes.loadUnaligned(as: T.self))
        }
    }
}
