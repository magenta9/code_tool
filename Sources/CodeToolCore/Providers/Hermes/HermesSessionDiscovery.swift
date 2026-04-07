import Foundation

public enum HermesSessionDiscoveryError: LocalizedError {
    case unsupported
    case unavailable(String)
    case unparseableOutput

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Current Hermes CLI version does not support session discovery."
        case .unavailable(let message):
            return message
        case .unparseableOutput:
            return "Unable to parse Hermes sessions list output."
        }
    }
}

public enum HermesSessionDiscovery {
    public static func discover(
        capabilities: HermesCapabilityMatrix
    ) async -> Result<[HermesSessionSummary], HermesSessionDiscoveryError> {
        guard capabilities.supportsSessionsList else {
            return .failure(.unsupported)
        }

        do {
            let output = try run(binaryPath: capabilities.binaryPath, arguments: ["sessions", "list"])
            let sessions = try parseListOutput(output)
            return .success(sessions)
        } catch let error as HermesSessionDiscoveryError {
            return .failure(error)
        } catch {
            return .failure(.unavailable(error.localizedDescription))
        }
    }

    public static func parseListOutput(_ output: String) throws -> [HermesSessionSummary] {
        let lines = output
            .split(whereSeparator: \ .isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let header = lines.first else {
            throw HermesSessionDiscoveryError.unparseableOutput
        }

        let hasTitleColumn = header.lowercased().contains("title")
        let hasSourceColumn = header.lowercased().contains("src")
        guard hasTitleColumn || hasSourceColumn else {
            throw HermesSessionDiscoveryError.unparseableOutput
        }

        let rows = lines.dropFirst().compactMap { line -> HermesSessionSummary? in
            let columns = line.components(separatedBy: Self.columnSeparator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if hasTitleColumn {
                guard columns.count >= 4 else { return nil }
                return HermesSessionSummary(
                    id: columns[3],
                    title: columns[0],
                    preview: columns[1],
                    updatedAtText: columns[2]
                )
            }

            guard columns.count >= 4 else { return nil }
            return HermesSessionSummary(
                id: columns[3],
                title: nil,
                preview: columns[0],
                updatedAtText: columns[1],
                source: columns[2]
            )
        }

        guard !rows.isEmpty else {
            throw HermesSessionDiscoveryError.unparseableOutput
        }

        return rows
    }

    private static let columnSeparator = try! NSRegularExpression(pattern: #"\s{2,}"#)

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
            throw HermesSessionDiscoveryError.unavailable(
                stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Hermes sessions list failed."
                    : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return stdout
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: range)

        guard !matches.isEmpty else {
            return [self]
        }

        var parts: [String] = []
        var previousLocation = startIndex

        for match in matches {
            guard let range = Range(match.range, in: self) else {
                continue
            }
            parts.append(String(self[previousLocation..<range.lowerBound]))
            previousLocation = range.upperBound
        }

        parts.append(String(self[previousLocation...]))
        return parts
    }
}