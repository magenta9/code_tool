import Foundation

/// Events emitted by the Claude CLI NDJSON stream.
public enum ClaudeCLIEvent: Sendable {
    /// Session initialized with session ID and model name
    case initialized(sessionId: String, model: String)
    /// Thinking content delta
    case thinkingDelta(text: String)
    /// Text content delta (main streaming source)
    case textDelta(text: String)
    /// Tool use started
    case toolUseStart(id: String, name: String)
    /// Tool input JSON delta
    case toolInputDelta(text: String)
    /// Tool result received
    case toolResult(toolUseId: String, content: String)
    /// Content block completed
    case blockStop(index: Int)
    /// Final result with cost/usage
    case result(
        isError: Bool,
        totalCostUSD: Double,
        inputTokens: Int,
        outputTokens: Int,
        durationMs: Int,
        sessionId: String
    )
    /// Process exited
    case completed(exitCode: Int32)
    /// Error from stderr or process failure
    case error(message: String)
}

/// Request model for a single Claude CLI turn.
public struct ClaudeCLITurnRequest {
    public let prompt: String
    public let sessionID: String?
    public let referenceID: String?

    public init(prompt: String, sessionID: String?, referenceID: String? = nil) {
        self.prompt = prompt
        self.sessionID = sessionID
        self.referenceID = referenceID
    }
}

public final class ClaudeCLIClient: @unchecked Sendable {
    private var process: Process?
    private var isCancelled = false
    private let lock = NSLock()

    public init() {}

    /// Send a message to Claude CLI and receive streaming events via callback.
    public func send(
        request: ClaudeCLITurnRequest,
        settings: ClaudeCLISettingsStore,
        onEvent: @escaping @Sendable (ClaudeCLIEvent) -> Void
    ) async {
        await send(
            message: request.prompt,
            settings: settings,
            sessionId: request.sessionID,
            referenceID: request.referenceID,
            onEvent: onEvent
        )
    }

