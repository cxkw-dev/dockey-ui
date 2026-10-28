import AppKit
import CoreText
import DockeyCore
import SwiftUI

// Keep the stable property-wrapper API when an SDK also exports a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum DockeyFonts {
    @MainActor
    private static var registered = false

    @MainActor
    static func register() {
        guard !registered else { return }
        registered = true
        guard let directory = Bundle.module.resourceURL?.appendingPathComponent("Resources/Fonts"),
            let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func ui(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        let name =
            weight == .semibold || weight == .bold
            ? "Geist-SemiBold" : weight == .medium ? "Geist-Medium" : "Geist-Regular"
        return .custom(name, size: size).weight(weight)
    }

    static func mono(_ size: CGFloat = 11) -> Font {
        .custom("GeistMono-Regular", size: size)
    }
}

struct DockeyPalette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    var background: Color { Color(hex: dark ? 0x0A0A0A : 0xFFFFFF) }
    var secondary: Color { Color(hex: dark ? 0x111111 : 0xFAFAFA) }
    var hover: Color { Color(hex: dark ? 0x1A1A1A : 0xF2F2F2) }
    var border: Color { Color(hex: dark ? 0x262626 : 0xEAEAEA) }
    var primary: Color { Color(hex: dark ? 0xEDEDED : 0x171717) }
    var muted: Color { Color(hex: dark ? 0xA1A1A1 : 0x666666) }
    var blue: Color { Color(hex: dark ? 0x52A8FF : 0x0070F3) }
    var green: Color { Color(hex: dark ? 0x45C985 : 0x067A3B) }
    var amber: Color { Color(hex: dark ? 0xF5B943 : 0x946000) }
    var red: Color { Color(hex: dark ? 0xFF7077 : 0xC52A31) }
    var start: Color { Color(hex: dark ? 0x79B995 : 0x25704B) }
    var startSurface: Color { Color(hex: dark ? 0x14251C : 0xEEF7F1) }
    var stop: Color { Color(hex: dark ? 0xD38E92 : 0xA34850) }
    var stopSurface: Color { Color(hex: dark ? 0x2A1B1D : 0xFBF0F1) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct DockeyWordmark: View {
    var size: CGFloat = 19
    var body: some View {
        Text("Dockey").font(DockeyFonts.ui(size, weight: .semibold)).tracking(-size * 0.04)
    }
}

/// Native vector rendition of design-assets/dockey-mark.svg.
struct DockeyMascot: View {
    private let charcoal = Color(hex: 0x34363C)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Canvas { context, _ in
                    var arms = Path()
                    arms.move(to: CGPoint(x: 35, y: 65))
                    arms.addQuadCurve(to: CGPoint(x: 34, y: 34), control: CGPoint(x: 24, y: 52))
                    arms.move(to: CGPoint(x: 93, y: 65))
                    arms.addQuadCurve(to: CGPoint(x: 94, y: 34), control: CGPoint(x: 104, y: 52))
                    context.stroke(arms, with: .color(charcoal), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    context.fill(Path(ellipseIn: CGRect(x: 38, y: 103, width: 18, height: 14)), with: .color(charcoal))
                    context.fill(Path(ellipseIn: CGRect(x: 72, y: 103, width: 18, height: 14)), with: .color(charcoal))
                    context.fill(bodyPath, with: .color(charcoal))
                    let crate = Path(roundedRect: CGRect(x: 36, y: 11, width: 56, height: 28), cornerRadius: 5)
                    context.fill(crate, with: .color(Color(hex: 0x6BAEB3)))
                    var ribs = Path()
                    for x in [48.0, 64.0, 80.0] {
                        ribs.move(to: CGPoint(x: x, y: 18))
                        ribs.addLine(to: CGPoint(x: x, y: 32))
                    }
                    context.stroke(
                        ribs, with: .color(Color(hex: 0x397D86)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    for x in [34.0, 94.0] {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 4.5, y: 31.5, width: 9, height: 9)), with: .color(charcoal))
                    }
                    for x in [49.0, 79.0] {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 13, y: 59, width: 26, height: 28)),
                            with: .color(Color(hex: 0xFAF8F1)))
                    }
                    for x in [53.0, 75.0] {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 5.5, y: 64.5, width: 11, height: 11)),
                            with: .color(Color(hex: 0x24262B)))
                    }
                }
                .frame(width: 128, height: 128)
                .scaleEffect(side / 128)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var bodyPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 64, y: 39))
        let curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (70, 35, 77, 38, 80, 43), (87, 39, 94, 44, 94, 50), (102, 48, 107, 56, 103, 62),
            (110, 67, 108, 74, 104, 78), (109, 85, 104, 92, 98, 93), (100, 101, 92, 106, 85, 103),
            (81, 111, 72, 109, 65, 108), (58, 112, 50, 109, 47, 104), (38, 108, 29, 101, 30, 94),
            (22, 94, 19, 86, 24, 80), (17, 74, 20, 65, 25, 62), (20, 55, 26, 47, 33, 48),
            (34, 40, 43, 36, 49, 41), (53, 35, 60, 35, 64, 39),
        ]
        for curve in curves {
            path.addCurve(
                to: CGPoint(x: curve.4, y: curve.5),
                control1: CGPoint(x: curve.0, y: curve.1),
                control2: CGPoint(x: curve.2, y: curve.3))
        }
        path.closeSubpath()
        return path
    }
}

struct LifecycleButton: View {
    let action: ContainerAction
    var showLabel = false
    var isPending = false
    var disabled = false
    var accessibilityName: String? = nil
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                if isPending {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                } else {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                }
                if showLabel { Text(action.label).font(DockeyFonts.ui(11, weight: .medium)) }
            }
            .frame(minWidth: showLabel ? 42 : 24, minHeight: 25)
            .padding(.horizontal, showLabel ? 8 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(LifecycleStyle(action: action, filled: showLabel))
        .disabled(disabled || isPending)
        .help(accessibilityName ?? action.label + " existing containers")
        .accessibilityLabel(accessibilityName ?? action.label)
        .accessibilityValue(isPending ? "In progress" : "")
    }

    private var symbol: String {
        switch action {
        case .start: "play"
        case .stop: "stop"
        case .restart: "arrow.clockwise"
        }
    }
}

private struct LifecycleStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    let action: ContainerAction
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let palette = DockeyPalette(scheme: scheme)
        let foreground: Color = action == .start ? palette.start : action == .stop ? palette.stop : palette.muted
        let surface: Color =
            action == .start ? palette.startSurface : action == .stop ? palette.stopSurface : palette.hover
        configuration.label
            .foregroundStyle(foreground.opacity(enabled ? 1 : 0.35))
            .background((filled || configuration.isPressed ? surface : .clear), in: RoundedRectangle(cornerRadius: 5))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ContainerStatus: View {
    @Environment(\.colorScheme) private var scheme
    let container: DockerContainer

    var body: some View {
        let palette = DockeyPalette(scheme: scheme)
        let color = container.isUnhealthy ? palette.amber : container.isRunning ? palette.green : palette.muted
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(
                container.isUnhealthy ? "Unhealthy" : container.health == .starting ? "Starting" : container.state.label
            )
            .font(DockeyFonts.ui(11))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

struct DockeyEmptyState: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let message: String
    var symbol: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        let palette = DockeyPalette(scheme: scheme)
        VStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(palette.muted)
            } else {
                DockeyMascot().frame(width: 78, height: 78)
            }
            Text(title).font(DockeyFonts.ui(18, weight: .semibold))
            Text(message).font(DockeyFonts.ui(12)).foregroundStyle(palette.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.bordered).padding(.top, 2)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
