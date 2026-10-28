import DockeyCore
import SwiftUI

/// Original Dockey service illustrations, not vendor logos or authenticity indicators.
/// Matching editable SVG references live in design-assets/services/.
struct ServiceIcon: View {
    let identity: ServiceIdentity
    var size: CGFloat = 24
    @Environment(\.colorScheme) private var scheme

    private var colors: ServiceIconColors { ServiceIconColors(identity: identity, dark: scheme == .dark) }

    var body: some View {
        let colors = colors
        ZStack {
            RoundedRectangle(cornerRadius: size / 4).fill(colors.surface)
            RoundedRectangle(cornerRadius: size / 4).strokeBorder(colors.border, lineWidth: 1)
            Canvas { context, canvasSize in
                var context = context
                let scale = min(canvasSize.width, canvasSize.height) / 24
                context.scaleBy(x: scale, y: scale)
                switch identity {
                case .clickhouse: analytics(context, colors: colors)
                case .mongodb: document(context, colors: colors)
                case .redis: cache(context, colors: colors)
                case .postgresql: elephant(context, colors: colors)
                case .generic: container(context, colors: colors)
                }
            }
        }
        .frame(width: size, height: size)
        .help(identity == .generic ? "Container image" : "\(identity.displayName) image")
        .accessibilityHidden(true)
    }

    private func analytics(_ context: GraphicsContext, colors: ServiceIconColors) {
        // A compact bar chart, intentionally unrelated to any vendor's logo geometry.
        for rect in [
            CGRect(x: 3.5, y: 11, width: 4, height: 9.5),
            CGRect(x: 10, y: 3.5, width: 4, height: 17),
            CGRect(x: 16.5, y: 7.5, width: 4, height: 13),
        ] {
            context.fill(Path(roundedRect: rect, cornerRadius: 1.25), with: .color(colors.accent))
        }
    }