    /// Send a message to Claude CLI and receive streaming events via callback (legacy signature).
    public func send(
        message: String,
        settings: ClaudeCLISettingsStore,
        sessionId: String?,
        referenceID: String? = nil,
        onEvent: @escaping @Sendable (ClaudeCLIEvent) -> Void
    ) async {
        setCancelled(false)
        let resolvedReferenceID = referenceID ?? AppLogger.makeReferenceID()
        let promptSummary = AppRedactionPolicy.standard.redact(text: message)?.summary ?? ""

        let claudePath = settings.resolvedClaudePath
        guard !claudePath.isEmpty else {
            let missingCLIError = NSError(
                domain: "ClaudeCLIClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Claude CLI not found"]
            )
            _ = await AppLogger.shared.error(
                category: .claudechat,
                event: "claude_process_failed",
                referenceID: resolvedReferenceID,
                message: "Claude CLI binary is unavailable.",
                metadata: ["stage": "resolve_cli_path"],
                error: missingCLIError
            )
            onEvent(.error(message: "Claude CLI not found"))
            onEvent(.completed(exitCode: -1))
            return
        }

        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model", settings.model,
            "--max-turns", String(settings.maxTurns),
        ]

        if settings.maxBudgetUSD > 0 {
            arguments += ["--max-budget-usd", String(settings.maxBudgetUSD)]
        }

        if settings.useBare {
            arguments.append("--bare")
        }

        if let sessionId, !sessionId.isEmpty {
            arguments += ["--resume", sessionId]
        }

        let trimmedSystemPrompt = settings.systemPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystemPrompt.isEmpty {
            arguments += ["--append-system-prompt", trimmedSystemPrompt]
        }

        // User message is the last positional argument
        arguments.append(message)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = arguments

        // Working directory
        let cwd = settings.workingDirectory
        if FileManager.default.fileExists(atPath: cwd) {
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        // Environment: only pass API key if set
        var env = ProcessInfo.processInfo.environment
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            env["ANTHROPIC_API_KEY"] = apiKey
        }
        proc.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        await AppLogger.shared.info(
            category: .claudechat,
            event: "claude_process_started",
            referenceID: resolvedReferenceID,
            message: "Started Claude CLI subprocess.",
            metadata: [
                "model": settings.model,
                "workingDirectory": proc.currentDirectoryURL?.lastPathComponent ?? URL(fileURLWithPath: settings.workingDirectory).lastPathComponent,
                "resumingSession": String(!(sessionId ?? "").isEmpty),
                "promptSummary": promptSummary
            ]
        )

        setProcess(proc)

        do {
            try proc.run()
        } catch {
            _ = await AppLogger.shared.error(
                category: .claudechat,
                event: "claude_process_failed",
                referenceID: resolvedReferenceID,
                message: "Failed to launch Claude CLI subprocess.",
                metadata: ["stage": "launch_process", "model": settings.model],
                error: error
            )
            onEvent(.error(message: "Failed to launch Claude CLI: \(error.localizedDescription)"))
            onEvent(.completed(exitCode: -1))
            return
        }

        // Read stdout line by line on a background thread
        let fileHandle = stdoutPipe.fileHandleForReading

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var leftover = Data()

                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty { break } // EOF

                    leftover.append(data)

                    // Split by newlines
                    while let newlineIndex = leftover.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = leftover[leftover.startIndex..<newlineIndex]
                        leftover = Data(leftover[leftover.index(after: newlineIndex)...])

                        guard !lineData.isEmpty else { continue }

                        self?.parseLine(
                            Data(lineData),
                            referenceID: resolvedReferenceID,
                            onEvent: onEvent
                        )
                    }
                }

                // Process remaining data
                if !leftover.isEmpty {
                    self?.parseLine(
                        leftover,
                        referenceID: resolvedReferenceID,
                        onEvent: onEvent
                    )
                }

                proc.waitUntilExit()

                // Read stderr
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !stderrData.isEmpty,
                   let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !stderrText.isEmpty {
                    Task {
                        let stderrError = NSError(
                            domain: "ClaudeCLIClient.stderr",
                            code: Int(proc.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: stderrText]
                        )
                        _ = await AppLogger.shared.error(
                            category: .claudechat,
                            event: "claude_process_stderr",
                            referenceID: resolvedReferenceID,
                            message: "Claude CLI wrote to stderr.",
                            metadata: [
                                "stage": "stderr",
                                "stderrSummary": AppRedactionPolicy.standard.redact(text: stderrText)?.summary ?? ""
                            ],
                            error: stderrError,
                            stackTrace: []
                        )
                    }
                    onEvent(.error(message: stderrText))
                }

                Task {
                    if proc.terminationStatus == 0 {
                        await AppLogger.shared.info(
                            category: .claudechat,
                            event: "claude_process_completed",
                            referenceID: resolvedReferenceID,
                            message: "Claude CLI subprocess completed.",
                            metadata: ["exitCode": String(proc.terminationStatus)]
                        )
                    } else {
                        let exitError = NSError(
                            domain: "ClaudeCLIClient.exit",
                            code: Int(proc.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Claude CLI exited with a non-zero status."]
                        )
                        _ = await AppLogger.shared.error(
                            category: .claudechat,
                            event: "claude_process_failed",
                            referenceID: resolvedReferenceID,
                            message: "Claude CLI subprocess exited with a non-zero status.",
                            metadata: ["stage": "process_exit", "exitCode": String(proc.terminationStatus)],
                            error: exitError,
                            stackTrace: []
                        )
                    }
                }
                onEvent(.completed(exitCode: proc.terminationStatus))
                continuation.resume()
            }
        }

        clearProcess()
    }

    /// Cancel the current Claude CLI process.
    public func cancel() {
        setCancelled(true)
        let proc = currentProcess()
        proc?.terminate()
    }

    private func setCancelled(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = newValue
    }

    private func setProcess(_ newProcess: Process?) {
        lock.lock()
        defer { lock.unlock() }
        process = newProcess
    }

    private func clearProcess() {
        setProcess(nil)
    }

    private func currentProcess() -> Process? {
        lock.lock()
        defer { lock.unlock() }
        return process
    }

    // MARK: - NDJSON Parsing

    private func parseLine(
        _ data: Data,
        referenceID: String,
        onEvent: @escaping (ClaudeCLIEvent) -> Void
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "system":
            if let subtype = json["subtype"] as? String, subtype == "init" {
                let sessionId = json["session_id"] as? String ?? ""
                let model = json["model"] as? String ?? ""
                Task {
                    await AppLogger.shared.info(
                        category: .claudechat,
                        event: "claude_session_initialized",
                        referenceID: referenceID,
                        message: "Claude CLI session initialized.",
                        metadata: ["sessionId": sessionId, "model": model]
                    )
                }
                onEvent(.initialized(sessionId: sessionId, model: model))
            }

        case "stream_event":
            guard let event = json["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return }

            switch eventType {
            case "content_block_start":
                if let block = event["content_block"] as? [String: Any],
                   let blockType = block["type"] as? String {
                    if blockType == "tool_use" {
                        let id = block["id"] as? String ?? ""
                        let name = block["name"] as? String ?? ""
                        onEvent(.toolUseStart(id: id, name: name))
                    }
                }

            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   let deltaType = delta["type"] as? String {
                    switch deltaType {
                    case "thinking_delta":
                        if let text = delta["thinking"] as? String {
                            onEvent(.thinkingDelta(text: text))
                        }
                    case "text_delta":
                        if let text = delta["text"] as? String {
                            onEvent(.textDelta(text: text))
                        }
                    case "input_json_delta":
                        if let text = delta["partial_json"] as? String {
                            onEvent(.toolInputDelta(text: text))
                        }
                    default:
                        break
                    }
                }

            case "content_block_stop":
                let index = event["index"] as? Int ?? -1
                onEvent(.blockStop(index: index))

            default:
                break
            }

        case "result":
            let isError = json["is_error"] as? Bool ?? false
            let cost = json["total_cost_usd"] as? Double ?? 0.0
            let durationMs = json["duration_ms"] as? Int ?? 0
            let sessionId = json["session_id"] as? String ?? ""

            var inputTokens = 0
            var outputTokens = 0
            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["input_tokens"] as? Int ?? 0
                outputTokens = usage["output_tokens"] as? Int ?? 0
            }

            Task {
                await AppLogger.shared.log(
                    level: isError ? .error : .info,
                    category: .claudechat,
                    event: isError ? "claude_turn_failed" : "claude_turn_finished",
                    referenceID: referenceID,
                    message: isError ? "Claude CLI reported an error result." : "Claude CLI reported a successful result.",
                    metadata: [
                        "sessionId": sessionId,
                        "inputTokens": String(inputTokens),
                        "outputTokens": String(outputTokens),
                        "totalCostUSD": String(cost)
                    ],
                    durationMs: durationMs
                )
            }
            onEvent(.result(
                isError: isError,
                totalCostUSD: cost,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                durationMs: durationMs,
                sessionId: sessionId
            ))

        default:
            break // Ignore "assistant" snapshot messages etc.
        }
    }
}
