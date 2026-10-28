import DockeyCore
import SwiftUI

struct GroupedContainerList: View {
    @ObservedObject var store: AppStore
    let requestAction: (ContainerAction, [DockerContainer]) -> Void
    @Environment(\.colorScheme) private var scheme
    private var palette: DockeyPalette { DockeyPalette(scheme: scheme) }

    var body: some View {
        GeometryReader { geometry in
            let metricsVisible = geometry.size.width >= 850
            VStack(spacing: 0) {
                searchToolbar
                columns(metricsVisible: metricsVisible)
                if store.containers.isEmpty && store.isRefreshing {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Loading containers…").font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.containers.isEmpty {
                    DockeyEmptyState(
                        title: "Your workspace starts here",
                        message:
                            "Containers from your selected engine appear here automatically, grouped by Compose project. Start a container with your Docker CLI to get going."
                    )
                } else if store.groups.isEmpty {
                    DockeyEmptyState(
                        title: "No matching containers",
                        message: "Try a project, container, or image name, or choose a different state filter.",
                        symbol: "magnifyingglass", actionTitle: "Clear filters"
                    ) {
                        store.searchText = ""
                        store.stateFilter = .all
                        store.preferences.showStopped = true
                        store.savePreferences()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.groups) { group in
                                groupHeader(group)
                                if isExpanded(group) {
                                    ForEach(group.containers) { container in
                                        ContainerTableRow(
                                            store: store, container: container, metricsVisible: metricsVisible,
                                            requestAction: requestAction)
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("container-list")
                }
            }
            .preference(
                key: DockeyMetricsVisibilityKey.self,
                value: metricsVisible
                    && store.groups.contains { group in
                        isExpanded(group) && group.containers.contains(where: \.isRunning)
                    })
        }
    }

    private var searchToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(palette.muted)
                TextField("Search containers, projects, images…", text: $store.searchText)
                    .textFieldStyle(.plain).font(DockeyFonts.ui(12))
                    .accessibilityLabel("Search containers")
                    .accessibilityIdentifier("container-search")
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(palette.muted).help("Clear search")
                }
            }
            .padding(.horizontal, 10).frame(maxWidth: 330).frame(height: 31)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border))
            DockeySelect(
                title: "Container state", selection: $store.stateFilter,
                options: ContainerFilter.allCases.map { .init(value: $0, title: $0.label) }
            )
            .frame(width: 120)
            Toggle(
                isOn: Binding(
                    get: { store.preferences.showStopped },
                    set: {
                        store.preferences.showStopped = $0
                        store.savePreferences()
                    })
            ) { Text("Show stopped").font(DockeyFonts.ui(11)) }
            .toggleStyle(DockeyCheckboxStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.bottom, 18)
    }

    private func columns(metricsVisible: Bool) -> some View {
        HStack(spacing: 12) {
            Text("Name / image").frame(maxWidth: .infinity, alignment: .leading)
            Text("Status").frame(width: 108, alignment: .leading)
            if metricsVisible {
                Text("CPU").frame(width: 66, alignment: .leading)
                Text("Memory").frame(width: 82, alignment: .leading)
            }
            Text("Ports").frame(width: 86, alignment: .leading)
            Text("Actions").frame(width: 86, alignment: .trailing)
        }
        .font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
        .padding(.horizontal, 26).frame(height: 32)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func groupHeader(_ group: ContainerGroup) -> some View {
        let completeGroup =
            ContainerGrouping.groups(containers: store.containers, context: store.selectedContext)
            .first { $0.id == group.id } ?? group
        let hasStartable = completeGroup.containers.contains { [.created, .exited].contains($0.state) }
        let hasStoppable = completeGroup.containers.contains { [.running, .paused, .restarting].contains($0.state) }
        let primaryAction: ContainerAction = hasStartable ? .start : .stop
        let pending = completeGroup.containers.contains { store.pendingContainerIDs.contains($0.id) }
        return HStack(spacing: 9) {
            Button {
                store.toggleGroup(group.id)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: isExpanded(group) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(palette.muted).frame(width: 10)
                    Image(systemName: group.isCompose ? "square.3.layers.3d" : "shippingbox")
                        .font(.system(size: 13))
                    Text(group.name).font(DockeyFonts.ui(12, weight: .medium)).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isExpanded(group) ? "Collapse" : "Expand") \(group.name)")
            if group.isCompose {
                Text("Compose").font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
            }
            Text("\(completeGroup.runningCount)/\(completeGroup.containers.count)")
                .font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(palette.hover, in: RoundedRectangle(cornerRadius: 3))
            if completeGroup.unhealthyCount > 0 {
                Text("\(completeGroup.unhealthyCount) unhealthy").font(DockeyFonts.ui(10)).foregroundStyle(
                    palette.amber
                )
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(palette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
            }
            Spacer(minLength: 8)
            LifecycleButton(
                action: primaryAction, showLabel: true, isPending: pending,
                disabled: !store.isConnected || (!hasStartable && !hasStoppable),
                accessibilityName: "\(primaryAction.label) all eligible containers in \(group.name)"
            ) {
                requestAction(primaryAction, completeGroup.containers)
            }
            Menu {
                Button("Start existing containers") { requestAction(.start, completeGroup.containers) }
                    .disabled(!completeGroup.containers.contains { [.created, .exited].contains($0.state) })
                    .accessibilityLabel("Start all eligible containers in \(group.name)")
                Button("Stop existing containers") { requestAction(.stop, completeGroup.containers) }
                    .disabled(!hasStoppable)
                    .accessibilityLabel("Stop all eligible containers in \(group.name)")
                Button("Restart running containers") { requestAction(.restart, completeGroup.containers) }
                    .disabled(completeGroup.runningCount == 0)
                    .accessibilityLabel("Restart running containers in \(group.name)")
            } label: {
                Image(systemName: "ellipsis").frame(width: 22, height: 24)
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
            .tint(palette.muted).foregroundStyle(palette.muted)
            .disabled(pending || !store.isConnected)
            .help(
                "Controls all \(completeGroup.containers.count) existing containers in \(group.name), including filtered rows; does not apply Compose configuration"
            )
            .accessibilityLabel("Actions for \(group.name)")
        }
        .padding(.horizontal, 26).frame(height: 43)
        .background(palette.secondary)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func isExpanded(_ group: ContainerGroup) -> Bool {
        !store.searchText.isEmpty || store.expandedGroupIDs.contains(group.id)
    }
}

private struct ContainerTableRow: View {
    @ObservedObject var store: AppStore
    let container: DockerContainer
    let metricsVisible: Bool
    let requestAction: (ContainerAction, [DockerContainer]) -> Void
    @Environment(\.colorScheme) private var scheme
    @ViewState<Bool> private var hovered = false
    private var palette: DockeyPalette { DockeyPalette(scheme: scheme) }
    private var pending: Bool { store.pendingContainerIDs.contains(container.id) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.selectContainer(container)
            } label: {
                HStack(spacing: 10) {
                    ServiceIcon(identity: ServiceIdentity(imageReference: container.image))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(container.name).font(DockeyFonts.ui(12, weight: .medium)).foregroundStyle(palette.primary)
                            .lineLimit(1)
                        Text(container.image).font(DockeyFonts.ui(10)).foregroundStyle(palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Inspect \(container.name)")
            .accessibilityLabel("Inspect \(container.name)")
            ContainerStatus(container: container).frame(width: 108, alignment: .leading)
            if metricsVisible {
                Text(metric?.cpuPercent.formatted(.number.precision(.fractionLength(2))).appending("%") ?? "—")
                    .frame(width: 66, alignment: .leading)
                Text(metric?.memoryUsage ?? "—").frame(width: 82, alignment: .leading)
            }
            portLabel.frame(width: 86, alignment: .leading)
            HStack(spacing: 2) {
                LifecycleButton(
                    action: shouldStop ? .stop : .start, isPending: pending,
                    disabled: !store.isConnected || !canToggle,
                    accessibilityName: "\(shouldStop ? "Stop" : "Start") \(container.name)"
                ) {
                    requestAction(shouldStop ? .stop : .start, [container])
                }
                LifecycleButton(
                    action: .restart, disabled: !container.isRunning || pending || !store.isConnected,
                    accessibilityName: "Restart \(container.name)"
                ) {
                    requestAction(.restart, [container])
                }
                Button {
                    store.selectContainer(container)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 24, height: 25)
                }
                .buttonStyle(.plain).foregroundStyle(palette.muted)
                .help("Inspect \(container.name)")
                .accessibilityLabel("Details for \(container.name)")
            }
            .frame(width: 86, alignment: .trailing)
        }
        .font(DockeyFonts.mono(10)).foregroundStyle(palette.muted)
        .padding(.horizontal, 26)
        .frame(height: store.preferences.density == "comfortable" ? 59 : 47)
        .background(hovered ? palette.secondary : palette.background)
        .onHover { hovered = $0 }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
        .contextMenu {
            Button("Copy container name") { store.copyToClipboard(container.name) }
            Button("Copy container ID") { store.copyToClipboard(container.id) }
            Divider()
            Button("Inspect") { store.selectContainer(container) }
        }
    }

    private var metric: ContainerStats? { container.isRunning ? store.stats[container.id] : nil }
    private var shouldStop: Bool { [.running, .paused, .restarting].contains(container.state) }
    private var canToggle: Bool { shouldStop || [.created, .exited].contains(container.state) }

    @ViewBuilder
    private var portLabel: some View {
        if let port = container.ports.first {
            Menu {
                ForEach(container.ports) { binding in
                    Button("Copy \(binding.display)") { store.copyToClipboard(binding.display) }
                    if binding.transport.lowercased() == "tcp" {
                        Button("Open \(binding.hostPort) as HTTP") { store.openPort(binding) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(String(port.hostPort)).font(DockeyFonts.mono(10))
                    if container.ports.count > 1 { Text("+\(container.ports.count - 1)").font(DockeyFonts.ui(9)) }
                    Image(systemName: "arrow.up.right").font(.system(size: 8))
                }
                .foregroundStyle(palette.blue)
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
            .tint(palette.blue)
            .help(container.ports.map(\.display).joined(separator: "\n"))
            .accessibilityLabel("Published ports for \(container.name)")
        } else {
            Text("—")
        }
    }
}
