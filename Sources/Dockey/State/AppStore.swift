import AppKit
import Combine
import DockeyCore
import Foundation

enum LogStreamState: Equatable { case idle, connecting, following, ended, failed }

@MainActor
final class AppStore: ObservableObject {
    @Published var containers: [DockerContainer] = []
    @Published var contexts: [DockerContext] = []
    @Published var stats: [String: ContainerStats] = [:]
    @Published var images: [ImageSummary] = []
    @Published var volumes: [VolumeSummary] = []
    @Published var networks: [NetworkSummary] = []
    @Published var engineInfo: EngineInfo?
    @Published var selectedContext = "" {
        didSet {
            if oldValue != selectedContext, started {
                invalidateConnection(cancelRefresh: !selectingDiscoveredContext)
            }
        }
    }
    @Published var selectedSection: AppSection = .containers
    @Published var selectedContainerID: String?
    @Published var searchText = ""
    @Published var stateFilter: ContainerFilter = .all
    @Published var expandedGroupIDs: Set<String> = []
    @Published var isRefreshing = false
    @Published private var loadingResourceSections: Set<String> = []
    @Published private var resourceErrors: [String: String] = [:]
    @Published private(set) var liveUpdateError: String?
    @Published private(set) var metricsError: String?
    @Published var connectionError: String?
    @Published var operationError: String?
    @Published var pendingContainerIDs: Set<String> = []
    @Published var activity: [ActivityEntry] = []
    @Published var inspection: ContainerInspection?
    @Published private(set) var isLoadingInspection = false
    @Published private(set) var inspectionError: String?
    @Published private(set) var logStreamState: LogStreamState = .idle
    @Published private(set) var logError: String?
    @Published var logText = ""
    @Published var detailTab: DetailTab = .logs
    @Published var isDemo: Bool
    @Published var preferences: AppPreferences
    @Published private var connected = false

    private var client: DockerClient?
    private var started = false
    private var loadedContext = ""
    private var snapshotTask: Task<Void, Never>?
    private var snapshotRequestID: UUID?
    private var followUpSnapshot = false
    private var forceMetadataOnNextPass = false
    private var currentPassForcesMetadata = false
    private var selectingDiscoveredContext = false
    private var statsTask: Task<Void, Never>?
    private var statsRequestID: UUID?
    private var statsPublicationTask: Task<Void, Never>?
    private var pendingStats: [String: ContainerStats] = [:]
    private var eventsTask: Task<Void, Never>?
    private var eventsRequestID: UUID?
    private var eventReconciliationTask: Task<Void, Never>?
    private var eventResynchronizationTask: Task<Void, Never>?
    private var eventResynchronizationRequested = false
    private var eventStreamID: UUID?
    private var inventoryInvalidated = false
    private var resourcesInvalidated: Set<String> = []
    private var isApplicationActive = false
    private var areMetricsVisible = false
    private var engineInfoTask: Task<Void, Never>?
    private var resourceTasks: [String: Task<Void, Never>] = [:]
    private var resourceRequestIDs: [String: UUID] = [:]
    private var resourceInvalidationVersions: [String: UInt64] = [:]
    private let clock = ContinuousClock()
    private var contextsFetchedAt: ContinuousClock.Instant?
    private var engineInfoFetchedAt: ContinuousClock.Instant?
    private var resourcesFetchedAt: [String: ContinuousClock.Instant] = [:]
    private var logTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var inspectionTask: Task<ContainerInspection, Error>?
    private var mutationTasks: [UUID: Task<Void, Never>] = [:]
    private var mutationClients: [UUID: DockerClient] = [:]
    private var configurationGeneration = 0
    private var currentDetailRequest: UUID?
    private var currentLogRequest: UUID?
    private var isShuttingDown = false
    private var logBuffer = LogBuffer()
    private let defaults: UserDefaults
    private let preferencesKey = "appPreferences.v1"
    private let contextKey = "selectedContext.v1"

