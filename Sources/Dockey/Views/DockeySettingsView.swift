import AppKit
import DockeyCore
import SwiftUI

@MainActor
struct DockeySettingsView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @ViewState<SettingsSection> private var selected = .appearance
    @ViewState<String> private var executableDraft = ""
    @ViewState<Bool> private var showResetConfirmation = false
    @FocusState private var executableFocused: Bool
    private var palette: DockeyPalette { DockeyPalette(scheme: scheme) }

    init(store: AppStore) {
        self.store = store
        DockeyFonts.register()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings").font(DockeyFonts.ui(16, weight: .semibold)).padding(.horizontal, 11).padding(
                    .vertical, 17)
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selected = section
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: section.symbol).font(.system(size: 13)).frame(width: 17)
                            Text(section.label).font(DockeyFonts.ui(12))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(selected == section ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected == section ? palette.primary : palette.muted)
                }
                Spacer()
                Text(store.isDemo ? "Demo · sample data" : "Dockey preferences")
                    .font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
                    .padding(.horizontal, 11).padding(.bottom, 17)
            }
            .padding(.horizontal, 10).frame(width: 180).background(palette.secondary)
            Rectangle().fill(palette.border).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(selected.label).font(DockeyFonts.ui(21, weight: .semibold)).tracking(-0.5)
                    .padding(.horizontal, 26).padding(.top, 27).padding(.bottom, 18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { settingsContent }
                        .padding(.horizontal, 26).padding(.bottom, 25)
                }
                Rectangle().fill(palette.border).frame(height: 1)
                Text("Preferences are saved locally. Engine data is managed separately.")
                    .font(DockeyFonts.ui(10)).foregroundStyle(palette.muted)
                    .padding(.horizontal, 26).frame(height: 38)
            }
            .frame(maxWidth: .infinity)
        }
        .font(DockeyFonts.ui())
        .foregroundStyle(palette.primary)
        .background(palette.background)
        .tint(palette.blue)
        .frame(width: 790, height: 570)
        .onAppear { executableDraft = store.preferences.dockerExecutable }
        .onChange(of: store.preferences.dockerExecutable) { _, newValue in executableDraft = newValue }
        .alert("Reset Dockey preferences?", isPresented: $showResetConfirmation) {
            Button("Reset preferences", role: .destructive) { store.resetPreferences() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Appearance, list, log, and connection preferences return to their defaults. Docker containers, images, volumes, and runtime configuration are preserved."
            )
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selected {
        case .appearance: appearance
        case .connections: connections
        case .containers: containers
        case .logs: logs
        case .safety: safety
        case .about: about
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A quiet interface, tuned to your workspace.").font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
                .padding(.bottom, 10)
            sectionTitle("Color theme")
            HStack(spacing: 12) {
                themeChoice("light", label: "Light")
                themeChoice("dark", label: "Dark")
                themeChoice("system", label: "System")
            }.padding(.vertical, 17)
            sectionTitle("Density")
            settingRow("Row density", detail: "Compact keeps more containers in view.") {
                DockeySelect(
                    title: "Row density", selection: preference(\.density),
                    options: [
                        .init(value: "compact", title: "Compact"),
                        .init(value: "comfortable", title: "Comfortable"),
                    ]
                ).frame(width: 145)
            }
            readOnlyRow("Typography", detail: "Geist Sans for the interface; Geist Mono for logs.", value: "Geist")
            readOnlyRow("Motion", detail: "Follows the macOS Reduce Motion preference.", value: "System")
        }
    }

    private func themeChoice(_ value: String, label: String) -> some View {
        let dark = value == "dark"
        let selected = store.preferences.appearance == value
        return Button {
            store.preferences.appearance = value
            store.savePreferences()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 1).fill(Color.gray.opacity(0.4)).frame(height: 3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8).frame(width: 30)
                    .background(Color.gray.opacity(0.08))
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.gray.opacity(0.5)).frame(width: 33, height: 5)
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 1).fill(Color.gray.opacity(0.3)).frame(height: 3)
                        }
                        Spacer(minLength: 0)
                    }.padding(9)
                }
                .frame(height: 67)
                .background(dark ? Color(hex: 0x0A0A0A) : value == "system" ? palette.background : Color(hex: 0xFAFAFA))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.2)))
                HStack {
                    Text(label).font(DockeyFonts.ui(11))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .medium)).foregroundStyle(
                            palette.primary)
                    }
                }
            }
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    selected ? palette.primary : palette.controlBorder, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) appearance")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Local engine")
            settingRow("Docker context", detail: "Selected for Dockey; does not switch your global CLI context.") {
                DockeySelect(
                    title: "Docker context", selection: $store.selectedContext,
                    options: store.contexts.filter(\.isLocal).map { .init(value: $0.name, title: $0.name) }
                )
                .frame(width: 160).disabled(store.isDemo)
            }
            if let context = store.contexts.first(where: { $0.name == store.selectedContext }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Endpoint").font(DockeyFonts.ui(12, weight: .medium))
                    Text(context.endpoint).font(DockeyFonts.mono(10)).foregroundStyle(palette.muted).textSelection(
                        .enabled)
                }.padding(.vertical, 14)
            }
            readOnlyRow(
                "Connection", detail: "Uses an existing Docker Engine over a local Unix socket.",
                value: store.isConnected ? "Connected" : "Unavailable")
            sectionTitle("Docker executable")
            Text(
                "Dockey finds Homebrew and standard install paths when launched from Finder. Set an explicit executable if needed."
            )
            .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).padding(.vertical, 12)
            HStack(spacing: 9) {
                TextField("Auto-detect Docker", text: $executableDraft).textFieldStyle(.plain)
                    .font(DockeyFonts.mono(11))
                    .focused($executableFocused)
                    .padding(.horizontal, 10).frame(height: 31)
                    .background(palette.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(
                            executableFocused ? palette.blue : palette.controlBorder)
                    )
                    .accessibilityLabel("Docker executable path")
                Button("Browse…") { store.chooseDockerExecutable() }.buttonStyle(DockeyButtonStyle())
            }.disabled(store.isDemo)
            HStack(spacing: 10) {
                Button("Apply & reconnect") {
                    store.preferences.dockerExecutable = executableDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.savePreferences()
                    Task { await store.refresh() }
                }
                .buttonStyle(DockeyButtonStyle(prominent: true))
                .disabled(store.isDemo || store.isRefreshing)
                if store.isRefreshing { ProgressView().controlSize(.small) }
            }.padding(.top, 15)
            if let error = store.connectionError {
                Text(error).font(DockeyFonts.ui(11)).foregroundStyle(palette.red).textSelection(.enabled).padding(
                    .top, 16)
            }
        }
    }

    private var containers: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("List preferences")
            toggleRow(
                "Show stopped containers", detail: "Keep stopped services visible in their project.",
                binding: preference(\.showStopped))
            readOnlyRow(
                "Updates", detail: "Container changes arrive automatically from the selected engine.",
                value: "Automatic")
            sectionTitle("Operation defaults")
            settingRow("Stop timeout", detail: "Seconds to wait for a graceful container shutdown.") {
                DockeySelect(
                    title: "Stop timeout", selection: preference(\.stopTimeout),
                    options: [10, 20, 30, 60].map { .init(value: $0, title: "\($0) seconds") }
                )
                .frame(width: 140)
            }
            Text(
                "Group controls act on existing containers. They do not create services or apply changed Compose files."
            )
            .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).padding(.top, 18)
        }
    }

    private var logs: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Log display")
            settingRow("Initial tail", detail: "Existing log lines to load when opening a container.") {
                DockeySelect(
                    title: "Initial log tail", selection: preference(\.logTail),
                    options: [100, 500, 1000, 5000].map { .init(value: $0, title: "\($0.formatted()) lines") }
                )
                .frame(width: 140)
            }
            toggleRow(
                "Show timestamps", detail: "Display the container's log timestamps.",
                binding: preference(\.logTimestamps))
            toggleRow(
                "Wrap long lines", detail: "Fit long log messages to the available width.",
                binding: preference(\.logWrap))
            settingRow("Text size", detail: "Independent of the interface text size.") {
                DockeySelect(
                    title: "Log text size", selection: preference(\.logFontSize),
                    options: [10.0, 11.0, 12.0, 13.0, 14.0, 16.0].map { .init(value: $0, title: "\(Int($0)) pt") }
                )
                .frame(width: 140)
            }
            Text(
                "The in-memory display buffer is bounded. These preferences do not change Docker's log retention policy."
            )
            .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).padding(.top, 18)
        }
    }

    private var safety: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Container operations")
            toggleRow(
                "Confirm before stopping", detail: "Review context and exact container names before a stop operation.",
                binding: preference(\.confirmStop))
            readOnlyRow(
                "Resource removal", detail: "This release does not remove containers, images, networks, or volumes.",
                value: "Unavailable")
            readOnlyRow("Automatic cleanup", detail: "Dockey does not automatically prune engine data.", value: "Off")
            sectionTitle("Privacy")
            readOnlyRow("Telemetry", detail: "No analytics or cloud account is required.", value: "None")
            readOnlyRow(
                "Inspection", detail: "Environment values and sensitive fields are redacted before display.",
                value: "Redacted")
            Text(
                "Container logs can contain application secrets. Dockey keeps them in memory; copy them only when you intend to share their contents."
            )
            .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).padding(.top, 18)
            sectionTitle("Application preferences")
            Button("Reset app preferences…") { showResetConfirmation = true }
                .buttonStyle(DockeyButtonStyle()).padding(.top, 16)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 15) {
                DockeyMascot().frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 6) {
                    DockeyWordmark(size: 29)
                    Text(
                        "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")"
                    )
                    .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
                }
            }.padding(.bottom, 23)
            Text("A native Mac companion for your local Docker Engine.")
                .font(DockeyFonts.ui(13)).padding(.bottom, 12)
            Text("Built with SwiftUI and AppKit. Docker Engine and its runtime are installed and managed separately.")
                .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
            sectionTitle("Project")
            Link(destination: URL(string: "https://github.com/cxkw-dev/dockey-ui")!) {
                Label("Source, documentation & releases", systemImage: "arrow.up.right.square")
                    .font(DockeyFonts.ui(12))
            }.padding(.vertical, 15)
            sectionTitle("Credits & licenses")
            Text(
                "Original Dockey mascot artwork. Geist Sans and Geist Mono are bundled with their SIL Open Font License notices. See the repository for application licensing and third-party notices."
            )
            .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).padding(.vertical, 14)
            Link(
                "License and third-party notices",
                destination: URL(string: "https://github.com/cxkw-dev/dockey-ui/blob/main/THIRD_PARTY_NOTICES.md")!
            )
            .font(DockeyFonts.ui(11))
        }
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: {
                store.preferences[keyPath: keyPath] = $0
                store.savePreferences()
            })
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(DockeyFonts.ui(11, weight: .medium)).foregroundStyle(palette.muted)
            .padding(.top, 18).padding(.bottom, 9).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control)
        -> some View
    {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DockeyFonts.ui(12, weight: .medium))
                Text(detail).font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).fixedSize(
                    horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control().controlSize(.small)
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func toggleRow(_ title: String, detail: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DockeyFonts.ui(12, weight: .medium))
                Text(detail).font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(DockeyCheckboxStyle(placement: .trailing, expands: true))
        .accessibilityLabel(title)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func readOnlyRow(_ title: String, detail: String, value: String) -> some View {
        settingRow(title, detail: detail) {
            Text(value).font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).fixedSize()
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance, connections, containers, logs, safety, about
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appearance: "Appearance"
        case .connections: "Connections"
        case .containers: "Containers"
        case .logs: "Logs"
        case .safety: "Safety & privacy"
        case .about: "About Dockey"
        }
    }
    var symbol: String {
        switch self {
        case .appearance: "sun.max"
        case .connections: "cable.connector"
        case .containers: "shippingbox"
        case .logs: "text.alignleft"
        case .safety: "checkmark.shield"
        case .about: "info.circle"
        }
    }
}
