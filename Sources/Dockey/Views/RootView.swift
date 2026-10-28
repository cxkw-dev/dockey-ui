import AppKit
import DockeyCore
import SwiftUI

@MainActor
struct RootView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings
    @ViewState<StopRequest?> private var stopRequest = nil
    @FocusState private var contextMenuFocused: Bool
    @ViewState<Bool> private var contextMenuHovered = false

    init(store: AppStore) {
        self.store = store
        DockeyFonts.register()
    }

    private var palette: DockeyPalette { DockeyPalette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(palette.border).frame(width: 1)
                VStack(spacing: 0) {
                    if store.selectedSection == .containers, let container = store.selectedContainer {
                        ContainerDetailView(store: store, container: container, requestAction: requestAction)
                    } else {
                        pageHeader
                        if let error = store.connectionError {
                            connectionState(error)
                        } else {
                            sectionContent
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
            }
            footer
        }
        .font(DockeyFonts.ui())
        .foregroundStyle(palette.primary)
        .background(palette.background)
        .tint(palette.blue)
        .frame(minWidth: 900, minHeight: 580)
        .toolbar { toolbar }
        .task { await store.start() }
        .onPreferenceChange(DockeyMetricsVisibilityKey.self) { visible in
            Task { @MainActor in store.setMetricsVisible(visible) }
        }
        .onDisappear { store.setMainWindowVisible(false) }
        .onChange(of: store.selectedContext) { _, _ in Task { await store.refresh() } }
        .confirmationDialog(
            "Stop existing containers?",
            isPresented: Binding(
                get: { stopRequest != nil }, set: { if !$0 { stopRequest = nil } }
            ), titleVisibility: .visible
        ) {
            if let request = stopRequest {
                Button(
                    "Stop \(request.containers.count == 1 ? "container" : "\(request.containers.count) containers")",
                    role: .destructive
                ) {
                    guard request.context == store.selectedContext else {
                        store.operationError = "The selected context changed. Review the containers and try again."
                        stopRequest = nil
                        return
                    }
                    store.perform(.stop, on: request.containers)
                    stopRequest = nil
                }
            }
            Button("Cancel", role: .cancel) { stopRequest = nil }
        } message: {
            if let request = stopRequest {
                Text(
                    "Context: \(request.context)\n\n\(request.containers.map(\.name).joined(separator: "\n"))\n\nContainers remain available to start again. Volumes and networks are preserved."
                )
            }
        }
        .alert(
            "Operation could not complete",
            isPresented: Binding(
                get: { store.operationError != nil }, set: { if !$0 { store.clearOperationError() } }
            )
        ) {
            Button("OK") { store.clearOperationError() }
        } message: {
            Text(store.operationError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                DockeyMascot().frame(width: 32, height: 32)
                DockeyWordmark()
            }
            .padding(.horizontal, 9).padding(.top, 15).padding(.bottom, 21)

            ForEach(AppSection.allCases) { section in
                Button {
                    store.selectSection(section)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol).font(.system(size: 14, weight: .regular)).frame(width: 17)
                        Text(section.label).font(
                            DockeyFonts.ui(12, weight: store.selectedSection == section ? .medium : .regular))
                        Spacer(minLength: 3)
                        if let count = sectionCount(section) {
                            Text(count.formatted()).font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(
                        store.selectedSection == section ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.selectedSection == section ? palette.primary : palette.muted)
                .accessibilityIdentifier("navigation-\(section.rawValue)")
                .accessibilityAddTraits(store.selectedSection == section ? .isSelected : [])
            }

            if !composeGroups.isEmpty {
                Text("Compose projects").font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
                    .padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 4)
                ForEach(composeGroups.prefix(6)) { group in
                    Button {
                        store.selectSection(.containers)
                        store.searchText = group.name
                    } label: {
                        HStack(spacing: 9) {
                            Circle().fill(group.runningCount > 0 ? palette.green : palette.muted).frame(
                                width: 5, height: 5)
                            Text(group.name).lineLimit(1)
                            Spacer(minLength: 3)
                            Text("\(group.runningCount)/\(group.containers.count)").font(DockeyFonts.ui(10))
                        }
                        .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
                        .padding(.horizontal, 12).frame(height: 31).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Show \(group.name)")
                }
            }
            Spacer(minLength: 12)
            Rectangle().fill(palette.border).frame(height: 1).padding(.bottom, 7)
            Button {
                openSettings()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 17)
                    Text("Settings")
                    Spacer()
                    Text("⌘,").font(DockeyFonts.ui(10))
                }
                .font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
                .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open-settings")
            HStack(spacing: 8) {
                Circle().fill(store.isConnected ? palette.green : palette.muted).frame(width: 5, height: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isDemo ? "Demo workspace" : store.isConnected ? "Engine connected" : "Disconnected")
                        .font(DockeyFonts.ui(11))
                    Text(
                        store.isDemo
                            ? "Sample data" : store.selectedContext.isEmpty ? "Select a context" : store.selectedContext
                    )
                    .font(DockeyFonts.ui(10)).foregroundStyle(palette.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 15)
        }
        .padding(.horizontal, 10)
        .frame(width: 188)
        .frame(maxHeight: .infinity)
        .background(palette.secondary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) { DockeyWordmark(size: 14) }
        ToolbarItemGroup(placement: .primaryAction) {
            if store.isDemo {
                Label("Demo · sample data", systemImage: "sparkles")
                    .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
            } else {
                Menu {
                    ForEach(store.contexts) { context in
                        Button {
                            store.selectedContext = context.name
                        } label: {
                            if store.selectedContext == context.name {
                                Label(context.name, systemImage: "checkmark")
                            } else {
                                Text(context.name + (context.isLocal ? "" : " (remote unsupported)"))
                            }
                        }
                        .disabled(!context.isLocal)
                    }
                    if store.contexts.isEmpty { Text("No local Docker contexts found") }
                    Divider()
                    Button("Connection settings…") { openSettings() }
                } label: {
                    DockeyMenuLabel(
                        title: store.selectedContext.isEmpty ? "Connection" : store.selectedContext,
                        statusColor: store.isConnected ? palette.green : palette.muted, expands: false)
                }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
                .tint(palette.primary).foregroundStyle(palette.primary)
                .fixedSize(horizontal: true, vertical: false)
                .background(contextMenuHovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if contextMenuFocused { RoundedRectangle(cornerRadius: 6).stroke(palette.blue) }
                }
                .onHover { contextMenuHovered = $0 }
                .focused($contextMenuFocused)
                .accessibilityLabel("Docker context")
                .accessibilityValue(store.selectedContext.isEmpty ? "No context selected" : store.selectedContext)
                .help("Choose a local context for Dockey")
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.selectedSection.label).font(DockeyFonts.ui(24, weight: .semibold)).tracking(-0.8)
                if store.selectedSection == .containers {
                    Text(
                        store.isConnected
                            ? "\(store.runningCount) running · \(composeGroups.count) Compose projects\(store.unhealthyCount > 0 ? " · \(store.unhealthyCount) unhealthy" : "")"
                            : "Manage containers through your existing Docker Engine"
                    )
                    .font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
                } else {
                    Text(sectionDescription).font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
                }
            }
            Spacer()
            if store.isRefreshing { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 26).padding(.top, 25).padding(.bottom, 22)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch store.selectedSection {
        case .containers:
            GroupedContainerList(store: store, requestAction: requestAction)
        case .images:
            ResourceListView(kind: .images, store: store)
        case .volumes:
            ResourceListView(kind: .volumes, store: store)
        case .networks:
            ResourceListView(kind: .networks, store: store)
        case .activity:
            activityList
        }
    }

    private var activityList: some View {
        Group {
            if store.activity.isEmpty {
                DockeyEmptyState(
                    title: "No operations yet",
                    message: "Container operations and connection events appear here for this session.",
                    symbol: "waveform.path.ecg")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.activity) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.isError ? "exclamationmark.circle" : "checkmark.circle")
                                    .foregroundStyle(entry.isError ? palette.red : palette.green)
                                Text(entry.message).font(DockeyFonts.ui(12)).textSelection(.enabled)
                                Spacer(minLength: 12)
                                Text(entry.timestamp, style: .time).font(DockeyFonts.ui(10)).foregroundStyle(
                                    palette.muted)
                            }
                            .padding(.vertical, 16)
                            Rectangle().fill(palette.border).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 26)
                }
            }
        }
    }

    private func connectionState(_ message: String) -> some View {
        DockeyEmptyState(
            title: "Connect your Docker Engine", message: message,
            symbol: "cable.connector", actionTitle: "Try again"
        ) {
            Task { await store.refresh() }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(palette.border).frame(height: 1)
            HStack(spacing: 14) {
                Circle().fill(store.isConnected ? palette.green : palette.muted).frame(width: 5, height: 5)
                Text(
                    store.isDemo
                        ? "Demo · sample data" : store.isConnected ? "Docker Engine connected" : "Engine unavailable")
                if let error = store.liveUpdateError {
                    Text("Updates reconnecting").foregroundStyle(palette.amber).help(error)
                } else if let error = store.metricsError {
                    Text("Metrics reconnecting").foregroundStyle(palette.amber).help(error)
                } else if store.isConnected && !store.isDemo {
                    Text("Live updates").help("Container changes arrive from the selected engine automatically.")
                }
                if let info = store.engineInfo {
                    Rectangle().fill(palette.border).frame(width: 1, height: 13)
                    Label("\(info.cpus) CPUs", systemImage: "cpu")
                    Label(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(clamping: info.memoryBytes), countStyle: .memory),
                        systemImage: "memorychip")
                    Spacer()
                    Text("Engine \(info.serverVersion)")
                    Text(info.architecture)
                } else {
                    Spacer()
                }
                if store.isRefreshing { Text("Refreshing…") }
            }
            .font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
            .padding(.horizontal, 16).frame(height: 31)
            .background(palette.secondary)
        }
    }

    private var composeGroups: [ContainerGroup] {
        ContainerGrouping.groups(containers: store.containers, context: store.selectedContext).filter(\.isCompose)
    }

    private var sectionDescription: String {
        switch store.selectedSection {
        case .images: "Local images available in the selected engine"
        case .volumes: "Storage volumes · inspection only"
        case .networks: "Networks in the selected engine"
        case .activity: "Operations and connection events from this session"
        case .containers: ""
        }
    }

    private func sectionCount(_ section: AppSection) -> Int? {
        switch section {
        case .containers: store.containers.count
        case .images: store.images.count
        case .volumes: store.volumes.count
        case .networks: store.networks.count
        case .activity: nil
        }
    }

    private func requestAction(_ action: ContainerAction, _ containers: [DockerContainer]) {
        let eligible = containers.filter { container in
            guard !store.pendingContainerIDs.contains(container.id) else { return false }
            switch action {
            case .start: return [.exited, .created].contains(container.state)
            case .stop: return [.running, .paused, .restarting].contains(container.state)
            case .restart: return container.isRunning
            }
        }
        guard !eligible.isEmpty else { return }
        if action == .stop && store.preferences.confirmStop {
            stopRequest = StopRequest(context: store.selectedContext, containers: eligible)
        } else {
            store.perform(action, on: eligible)
        }
    }
}

private struct StopRequest {
    let context: String
    let containers: [DockerContainer]
}