    init(
        demo: Bool = false, appearance: String? = nil, defaults: UserDefaults = .standard,
        client injectedClient: DockerClient? = nil
    ) {
        self.defaults = defaults
        self.isDemo = demo
        var saved = AppPreferences()
        if !demo, let data = defaults.data(forKey: preferencesKey),
            let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data)
        {
            saved = decoded
        }
        if let appearance, ["dark", "light", "system"].contains(appearance) { saved.appearance = appearance }
        saved.normalize()
        self.preferences = saved
        self.currentExecutablePath = saved.dockerExecutable
        self.selectedContext = demo ? DemoData.context.name : defaults.string(forKey: contextKey) ?? ""
        if !demo {
            self.client =
                injectedClient
                ?? DockerClient(
                    executableURL: saved.dockerExecutable.isEmpty ? nil : URL(fileURLWithPath: saved.dockerExecutable))
        }
    }

    var selectedContainer: DockerContainer? { containers.first { $0.id == selectedContainerID } }
    var runningCount: Int { containers.filter(\.isRunning).count }
    var unhealthyCount: Int { containers.filter(\.isUnhealthy).count }
    var isConnected: Bool { connected && connectionError == nil && loadedContext == selectedContext }
    var isLoadingResources: Bool { loadingResourceSections.contains(selectedSection.rawValue) }
    var resourceError: String? { resourceErrors[selectedSection.rawValue] }

    var groups: [ContainerGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContainerGrouping.groups(containers: containers, context: selectedContext).compactMap { group in
            let filtered = group.containers.filter { container in
                guard preferences.showStopped || ![.created, .exited, .dead].contains(container.state) else { return false }
                let stateMatches: Bool
                switch stateFilter {
                case .all: stateMatches = true
                case .running: stateMatches = container.isRunning
                case .stopped: stateMatches = [.exited, .created].contains(container.state)
                case .unhealthy: stateMatches = container.isUnhealthy
                }
                return stateMatches
                    && (query.isEmpty
                        || [container.name, container.image, group.name, container.service ?? ""].contains {
                            $0.localizedCaseInsensitiveContains(query)
                        })
            }
            return filtered.isEmpty
                ? nil : ContainerGroup(id: group.id, name: group.name, isCompose: group.isCompose, containers: filtered)
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        if isDemo {
            containers = DemoData.containers
            contexts = [DemoData.context]
            stats = DemoData.stats
            engineInfo = DemoData.engine
            images = DemoData.images
            volumes = DemoData.volumes
            networks = DemoData.networks
            loadedContext = selectedContext
            connected = true
            expandNewGroups(previous: [])
            addActivity("Demo workspace opened. All resources and operations are simulated.")
            return
        }
        await refresh()
    }

    func refresh() async {
        await requestSnapshot(explicit: true)
    }

    /// Reconcile an invalidated snapshot without replacing cached rows with a global busy state.
    func refreshInBackground() async {
        await requestSnapshot(explicit: false)
    }

    private func requestSnapshot(explicit: Bool, afterInvalidation: Bool = false) async {
        guard !isDemo, !isShuttingDown else { return }
        if let snapshotTask {
            if explicit {
                isRefreshing = true
                if !currentPassForcesMetadata { forceMetadataOnNextPass = true }
            }
            // A command may finish after this pass began. Read once more before calling it current.
            if afterInvalidation { followUpSnapshot = true }
            await snapshotTask.value
            return
        }
        guard let client else { return }
        let requestID = UUID()
        snapshotRequestID = requestID
        forceMetadataOnNextPass = explicit
        let showsProgress = explicit || loadedContext.isEmpty || loadedContext != selectedContext
        if isRefreshing != showsProgress { isRefreshing = showsProgress }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                guard self.snapshotRequestID == requestID, !Task.isCancelled, !self.isShuttingDown else { break }
                let forceMetadata = self.forceMetadataOnNextPass
                self.forceMetadataOnNextPass = false
                self.currentPassForcesMetadata = forceMetadata
                self.followUpSnapshot = false
                await self.refreshSnapshot(client: client, requestID: requestID, forceMetadata: forceMetadata)
                guard self.snapshotRequestID == requestID else { return }
            } while self.followUpSnapshot || self.forceMetadataOnNextPass
            if self.snapshotRequestID == requestID {
                self.snapshotTask = nil
                self.snapshotRequestID = nil
                self.currentPassForcesMetadata = false
                if self.isRefreshing { self.isRefreshing = false }
            }
        }
        snapshotTask = task
        await task.value
    }

    private func refreshSnapshot(client: DockerClient, requestID: UUID, forceMetadata: Bool) async {
        var generation = configurationGeneration
        let snapshotBeganAt = Date()
        do {
            if forceMetadata || !isRecent(contextsFetchedAt, seconds: 30) {
                let discovered = try await client.contexts()
                guard generation == configurationGeneration, snapshotRequestID == requestID,
                    !Task.isCancelled, !isShuttingDown
                else { return }
                if contexts != discovered { contexts = discovered }
                let local = discovered.filter(\.isLocal)
                if !local.contains(where: { $0.name == selectedContext }) {
                    selectingDiscoveredContext = true
                    selectedContext =
                        local.first(where: { $0.name == "colima" })?.name ?? local.first(where: \.isCurrent)?.name
                        ?? local.first?.name ?? ""
                    selectingDiscoveredContext = false
                }
                contextsFetchedAt = clock.now
            }
            generation = configurationGeneration
            guard !selectedContext.isEmpty else {
                throw DockerError.commandFailed(
                    "No local Docker context was found. Configure a local engine such as Colima, then refresh.")
            }
            let context = selectedContext
            observeEngine(client: client, context: context, generation: generation, since: snapshotBeganAt)
            let fresh = try await client.containers(context: context)
            guard scopeMatches(context, generation: generation), snapshotRequestID == requestID,
                !Task.isCancelled
            else { return }
            let previous = Set(ContainerGrouping.groups(containers: containers, context: context).map(\.id))
            // Avoid invalidating the entire SwiftUI list for an unchanged reconciliation result.
            if containers != fresh { containers = fresh }
            loadedContext = context
            if connectionError != nil { connectionError = nil }
            if !connected {
                addActivity("Connected to local context \(context).")
                connected = true
            }
            expandNewGroups(previous: previous)
            if defaults.string(forKey: contextKey) != context { defaults.set(context, forKey: contextKey) }
            if let selectedContainerID, !fresh.contains(where: { $0.id == selectedContainerID }) { closeDetail() }
            let activeIDs = Set(fresh.filter { [.running, .paused, .restarting].contains($0.state) }.map(\.id))
            let validStats = stats.filter { activeIDs.contains($0.key) }
            if validStats != stats { stats = validStats }
            refreshEngineInfo(client: client, context: context, generation: generation, force: forceMetadata)
            updateStatsSubscription()
            await refreshResources(
                selectedSection, client: client, context: context, generation: generation,
                force: forceMetadata, reportErrors: forceMetadata)
        } catch is CancellationError {
            return
        } catch {
            guard generation == configurationGeneration, snapshotRequestID == requestID,
                !Task.isCancelled, !isShuttingDown
            else { return }
            let message = error.localizedDescription
            if connectionError != message { addActivity("Connection unavailable: \(message)", isError: true) }
            connectionError = message
            connected = false
            stats = [:]
            stopStatsSubscription()
            logTask?.cancel()
            if selectedContainerID != nil {
                logError = "Engine unavailable: \(message)"
                logStreamState = .failed
            }
        }
    }

    private func scopeMatches(_ context: String, generation: Int) -> Bool {
        selectedContext == context && configurationGeneration == generation && !isShuttingDown
    }

    private func isRecent(_ timestamp: ContinuousClock.Instant?, seconds: Double) -> Bool {
        guard let timestamp else { return false }
        return timestamp.duration(to: clock.now) < .seconds(seconds)
    }

    private func refreshEngineInfo(client: DockerClient, context: String, generation: Int, force: Bool) {
        guard engineInfoTask == nil, force || !isRecent(engineInfoFetchedAt, seconds: 60) else { return }
        // Throttle failed metadata reads too; container discovery remains the connection authority.
        engineInfoFetchedAt = clock.now
        engineInfoTask = Task { [weak self] in
            defer {
                if let self, self.scopeMatches(context, generation: generation) { self.engineInfoTask = nil }
            }
            do {
                let value = try await client.engineInfo(context: context)
                guard let self, self.scopeMatches(context, generation: generation), !Task.isCancelled else { return }
                if self.engineInfo != value { self.engineInfo = value }
            } catch {}
        }
    }

    func setApplicationActive(_ active: Bool) {
        guard isApplicationActive != active else { return }
        isApplicationActive = active
        updateStatsSubscription()
        // A user returning to a disconnected workspace may have installed or started an engine.
        if active, started, !isDemo, eventsTask == nil {
            Task { [weak self] in await self?.refreshInBackground() }
        }
    }

    func setMetricsVisible(_ visible: Bool) {
        guard areMetricsVisible != visible else { return }
        areMetricsVisible = visible
        updateStatsSubscription()
    }

    private func observeEngine(client: DockerClient, context: String, generation: Int, since initialSince: Date) {
        guard eventsTask == nil, scopeMatches(context, generation: generation) else { return }
        let requestID = UUID()
        eventsRequestID = requestID
        eventsTask = Task { [weak self] in
            var delay = 1.0
            var since = initialSince
            while !Task.isCancelled {
                guard let self, self.scopeMatches(context, generation: generation),
                    self.eventsRequestID == requestID
                else { return }
                let openedAt = self.clock.now
                let stream = await client.events(context: context, since: since)
                guard !Task.isCancelled, self.scopeMatches(context, generation: generation),
                    self.eventsRequestID == requestID
                else { return }
                // Event gaps may include resource changes with no subsequent event to invalidate a fresh cache.
                for section in [AppSection.images, .volumes, .networks] {
                    self.resourcesFetchedAt.removeValue(forKey: section.rawValue)
                    self.resourceInvalidationVersions[section.rawValue, default: 0] &+= 1
                }
                self.engineInfoFetchedAt = nil
                // Drain events immediately; reconciliation must not fill the bounded stream buffer.
                self.eventStreamID = UUID()
                self.scheduleEventResynchronization(context: context, generation: generation)
                do {
                    for try await event in stream {
                        guard !Task.isCancelled, self.scopeMatches(context, generation: generation),
                            self.eventsRequestID == requestID
                        else { return }
                        delay = 1
                        if self.liveUpdateError != nil { self.liveUpdateError = nil }
                        self.receiveEngineEvent(event, client: client, context: context, generation: generation)
                    }
                    guard !Task.isCancelled else { return }
                    self.eventStreamID = nil
                    self.liveUpdateError = "Live engine updates disconnected. Reconnecting…"
                } catch {
                    guard !Task.isCancelled, self.scopeMatches(context, generation: generation),
                        self.eventsRequestID == requestID
                    else { return }
                    self.eventStreamID = nil
                    let message = "Live engine updates interrupted: \(error.localizedDescription)"
                    if self.liveUpdateError != message { self.liveUpdateError = message }
                }
                if openedAt.duration(to: self.clock.now) >= .seconds(30) { delay = 1 }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                delay = min(delay * 2, 30)
                since = Date()
            }
        }
    }

    private func scheduleEventResynchronization(context: String, generation: Int) {
        eventResynchronizationRequested = true
        guard eventResynchronizationTask == nil else { return }
        eventResynchronizationTask = Task { [weak self] in
            guard let self else { return }
            while self.eventResynchronizationRequested {
                guard self.scopeMatches(context, generation: generation), !Task.isCancelled else { return }
                self.eventResynchronizationRequested = false
                let streamID = self.eventStreamID
                await self.requestSnapshot(explicit: false, afterInvalidation: true)
                guard self.scopeMatches(context, generation: generation), !Task.isCancelled else { return }
                if self.eventStreamID == streamID, streamID != nil, self.isConnected {
                    self.liveUpdateError = nil
                }
            }
            self.eventResynchronizationTask = nil
        }
    }

    private func receiveEngineEvent(_ event: DockerEvent, client: DockerClient, context: String, generation: Int) {
        switch event.type.lowercased() {
        case "container":
            let action = event.action.lowercased()
            let lifecycle: Set<String> = [
                "create", "start", "stop", "die", "destroy", "pause", "unpause", "restart", "rename", "update", "oom",
                "kill",
            ]
            guard lifecycle.contains(action) || action.hasPrefix("health_status") else { return }
            inventoryInvalidated = true
        case "image": resourcesInvalidated.insert(AppSection.images.rawValue)
        case "volume": resourcesInvalidated.insert(AppSection.volumes.rawValue)
        case "network":
            resourcesInvalidated.insert(AppSection.networks.rawValue)
            if ["connect", "disconnect"].contains(event.action.lowercased()) { inventoryInvalidated = true }
        case "daemon":
            inventoryInvalidated = true
            engineInfoFetchedAt = nil
            resourcesInvalidated.formUnion([
                AppSection.images.rawValue, AppSection.volumes.rawValue, AppSection.networks.rawValue,
            ])
        default: return
        }
        for key in resourcesInvalidated {
            resourcesFetchedAt[key] = nil
            resourceInvalidationVersions[key, default: 0] &+= 1
        }
        guard eventReconciliationTask == nil else { return }
        // One bounded coalescing window per event burst; idle engines execute no reconciliation work.
        eventReconciliationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.scopeMatches(context, generation: generation), !Task.isCancelled else { return }
            self.eventReconciliationTask = nil
            let needsInventory = self.inventoryInvalidated
            let resources = self.resourcesInvalidated
            self.inventoryInvalidated = false
            self.resourcesInvalidated.removeAll()
            if needsInventory { await self.requestSnapshot(explicit: false, afterInvalidation: true) }
            guard self.scopeMatches(context, generation: generation), !Task.isCancelled else { return }
            if resources.contains(self.selectedSection.rawValue) {
                await self.refreshResources(
                    self.selectedSection, client: client, context: context, generation: generation,
                    force: false, reportErrors: false)
            }
        }
    }

    private func updateStatsSubscription() {
        guard !isDemo, !isShuttingDown, isApplicationActive, areMetricsVisible, isConnected,
            containers.contains(where: { [.running, .paused, .restarting].contains($0.state) }), let client
        else {
            stopStatsSubscription()
            return
        }
        guard statsTask == nil else { return }
        let context = selectedContext
        let generation = configurationGeneration
        let requestID = UUID()
        statsRequestID = requestID
        statsTask = Task { [weak self] in
            var delay = 1.0
            while !Task.isCancelled {
                guard let self, self.scopeMatches(context, generation: generation), self.statsRequestID == requestID
                else {
                    return
                }
                let openedAt = self.clock.now
                let stream = await client.statsStream(context: context)
                do {
                    for try await value in stream {
                        guard !Task.isCancelled, self.scopeMatches(context, generation: generation),
                            self.statsRequestID == requestID
                        else { return }
                        delay = 1
                        if self.metricsError != nil { self.metricsError = nil }
                        guard
                            self.containers.contains(where: {
                                $0.id == value.id && [.running, .paused, .restarting].contains($0.state)
                            })
                        else {
                            continue
                        }
                        self.pendingStats[value.id] = value
                        self.publishStatsWhenReady(context: context, generation: generation, requestID: requestID)
                    }
                    guard !Task.isCancelled else { return }
                    self.metricsError = "Live metrics disconnected. Reconnecting…"
                } catch {
                    guard !Task.isCancelled, self.scopeMatches(context, generation: generation),
                        self.statsRequestID == requestID
                    else { return }
                    let message = "Live metrics interrupted: \(error.localizedDescription)"
                    if self.metricsError != message { self.metricsError = message }
                }
                if openedAt.duration(to: self.clock.now) >= .seconds(30) { delay = 1 }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                delay = min(delay * 2, 30)
            }
        }
    }

    private func publishStatsWhenReady(context: String, generation: Int, requestID: UUID) {
        guard statsPublicationTask == nil else { return }
        statsPublicationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.scopeMatches(context, generation: generation), self.statsRequestID == requestID,
                !Task.isCancelled
            else { return }
            self.statsPublicationTask = nil
            let activeIDs = Set(
                self.containers.filter { [.running, .paused, .restarting].contains($0.state) }.map(\.id))
            var merged = self.stats.filter { activeIDs.contains($0.key) }
            for (id, value) in self.pendingStats where activeIDs.contains(id) { merged[id] = value }
            self.pendingStats.removeAll(keepingCapacity: true)
            if self.stats != merged { self.stats = merged }
        }
    }

    private func stopStatsSubscription() {
        statsTask?.cancel()
        statsTask = nil
        statsRequestID = nil
        statsPublicationTask?.cancel()
        statsPublicationTask = nil
        pendingStats.removeAll(keepingCapacity: true)
        if metricsError != nil { metricsError = nil }
    }

    private func refreshResources(
        _ section: AppSection, client: DockerClient, context: String, generation: Int, force: Bool,
        reportErrors: Bool
    ) async {
        guard [.images, .volumes, .networks].contains(section), scopeMatches(context, generation: generation) else {
            return
        }
        let key = section.rawValue
        if let task = resourceTasks[key] {
            await task.value
            return
        }
        guard force || !isRecent(resourcesFetchedAt[key], seconds: 15) else { return }
        let requestID = UUID()
        let invalidationVersion = resourceInvalidationVersions[key, default: 0]
        resourceRequestIDs[key] = requestID
        loadingResourceSections.insert(key)
        resourcesFetchedAt[key] = clock.now
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.resourceRequestIDs[key] == requestID {
                    self.resourceTasks[key] = nil
                    self.resourceRequestIDs[key] = nil
                    self.loadingResourceSections.remove(key)
                }
            }
            do {
                switch section {
                case .images:
                    let result = try await client.images(context: context)
                    if self.scopeMatches(context, generation: generation), !Task.isCancelled,
                        self.images != result
                    {
                        self.images = result
                    }
                case .volumes:
                    let result = try await client.volumes(context: context)
                    if self.scopeMatches(context, generation: generation), !Task.isCancelled,
                        self.volumes != result
                    {
                        self.volumes = result
                    }
                case .networks:
                    let result = try await client.networks(context: context)
                    if self.scopeMatches(context, generation: generation), !Task.isCancelled,
                        self.networks != result
                    {
                        self.networks = result
                    }
                default: break
                }
                if self.scopeMatches(context, generation: generation), !Task.isCancelled {
                    self.resourceErrors.removeValue(forKey: key)
                }
            } catch {
                if self.scopeMatches(context, generation: generation), !Task.isCancelled {
                    self.resourceErrors[key] = error.localizedDescription
                    if reportErrors { self.addActivity("\(section.label) could not load: \(error.localizedDescription)", isError: true) }
                }
            }
        }
        resourceTasks[key] = task
        await task.value
        // A resource event arriving during the read requires one newer result, not a stale cache hit.
        if scopeMatches(context, generation: generation), !Task.isCancelled,
            resourceInvalidationVersions[key, default: 0] != invalidationVersion
        {
            await refreshResources(
                section, client: client, context: context, generation: generation, force: true,
                reportErrors: reportErrors)
        }
    }

    private func expandNewGroups(previous: Set<String>) {
        let ids = Set(ContainerGrouping.groups(containers: containers, context: selectedContext).map(\.id))
        let updated = expandedGroupIDs.intersection(ids).union(ids.subtracting(previous))
        if expandedGroupIDs != updated { expandedGroupIDs = updated }
    }

    func retryResources() async {
        guard !isDemo, isConnected, let client else { return }
        await refreshResources(selectedSection, client: client, context: selectedContext,
            generation: configurationGeneration, force: true, reportErrors: true)
    }

    func selectSection(_ section: AppSection) {
        selectedSection = section
        searchText = ""
        closeDetail()
        guard !isDemo, !isShuttingDown else { return }
        guard isConnected, let client else {
            Task { [weak self] in await self?.refreshInBackground() }
            return
        }
        let context = selectedContext
        let generation = configurationGeneration
        Task { [weak self] in
            await self?.refreshResources(
                section, client: client, context: context, generation: generation, force: false, reportErrors: true)
        }
    }

    func selectContainer(_ container: DockerContainer) {
        detailTask?.cancel()
        inspectionTask?.cancel()
        selectedContainerID = container.id
        currentLogRequest = nil
        logError = nil
        logStreamState = .connecting
        detailTab = .logs
        inspection = nil
        inspectionError = nil
        isLoadingInspection = true
        resetLogs()
        logTask?.cancel()
        detailTask = Task { [weak self] in await self?.refreshDetail() }
    }

    func closeDetail() {
        detailTask?.cancel()
        detailTask = nil
        inspectionTask?.cancel()
        inspectionTask = nil
        currentDetailRequest = nil
        currentLogRequest = nil
        isLoadingInspection = false
        inspectionError = nil
        logError = nil
        logStreamState = .idle
        logTask?.cancel()
        logTask = nil
        selectedContainerID = nil
        inspection = nil
        resetLogs()
    }

    func toggleGroup(_ id: String) {
        if expandedGroupIDs.contains(id) { expandedGroupIDs.remove(id) } else { expandedGroupIDs.insert(id) }
    }

    func perform(_ action: ContainerAction, on selected: [DockerContainer]) {
        guard !isShuttingDown, isDemo || (isConnected && loadedContext == selectedContext) else {
            operationError = "Wait for the selected engine to finish connecting before controlling containers."
            return
        }
        let requestedIDs = Set(selected.map(\.id))
        let currentSelection = containers.filter { requestedIDs.contains($0.id) }
        guard currentSelection.count == requestedIDs.count else {
            operationError = "The selected containers changed. Refresh and select them again before continuing."
            return
        }
        let eligible = currentSelection.filter { container in
            guard !pendingContainerIDs.contains(container.id) else { return false }
            switch action {
            case .start: return [.created, .exited].contains(container.state)
            case .stop: return [.running, .paused, .restarting].contains(container.state)
            case .restart: return container.isRunning
            }
        }
        guard !eligible.isEmpty else {
            operationError =
                "No containers are eligible for \(action.label.lowercased()). Refresh the list and check their current state."
            return
        }
        guard isDemo || isConnected else {
            operationError = "Connect to the engine before controlling containers."
            return
        }
        let ids = eligible.map(\.id)
        let context = selectedContext
        let timeout = preferences.stopTimeout
        let actionClient = client
        let operationID = UUID()
        if let actionClient { mutationClients[operationID] = actionClient }
        pendingContainerIDs.formUnion(ids)
        operationError = nil
        mutationTasks[operationID] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.pendingContainerIDs.subtract(ids)
                self.mutationTasks.removeValue(forKey: operationID)
                self.mutationClients.removeValue(forKey: operationID)
            }
            if self.isDemo {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self.containers = self.containers.map { container in
                    guard ids.contains(container.id) else { return container }
                    return DockerContainer(
                        id: container.id, name: container.name, image: container.image,
                        state: action == .stop ? .exited : .running,
                        health: action == .stop ? nil : .healthy, project: container.project,
                        service: container.service, ports: container.ports, createdAt: container.createdAt,
                        status: action == .stop ? "Exited (0)" : "Up just now")
                }
                self.addActivity("\(action.label): \(ids.count) demo container(s). Simulated operation.")
                return
            }
            guard let client = actionClient else { return }
            do {
                let report = try await client.perform(action, containerIDs: ids, context: context, stopTimeout: timeout)
                for result in report.results {
                    let name =
                        eligible.first(where: { $0.id == result.containerID })?.name
                        ?? String(result.containerID.prefix(12))
                    self.addActivity(
                        "\(context) · \(action.label) \(name): \(result.message)", isError: !result.succeeded)
                }
                let failed = report.results.filter { !$0.succeeded }
                if !failed.isEmpty {
                    self.operationError =
                        "\(context): \(failed.count) of \(report.results.count) operations failed. "
                        + failed.map(\.message).joined(separator: "\n")
                }
                await self.requestSnapshot(explicit: false, afterInvalidation: true)
            } catch {
                guard !Task.isCancelled, !self.isShuttingDown else { return }
                self.operationError = "\(context): \(error.localizedDescription)"
                self.addActivity("\(action.label) failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func clearOperationError() { operationError = nil }

    func refreshDetail() async {
        beginLogs(clearBuffer: true)
        await retryInspection()
    }

    func retryInspection() async {
        guard let container = selectedContainer else { return }
        let id = container.id
        let context = selectedContext
        let generation = configurationGeneration
        let requestID = UUID()
        currentDetailRequest = requestID
        inspectionTask?.cancel()
        inspectionError = nil
        isLoadingInspection = true
        defer {
            if currentDetailRequest == requestID, scopeMatches(context, generation: generation) {
                isLoadingInspection = false
            }
        }
        if isDemo {
            inspection = DemoData.inspection(for: container)
            return
        }
        guard let client else {
            inspectionError = "Connect to the engine before loading inspection."
            return
        }
        let request = Task { try await client.inspect(containerID: id, context: context) }
        inspectionTask = request
        do {
            let value = try await request.value
            guard selectedContainerID == id, scopeMatches(context, generation: generation),
                currentDetailRequest == requestID, !Task.isCancelled else { return }
            inspection = value
        } catch is CancellationError {
            return
        } catch {
            guard selectedContainerID == id, scopeMatches(context, generation: generation),
                currentDetailRequest == requestID, !Task.isCancelled else { return }
            inspectionError = error.localizedDescription
        }
    }

    func retryLogs() { beginLogs(clearBuffer: false) }

    private func beginLogs(clearBuffer: Bool) {
        guard let container = selectedContainer else { return }
        logTask?.cancel()
        let id = container.id
        let context = selectedContext
        let generation = configurationGeneration
        let requestID = UUID()
        currentLogRequest = requestID
        logError = nil
        logStreamState = .connecting
        if clearBuffer { resetLogs() }
        if isDemo {
            resetLogs()
            appendLog(DemoData.logs)
            logStreamState = .following
            return
        }
        guard let client else {
            logError = "Connect to the engine before loading logs."
            logStreamState = .failed
            return
        }
        let tail = preferences.logTail
        let timestamps = preferences.logTimestamps
        logTask = Task { [weak self] in
            let stream = await client.logStream(containerID: id, context: context, tail: tail, timestamps: timestamps)
            guard let self, self.selectedContainerID == id, self.scopeMatches(context, generation: generation),
                self.currentLogRequest == requestID, !Task.isCancelled else { return }
            self.logStreamState = .following
            var replaceBufferOnFirstChunk = !clearBuffer
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled, self.selectedContainerID == id,
                        self.scopeMatches(context, generation: generation), self.currentLogRequest == requestID else { return }
                    if replaceBufferOnFirstChunk {
                        self.resetLogs()
                        replaceBufferOnFirstChunk = false
                    }
                    self.appendLog(chunk)
                }
                guard !Task.isCancelled, self.selectedContainerID == id,
                    self.scopeMatches(context, generation: generation), self.currentLogRequest == requestID else { return }
                self.logStreamState = .ended
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.selectedContainerID == id,
                    self.scopeMatches(context, generation: generation), self.currentLogRequest == requestID else { return }
                self.logError = error.localizedDescription
                self.logStreamState = .failed
            }
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openPort(_ binding: PortBinding) {
        guard (1...65535).contains(binding.hostPort), binding.transport == "tcp" else { return }
        let host = ["", "0.0.0.0", "::", "127.0.0.1", "::1"].contains(binding.hostIP) ? "127.0.0.1" : binding.hostIP
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = host
        parts.port = binding.hostPort
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }

    func savePreferences() {
        let previousPath = currentExecutablePath
        preferences.normalize()
        guard !isDemo else { return }
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: preferencesKey) }
        if previousPath != preferences.dockerExecutable {
            client?.cancelPendingCommands()
            invalidateConnection()
            currentExecutablePath = preferences.dockerExecutable
            client = DockerClient(
                executableURL: preferences.dockerExecutable.isEmpty
                    ? nil : URL(fileURLWithPath: preferences.dockerExecutable))
            closeDetail()
            Task { [weak self] in await self?.refresh() }
        }
    }
    private var currentExecutablePath = ""

    private func invalidateConnection(cancelRefresh: Bool = true) {
        configurationGeneration &+= 1
        if cancelRefresh {
            snapshotTask?.cancel()
            snapshotTask = nil
            snapshotRequestID = nil
            followUpSnapshot = false
            forceMetadataOnNextPass = false
            currentPassForcesMetadata = false
            if isRefreshing { isRefreshing = false }
        }
        eventsTask?.cancel()
        eventsTask = nil
        eventsRequestID = nil
        eventReconciliationTask?.cancel()
        eventReconciliationTask = nil
        eventResynchronizationTask?.cancel()
        eventResynchronizationTask = nil
        eventResynchronizationRequested = false
        eventStreamID = nil
        inventoryInvalidated = false
        resourcesInvalidated.removeAll()
        liveUpdateError = nil
        stopStatsSubscription()
        engineInfoTask?.cancel()
        engineInfoTask = nil
        for task in resourceTasks.values { task.cancel() }
        resourceTasks.removeAll()
        resourceRequestIDs.removeAll()
        resourceInvalidationVersions.removeAll()
        loadingResourceSections.removeAll()
        resourceErrors.removeAll()
        contextsFetchedAt = nil
        engineInfoFetchedAt = nil
        resourcesFetchedAt.removeAll()
        connected = false
        loadedContext = ""
        connectionError = nil
        containers = []
        stats = [:]
        images = []
        volumes = []
        networks = []
        engineInfo = nil
        closeDetail()
    }

    private func resetLogs() {
        logBuffer.clear()
        logText = ""
    }

    private func appendLog(_ chunk: String) {
        logBuffer.append(chunk)
        logText = logBuffer.text
    }

    func shutdown() {
        isShuttingDown = true
        snapshotTask?.cancel()
        eventsTask?.cancel()
        eventReconciliationTask?.cancel()
        eventResynchronizationTask?.cancel()
        stopStatsSubscription()
        engineInfoTask?.cancel()
        for task in resourceTasks.values { task.cancel() }
        closeDetail()
        for task in mutationTasks.values { task.cancel() }
        for client in mutationClients.values { client.cancelPendingCommands() }
        client?.cancelPendingCommands()
    }

    func resetPreferences() {
        preferences = AppPreferences()
        savePreferences()
    }

    func chooseDockerExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Docker CLI"
        panel.message = "Select the docker executable installed on this Mac."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            preferences.dockerExecutable = url.path
            savePreferences()
        }
    }

    private func addActivity(_ message: String, isError: Bool = false) {
        activity.insert(ActivityEntry(timestamp: Date(), message: message, isError: isError), at: 0)
        if activity.count > 200 { activity.removeLast(activity.count - 200) }
    }
}
