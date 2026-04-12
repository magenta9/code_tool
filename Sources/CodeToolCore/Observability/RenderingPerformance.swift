import CodeToolFoundation
import Foundation

#if canImport(AppKit)
    import AppKit
#endif

enum RenderingPerformanceEvent: String {
    case toolSwitchStarted = "tool_switch_started"
    case toolSwitchFinished = "tool_switch_finished"
    case toolVisibilityChanged = "tool_visibility_changed"
    case toolCacheSnapshot = "tool_cache_snapshot"
    case historyDrawerOpened = "history_drawer_opened"
    case imageRestoreFirstPreviewReady = "image_restore_first_preview_ready"
    case imageRestoreCompleted = "image_restore_completed"
    case playbackTickObserved = "playback_tick_observed"
    case interactionLagObserved = "interaction_lag_observed"
}

struct RenderingPerformanceDashboard: Sendable {
    let isCaptureEnabled: Bool
    let recentEntries: [DiagnosticsMetricSummary]
    let latestSelectedToolID: String?
    let latestRetainedCount: Int?
    let latestMountedCount: Int?
    let latestHiddenMountedCount: Int?
    let maxRetainedCount: Int
    let maxHiddenMountedCount: Int
    let interactionLagSampleCount: Int
    let maxInteractionLagMs: Int?
    let slowToolSwitchCount: Int
    let maxToolSwitchDurationMs: Int?
}

private struct RenderingPerformanceSessionContext: Sendable {
    var selectedToolID: ToolID?
    var retainedToolIDs: [ToolID]
    var mountedToolIDs: [ToolID]
    var hiddenMountedToolIDs: [ToolID]
    var unloadedHiddenToolIDs: [ToolID]

    var metadata: [String: String] {
        [
            "selectedToolID": selectedToolID?.rawValue ?? "none",
            "retainedCount": String(retainedToolIDs.count),
            "mountedCount": String(mountedToolIDs.count),
            "hiddenMountedCount": String(hiddenMountedToolIDs.count),
            "unloadedHiddenCount": String(unloadedHiddenToolIDs.count),
            "retainedToolIDs": retainedToolIDs.map(\.rawValue).joined(separator: ","),
            "mountedToolIDs": mountedToolIDs.map(\.rawValue).joined(separator: ","),
            "hiddenMountedToolIDs": hiddenMountedToolIDs.map(\.rawValue).joined(separator: ","),
            "unloadedHiddenToolIDs": unloadedHiddenToolIDs.map(\.rawValue).joined(separator: ",")
        ]
    }
}

private final class RenderingPerformanceSessionState {
    static let shared = RenderingPerformanceSessionState()

    private let lock = NSLock()
    private var context = RenderingPerformanceSessionContext(
        selectedToolID: nil,
        retainedToolIDs: [],
        mountedToolIDs: [],
        hiddenMountedToolIDs: [],
        unloadedHiddenToolIDs: []
    )

    func update(_ context: RenderingPerformanceSessionContext) {
        lock.lock()
        self.context = context
        lock.unlock()
    }

    func snapshot() -> RenderingPerformanceSessionContext {
        lock.lock()
        defer { lock.unlock() }
        return context
    }
}

#if canImport(AppKit)
    @MainActor
    private final class RenderingPerformanceInteractionMonitor {
        static let shared = RenderingPerformanceInteractionMonitor()

        private var localMonitor: Any?
        private var sampleCount = 0
        private var lastRecordedAt = Date.distantPast
        private let sampleEvery = 8
        private let minimumLagMs = 24
        private let cooldown: TimeInterval = 0.4

        func setEnabled(_ isEnabled: Bool) {
            if isEnabled {
                startIfNeeded()
            } else {
                stop()
            }
        }

        private func startIfNeeded() {
            guard localMonitor == nil else {
                return
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] event in
                self?.sample(event: event)
                return event
            }
        }

        private func stop() {
            guard let localMonitor else {
                return
            }

            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
            sampleCount = 0
            lastRecordedAt = .distantPast
        }

        private func sample(event: NSEvent) {
            sampleCount += 1
            guard sampleCount.isMultiple(of: sampleEvery) else {
                return
            }

            let sampledAt = Date()
            let inputType = String(describing: event.type)

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                let lagMs = max(0, Int(Date().timeIntervalSince(sampledAt) * 1000))
                guard lagMs >= self.minimumLagMs else {
                    return
                }

                let now = Date()
                guard now.timeIntervalSince(self.lastRecordedAt) >= self.cooldown else {
                    return
                }

                self.lastRecordedAt = now
                RenderingPerformance.interactionLagObserved(durationMs: lagMs, inputType: inputType)
            }
        }
    }
