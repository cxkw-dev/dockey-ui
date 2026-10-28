import DockeyCore
import SwiftUI

struct ContainerDetailView: View {
    @ObservedObject var store: AppStore
    let container: DockerContainer
    let requestAction: (ContainerAction, [DockerContainer]) -> Void
    @Environment(\.colorScheme) private var scheme
    @ViewState<String> private var logSearch = ""
    @ViewState<Bool> private var followLogs = true
    private var palette: DockeyPalette { DockeyPalette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    store.closeDetail()
                } label: {
                    Label("Containers", systemImage: "arrow.left")
                        .font(DockeyFonts.ui(11))
                }
                .buttonStyle(.plain).foregroundStyle(palette.muted)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(palette.muted)
                Text(container.name).font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 26).padding(.top, 20)

            HStack(spacing: 12) {
                Image(systemName: "shippingbox").font(.system(size: 22, weight: .light))
                    .frame(width: 41, height: 41).background(palette.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
                VStack(alignment: .leading, spacing: 6) {
                    Text(container.name).font(DockeyFonts.ui(21, weight: .semibold)).tracking(-0.6).lineLimit(1)
                    HStack(spacing: 8) {
                        ContainerStatus(container: container)
                        Text("·").foregroundStyle(palette.muted)
                        Text(container.image).font(DockeyFonts.mono(11)).foregroundStyle(palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                LifecycleButton(
                    action: shouldStop ? .stop : .start, showLabel: true,
                    isPending: store.pendingContainerIDs.contains(container.id),
                    disabled: !store.isConnected || !canToggle,
                    accessibilityName: "\(shouldStop ? "Stop" : "Start") \(container.name)"
                ) {
                    requestAction(shouldStop ? .stop : .start, [container])
                }
                LifecycleButton(
                    action: .restart,
                    disabled: !container.isRunning || !store.isConnected
                        || store.pendingContainerIDs.contains(container.id),
                    accessibilityName: "Restart \(container.name)"
                ) {
                    requestAction(.restart, [container])
                }
            }
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 23)

            HStack(spacing: 23) {
                ForEach(DetailTab.allCases) { tab in
                    Button {
                        store.detailTab = tab
                    } label: {
                        Text(tab.label).font(DockeyFonts.ui(12, weight: store.detailTab == tab ? .medium : .regular))
                            .foregroundStyle(store.detailTab == tab ? palette.primary : palette.muted)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if store.detailTab == tab { Rectangle().fill(palette.primary).frame(height: 2) }
                            }
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(store.detailTab == tab ? .isSelected : [])
                }
                Spacer()
                Button {
                    Task { await store.refreshDetail() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain).foregroundStyle(palette.muted).help("Refresh container details")
                .accessibilityLabel("Refresh details")
            }
            .padding(.horizontal, 26)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }

            metricStrip
            detailContent
        }
        .preference(key: DockeyMetricsVisibilityKey.self, value: container.isRunning)
        .onChange(of: store.detailTab) { _, _ in Task { await store.refreshDetail() } }
    }

    private var shouldStop: Bool { [.running, .paused, .restarting].contains(container.state) }
    private var canToggle: Bool { shouldStop || [.created, .exited].contains(container.state) }
    private var metric: ContainerStats? { store.stats[container.id] }

    private var metricStrip: some View {
        HStack(spacing: 22) {
            metricLabel(
                "cpu", "CPU", container.isRunning ? metric.map { String(format: "%.2f%%", $0.cpuPercent) } ?? "—" : "—")
            metricLabel("memorychip", "Memory", container.isRunning ? metric?.memoryUsage ?? "—" : "—")
            if let binding = container.ports.first {
                Button {
                    store.copyToClipboard(binding.display)
                } label: {
                    Label(binding.display, systemImage: "network").font(DockeyFonts.mono(10))
                }
                .buttonStyle(.plain).foregroundStyle(palette.blue).help("Copy published port binding")
            }
            Spacer(minLength: 0)
            Text(String(container.id.prefix(12))).font(DockeyFonts.mono(10)).foregroundStyle(palette.muted)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 26).frame(height: 43)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func metricLabel(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(palette.muted)
            Text(title).foregroundStyle(palette.muted)
            Text(value).font(DockeyFonts.ui(11, weight: .medium))
        }
        .font(DockeyFonts.ui(11))
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.detailTab {
        case .logs: logContent
        case .inspect: inspectionContent
        case .stats: statsContent
        case .mounts: mountsContent
        }
    }

    private var filteredLogs: String {
        guard !logSearch.isEmpty else { return store.logText }
        return store.logText.components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(logSearch) }.joined(separator: "\n")
    }

    private var logContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                    TextField("Search logs…", text: $logSearch).textFieldStyle(.plain)
                        .accessibilityLabel("Search container logs")
                }
                .font(DockeyFonts.ui(11)).padding(.horizontal, 10).frame(height: 30)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border))
                Toggle("Follow", isOn: $followLogs).toggleStyle(DockeyCheckboxStyle()).font(DockeyFonts.ui(11))
                    .fixedSize().help("Automatically scroll to new log output")
                Button {
                    store.copyToClipboard(filteredLogs)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain).disabled(filteredLogs.isEmpty).help("Copy displayed logs")
                .accessibilityLabel("Copy displayed logs")
            }
            .padding(.horizontal, 26).padding(.vertical, 15)
            if store.logText.isEmpty {
                DockeyEmptyState(
                    title: "No log output yet",
                    message: "Output appears here when this container writes to stdout or stderr.",
                    symbol: "text.alignleft")
            } else {
                LogOutputView(
                    text: filteredLogs, wrap: store.preferences.logWrap,
                    fontSize: store.preferences.logFontSize,
                    follow: followLogs && logSearch.isEmpty, palette: palette)
            }
            HStack(spacing: 7) {
                Circle().fill(container.isRunning ? palette.green : palette.muted).frame(width: 5, height: 5)
                Text(
                    store.isDemo
                        ? "Sample log output" : container.isRunning ? "Following container output" : "Container stopped"
                )
                Spacer()
                Text("Bounded session buffer")
            }
            .font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
            .padding(.horizontal, 26).frame(height: 31)
            .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        }
    }

    private var inspectionContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Environment values and sensitive fields are redacted.").font(DockeyFonts.ui(11)).foregroundStyle(
                    palette.muted)
                Spacer()
                Button("Copy JSON") { store.copyToClipboard(store.inspection?.json ?? "") }
                    .controlSize(.small).disabled(store.inspection == nil)
            }
            .padding(.horizontal, 26).padding(.vertical, 15)
            ScrollView([.horizontal, .vertical]) {
                Text(store.inspection?.json ?? "Loading inspection…")
                    .font(DockeyFonts.mono(11)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(.horizontal, 26).padding(.bottom, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var statsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statsRow(
                    "CPU usage",
                    container.isRunning
                        ? metric.map { String(format: "%.2f%%", $0.cpuPercent) } ?? "Unavailable" : "Container stopped")
                statsRow("Memory", container.isRunning ? metric?.memoryUsage ?? "Unavailable" : "—")
                if let memory = metric?.memoryPercent, container.isRunning {
                    ProgressView(value: min(max(memory, 0), 100), total: 100).tint(palette.blue).padding(.vertical, 14)
                        .accessibilityLabel("Memory usage for \(container.name)")
                        .accessibilityValue("\(memory.formatted(.number.precision(.fractionLength(1)))) percent")
                }
                statsRow(
                    "Memory usage",
                    container.isRunning ? metric.map { String(format: "%.1f%%", $0.memoryPercent) } ?? "—" : "—")
                statsRow("Network I/O", container.isRunning ? metric?.networkIO ?? "—" : "—")
                statsRow("Block I/O", container.isRunning ? metric?.blockIO ?? "—" : "—")
                Text("Values come from Docker stats. CPU can exceed 100% when a container uses multiple cores.")
                    .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).padding(.top, 22)
            }
            .padding(26)
        }
    }

    private func statsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
            Spacer()
            Text(value).font(DockeyFonts.mono(12)).textSelection(.enabled)
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private var mountsContent: some View {
        Group {
            if let mounts = store.inspection?.mounts, !mounts.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(mounts.enumerated()), id: \.offset) { _, mount in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "externaldrive").foregroundStyle(palette.muted)
                                Text(mount).font(DockeyFonts.mono(11)).textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 18)
                            Rectangle().fill(palette.border).frame(height: 1)
                        }
                        Text("Mount inspection only. Dockey does not remove or change volumes.")
                            .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).padding(.top, 20)
                    }.padding(.horizontal, 26)
                }
            } else {
                DockeyEmptyState(
                    title: "No mounts", message: "This container has no bind mounts or named volumes.",
                    symbol: "externaldrive")
            }
        }
    }
}

private struct LogOutputView: View {
    let text: String
    let wrap: Bool
    let fontSize: Double
    let follow: Bool
    let palette: DockeyPalette

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(wrap ? .vertical : [.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text.isEmpty ? "No matching log lines." : text)
                        .font(DockeyFonts.mono(CGFloat(fontSize))).lineSpacing(4)
                        .foregroundStyle(palette.muted).textSelection(.enabled)
                    Color.clear.frame(height: 1).id("log-end")
                }
                .frame(maxWidth: wrap ? .infinity : nil, alignment: .topLeading)
                .padding(.horizontal, 26).padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityLabel("Container logs")
            .onChange(of: text) { _, _ in if follow { proxy.scrollTo("log-end", anchor: .bottom) } }
            .onChange(of: follow) { _, enabled in if enabled { proxy.scrollTo("log-end", anchor: .bottom) } }
            .onAppear { if follow { proxy.scrollTo("log-end", anchor: .bottom) } }
        }
    }
}
