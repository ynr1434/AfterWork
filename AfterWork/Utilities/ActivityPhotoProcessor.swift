import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ActivityPhotoPixelSize: Equatable {
    let width: Int
    let height: Int
}

nonisolated enum ActivityPhotoProcessor {
    static let jpegQuality = 0.82

    static func resizedSize(width: Int, height: Int, maxLongEdge: Int = ActivityPhotoRules.maximumLongEdge) -> ActivityPhotoPixelSize? {
        guard width > 0, height > 0, maxLongEdge > 0 else { return nil }
        let scale = min(1, Double(maxLongEdge) / Double(max(width, height)))
        return ActivityPhotoPixelSize(
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }

    static func validateProcessedData(_ data: Data) throws {
        guard !data.isEmpty else { throw ActivityPhotoError.invalidImage }
        guard data.count <= ActivityPhotoRules.maximumUploadBytes else { throw ActivityPhotoError.tooLarge }
    }

    static func process(data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: ActivityPhotoRules.maximumLongEdge,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw ActivityPhotoError.invalidImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ActivityPhotoError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ActivityPhotoError.invalidImage }
        let processed = output as Data
        try validateProcessedData(processed)
        return processed
    }
}
