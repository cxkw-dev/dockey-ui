import DockeyCore
import SwiftUI

enum ResourceKind: Equatable {
    case images, volumes, networks
}

struct ResourceListView: View {
    let kind: ResourceKind
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    private var palette: DockeyPalette { DockeyPalette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.resourceError, !rows.isEmpty {
                DockeyFailureView(title: "\(title) may be out of date", message: error, isRetrying: store.isLoadingResources) {
                    Task { await store.retryResources() }
                }
            }
            resourceContent
        }
    }

    @ViewBuilder
    private var resourceContent: some View {
        if rows.isEmpty && (store.isLoadingResources || store.isRefreshing) {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Loading \(title.lowercased())…")
                    .font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if rows.isEmpty, let error = store.resourceError {
            DockeyEmptyState(title: "Could not load \(title.lowercased())", message: error,
                symbol: "exclamationmark.circle", actionTitle: "Retry") {
                Task { await store.retryResources() }
            }
        } else if rows.isEmpty {
            DockeyEmptyState(
                title: "No \(title.lowercased()) found",
                message: "Resources from the selected local engine appear here.", symbol: symbol)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 14) {
                            if let imageReference = row.imageReference {
                                ServiceIcon(identity: ServiceIdentity(imageReference: imageReference))
                            } else {
                                Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(
                                    palette.muted
                                ).frame(width: 24)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name).font(DockeyFonts.ui(12, weight: .medium)).lineLimit(1)
                                Text(row.detail).font(DockeyFonts.ui(10)).foregroundStyle(palette.muted).lineLimit(2)
                            }
                            Spacer(minLength: 20)
                            Text(row.metadata).font(DockeyFonts.mono(10)).foregroundStyle(palette.muted)
                            Button {
                                store.copyToClipboard(row.copyID)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 12)).frame(width: 25, height: 28)
                            }
                            .buttonStyle(.plain).foregroundStyle(palette.muted)
                            .help("Copy \(kind == .volumes ? "volume name" : "resource ID")")
                            .accessibilityLabel("Copy identifier for \(row.name)")
                        }
                        .padding(.vertical, 18)
                        Rectangle().fill(palette.border).frame(height: 1)
                    }
                    if kind == .volumes {
                        Text(
                            "Volumes may contain valuable data even when no container is using them. This view is read-only."
                        )
                        .font(DockeyFonts.ui(11)).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 26).padding(.bottom, 24)
            }
            .textSelection(.enabled)
        }
    }

    private var rows: [ResourceRow] {
        switch kind {
        case .images:
            store.images.map {
                ResourceRow(
                    id: $0.id, name: $0.displayName, detail: String($0.id.prefix(19)),
                    metadata: "\($0.size) · \($0.createdSince)", imageReference: $0.displayName, copyID: $0.imageID)
            }
        case .volumes:
            store.volumes.map { ResourceRow(id: $0.name, name: $0.name, detail: $0.mountpoint, metadata: $0.driver) }
        case .networks:
            store.networks.map {
                ResourceRow(
                    id: $0.id, name: $0.name, detail: String($0.id.prefix(12)), metadata: "\($0.driver) · \($0.scope)")
            }
        }
    }

    private var title: String {
        switch kind {
        case .images: "Images"
        case .volumes: "Volumes"
        case .networks: "Networks"
        }
    }
    private var symbol: String {
        switch kind {
        case .images: "square.stack"
        case .volumes: "externaldrive"
        case .networks: "network"
        }
    }
}

private struct ResourceRow {
    let id: String
    let name: String
    let detail: String
    let metadata: String
    let imageReference: String?
    let copyID: String

    init(id: String, name: String, detail: String, metadata: String, imageReference: String? = nil, copyID: String? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.metadata = metadata
        self.imageReference = imageReference
        self.copyID = copyID ?? id
    }
}
