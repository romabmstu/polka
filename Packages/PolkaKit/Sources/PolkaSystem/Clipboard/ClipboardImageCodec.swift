import Foundation
import ImageIO
import PolkaCore
import UniformTypeIdentifiers

/// Turns pasteboard picture data into a `ClipboardImage` with ImageIO, which
/// is safe to call off the main thread. Large pictures take hundreds of
/// milliseconds to re-encode, so this never runs on the main actor.
public enum ClipboardImageCodec {
    /// Longest side of the preview shown in the clipboard list, in pixels
    /// (it is drawn at half that size in points).
    public static let previewPixelSize = 192

    /// Raw picture bytes as copied: PNG kept as is, anything else ImageIO
    /// reads (TIFF from Preview or Photos, JPEG, HEIC) converted to PNG.
    public enum Source: Sendable {
        case png(Data)
        case other(Data)
    }

    public static func makeImage(from source: Source) -> ClipboardImage? {
        let limit = ClipboardHistory.maximumImageBytes
        let png: Data
        switch source {
        case .png(let data):
            guard data.count <= limit else { return nil }
            png = data
        case .other(let data):
            guard let converted = pngData(from: data), converted.count <= limit else { return nil }
            png = converted
        }
        guard let image = CGImageSourceCreateWithData(png as CFData, nil),
            CGImageSourceGetCount(image) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        return ClipboardImage(png: png, pixelWidth: width, pixelHeight: height, preview: preview(of: image) ?? Data())
    }

    /// TIFF for apps that can't paste PNG. Made only when such an app asks.
    public static func tiffData(fromPNG png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return encode(image, as: .tiff)
    }

    static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return encode(image, as: .png)
    }

    private static func preview(of source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: previewPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encode(thumbnail, as: .png)
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
