import AppKit
import CoreText
import DockeyCore
import SwiftUI

// Keep the stable property-wrapper API when an SDK also exports a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum DockeyFonts {
    @MainActor
    private static var registered = false

    // SwiftPM toolchains disagree about Bundle.module's lookup inside .app files.
    // Packaged apps use the standard macOS Resources directory explicitly.
    private static var fontDirectory: URL? {
        let bundleURL: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resourceURL = Bundle.main.resourceURL else { return nil }
            bundleURL = resourceURL.appendingPathComponent("Dockey_Dockey.bundle")
        } else {
            bundleURL = Bundle.module.bundleURL
        }
        // Native SwiftPM emits a flat bundle; SwiftBuild emits a wrapped bundle.
        // Bundle.resourceURL may already enter the flat bundle's Resources folder.
        return ["Contents/Resources/Resources/Fonts", "Resources/Fonts"]
            .map { bundleURL.appendingPathComponent($0, isDirectory: true) }
            .first { candidate in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory)
                    && directory.boolValue
            }
    }

    @MainActor
    static func register() {
        guard !registered else { return }
        guard let directory = fontDirectory,
            let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
        registered = true
    }

    @MainActor
    static func verifyBundledFonts() throws {
        let fonts = [
            ("Geist-Regular.ttf", "Geist-Regular"),
            ("Geist-Medium.ttf", "Geist-Medium"),
            ("Geist-Semibold.ttf", "Geist-SemiBold"),
            ("GeistMono-Regular.ttf", "GeistMono-Regular"),
        ]
        guard Bundle.main.bundleURL.pathExtension == "app", let directory = fontDirectory,
            fonts.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.0).path) })
        else { throw CocoaError(.fileReadNoSuchFile) }
        let notices =
            [directory.appendingPathComponent("Geist-OFL.txt"), directory.appendingPathComponent("GeistMono-OFL.txt")]
            + ["Apache-2.0.txt", "THIRD_PARTY_NOTICES.md"].compactMap {
                Bundle.main.resourceURL?.appendingPathComponent("Licenses/\($0)")
            }
        guard notices.count == 4, notices.allSatisfy({ (try? Data(contentsOf: $0).isEmpty) == false }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        register()
        guard fonts.allSatisfy({ NSFont(name: $0.1, size: 12)?.fontName == $0.1 }) else {
            throw CocoaError(.fileReadCorruptFile)
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
    var controlBorder: Color { Color(hex: dark ? 0x3E3E3E : 0xD4D4D4) }
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
    var size: CGFloat = 26
    var body: some View {
        DockeyWordmarkShape()
            .fill()
            .frame(width: size * DockeyWordmarkShape.aspectRatio, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dockey")
            .accessibilityAddTraits(.isImage)
    }
}

struct DockeyBrandLockup: View {
    var mascotSize: CGFloat = 32
    var wordmarkSize: CGFloat = 26
    var spacing: CGFloat = 3

    private enum OpticalCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
    }
    private static let opticalCenter = VerticalAlignment(OpticalCenter.self)

    var body: some View {
        HStack(alignment: Self.opticalCenter, spacing: spacing) {
            DockeyMascot().frame(width: mascotSize, height: mascotSize)
                .alignmentGuide(Self.opticalCenter) { $0.height * 0.53 }
            DockeyWordmark(size: wordmarkSize)
                .alignmentGuide(Self.opticalCenter) { $0.height * DockeyWordmarkShape.opticalCenterRatio }
        }
    }
}

/// Native vector mascot based on design-assets/dockey-mark.svg.
struct DockeyMascot: View {
    enum Treatment { case flat, dock }
    var treatment: Treatment = .flat
    private var charcoal: Color { Color(hex: treatment == .dock ? 0x4D5561 : 0x34363C) }
    private var rim: Color { Color(hex: 0xB3E7E9).opacity(0.82) }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            // Keep the outline readable in the 32-point sidebar without thickening Dock artwork.
            let rimScale = treatment == .dock ? 1 : max(1, 64 / max(side, 1))
            ZStack {
                Canvas { context, _ in
                    var arms = Path()
                    arms.move(to: CGPoint(x: 35, y: 65))
                    arms.addQuadCurve(to: CGPoint(x: 34, y: 34), control: CGPoint(x: 24, y: 52))
                    arms.move(to: CGPoint(x: 93, y: 65))
                    arms.addQuadCurve(to: CGPoint(x: 94, y: 34), control: CGPoint(x: 104, y: 52))
                    context.stroke(
                        arms, with: .color(rim), style: StrokeStyle(lineWidth: 7 + 2.2 * rimScale, lineCap: .round))
                    context.stroke(arms, with: .color(charcoal), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    for x in [38.0, 72.0] {
                        let foot = Path(ellipseIn: CGRect(x: x, y: 103, width: 18, height: 14))
                        context.fill(foot, with: .color(charcoal))
                        context.stroke(foot, with: .color(rim), lineWidth: 1.3 * rimScale)
                    }
                    context.fill(bodyPath, with: .color(charcoal))
                    context.stroke(
                        bodyPath, with: .color(rim), style: StrokeStyle(lineWidth: 1.3 * rimScale, lineJoin: .round))
                    let crate = Path(roundedRect: CGRect(x: 36, y: 11, width: 56, height: 28), cornerRadius: 5)
                    context.fill(crate, with: .color(Color(hex: treatment == .dock ? 0x92D6DA : 0x6BAEB3)))
                    context.stroke(crate, with: .color(rim), lineWidth: rimScale)
                    var ribs = Path()
                    for x in [48.0, 64.0, 80.0] {
                        ribs.move(to: CGPoint(x: x, y: 18))
                        ribs.addLine(to: CGPoint(x: x, y: 32))
                    }
                    context.stroke(
                        ribs, with: .color(Color(hex: 0x397D86)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    for x in [34.0, 94.0] {
                        let hand = Path(ellipseIn: CGRect(x: x - 4.5, y: 31.5, width: 9, height: 9))
                        context.fill(hand, with: .color(charcoal))
                        context.stroke(hand, with: .color(rim), lineWidth: 1.1 * rimScale)
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
                Button(actionTitle, action: action).buttonStyle(DockeyButtonStyle()).padding(.top, 2)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact custom chrome around a native menu and native picker semantics.
struct DockeySelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

struct DockeySelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [DockeySelectOption<Value>]
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? "Choose…"
    }

    var body: some View {
        let palette = DockeyPalette(scheme: scheme)
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { option in Text(option.title).tag(option.value) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            DockeyMenuLabel(title: selectedTitle)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .tint(palette.primary)
        .foregroundStyle(palette.primary)
        .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
        .modifier(DockeyMenuChrome(focused: focused))
        .focused($focused)
        .disabled(options.isEmpty)
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }
}

/// Shared label for selects and menus that have additional commands.
struct DockeyMenuLabel: View {
    let title: String
    var statusColor: Color? = nil
    var expands = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = DockeyPalette(scheme: scheme)
        HStack(spacing: 8) {
            if let statusColor { Circle().fill(statusColor).frame(width: 5, height: 5) }
            Text(title).font(DockeyFonts.ui(11)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: expands ? nil : 160, alignment: .leading)
            if expands { Spacer(minLength: 8) }
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .foregroundStyle(palette.primary)
        .padding(.horizontal, 10)
        .frame(minHeight: 31)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Applied to the actual Menu rather than its label, whose styling AppKit can discard.
struct DockeyMenuChrome: ViewModifier {
    var focused = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        let palette = DockeyPalette(scheme: scheme)
        content
            .background(palette.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? palette.blue : palette.controlBorder))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct DockeyCheckboxStyle: ToggleStyle {
    enum Placement: Equatable { case leading, trailing }
    var placement: Placement = .leading
    var expands = false

    func makeBody(configuration: Configuration) -> some View {
        DockeyCheckboxControl(configuration: configuration, placement: placement, expands: expands)
    }
}

private struct DockeyCheckboxControl: View {
    let configuration: ToggleStyleConfiguration
    let placement: DockeyCheckboxStyle.Placement
    let expands: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    @ViewState<Bool> private var hovered = false

    var body: some View {
        let palette = DockeyPalette(scheme: scheme)
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                if placement == .leading { mark(palette) }
                configuration.label
                if expands { Spacer(minLength: 16) }
                if placement == .trailing { mark(palette) }
            }
            .font(DockeyFonts.ui(11))
            .foregroundStyle(palette.primary)
            .padding(.vertical, 7)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 31, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovered = $0 }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 5).stroke(palette.blue, lineWidth: 2).padding(-3)
            }
        }
        .opacity(enabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) {
                configuration.label
            }
            .toggleStyle(.checkbox)
        }
    }

    private func mark(_ palette: DockeyPalette) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(configuration.isOn ? palette.primary : palette.background)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(configuration.isOn ? palette.primary : hovered ? palette.muted : palette.controlBorder)
            }
            .overlay {
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.background)
                }
            }
            .frame(width: 15, height: 15)
            .accessibilityHidden(true)
    }
}

struct DockeyButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = DockeyPalette(scheme: scheme)
        configuration.label
            .font(DockeyFonts.ui(11, weight: .medium))
            .foregroundStyle(prominent ? palette.background : palette.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 31)
            .background(
                prominent ? palette.primary : configuration.isPressed ? palette.hover : palette.background,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(prominent ? palette.primary : palette.controlBorder))
            .opacity(enabled ? configuration.isPressed ? 0.8 : 1 : 0.4)
    }
}
