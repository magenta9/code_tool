import Foundation

public struct HermesCLIProbeResult: Sendable {
    public let resolvedBinaryPath: String
    public let capabilityMatrix: HermesCapabilityMatrix?
    public let errorMessage: String?

    public init(
        resolvedBinaryPath: String,
        capabilityMatrix: HermesCapabilityMatrix?,
        errorMessage: String?
    ) {
        self.resolvedBinaryPath = resolvedBinaryPath
        self.capabilityMatrix = capabilityMatrix
        self.errorMessage = errorMessage
    }
}

public enum HermesCLIContractProbe {
    public static func discoverBinaryPath(customPath: String) -> String? {
        let trimmedCustomPath = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchPaths = trimmedCustomPath.isEmpty
            ? [
                "/opt/homebrew/bin/hermes",
                "/usr/local/bin/hermes",
                NSHomeDirectory() + "/.local/bin/hermes",
            ]
            : [trimmedCustomPath]

        for path in searchPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["hermes"]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }

    public static func probe(customPath: String = "") -> HermesCLIProbeResult {
        guard let resolvedBinaryPath = discoverBinaryPath(customPath: customPath) else {
            return HermesCLIProbeResult(
                resolvedBinaryPath: "",
                capabilityMatrix: nil,
                errorMessage: "Hermes CLI not found. Install Hermes or set a custom binary path."
            )
        }

        do {
            let snapshot = try collectHelpSnapshot(binaryPath: resolvedBinaryPath)
            let capabilityMatrix = parseCapabilityMatrix(
                binaryPath: resolvedBinaryPath,
                snapshot: snapshot
            )
            return HermesCLIProbeResult(
                resolvedBinaryPath: resolvedBinaryPath,
                capabilityMatrix: capabilityMatrix,
                errorMessage: nil
            )
        } catch {
            return HermesCLIProbeResult(
                resolvedBinaryPath: resolvedBinaryPath,
                capabilityMatrix: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    public static func parseCapabilityMatrix(
        binaryPath: String,
        snapshot: HermesCLIHelpSnapshot
    ) -> HermesCapabilityMatrix {
        let rawRootHelp = snapshot.rootHelpOutput
        let rawChatHelp = snapshot.chatHelpOutput
        let rootHelp = rawRootHelp.lowercased()
        let chatHelp = rawChatHelp.lowercased()
        let sessionsHelp = snapshot.sessionsHelpOutput.lowercased()
        let sessionsListHelp = snapshot.sessionsListHelpOutput?.lowercased() ?? ""

        let hasVerbose = containsAny(chatHelp + "\n" + rootHelp, needles: ["--verbose", "-v"])
        let hasStructuredOutput = containsAny(
            chatHelp + "\n" + rootHelp,
            needles: ["--output-format", "stream-json", "ndjson", "json output"]
        )
        let hasQuietOutput = containsAnyExact(rawRootHelp + "\n" + rawChatHelp, needles: ["--quiet", "-Q"])
            || containsAny(rootHelp + "\n" + chatHelp, needles: ["only output the final response"])
        let supportsSessionsList = !sessionsListHelp.isEmpty
            || sessionsHelp.contains("commands:\n  list")
            || sessionsHelp.contains("\n  list")
            || sessionsHelp.contains("\nlist")

        let outputMode: HermesOutputMode
        if hasStructuredOutput {
            outputMode = .structured
        } else if hasQuietOutput {
            outputMode = .finalTextOnly
        } else if hasVerbose {
            outputMode = .humanStreaming
        } else {
            outputMode = .finalTextOnly
        }

        return HermesCapabilityMatrix(
            binaryPath: binaryPath,
            versionString: normalizeVersion(snapshot.versionOutput),
            supportsChatQuery: containsAny(chatHelp, needles: ["-q", "--query"]),
            supportsQuietOutput: hasQuietOutput,
            supportsResumeFlag: containsAny(rootHelp + "\n" + chatHelp, needles: ["--resume", "-r"]),
            supportsContinueFlag: containsAny(rootHelp + "\n" + chatHelp, needles: ["--continue", "-c"]),
            supportsSessionsList: supportsSessionsList,
            supportsModelFlag: containsAny(chatHelp, needles: ["--model", "-m"]),
            supportsProfileFlag: containsAny(rootHelp, needles: ["--profile", "-p"]),
            supportsContextReferences: containsAny(
                snapshot.chatHelpOutput + "\n" + snapshot.rootHelpOutput,
                needles: ["@file:", "@folder:", "context reference", "context references", "@diff", "@staged"]
            ),
            outputMode: outputMode
        )
    }

    private static func collectHelpSnapshot(binaryPath: String) throws -> HermesCLIHelpSnapshot {
        HermesCLIHelpSnapshot(
            versionOutput: try run(binaryPath: binaryPath, arguments: ["--version"]),
            rootHelpOutput: try run(binaryPath: binaryPath, arguments: ["--help"]),
            chatHelpOutput: try run(binaryPath: binaryPath, arguments: ["chat", "--help"]),
            sessionsHelpOutput: try run(binaryPath: binaryPath, arguments: ["sessions", "--help"]),
            sessionsListHelpOutput: try? run(binaryPath: binaryPath, arguments: ["sessions", "list", "--help"])
        )
    }

    private static func run(binaryPath: String, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "HermesCLIContractProbe",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: stderr.isEmpty
                        ? "Hermes help command failed."
                        : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
            )
        }

        return stdout.isEmpty ? stderr : stdout
    }

    private static func containsAny(_ haystack: String, needles: [String]) -> Bool {
        let normalized = haystack.lowercased()
        return needles.contains { normalized.contains($0.lowercased()) }
    }

    private static func containsAnyExact(_ haystack: String, needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func normalizeVersion(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.lowercased().hasPrefix("hermes ") {
            return String(trimmed.dropFirst("hermes ".count))
        }

        if trimmed.lowercased().hasPrefix("hermes") {
            return trimmed.replacingOccurrences(of: "hermes", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }
}