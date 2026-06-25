import CoreVideo
import ImageIO
import XCTest
@testable import GreenhouseCore
@testable import GreenhouseRuntime

final class AppStreamControlHelperTests: XCTestCase {
    func testAndroidNavigationKeyConstantsMatchAndroidKeyCodes() {
        XCTAssertEqual(AndroidNavigationKey.back.rawValue, 111)
        XCTAssertEqual(AndroidNavigationKey.home.rawValue, 3)
        XCTAssertEqual(AndroidNavigationKey.appSwitch.rawValue, 187)
    }

    @MainActor
    func testSessionMuteStateUpdatesModel() {
        let session = AppStreamSession(
            app: .demoGame,
            streamID: 1,
            localPort: 27184
        )

        XCTAssertFalse(session.model.isMuted)

        session.setMuted(true)
        XCTAssertTrue(session.model.isMuted)

        session.setMuted(false)
        XCTAssertFalse(session.model.isMuted)
    }

    func testScreenshotExporterCreatesPNGFromPixelBuffer() throws {
        let pixelBuffer = try makePixelBuffer(width: 2, height: 2)

        let png = try AppStreamScreenshotExporter.pngData(from: pixelBuffer)

        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(result, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
            .assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                base[offset] = 0x20
                base[offset + 1] = 0x90
                base[offset + 2] = 0xD0
                base[offset + 3] = 0xFF
            }
        }
        return buffer
    }
}
