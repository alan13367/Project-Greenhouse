import AVFoundation
import CoreGraphics
import Foundation
import GreenhouseCore
import Network

@MainActor
public final class AppStreamSession {
    public let app: AndroidApp
    public let streamID: UInt32
    public let localPort: Int
    public let model: AppStreamModel

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var parser = GreenhousePacketParser()
    private var decoder: VideoToolboxDecoder!
    private let audio = AudioPlaybackEngine()
    private let clockSynchronizer = StreamClockSynchronizer()
    private var isClosed = false
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var startConfiguration: StartConfiguration?
    private var startTimeoutTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    public init(
        app: AndroidApp,
        streamID: UInt32,
        localPort: Int,
        model: AppStreamModel
    ) {
        self.app = app
        self.streamID = streamID
        self.localPort = localPort
        self.model = model
        queue = DispatchQueue(label: "dev.greenhouse.stream.\(streamID)")
        connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: UInt16(localPort))!,
            using: .tcp
        )
        decoder = VideoToolboxDecoder { [weak model, clockSynchronizer] pixelBuffer, time in
            let now = DispatchTime.now().uptimeNanoseconds
            let latency = clockSynchronizer.hostLatencyMilliseconds(
                forGuestPresentationTime: time,
                hostNowNanos: now
            )
            Task { @MainActor in
                model?.present(
                    pixelBuffer,
                    at: time,
                    decodeLatencyMilliseconds: latency
                )
            }
        }
    }

    public convenience init(
        app: AndroidApp,
        streamID: UInt32,
        localPort: Int
    ) {
        self.init(
            app: app,
            streamID: streamID,
            localPort: localPort,
            model: AppStreamModel()
        )
    }

    deinit {
        connection.cancel()
    }

    public func start(
        width: Int = 1280,
        height: Int = 720,
        densityDpi: Int = 240,
        frameRate: Int = 60,
        bitRate: Int = 12_000_000,
        audioEnabled: Bool = true
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            startConfiguration = StartConfiguration(
                width: width,
                height: height,
                densityDpi: densityDpi,
                frameRate: frameRate,
                bitRate: bitRate,
                audioEnabled: audioEnabled
            )
            startTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.resumeStart(throwing: StreamError.handshakeTimedOut)
            }
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleConnectionState(state)
                }
            }
            receiveNextChunk()
            connection.start(queue: queue)
        }
    }

    public func focus() {
        try? sendJSON(kind: .focus, object: [:])
    }

    public func resize(width: Int, height: Int, densityDpi: Int) {
        guard width > 0, height > 0, densityDpi > 0 else { return }
        try? sendJSON(
            kind: .resize,
            object: [
                "width": width,
                "height": height,
                "densityDpi": densityDpi,
                "bitRate": recommendedBitRate(width: width, height: height)
            ]
        )
    }

    public func pointer(
        action: Int,
        point: CGPoint,
        buttons: Int,
        deltaX: Double = 0,
        deltaY: Double = 0,
        scrollX: Double = 0,
        scrollY: Double = 0,
        source: Int = 0x0000_2002
    ) {
        try? sendJSON(
            kind: .pointer,
            object: [
                "action": action,
                "x": point.x,
                "y": point.y,
                "buttons": buttons,
                "deltaX": deltaX,
                "deltaY": deltaY,
                "scrollX": scrollX,
                "scrollY": scrollY,
                "source": source
            ]
        )
    }

    public func key(
        action: Int,
        keyCode: Int,
        metaState: Int = 0,
        repeatCount: Int = 0
    ) {
        try? sendJSON(
            kind: .key,
            object: [
                "action": action,
                "keyCode": keyCode,
                "metaState": metaState,
                "repeat": repeatCount
            ]
        )
    }

    public func text(_ text: String) {
        guard !text.isEmpty else { return }
        try? sendJSON(kind: .text, object: ["text": text])
    }

    public func controller(_ state: [String: Any]) {
        try? sendJSON(kind: .controller, object: state)
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        resumeStart(throwing: CancellationError())
        pingTask?.cancel()
        pingTask = nil
        try? sendJSON(kind: .close, object: [:])
        decoder.invalidate()
        audio.stop()
        connection.cancel()
    }

    private func receiveNextChunk() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                self?.processReceived(
                    data: data,
                    isComplete: isComplete,
                    error: error
                )
            }
        }
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            guard let configuration = startConfiguration else { return }
            do {
                try sendJSON(
                    kind: .create,
                    object: [
                        "packageName": app.packageName,
                        "width": configuration.width,
                        "height": configuration.height,
                        "densityDpi": configuration.densityDpi,
                        "frameRate": configuration.frameRate,
                        "bitRate": configuration.bitRate,
                        "audio": configuration.audioEnabled
                    ]
                )
            } catch {
                resumeStart(throwing: error)
            }
        case let .failed(error):
            model.fail(error.localizedDescription)
            resumeStart(throwing: error)
        case .cancelled:
            resumeStart(throwing: CancellationError())
        default:
            break
        }
    }

    private func processReceived(
        data: Data?,
        isComplete: Bool,
        error: NWError?
    ) {
        if let data, !data.isEmpty {
            do {
                let packets = try parser.append(data)
                for packet in packets {
                    handle(packet)
                }
            } catch {
                model.fail(error.localizedDescription)
                resumeStart(throwing: error)
                connection.cancel()
                return
            }
        }
        if let error {
            model.fail(error.localizedDescription)
            resumeStart(throwing: error)
            connection.cancel()
            return
        }
        if isComplete {
            guard !isClosed else { return }
            let error = StreamError.connectionClosed
            model.fail(error.localizedDescription)
            resumeStart(throwing: error)
            connection.cancel()
            return
        }
        receiveNextChunk()
    }

    private func resumeStart(throwing error: Error? = nil) {
        guard let continuation = startContinuation else { return }
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        startContinuation = nil
        startConfiguration = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func handle(_ packet: GreenhousePacket) {
        guard packet.streamID == streamID else { return }
        do {
            switch packet.kind {
            case .hello:
                let json = try jsonObject(from: packet.payload)
                if let displayID = json["displayId"] as? Int {
                    model.setDisplayID(displayID)
                }
                resumeStart()
                startPinging()
            case .videoConfig:
                let config = try JSONDecoder().decode(
                    VideoConfiguration.self,
                    from: packet.payload
                )
                guard let sps = Data(base64Encoded: config.sps),
                      let pps = Data(base64Encoded: config.pps) else {
                    throw StreamError.invalidVideoConfiguration
                }
                try decoder.configure(sps: sps, pps: pps)
                Task { @MainActor in
                    self.model.setVideoSize(
                        width: config.width,
                        height: config.height
                    )
                    self.model.setDisplayID(config.displayId)
                }
            case .videoFrame:
                guard packet.payload.count >= 12 else {
                    throw StreamError.invalidVideoFrame
                }
                let presentationTimeUs: Int64 = packet.payload.integer(at: 0)
                let flags: UInt32 = packet.payload.integer(at: 8)
                try decoder.decode(
                    packet.payload.dropFirst(12),
                    presentationTimeUs: presentationTimeUs,
                    flags: flags
                )
            case .audioConfig:
                let config = try JSONDecoder().decode(
                    AudioConfiguration.self,
                    from: packet.payload
                )
                guard config.codec == "pcm_s16le" else {
                    throw StreamError.unsupportedAudioCodec
                }
                model.setAudioScope(
                    config.scope,
                    packageName: config.packageName
                )
                Task { @MainActor in
                    do {
                        try self.audio.configure(
                            sampleRate: Double(config.sampleRate),
                            channels: AVAudioChannelCount(config.channels)
                        )
                    } catch {
                        self.model.fail(error.localizedDescription)
                    }
                }
            case .audioFrame:
                guard packet.payload.count >= 8 else {
                    throw StreamError.invalidAudioFrame
                }
                let presentationTimeUs: Int64 = packet.payload.integer(at: 0)
                let latency = clockSynchronizer.hostLatencyMilliseconds(
                    forGuestPresentationTime: CMTime(
                        value: presentationTimeUs,
                        timescale: 1_000_000
                    ),
                    hostNowNanos: DispatchTime.now().uptimeNanoseconds
                )
                model.recordAudioLatency(latency)
                let pcm = Data(packet.payload.dropFirst(8))
                Task { @MainActor in
                    do {
                        try self.audio.enqueue(pcm)
                    } catch {
                        self.model.fail(error.localizedDescription)
                    }
                }
            case .error:
                let json = try jsonObject(from: packet.payload)
                let message = json["message"] as? String ?? "Android stream failed."
                Task { @MainActor in
                    self.model.fail(message)
                }
            case .pong:
                let pong = try JSONDecoder().decode(
                    Pong.self,
                    from: packet.payload
                )
                clockSynchronizer.acceptPong(
                    hostSendNanos: pong.hostSendNanos,
                    guestReceiveNanos: pong.guestReceiveNanos,
                    guestSendNanos: pong.guestSendNanos,
                    hostReceiveNanos: DispatchTime.now().uptimeNanoseconds
                )
                model.updateControlRoundTrip(
                    clockSynchronizer.roundTripMilliseconds
                )
            default:
                break
            }
        } catch {
            Task { @MainActor in
                self.model.fail(error.localizedDescription)
            }
        }
    }

    private func sendJSON(
        kind: GreenhousePacketKind,
        object: [String: Any]
    ) throws {
        guard !isClosed || kind == .close else { return }
        let packet = try GreenhousePacket.json(
            kind: kind,
            streamID: streamID,
            object: object
        )
        connection.send(
            content: packet.encoded(),
            completion: .contentProcessed { [weak model] error in
                if let error {
                    Task { @MainActor in
                        model?.fail(error.localizedDescription)
                    }
                }
            }
        )
    }

    private func recommendedBitRate(width: Int, height: Int) -> Int {
        min(max(width * height * 8, 4_000_000), 32_000_000)
    }

    func presentationLatencyMilliseconds(
        for presentationTime: CMTime,
        hostNowNanos: UInt64
    ) -> Double? {
        clockSynchronizer.hostLatencyMilliseconds(
            forGuestPresentationTime: presentationTime,
            hostNowNanos: hostNowNanos
        )
    }

    private func startPinging() {
        guard pingTask == nil else { return }
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? self.sendJSON(
                    kind: .ping,
                    object: [
                        "hostSendNanos": DispatchTime.now().uptimeNanoseconds
                    ]
                )
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw StreamError.invalidJSON
        }
        return object
    }

    private struct VideoConfiguration: Decodable {
        let width: Int
        let height: Int
        let displayId: Int
        let sps: String
        let pps: String
    }

    private struct AudioConfiguration: Decodable {
        let codec: String
        let sampleRate: Int
        let channels: UInt32
        let packageName: String?
        let scope: String?
    }

    private struct StartConfiguration: Sendable {
        let width: Int
        let height: Int
        let densityDpi: Int
        let frameRate: Int
        let bitRate: Int
        let audioEnabled: Bool
    }

    private struct Pong: Decodable {
        let hostSendNanos: UInt64
        let guestReceiveNanos: UInt64
        let guestSendNanos: UInt64
    }

    private enum StreamError: Error, LocalizedError {
        case invalidJSON
        case invalidVideoConfiguration
        case invalidVideoFrame
        case invalidAudioFrame
        case unsupportedAudioCodec
        case handshakeTimedOut
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                "The Android app-window agent sent invalid control data."
            case .invalidVideoConfiguration:
                "The Android encoder sent an incomplete H.264 configuration."
            case .invalidVideoFrame:
                "The Android encoder sent an invalid video frame."
            case .invalidAudioFrame:
                "The Android audio capture sent an invalid audio frame."
            case .unsupportedAudioCodec:
                "The Android audio capture selected an unsupported codec."
            case .handshakeTimedOut:
                "The Android app-window agent did not complete its handshake."
            case .connectionClosed:
                "The Android app-window stream closed unexpectedly."
            }
        }
    }
}

private extension Data {
    func integer<T: FixedWidthInteger>(at offset: Int) -> T {
        let size = MemoryLayout<T>.size
        return subdata(in: offset..<(offset + size)).withUnsafeBytes { bytes in
            T(bigEndian: bytes.loadUnaligned(as: T.self))
        }
    }
}