    private func document(_ context: GraphicsContext, colors: ServiceIconColors) {
        var page = Path()
        page.move(to: CGPoint(x: 8, y: 3.5))
        page.addLine(to: CGPoint(x: 13.5, y: 3.5))
        page.addLine(to: CGPoint(x: 17.5, y: 7.5))
        page.addLine(to: CGPoint(x: 17.5, y: 18.5))
        page.addQuadCurve(to: CGPoint(x: 15.5, y: 20.5), control: CGPoint(x: 17.5, y: 20.5))
        page.addLine(to: CGPoint(x: 8, y: 20.5))
        page.addQuadCurve(to: CGPoint(x: 6, y: 18.5), control: CGPoint(x: 6, y: 20.5))
        page.addLine(to: CGPoint(x: 6, y: 5.5))
        page.addQuadCurve(to: CGPoint(x: 8, y: 3.5), control: CGPoint(x: 6, y: 3.5))
        page.closeSubpath()
        context.fill(page, with: .color(colors.accent.opacity(0.1)))
        context.stroke(page, with: .color(colors.accent), style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
        var fold = Path()
        fold.move(to: CGPoint(x: 13.5, y: 3.5))
        fold.addLine(to: CGPoint(x: 13.5, y: 7.5))
        fold.addLine(to: CGPoint(x: 17.5, y: 7.5))
        context.stroke(fold, with: .color(colors.accent), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
        var leaf = Path()
        leaf.move(to: CGPoint(x: 9, y: 15.5))
        leaf.addCurve(
            to: CGPoint(x: 14.8, y: 10),
            control1: CGPoint(x: 7.7, y: 11.8), control2: CGPoint(x: 11, y: 9.7))
        leaf.addCurve(
            to: CGPoint(x: 9, y: 15.5),
            control1: CGPoint(x: 15.1, y: 13.8), control2: CGPoint(x: 12.1, y: 17.1))
        leaf.closeSubpath()
        context.fill(leaf, with: .color(colors.accent))
        var vein = Path()
        vein.move(to: CGPoint(x: 9.5, y: 15))
        vein.addLine(to: CGPoint(x: 13.4, y: 11.3))
        context.stroke(vein, with: .color(colors.surface), style: StrokeStyle(lineWidth: 0.85, lineCap: .round))
    }

    private func cache(_ context: GraphicsContext, colors: ServiceIconColors) {
        // Three front-facing cache lines, rather than a vendor's stacked diamond mark.
        for y in [4.1, 10, 15.9] {
            let line = Path(roundedRect: CGRect(x: 3.5, y: y, width: 17, height: 4), cornerRadius: 1.3)
            context.fill(line, with: .color(colors.accent.opacity(0.12)))
            context.stroke(line, with: .color(colors.accent), lineWidth: 1.25)
            context.fill(
                Path(ellipseIn: CGRect(x: 6, y: y + 1.3, width: 1.4, height: 1.4)),
                with: .color(colors.accent))
            var contents = Path()
            contents.move(to: CGPoint(x: 10, y: y + 2))
            contents.addLine(to: CGPoint(x: 17.3, y: y + 2))
            context.stroke(contents, with: .color(colors.accent), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
    }

    private func elephant(_ context: GraphicsContext, colors: ServiceIconColors) {
        // A new front-facing character built from simple ovals and a rounded head.
        for x in [3.3, 13.9] {
            let ear = Path(ellipseIn: CGRect(x: x, y: 7.9, width: 6.8, height: 9.2))
            context.fill(ear, with: .color(colors.accent.opacity(0.18)))
            context.stroke(ear, with: .color(colors.accent), lineWidth: 1.2)
        }
        context.fill(
            Path(roundedRect: CGRect(x: 7.2, y: 5.5, width: 9.6, height: 12.4), cornerRadius: 4.8),
            with: .color(colors.accent))
        var trunk = Path()
        trunk.move(to: CGPoint(x: 12, y: 14.5))
        trunk.addLine(to: CGPoint(x: 12, y: 18.5))
        trunk.addQuadCurve(to: CGPoint(x: 14.4, y: 21), control: CGPoint(x: 12, y: 21))
        trunk.addQuadCurve(to: CGPoint(x: 16.8, y: 18.6), control: CGPoint(x: 16.8, y: 21))
        context.stroke(trunk, with: .color(colors.accent), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        for x in [9.8, 14.2] {
            context.fill(
                Path(ellipseIn: CGRect(x: x - 0.75, y: 9.65, width: 1.5, height: 1.5)),
                with: .color(Color(hex: 0xFAFAF8)))
        }
    }

    private func container(_ context: GraphicsContext, colors: ServiceIconColors) {
        var cube = Path()
        cube.move(to: CGPoint(x: 12, y: 3.5))
        cube.addLine(to: CGPoint(x: 20, y: 8))
        cube.addLine(to: CGPoint(x: 20, y: 16.5))
        cube.addLine(to: CGPoint(x: 12, y: 21))
        cube.addLine(to: CGPoint(x: 4, y: 16.5))
        cube.addLine(to: CGPoint(x: 4, y: 8))
        cube.closeSubpath()
        cube.move(to: CGPoint(x: 4, y: 8))
        cube.addLine(to: CGPoint(x: 12, y: 12.5))
        cube.addLine(to: CGPoint(x: 20, y: 8))
        cube.move(to: CGPoint(x: 12, y: 12.5))
        cube.addLine(to: CGPoint(x: 12, y: 21))
        cube.move(to: CGPoint(x: 8, y: 5.75))
        cube.addLine(to: CGPoint(x: 16, y: 10.25))
        context.stroke(
            cube, with: .color(colors.accent),
            style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
    }
}

private struct ServiceIconColors {
    let identity: ServiceIdentity
    let dark: Bool
    var surface: Color { Color(hex: dark ? 0x171819 : 0xFAFAF9) }
    var border: Color { Color(hex: dark ? 0x2D3030 : 0xE5E6E5) }
    var accent: Color {
        let value: UInt32
        switch identity {
        case .clickhouse: value = dark ? 0xD0B76F : 0x9B7E24
        case .mongodb: value = dark ? 0x83B49A : 0x477D65
        case .redis: value = dark ? 0xCF9096 : 0xA65F63
        case .postgresql: value = dark ? 0x8EABC4 : 0x567E9D
        case .generic: value = dark ? 0xB0B6BC : 0x6D7278
        }
        return Color(hex: value)
    }
}
