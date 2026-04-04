import AppKit
import Foundation
import UniformTypeIdentifiers

struct ImportedImageAsset {
    let image: NSImage
    let pngData: Data
    let fileName: String
    let mimeType: String
    let sizeBytes: Int
}

enum ImageImportError: LocalizedError {
    case unreadableImage
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Unable to read the selected image."
        case .unsupportedType:
            return "Unsupported image type."
        }
    }
}

enum ImageImportSupport {
    static let supportedImageTypes: [UTType] = [.png, .jpeg, .gif, .webP]

    static func importAsset(from url: URL) throws -> ImportedImageAsset {
        let contentType =
            try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let inferredType = contentType ?? UTType(filenameExtension: url.pathExtension)

        guard let inferredType,
              supportedImageTypes.contains(where: { inferredType.conforms(to: $0) })
        else {
            throw ImageImportError.unsupportedType
        }

        let data = try Data(contentsOf: url)
        return try importAsset(from: data, suggestedFileName: url.lastPathComponent)
    }

    static func importAssets(from urls: [URL]) -> [ImportedImageAsset] {
        urls.compactMap { try? importAsset(from: $0) }
    }

    static func importAsset(
        from data: Data,
        suggestedFileName: String? = nil
    ) throws -> ImportedImageAsset {
        guard let image = NSImage(data: data) else {
            throw ImageImportError.unreadableImage
        }

        // Prefer preserving PNG data directly when possible to avoid
        // lossy TIFF-based reconversion which can fail for some images
        if isPNGData(data) {
            let fileName = normalizedPNGFileName(for: suggestedFileName)
            return ImportedImageAsset(
                image: image,
                pngData: data,
                fileName: fileName,
                mimeType: "image/png",
                sizeBytes: data.count
            )
        }

        return try importAsset(from: image, suggestedFileName: suggestedFileName)
    }

    private static func isPNGData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        return Array(data.prefix(4)) == magic
    }

    static func importAsset(
        from image: NSImage,
        suggestedFileName: String? = nil
    ) throws -> ImportedImageAsset {
        guard let pngData = pngData(for: image) else {
            throw ImageImportError.unreadableImage
        }

        let fileName = normalizedPNGFileName(for: suggestedFileName)
        return ImportedImageAsset(
            image: image,
            pngData: pngData,
            fileName: fileName,
            mimeType: "image/png",
            sizeBytes: pngData.count
        )
    }

    static func importAssets(from pasteboard: NSPasteboard = .general) -> [ImportedImageAsset] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: supportedImageTypes.map(\.identifier)
        ]) as? [URL] {
            let assets = importAssets(from: urls)
            if !assets.isEmpty {
                return assets
            }
        }

        let binaryTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in binaryTypes {
            if let data = pasteboard.data(forType: type),
               let asset = try? importAsset(from: data, suggestedFileName: "pasted-image.png") {
                return [asset]
            }
        }

        if let image = NSImage(pasteboard: pasteboard),
           let asset = try? importAsset(from: image, suggestedFileName: "pasted-image.png") {
            return [asset]
        }

        return []
    }

    static func pasteboardImages(from pasteboard: NSPasteboard = .general) -> [NSImage] {
        importAssets(from: pasteboard).map(\.image)
    }

    static func dataURI(for asset: ImportedImageAsset) -> String {
        "data:\(asset.mimeType);base64,\(asset.pngData.base64EncodedString())"
    }

    static func normalizedPNGFileName(for suggestedFileName: String?) -> String {
        let fallback = "\(UUID().uuidString).png"
        guard let suggestedFileName else { return fallback }

        let trimmed = suggestedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        let sanitizedBase = baseName
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))

        let resolvedBase = sanitizedBase.isEmpty ? UUID().uuidString : sanitizedBase
        return "\(resolvedBase).png"
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
