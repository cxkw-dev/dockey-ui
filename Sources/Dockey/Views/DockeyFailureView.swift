import SwiftUI

struct DockeyFailureView: View {
    let title: String
    let message: String
    var isRetrying = false
    let retry: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = DockeyPalette(scheme: scheme)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(palette.amber).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DockeyFonts.ui(11, weight: .medium))
                Text(message).font(DockeyFonts.ui(11)).foregroundStyle(palette.muted).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Button(isRetrying ? "Retrying…" : "Retry", action: retry)
                .buttonStyle(DockeyButtonStyle()).disabled(isRetrying)
                .accessibilityLabel("Retry \(title.lowercased())")
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.secondary)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}
