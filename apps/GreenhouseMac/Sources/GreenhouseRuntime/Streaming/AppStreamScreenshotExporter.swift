import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AppStreamScreenshotExporter {
    public enum ExportError: Error, LocalizedError {
        case imageCreationFailed
        case pngEncodingFailed

        public var errorDescription: String? {
            switch self {
            case .imageCreationFailed:
                "The current Android frame could not be converted into an image."
            case .pngEncodingFailed:
                "The current Android frame could not be encoded as a PNG."
            }
        }
    }

    public static func pngData(from pixelBuffer: CVPixelBuffer) throws -> Data {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw ExportError.imageCreationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.pngEncodingFailed
        }
        return data as Data
    }
}
