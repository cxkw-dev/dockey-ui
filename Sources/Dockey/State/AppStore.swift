import AppKit
import Combine
import DockeyCore
import Foundation

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
            if oldValue != selectedContext, started { invalidateConnection() }
        }
    }
    @Published var selectedSection: AppSection = .containers
    @Published var selectedContainerID: String?
    @Published var searchText = ""
    @Published var stateFilter: ContainerFilter = .all
    @Published var expandedGroupIDs: Set<String> = []
    @Published var isRefreshing = false
    @Published var connectionError: String?
    @Published var operationError: String?
    @Published var pendingContainerIDs: Set<String> = []
    @Published var activity: [ActivityEntry] = []
    @Published var inspection: ContainerInspection?
    @Published var logText = ""
    @Published var detailTab: DetailTab = .logs
    @Published var isDemo: Bool
    @Published var preferences: AppPreferences
    @Published private var connected = false

    private var client: DockerClient?
    private var started = false
    private var refreshAgain = false
    private var loadedContext = ""
    private var refreshLoop: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var inspectionTask: Task<ContainerInspection, Error>?
    private var mutationTasks: [UUID: Task<Void, Never>] = [:]
    private var mutationClients: [UUID: DockerClient] = [:]
    private var configurationGeneration = 0
    private var currentDetailRequest: UUID?
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

    var groups: [ContainerGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContainerGrouping.groups(containers: containers, context: selectedContext).compactMap { group in
            let filtered = group.containers.filter { container in
                guard preferences.showStopped || container.isRunning else { return false }
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
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.preferences.refreshInterval ?? 5
                do { try await Task.sleep(for: .seconds(interval)) } catch { break }
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !isDemo, !isShuttingDown else { return }
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        guard let client else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshAgain, !isShuttingDown {
                refreshAgain = false
                Task { [weak self] in await self?.refresh() }
            }
        }
        var generation = configurationGeneration
        do {
            let discovered = try await client.contexts()
            guard generation == configurationGeneration, !isShuttingDown else {
                refreshAgain = true
                return
            }
            contexts = discovered
            let local = discovered.filter(\.isLocal)
            if !local.contains(where: { $0.name == selectedContext }) {
                selectedContext =
                    local.first(where: { $0.name == "colima" })?.name ?? local.first(where: \.isCurrent)?.name ?? local
                    .first?.name ?? ""
            }
            guard !selectedContext.isEmpty else {
                throw DockerError.commandFailed(
                    "No local Docker context was found. Configure a local engine such as Colima, then refresh.")
            }
            let context = selectedContext
            generation = configurationGeneration
            if loadedContext != context {
                closeDetail()
                containers = []
                stats = [:]
                images = []
                volumes = []
                networks = []
                engineInfo = nil
                connected = false
                loadedContext = context
            }
            async let fetchedContainers = client.containers(context: context)
            async let fetchedInfo = client.engineInfo(context: context)
            let (fresh, info) = try await (fetchedContainers, fetchedInfo)
            guard context == selectedContext, generation == configurationGeneration, !isShuttingDown else {
                refreshAgain = true
                return
            }
            let previous = Set(ContainerGrouping.groups(containers: containers, context: context).map(\.id))
            containers = fresh
            engineInfo = info
            connectionError = nil
            if !connected { addActivity("Connected to local context \(context).") }
            connected = true
            expandNewGroups(previous: previous)
            defaults.set(context, forKey: contextKey)
            if let selectedContainerID, !fresh.contains(where: { $0.id == selectedContainerID }) { closeDetail() }
            do {
                let values = try await client.stats(context: context)
                if selectedContext == context, generation == configurationGeneration {
                    stats = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                }
            } catch {
                if selectedContext == context, generation == configurationGeneration { stats = [:] }
            }
            await refreshResources(client: client, context: context, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == configurationGeneration, !isShuttingDown else {
                refreshAgain = true
                return
            }
            let message = error.localizedDescription
            if connectionError != message { addActivity("Connection unavailable: \(message)", isError: true) }
            connectionError = message
            connected = false
            stats = [:]
            logTask?.cancel()
        }
    }

    private func refreshResources(client: DockerClient, context: String, generation: Int) async {
        guard selectedContext == context, generation == configurationGeneration, !isShuttingDown else { return }
        do {
            switch selectedSection {
            case .images:
                let result = try await client.images(context: context)
                if selectedContext == context, generation == configurationGeneration { images = result }
            case .volumes:
                let result = try await client.volumes(context: context)
                if selectedContext == context, generation == configurationGeneration { volumes = result }
            case .networks:
                let result = try await client.networks(context: context)
                if selectedContext == context, generation == configurationGeneration { networks = result }
            default: break
            }
        } catch {
            if selectedContext == context, generation == configurationGeneration {
                operationError = error.localizedDescription
            }
        }
    }

    private func expandNewGroups(previous: Set<String>) {
        let ids = Set(ContainerGrouping.groups(containers: containers, context: selectedContext).map(\.id))
        expandedGroupIDs.formIntersection(ids)
        expandedGroupIDs.formUnion(ids.subtracting(previous))
    }

    func selectSection(_ section: AppSection) {
        selectedSection = section
        searchText = ""
        closeDetail()
        if !isDemo { Task { [weak self] in await self?.refresh() } }
    }

    func selectContainer(_ container: DockerContainer) {
        detailTask?.cancel()
        inspectionTask?.cancel()
        selectedContainerID = container.id
        detailTab = .logs
        inspection = nil
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
        let eligible = selected.filter { container in
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
                await self.refresh()
            } catch {
                guard !Task.isCancelled, !self.isShuttingDown else { return }
                self.operationError = "\(context): \(error.localizedDescription)"
                self.addActivity("\(action.label) failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    func clearOperationError() { operationError = nil }

    func refreshDetail() async {
        guard let container = selectedContainer else { return }
        let id = container.id
        let context = selectedContext
        let generation = configurationGeneration
        let requestID = UUID()
        currentDetailRequest = requestID
        if isDemo {
            inspection = DemoData.inspection(for: container)
            resetLogs()
            appendLog(DemoData.logs)
            return
        }
        guard let client else { return }
        inspectionTask?.cancel()
        let request = Task { try await client.inspect(containerID: id, context: context) }
        inspectionTask = request
        do {
            let value = try await request.value
            guard selectedContainerID == id, selectedContext == context, generation == configurationGeneration,
                currentDetailRequest == requestID, !Task.isCancelled
            else { return }
            inspection = value
        } catch is CancellationError {
            return
        } catch {
            if selectedContainerID == id, selectedContext == context, generation == configurationGeneration,
                currentDetailRequest == requestID
            {
                operationError = error.localizedDescription
            }
        }
        guard selectedContainerID == id, selectedContext == context, generation == configurationGeneration,
            currentDetailRequest == requestID, !Task.isCancelled
        else { return }
        logTask?.cancel()
        resetLogs()
        let tail = preferences.logTail
        let timestamps = preferences.logTimestamps
        logTask = Task { [weak self] in
            let stream = await client.logStream(containerID: id, context: context, tail: tail, timestamps: timestamps)
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled, let self, self.selectedContainerID == id, self.selectedContext == context,
                        self.configurationGeneration == generation, self.currentDetailRequest == requestID
                    else { break }
                    self.appendLog(chunk)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.selectedContainerID == id, self.selectedContext == context,
                    self.configurationGeneration == generation, self.currentDetailRequest == requestID
                else { return }
                self.appendLog("\nLog connection ended: \(error.localizedDescription)")
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

    private func invalidateConnection() {
        configurationGeneration &+= 1
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
        refreshLoop?.cancel()
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
