import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class VideoToolboxDecoder {
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private let frameHandler: @Sendable (CVPixelBuffer, CMTime) -> Void

    init(frameHandler: @escaping @Sendable (CVPixelBuffer, CMTime) -> Void) {
        self.frameHandler = frameHandler
    }

    deinit {
        invalidate()
    }

    func configure(sps: Data, pps: Data) throws {
        invalidate()
        let parameterSets = [stripStartCode(from: sps), stripStartCode(from: pps)]
        var description: CMFormatDescription?
        let status = parameterSets.withUnsafeBytes { buffers in
            let pointers: [UnsafePointer<UInt8>] = buffers.map { buffer in
                buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            }
            let sizes = buffers.map(\.count)
            return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &description
            )
        }
        guard status == noErr, let description else {
            throw DecoderError.formatDescription(status)
        }
        formatDescription = description

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, imageBuffer, pts, _ in
                guard status == noErr,
                      let refcon,
                      let imageBuffer else {
                    return
                }
                let decoder = Unmanaged<VideoToolboxDecoder>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                decoder.frameHandler(imageBuffer, pts)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let attributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        var newSession: VTDecompressionSession?
        let createStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &newSession
        )
        guard createStatus == noErr, let newSession else {
            throw DecoderError.sessionCreation(createStatus)
        }
        session = newSession
    }

    func decode(_ encoded: Data, presentationTimeUs: Int64, flags: UInt32) throws {
        guard let formatDescription, let session else {
            throw DecoderError.notConfigured
        }
        let avcc = annexBToAVCC(encoded)
        var blockBuffer: CMBlockBuffer?
        let blockStatus = avcc.withUnsafeBytes { bytes in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: bytes.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: bytes.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw DecoderError.blockBuffer(blockStatus)
        }
        let replaceStatus = avcc.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: bytes.count
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw DecoderError.blockBuffer(replaceStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(
                value: presentationTimeUs,
                timescale: 1_000_000
            ),
            decodeTimeStamp: .invalid
        )
        var sampleSize = avcc.count
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw DecoderError.sampleBuffer(sampleStatus)
        }

        var infoFlags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: VTDecodeFrameFlags(rawValue: 1),
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )
        guard decodeStatus == noErr else {
            throw DecoderError.decode(decodeStatus)
        }
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

    private func stripStartCode(from data: Data) -> Data {
        if data.starts(with: [0, 0, 0, 1]) {
            return data.dropFirst(4)
        }
        if data.starts(with: [0, 0, 1]) {
            return data.dropFirst(3)
        }
        return data
    }

    private func annexBToAVCC(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var starts: [(offset: Int, length: Int)] = []
        var index = 0
        while index + 3 < bytes.count {
            if bytes[index] == 0 && bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 {
                    starts.append((index, 3))
                    index += 3
                    continue
                }
                if bytes[index + 2] == 0 && bytes[index + 3] == 1 {
                    starts.append((index, 4))
                    index += 4
                    continue
                }
            }
            index += 1
        }
        guard !starts.isEmpty else {
            return data
        }

        var output = Data()
        for nalIndex in starts.indices {
            let start = starts[nalIndex].offset + starts[nalIndex].length
            let end = nalIndex + 1 < starts.count
                ? starts[nalIndex + 1].offset
                : bytes.count
            guard end > start else { continue }
            var length = UInt32(end - start).bigEndian
            withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
            output.append(contentsOf: bytes[start..<end])
        }
        return output
    }

    enum DecoderError: Error {
        case notConfigured
        case formatDescription(OSStatus)
        case sessionCreation(OSStatus)
        case blockBuffer(OSStatus)
        case sampleBuffer(OSStatus)
        case decode(OSStatus)
    }
}

private extension Array where Element == Data {
    func withUnsafeBytes<Result>(
        _ body: ([UnsafeRawBufferPointer]) throws -> Result
    ) rethrows -> Result {
        func recurse(
            _ index: Int,
            _ buffers: [UnsafeRawBufferPointer]
        ) throws -> Result {
            if index == count {
                return try body(buffers)
            }
            return try self[index].withUnsafeBytes { buffer in
                try recurse(index + 1, buffers + [buffer])
            }
        }
        return try recurse(0, [])
    }
}
