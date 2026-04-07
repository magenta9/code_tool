import Foundation

enum HermesPromptComposerError: LocalizedError {
    case contextReferencesUnavailable
    case missingAttachment(URL)
    case unreadableAttachment(URL)

    var errorDescription: String? {
        switch self {
        case .contextReferencesUnavailable:
            return "Current Hermes CLI version does not expose context references for file attachments."
        case .missingAttachment(let url):
            return "Attachment is missing: \(url.lastPathComponent)"
        case .unreadableAttachment(let url):
            return "Attachment is not readable: \(url.lastPathComponent)"
        }
    }
}

public enum HermesPromptComposer {
    public static func compose(
        text: String,
        attachments: [HermesAttachmentReference],
        capabilities: HermesCapabilityMatrix
    ) throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let uniqueAttachments = deduplicate(attachments)

        guard uniqueAttachments.isEmpty || capabilities.supportsContextReferences else {
            throw HermesPromptComposerError.contextReferencesUnavailable
        }

        for attachment in uniqueAttachments {
            guard FileManager.default.fileExists(atPath: attachment.fileURL.path) else {
                throw HermesPromptComposerError.missingAttachment(attachment.fileURL)
            }
            guard FileManager.default.isReadableFile(atPath: attachment.fileURL.path) else {
                throw HermesPromptComposerError.unreadableAttachment(attachment.fileURL)
            }
        }

        guard !uniqueAttachments.isEmpty else {
            return trimmedText
        }

        var parts = uniqueAttachments.map { "@file:\($0.fileURL.path)" }
        parts.append("")
        parts.append(trimmedText.isEmpty ? "Please inspect the attached files." : trimmedText)
        return parts.joined(separator: "\n")
    }

    private static func deduplicate(
        _ attachments: [HermesAttachmentReference]
    ) -> [HermesAttachmentReference] {
        var seenPaths = Set<String>()
        var result: [HermesAttachmentReference] = []

        for attachment in attachments {
            let normalizedPath = attachment.fileURL.standardizedFileURL.path
            guard seenPaths.insert(normalizedPath).inserted else {
                continue
            }
            result.append(attachment)
        }

        return result
    }
}