#endif

enum RenderingPerformance {
    static let metricKind = "rendering_performance"
    static let captureEnabledDefaultsKey = "observability.renderingPerformance.captureEnabled"

    static var defaultCaptureEnabled: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    static func isCaptureEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard let storedValue = userDefaults.object(forKey: captureEnabledDefaultsKey) as? Bool else {
            return defaultCaptureEnabled
        }

        return storedValue
    }

    @MainActor
    static func configureCaptureIfNeeded(userDefaults: UserDefaults = .standard) {
        setCaptureEnabled(isCaptureEnabled(userDefaults: userDefaults), userDefaults: userDefaults)
    }

    @MainActor
    static func setCaptureEnabled(_ isEnabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(isEnabled, forKey: captureEnabledDefaultsKey)

        #if canImport(AppKit)
            RenderingPerformanceInteractionMonitor.shared.setEnabled(isEnabled)
        #endif
    }

    static func record(
        _ event: RenderingPerformanceEvent,
        toolID: ToolID? = nil,
        referenceID: String? = nil,
        durationMs: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        guard isCaptureEnabled() else {
            return
        }

        var enrichedMetadata = metadata
        if let toolID {
            enrichedMetadata["toolID"] = toolID.rawValue
        }
        if let durationMs {
            enrichedMetadata["durationMs"] = String(durationMs)
        }

        let normalizedMetadata = enrichedMetadata
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        Task {
            await AppLogger.shared.log(
                level: .debug,
                category: .observability,
                event: event.rawValue,
                referenceID: referenceID,
                metadata: normalizedMetadata,
                durationMs: durationMs
            )

            try? await DiagnosticsStore.shared.recordMetricSummary(
                DiagnosticsMetricSummary(
                    kind: metricKind,
                    metadata: [
                        "event": event.rawValue,
                        "referenceID": referenceID ?? ""
                    ].merging(normalizedMetadata, uniquingKeysWith: { _, new in new })
                )
            )
        }
    }

    static func toolSwitchStarted(
        from previousToolID: ToolID?,
        to nextToolID: ToolID?,
        retainedCount: Int,
        cacheHit: Bool
    ) {
        record(
            .toolSwitchStarted,
            toolID: nextToolID,
            metadata: [
                "previousToolID": previousToolID?.rawValue ?? "none",
                "nextToolID": nextToolID?.rawValue ?? "none",
                "retainedCount": String(retainedCount),
                "cacheHit": String(cacheHit)
            ]
        )
    }

    static func toolSwitchFinished(
        from previousToolID: ToolID?,
        to nextToolID: ToolID?,
        retainedCount: Int,
        durationMs: Int
    ) {
        record(
            .toolSwitchFinished,
            toolID: nextToolID,
            durationMs: durationMs,
            metadata: [
                "previousToolID": previousToolID?.rawValue ?? "none",
                "nextToolID": nextToolID?.rawValue ?? "none",
                "retainedCount": String(retainedCount)
            ]
        )
    }

    static func toolVisibilityChanged(
        toolID: ToolID?,
        isVisible: Bool,
        policy: ToolVisibilityPolicy,
        retained: Bool
    ) {
        record(
            .toolVisibilityChanged,
            toolID: toolID,
            metadata: [
                "isVisible": String(isVisible),
                "policy": policy.rawValue,
                "retained": String(retained)
            ]
        )
    }

    static func toolCacheSnapshot(selectedToolID: ToolID?, retainedToolIDs: [ToolID]) {
        let mountedToolIDs = retainedToolIDs.filter { toolID in
            selectedToolID == toolID || ToolVisibilityPolicyRegistry.policy(for: toolID) != .unloadOnHide
        }
        let hiddenMountedToolIDs = mountedToolIDs.filter { $0 != selectedToolID }
        let unloadedHiddenToolIDs = retainedToolIDs.filter {
            $0 != selectedToolID && ToolVisibilityPolicyRegistry.policy(for: $0) == .unloadOnHide
        }

        let context = RenderingPerformanceSessionContext(
            selectedToolID: selectedToolID,
            retainedToolIDs: retainedToolIDs,
            mountedToolIDs: mountedToolIDs,
            hiddenMountedToolIDs: hiddenMountedToolIDs,
            unloadedHiddenToolIDs: unloadedHiddenToolIDs
        )
        RenderingPerformanceSessionState.shared.update(context)

        record(
            .toolCacheSnapshot,
            toolID: selectedToolID,
            metadata: context.metadata
        )
    }

    static func interactionLagObserved(durationMs: Int, inputType: String) {
        let context = RenderingPerformanceSessionState.shared.snapshot()

        record(
            .interactionLagObserved,
            toolID: context.selectedToolID,
            durationMs: durationMs,
            metadata: context.metadata.merging(["inputType": inputType], uniquingKeysWith: { _, new in new })
        )
    }

    static func makeDashboard(
        from metricSummaries: [DiagnosticsMetricSummary],
        captureEnabled: Bool = isCaptureEnabled()
    ) -> RenderingPerformanceDashboard {
        let recentEntries = metricSummaries
            .filter { $0.kind == metricKind }
            .sorted { $0.createdAt > $1.createdAt }

        let cacheSnapshots = recentEntries.filter {
            $0.metadata["event"] == RenderingPerformanceEvent.toolCacheSnapshot.rawValue
        }
        let interactionLagEntries = recentEntries.filter {
            $0.metadata["event"] == RenderingPerformanceEvent.interactionLagObserved.rawValue
        }
        let toolSwitchFinishedEntries = recentEntries.filter {
            $0.metadata["event"] == RenderingPerformanceEvent.toolSwitchFinished.rawValue
        }

        let latestCacheSnapshot = cacheSnapshots.first
        let switchDurations = toolSwitchFinishedEntries.compactMap { summary in
            summary.metadata["durationMs"].flatMap(Int.init)
        }
        let interactionLagDurations = interactionLagEntries.compactMap { summary in
            summary.metadata["durationMs"].flatMap(Int.init)
        }

        return RenderingPerformanceDashboard(
            isCaptureEnabled: captureEnabled,
            recentEntries: Array(recentEntries.prefix(12)),
            latestSelectedToolID: latestCacheSnapshot?.metadata["selectedToolID"],
            latestRetainedCount: latestCacheSnapshot?.metadata["retainedCount"].flatMap(Int.init),
            latestMountedCount: latestCacheSnapshot?.metadata["mountedCount"].flatMap(Int.init),
            latestHiddenMountedCount: latestCacheSnapshot?.metadata["hiddenMountedCount"].flatMap(Int.init),
            maxRetainedCount: cacheSnapshots.compactMap { $0.metadata["retainedCount"].flatMap(Int.init) }.max() ?? 0,
            maxHiddenMountedCount: cacheSnapshots.compactMap { $0.metadata["hiddenMountedCount"].flatMap(Int.init) }.max() ?? 0,
            interactionLagSampleCount: interactionLagEntries.count,
            maxInteractionLagMs: interactionLagDurations.max(),
            slowToolSwitchCount: switchDurations.filter { $0 >= 80 }.count,
            maxToolSwitchDurationMs: switchDurations.max()
        )
    }
}
