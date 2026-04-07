import Foundation

public final class HermesCLIClient: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    public init() {}

    public static func makeCommand(
        request: HermesTurnRequest,
        capabilities: HermesCapabilityMatrix
    ) -> HermesCommand {
        var arguments: [String] = []
        let trimmedModelOrProfile = request.modelOrProfile?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedModelOrProfile, !trimmedModelOrProfile.isEmpty, capabilities.supportsProfileFlag {
            arguments += ["-p", trimmedModelOrProfile]
        }

        arguments.append("chat")

        if let trimmedModelOrProfile, !trimmedModelOrProfile.isEmpty,
           !capabilities.supportsProfileFlag,
           capabilities.supportsModelFlag {
            arguments += ["-m", trimmedModelOrProfile]
        }

        if capabilities.supportsChatQuery {
            arguments += ["-q", request.prompt]
        } else {
            arguments.append(request.prompt)
        }

        if let resumeSessionID = request.resumeSessionID,
           !resumeSessionID.isEmpty,
           capabilities.supportsResumeFlag {
            arguments += ["--resume", resumeSessionID]
        }

        switch capabilities.outputMode {
        case .finalTextOnly:
            if capabilities.supportsQuietOutput {
                arguments.append("-Q")
            }
        case .humanStreaming:
            arguments.append("-v")
        case .structured:
            arguments += ["--output-format", "stream-json"]
        }

        arguments.append(contentsOf: request.extraArguments)

        return HermesCommand(executablePath: capabilities.binaryPath, arguments: arguments)
    }

    public func send(
        request: HermesTurnRequest,
        capabilities: HermesCapabilityMatrix,
        onEvent: @escaping @Sendable (HermesAgentEvent) -> Void
    ) async {
        setCancelled(false)
        let command = Self.makeCommand(request: request, capabilities: capabilities)
        let promptSummary = AppLogger.summarize(text: request.prompt, limit: 120)

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startedAt = Date()
        onEvent(.phaseChanged(.launchingProcess))

        await AppLogger.shared.info(
            category: .hermesagent,
            event: "hermes_process_started",
            referenceID: request.referenceID,
            message: "Started Hermes CLI subprocess.",
            metadata: [
                "promptSummary": promptSummary,
                "resumingSession": String(!(request.resumeSessionID ?? "").isEmpty),
                "outputMode": capabilities.outputMode.rawValue,
            ]
        )

        do {
            try process.run()
        } catch {
            _ = await AppLogger.shared.error(
                category: .hermesagent,
                event: "hermes_process_failed",
                referenceID: request.referenceID,
                message: "Failed to launch Hermes CLI subprocess.",
                metadata: ["stage": HermesPhase.launchingProcess.rawValue],
                error: error,
                stackTrace: []
            )
            onEvent(.failed("Failed to launch Hermes CLI: \(error.localizedDescription)"))
            return
        }

        setProcess(process)
        onEvent(.phaseChanged(.waitingForResponse))

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let quietOutput = Self.parseQuietOutput(stdoutText)

                if capabilities.outputMode == .humanStreaming {
                    let trimmedOutput = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedOutput.isEmpty {
                        onEvent(.outputDelta(trimmedOutput))
                    }
                }

                Task {
                    if !stderrText.isEmpty {
                        await AppLogger.shared.log(
                            level: process.terminationStatus == 0 ? .info : .error,
                            category: .hermesagent,
                            event: process.terminationStatus == 0 ? "hermes_process_warning" : "hermes_process_stderr",
                            referenceID: request.referenceID,
                            message: "Hermes CLI wrote to stderr.",
                            metadata: [
                                "stderrSummary": AppLogger.summarize(text: stderrText, limit: 180)
                            ],
                            stackTrace: []
                        )
                    }
                }

                let finalOutput = capabilities.outputMode == .finalTextOnly
                    ? quietOutput.output
                    : stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedSessionID = quietOutput.sessionID ?? request.resumeSessionID
                let wasCancelled = self?.currentCancelled() ?? false

                if wasCancelled {
                    onEvent(.phaseChanged(.cancelled))
                    onEvent(.completed(
                        HermesTurnResult(
                            output: finalOutput,
                            sessionID: resolvedSessionID,
                            exitCode: process.terminationStatus,
                            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                            status: .cancelled
                        )
                    ))
                    continuation.resume()
                    return
                }

                if !stderrText.isEmpty && process.terminationStatus == 0 {
                    onEvent(.warning(stderrText))
                }

                guard process.terminationStatus == 0 else {
                    onEvent(.phaseChanged(.failed))
                    onEvent(.failed(stderrText.isEmpty ? "Hermes CLI exited with code \(process.terminationStatus)." : stderrText))
                    continuation.resume()
                    return
                }

                onEvent(.phaseChanged(.resolvingSessionMetadata))
                onEvent(.phaseChanged(.completed))
                onEvent(.completed(
                    HermesTurnResult(
                        output: finalOutput,
                        sessionID: resolvedSessionID,
                        exitCode: process.terminationStatus,
                        durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                        status: .completed
                    )
                ))

                continuation.resume()
            }
        }

        clearProcess()
    }

    public func cancel() {
        setCancelled(true)
        currentProcess()?.terminate()
    }

    private func setProcess(_ process: Process?) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
    }

    private func clearProcess() {
        setProcess(nil)
    }

    private func currentProcess() -> Process? {
        lock.lock()
        defer { lock.unlock() }
        return process
    }

    private func setCancelled(_ isCancelled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.isCancelled = isCancelled
    }

    private func currentCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    static func parseQuietOutput(_ output: String) -> (output: String, sessionID: String?) {
        let lines = output
            .split(omittingEmptySubsequences: false, whereSeparator: \ .isNewline)
            .map(String.init)

        var sessionID: String?
        var cleanedLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()

            if lowercased.hasPrefix("session_id:") {
                sessionID = trimmed
                    .split(separator: ":", maxSplits: 1)
                    .dropFirst()
                    .first?
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                continue
            }

            if trimmed.contains("Hermes") && (trimmed.contains("╭") || trimmed.contains("╰") || trimmed.contains("─")) {
                continue
            }

            cleanedLines.append(line)
        }

        let cleanedOutput = cleanedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        return (cleanedOutput, sessionID)
    }
}