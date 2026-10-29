import DockeyCore
import SwiftUI

/// Read-only disk usage analysis. Cleanup commands are shown for the user to review and run; Dockey never runs them.
struct StorageView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @ViewState<Set<CleanupKind>> private var expandedKinds = []
    @ViewState<String?> private var copiedID = nil
    private var palette: DockeyPalette { DockeyPalette(scheme: scheme) }
    private let collapsedRowLimit = 5

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.resourceError, store.storage != nil {
                DockeyFailureView(
                    title: "Storage may be out of date", message: error, isRetrying: store.isLoadingResources
                ) {
                    Task { await store.retryResources() }
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let report = store.storage {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summary(report)
                    let kinds = CleanupKind.allCases.filter { !report.candidates($0).isEmpty }
                    if kinds.isEmpty {
                        DockeyEmptyState(
                            title: "Nothing to clean up",
                            message: "Every image, container, and volume is in use, and there is no idle build cache.",
                            symbol: "checkmark.circle"
                        )
                        .frame(minHeight: 240)
                    }
                    ForEach(kinds) { kind in
                        section(kind, report: report)
                    }
                    Text(
                        "Dockey only measures storage and never removes anything. Copy a command, review what it covers, and run it in Terminal. Image sizes count unique layers, so actual savings can be higher."
                    )
                    .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                }
                .padding(.horizontal, 26).padding(.bottom, 24)
            }
        } else if store.isLoadingResources || store.isRefreshing {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Measuring disk usage…").font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
                Text("Volume sizes are calculated by the engine and can take a moment.")
                    .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if let error = store.resourceError {
            DockeyEmptyState(
                title: "Could not measure storage", message: error, symbol: "exclamationmark.circle",
                actionTitle: "Retry"
            ) {
                Task { await store.retryResources() }
            }
        } else {
            DockeyEmptyState(
                title: "No storage data", message: "Disk usage from the selected local engine appears here.",
                symbol: "internaldrive")
        }
    }

    private func summary(_ report: StorageReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ByteSize.format(report.reclaimableBytes))
                        .font(DockeyFonts.ui(30, weight: .semibold)).tracking(-1)
                    Text("could be reclaimed").font(DockeyFonts.ui(13)).foregroundStyle(palette.muted)
                }
                Text(
                    "\(ByteSize.format(report.lowRiskReclaimableBytes)) without touching named volumes or stopped containers"
                )
                .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                ForEach(report.usage) { usage in
                    usageTile(usage)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private func usageTile(_ usage: StorageUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(usage.category.label).font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
            Text(usage.bytes.map(ByteSize.format) ?? usage.count.formatted())
                .font(DockeyFonts.ui(16, weight: .medium))
            Text(activity(usage)).font(DockeyFonts.ui(10)).foregroundStyle(palette.muted).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
        .accessibilityElement(children: .combine)
    }

    private func activity(_ usage: StorageUsage) -> String {
        let total = usage.count.formatted()
        switch usage.category {
        case .images: return "\(usage.activeCount.formatted()) used by containers"
        case .containers: return "\(usage.activeCount.formatted()) of \(total) running"
        case .volumes: return "\(usage.activeCount.formatted()) of \(total) attached"
        case .buildCache: return "\(total) records · \(usage.activeCount.formatted()) in use"
        }
    }

    private func section(_ kind: CleanupKind, report: StorageReport) -> some View {
        let items = report.candidates(kind)
        let expanded = expandedKinds.contains(kind)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(kind.label).font(DockeyFonts.ui(13, weight: .semibold))
                        Text("\(items.count.formatted()) · \(ByteSize.format(report.reclaimableBytes(kind)))")
                            .font(DockeyFonts.mono(10)).foregroundStyle(palette.muted)
                        if kind.needsReview {
                            Text("Review first")
                                .font(DockeyFonts.ui(10, weight: .medium)).foregroundStyle(palette.amber)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.amber.opacity(0.5)))
                        }
                    }
                    Text(kind.explanation).font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if let arguments = kind.bulkArguments {
                    let command = CleanupCommand.render(arguments, context: store.selectedContext)
                    Button(copiedID == kind.id ? "Copied" : "Copy command") { copy(command, id: kind.id) }
                        .buttonStyle(DockeyButtonStyle())
                        .help(command)
                        .accessibilityLabel("Copy command to remove all \(kind.label.lowercased())")
                }
            }
            .padding(.top, 26).padding(.bottom, 10)
            ForEach(expanded ? items : Array(items.prefix(collapsedRowLimit))) { item in
                Rectangle().fill(palette.border).frame(height: 1)
                row(item)
            }
            if items.count > collapsedRowLimit {
                Rectangle().fill(palette.border).frame(height: 1)
                Button(expanded ? "Show fewer" : "Show all \(items.count.formatted())") {
                    if expanded { expandedKinds.remove(kind) } else { expandedKinds.insert(kind) }
                }
                .buttonStyle(.plain).font(DockeyFonts.ui(11)).foregroundStyle(palette.blue)
                .padding(.vertical, 10)
            }
        }
    }

    private func row(_ item: CleanupCandidate) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol(item.kind)).font(.system(size: 15, weight: .light))
                .foregroundStyle(palette.muted).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(DockeyFonts.ui(12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    if let project = item.project {
                        Text(project).font(DockeyFonts.ui(10)).foregroundStyle(palette.primary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(palette.hover, in: RoundedRectangle(cornerRadius: 3))
                            .help("Compose project \(project)")
                    }
                    Text(item.detail).font(DockeyFonts.ui(10)).foregroundStyle(palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 20)
            Text(item.bytes.map(ByteSize.format) ?? "—").font(DockeyFonts.mono(10)).foregroundStyle(palette.muted)
            if let arguments = item.removalArguments {
                let command = CleanupCommand.render(arguments, context: store.selectedContext)
                Button {
                    copy(command, id: item.id)
                } label: {
                    Image(systemName: copiedID == item.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12)).frame(width: 25, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(palette.muted)
                .help(command)
                .accessibilityLabel("Copy removal command for \(item.name)")
            } else {
                Color.clear.frame(width: 25, height: 28)
            }
        }
        .padding(.vertical, 12)
        .textSelection(.enabled)
    }

    private func symbol(_ kind: CleanupKind) -> String {
        switch kind {
        case .danglingImage, .unusedImage: AppSection.images.symbol
        case .stoppedContainer: "shippingbox"
        case .anonymousVolume, .namedVolume: "externaldrive"
        case .buildCache: "hammer"
        }
    }

    private func copy(_ command: String, id: String) {
        store.copyToClipboard(command)
        copiedID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == id { copiedID = nil }
        }
    }
}
