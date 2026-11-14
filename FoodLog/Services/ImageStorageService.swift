import Foundation
import UIKit

public final class ImageStorageService: @unchecked Sendable {
    public static let shared = ImageStorageService()
    public let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.baseDirectory = appSupport.appendingPathComponent("FoodLogPhotos", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
    }

    /// Downscales large photos to max 1440px and compresses as JPEG (0.76) so local storage never bloats.
    public func saveOptimizedPhoto(data: Data, maxDimension: CGFloat = 1440, compressionQuality: CGFloat = 0.76) throws -> String {
        let compressed = Self.compressImageData(data, maxDimension: maxDimension, quality: compressionQuality)
        let filename = "food-\(UUID().uuidString.lowercased()).jpg"
        let destination = baseDirectory.appendingPathComponent(filename)
        try compressed.write(to: destination, options: .atomic)
        return filename
    }

    public func saveRawPhotoData(_ data: Data, preferredFilename: String? = nil) throws -> String {
        let safeName: String
        if let preferredFilename, !preferredFilename.isEmpty {
            safeName = URL(fileURLWithPath: preferredFilename).lastPathComponent
        } else {
            safeName = "food-\(UUID().uuidString.lowercased()).jpg"
        }
        let destination = baseDirectory.appendingPathComponent(safeName)
        try data.write(to: destination, options: .atomic)
        return safeName
    }

    public func loadPhotoData(filename: String) -> Data? {
        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        let url = baseDirectory.appendingPathComponent(safeName)
        return try? Data(contentsOf: url)
    }

    public func loadImage(filename: String) -> UIImage? {
        guard let data = loadPhotoData(filename: filename) else { return nil }
        return UIImage(data: data)
    }

    public func deletePhotos(filenames: [String]) {
        for filename in filenames {
            let safeName = URL(fileURLWithPath: filename).lastPathComponent
            let url = baseDirectory.appendingPathComponent(safeName)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Prepares a compact JPEG payload (max 1024px) for sending to vision AI models.
    public static func prepareForAIUpload(_ data: Data) -> Data {
        compressImageData(data, maxDimension: 1024, quality: 0.72)
    }

    public static func compressImageData(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return data }

        let longest = max(size.width, size.height)
        let targetImage: UIImage
        if longest > maxDimension {
            let scale = maxDimension / longest
            let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            targetImage = image
        }
        return targetImage.jpegData(compressionQuality: quality) ?? data
    }
}
