import AppKit
import Foundation
import UniformTypeIdentifiers

enum FileReferenceImportError: LocalizedError {
    case fileMissing(URL)
    case unreadable(URL)
    case directoriesUnsupported(URL)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let url):
            return "File does not exist: \(url.lastPathComponent)"
        case .unreadable(let url):
            return "File is not readable: \(url.lastPathComponent)"
        case .directoriesUnsupported(let url):
            return "Directories are not supported as Hermes attachments: \(url.lastPathComponent)"
        }
    }
}

enum FileReferenceImportSupport {
    static func attachment(from url: URL) throws -> HermesAttachmentReference {
        let fileURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileReferenceImportError.fileMissing(fileURL)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw FileReferenceImportError.directoriesUnsupported(fileURL)
        }

        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw FileReferenceImportError.unreadable(fileURL)
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let kindDescription = resourceValues?.contentType?.localizedDescription
            ?? UTType(filenameExtension: fileURL.pathExtension)?.localizedDescription
            ?? fileURL.pathExtension.uppercased()

        return HermesAttachmentReference(
            fileURL: fileURL,
            displayName: fileURL.lastPathComponent,
            kindDescription: kindDescription.isEmpty ? "File" : kindDescription,
            sizeBytes: Int64(resourceValues?.fileSize ?? 0)
        )
    }

    static func attachments(from urls: [URL]) -> [HermesAttachmentReference] {
        urls.compactMap { try? attachment(from: $0) }
    }

    static func attachments(from pasteboard: NSPasteboard = .general) -> [HermesAttachmentReference] {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return []
        }
        return attachments(from: urls.filter(\.isFileURL))
    }

    @discardableResult
    static func loadAttachments(
        from providers: [NSItemProvider],
        completion: @escaping ([HermesAttachmentReference], Int) -> Void
    ) -> Bool {
        guard !providers.isEmpty else {
            completion([], 0)
            return false
        }

        let state = FileReferenceDropImportState()
        var requestedLoads = 0

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            requestedLoads += 1
            state.group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { state.group.leave() }

                let url: URL?
                switch item {
                case let data as Data:
                    url = URL(dataRepresentation: data, relativeTo: nil)
                case let urlValue as URL:
                    url = urlValue
                case let nsURL as NSURL:
                    url = nsURL as URL
                case let string as String:
                    url = URL(string: string)
                default:
                    url = nil
                }

                guard let url, url.isFileURL,
                      let attachment = try? attachment(from: url) else {
                    return
                }
                state.append(attachment)
            }
        }

        state.group.notify(queue: .main) {
            completion(state.attachments, requestedLoads)
        }

        return requestedLoads > 0
    }
}

private final class FileReferenceDropImportState {
    let group = DispatchGroup()
    private let lock = NSLock()
    private var storage: [HermesAttachmentReference] = []

    var attachments: [HermesAttachmentReference] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ attachment: HermesAttachmentReference) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(attachment)
    }
}