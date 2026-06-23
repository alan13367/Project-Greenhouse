import AVFoundation
import Foundation

@MainActor
final class AudioPlaybackEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?

    init() {
        engine.attach(player)
    }

    func configure(sampleRate: Double, channels: AVAudioChannelCount) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else {
            throw AudioError.invalidFormat
        }
        if engine.isRunning {
            player.stop()
            engine.stop()
        }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.play()
        self.format = format
    }

    func enqueue(_ pcm: Data) throws {
        guard let format else {
            throw AudioError.notConfigured
        }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else {
            throw AudioError.invalidFormat
        }
        let frameCount = pcm.count / bytesPerFrame
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
        guard let destination = audioBuffer.mData else {
            throw AudioError.invalidFormat
        }
        pcm.copyBytes(to: destination.assumingMemoryBound(to: UInt8.self), count: pcm.count)
        player.scheduleBuffer(buffer)
    }

    func stop() {
        player.stop()
        engine.stop()
        format = nil
    }

    private enum AudioError: Error {
        case notConfigured
        case invalidFormat
    }
}
