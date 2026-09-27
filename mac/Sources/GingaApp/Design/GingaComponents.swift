import SwiftUI

// The components of the Ginga design system (design/ginga-design/components), in SwiftUI.
// Motion: only transforms and opacity; nothing loops unless the window is visible, and reduced
// motion keeps the static equivalent (the text always says the state).

// MARK: Marks

/// Mark B, the monogram "g": a screen-shaped bowl with an S Pen tail and the star (design/brand/ginga-monogram.svg).
struct GingaMonogram: View {
    @Environment(\.ginga) private var palette

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 120
            context.scaleBy(x: s, y: s)
            context.translateBy(x: 4, y: -1)
            let bowl = Path(roundedRect: CGRect(x: 26, y: 16, width: 60, height: 54), cornerRadius: 16)
            context.stroke(bowl, with: .color(palette.isDark ? .white : palette.ink), lineWidth: 12)
            var tail = Path()
            tail.move(to: CGPoint(x: 86, y: 44))
            tail.addLine(to: CGPoint(x: 86, y: 80))
            tail.addQuadCurve(to: CGPoint(x: 58, y: 106), control: CGPoint(x: 86, y: 106))
            tail.addQuadCurve(to: CGPoint(x: 32, y: 96), control: CGPoint(x: 42, y: 106))
            context.stroke(tail, with: .color(palette.cobalt), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            context.fill(GingaStar.path(center: CGPoint(x: 56, y: 43), radius: 9), with: .color(palette.star))
        }
        .accessibilityHidden(true)
    }
}

/// Mark A, the orbit: the Mac's screen outline, the tilted tablet and the star (design/brand/ginga-orbit.svg).
struct GingaOrbitMark: View {
    @Environment(\.ginga) private var palette

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 120
            context.scaleBy(x: s, y: s)
            context.translateBy(x: 1.2, y: 6.4)
            GingaOrbitMark.draw(in: &context, outline: palette.isDark ? .white : palette.ink, tablet: palette.cobalt, star: palette.star)
        }
        .accessibilityHidden(true)
    }

    /// In the mark's own 120×120 coordinates.
    static func draw(in context: inout GraphicsContext, outline: Color, tablet: Color, star: Color) {
        context.stroke(Path(roundedRect: CGRect(x: 10, y: 22, width: 66, height: 48), cornerRadius: 9), with: .color(outline), lineWidth: 7)
        var tilted = context
        tilted.translateBy(x: 78, y: 70)
        tilted.rotate(by: .degrees(-10))
        tilted.translateBy(x: -78, y: -70)
        tilted.fill(Path(roundedRect: CGRect(x: 50, y: 48, width: 58, height: 42), cornerRadius: 9), with: .color(tablet))
        context.fill(GingaStar.path(center: CGPoint(x: 100, y: 22), radius: 9.5), with: .color(star))
    }
}

/// The brand's four-pointed star (the only illustration allowed).
enum GingaStar {
    /// The star of the SVGs (M0 -10 C1.2 -2.4 2.4 -1.2 10 0 …), scaled to `radius`.
    static func path(center: CGPoint, radius: CGFloat) -> Path {
        let k = radius / 10
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x * k, y: center.y + y * k) }
        var path = Path()
        path.move(to: p(0, -10))
        path.addCurve(to: p(10, 0), control1: p(1.2, -2.4), control2: p(2.4, -1.2))
        path.addCurve(to: p(0, 10), control1: p(2.4, 1.2), control2: p(1.2, 2.4))
        path.addCurve(to: p(-10, 0), control1: p(-1.2, 2.4), control2: p(-2.4, 1.2))
        path.addCurve(to: p(0, -10), control1: p(-2.4, -1.2), control2: p(-1.2, -2.4))
        path.closeSubpath()
        return path
    }
}

// MARK: SettingsGroup

/// The short title above a group (`g-group-title`).
struct GingaGroupTitle: View {
    @Environment(\.ginga) private var palette
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.3)
            .foregroundStyle(palette.inkMuted)
            .padding(.leading, GingaSpace.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A card of rows: `surface` on `bg`; in Black espacial only a 1px `line` outline on pure black.
struct GingaGroup<Content: View>: View {
    @Environment(\.ginga) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: GingaRadius.lg, style: .continuous))
            .overlay {
                if palette.isDark {
                    RoundedRectangle(cornerRadius: GingaRadius.lg, style: .continuous).strokeBorder(palette.line, lineWidth: 1)
                }
            }
            // Black espacial: a little star dust on the card's corner, above the controls.
            .overlay(alignment: .topTrailing) { if palette.isSpace { GingaStardust().offset(x: -18, y: -14) } }
            .shadow(color: palette.isDark ? .clear : Color(red: 0.078, green: 0.094, blue: 0.188).opacity(0.06), radius: 12, y: 8)
    }
}

/// The divider between rows, inset `space-4`.
struct GingaDivider: View {
    @Environment(\.ginga) private var palette

    var body: some View {
        Rectangle().fill(palette.line).frame(height: 1).padding(.leading, GingaSpace.s4)
    }
}

/// A row: optional icon, label with subtitle, and a trailing control or value.
struct GingaRow<Trailing: View>: View {
    @Environment(\.ginga) private var palette
    var icon: String?
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: GingaSpace.s3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.cobalt)
                    .frame(width: 28, height: 28)
                    .background(palette.cobaltSoft, in: RoundedRectangle(cornerRadius: GingaRadius.sm, style: .continuous))
                    .overlay {
                        if palette.isSpace { RoundedRectangle(cornerRadius: GingaRadius.sm, style: .continuous).strokeBorder(palette.line, lineWidth: 1) }
                    }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: 48)
        .padding(.horizontal, GingaSpace.s4)
        .padding(.vertical, GingaSpace.s2)
        .accessibilityElement(children: .combine)
    }
}

extension GingaRow where Trailing == EmptyView {
    init(icon: String? = nil, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A value on the right of a row; numbers and specs in mono.
struct GingaValue: View {
    @Environment(\.ginga) private var palette
    let text: String
    var mono = false

    var body: some View {
        Text(text)
            .font(mono ? .gingaMono(12) : .system(size: 13))
            .foregroundStyle(palette.inkMuted)
            .multilineTextAlignment(.trailing)
    }
}

/// Small stars in the corner of a group: the Black espacial detail.
struct GingaStardust: View {
    @Environment(\.ginga) private var palette

    var body: some View {
        Canvas { context, _ in
            for (x, y, r, a) in [(4.0, 3.0, 0.9, 0.9), (13.0, 9.0, 0.6, 0.5), (22.0, 2.0, 0.7, 0.7), (18.0, 15.0, 0.5, 0.35)] {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(palette.stardust.opacity(a)))
            }
            context.fill(GingaStar.path(center: CGPoint(x: 8, y: 13), radius: 2.2), with: .color(palette.star.opacity(0.8)))
        }
        .frame(width: 26, height: 18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Switch

/// Toggle for options that take effect at once. Turning it on throws the seven-dot spark.
struct GingaSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        GingaSwitch(isOn: configuration.$isOn, label: configuration.label)
    }
}

private struct GingaSwitch<Label: View>: View {
    @Environment(\.ginga) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isOn: Bool
    let label: Label
    @State private var sparks = 0
    @State private var pressed = false

    var body: some View {
        HStack {
            label
            Spacer(minLength: GingaSpace.s3)
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? palette.cobalt : palette.surface2)
                    .overlay { if !isOn { Capsule().strokeBorder(palette.line, lineWidth: 1) } }
                    .shadow(color: isOn && palette.isSpace ? palette.cobalt.opacity(0.35) : .clear, radius: 6)
                Capsule()
                    .fill(.white)
                    .frame(width: pressed ? 24 : 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .padding(3)
            }
            .frame(width: 44, height: 26)
            .overlay { GingaSpark(trigger: sparks) }
            .contentShape(Capsule())
            .onTapGesture { toggle() }
            .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityElement()
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? tr("Ligado", "On") : tr("Desligado", "Off"))
            .accessibilityAction { toggle() }
        }
    }

    private func toggle() {
        guard isEnabled else { return }
        withAnimation(reduceMotion ? nil : GingaMotion.ginga) { isOn.toggle() }
        if isOn, !reduceMotion { sparks += 1 }
    }
}

/// Seven `star` dots leaving the center (Ginga.spark), only when something is turned on or confirmed.
struct GingaSpark: View {
    @Environment(\.ginga) private var palette
    let trigger: Int
    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                let angle = Double(index) / 7 * 2 * .pi - .pi / 2
                Circle()
                    .fill(palette.star)
                    .frame(width: 5, height: 5)
                    .shadow(color: palette.star.opacity(0.7), radius: 6)
                    .scaleEffect(1 - 0.8 * progress)
                    .offset(x: cos(angle) * 22 * progress, y: sin(angle) * 22 * progress)
                    .opacity(1 - progress)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            progress = 0
            withAnimation(GingaMotion.easeOut.speed(0.22 / 0.52)) { progress = 1 }
        }
    }
}

// MARK: Button

struct GingaButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    var kind: Kind = .secondary
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        GingaButtonBody(configuration: configuration, kind: kind, small: small)
    }
}

private struct GingaButtonBody: View {
    @Environment(\.ginga) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let configuration: ButtonStyleConfiguration
    let kind: GingaButtonStyle.Kind
    let small: Bool
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: small ? GingaRadius.sm : GingaRadius.md, style: .continuous)
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, small ? GingaSpace.s3 : GingaSpace.s4)
            .frame(height: small ? 28 : 36)
            .background(background, in: shape)
            .overlay {
                if kind == .danger || (palette.isSpace && kind != .ghost && kind != .primary) {
                    shape.strokeBorder(palette.line, lineWidth: 1)
                }
            }
            .shadow(color: kind == .primary && (hovering || palette.isSpace) && isEnabled ? palette.cobalt.opacity(0.35) : .clear, radius: 8)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: GingaMotion.tap), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: palette.onCobalt
        case .secondary: palette.ink
        case .ghost: palette.cobalt
        case .danger: palette.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: palette.cobalt
        case .secondary: palette.surface2
        case .ghost: hovering && isEnabled ? palette.cobaltSoft : .clear
        case .danger: .clear
        }
    }
}

// MARK: StatusOrbit

/// The connection state as a pill: a colored "planet" with an orbit, and the state in words.
struct StatusOrbit: View {
    enum State: Equatable { case off, searching, pairing, connected, paused, error }

    @Environment(\.ginga) private var palette
    @Environment(\.gingaAnimates) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: State
    let text: String
    @SwiftUI.State private var phase = false

    var body: some View {
        HStack(spacing: GingaSpace.s2) {
            ZStack {
                Circle().fill(color).frame(width: 6, height: 6)
                orbit
            }
            .frame(width: 14, height: 14)
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.leading, GingaSpace.s2)
        .padding(.trailing, GingaSpace.s3)
        .frame(height: 28)
        .background(palette.surface2, in: Capsule())
        .overlay { if palette.isSpace { Capsule().strokeBorder(palette.line, lineWidth: 1) } }
        .shadow(color: palette.isSpace && state == .connected ? palette.success.opacity(0.25) : .clear, radius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear { restart() }
        .onChange(of: state) { restart() }
        .onChange(of: moving) { restart() }
    }

    private var moving: Bool { animates && !reduceMotion && [.searching, .pairing, .connected].contains(state) }

    @ViewBuilder private var orbit: some View {
        switch state {
        case .searching:
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(phase ? 360 : 0))
        case .pairing, .connected:
            Circle()
                .stroke(color, lineWidth: 1.5)
                .scaleEffect(moving ? (phase ? 1.7 : 0.6) : 1)
                .opacity(moving ? (phase ? 0 : 0.7) : 0.6)
        default:
            EmptyView()
        }
    }

    private func restart() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { phase = false }
        guard moving else { return }
        let duration: Double = switch state {
        case .searching: 1.1
        case .pairing: 1.6
        default: 2.4
        }
        let curve: Animation = state == .searching ? .linear(duration: duration) : .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
        DispatchQueue.main.async { withAnimation(curve.repeatForever(autoreverses: false)) { phase = true } }
    }

    private var color: Color {
        switch state {
        case .off: palette.inkMuted
        case .searching: palette.cobalt
        case .pairing, .paused: palette.warning
        case .connected: palette.success
        case .error: palette.danger
        }
    }
}

// MARK: DeviceRow

/// A device: the brand's tilted tablet with its star, a friendly name, a mono meta line, an action.
struct GingaDeviceRow<Action: View>: View {
    @Environment(\.ginga) private var palette
    let name: String
    let meta: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: GingaSpace.s3) {
            Canvas { context, _ in
                var tablet = context
                tablet.translateBy(x: 20, y: 14)
                tablet.rotate(by: .degrees(-8))
                tablet.fill(Path(roundedRect: CGRect(x: -16, y: -10, width: 32, height: 22), cornerRadius: 5), with: .color(palette.cobaltBrand))
                context.fill(GingaStar.path(center: CGPoint(x: 36, y: 2), radius: 4), with: .color(palette.star))
            }
            .frame(width: 40, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(meta).font(.gingaMono(11)).foregroundStyle(palette.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(.horizontal, GingaSpace.s4)
        .padding(.vertical, GingaSpace.s3)
        .accessibilityElement(children: .combine)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
    }
}

// MARK: Segmented

/// Two to four short choices, all visible; the thumb slides with ease-ginga.
struct GingaSegmented<Value: Hashable>: View {
    @Environment(\.ginga) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Text(option.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(selected ? palette.ink : palette.inkMuted)
                    .padding(.horizontal, GingaSpace.s3)
                    .frame(height: 26)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.isSpace ? palette.cobaltSoft : palette.surface)
                                .shadow(color: palette.isDark ? .clear : .black.opacity(0.08), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : GingaMotion.ginga) { selection = option.value }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(palette.surface2, in: RoundedRectangle(cornerRadius: GingaRadius.md, style: .continuous))
        .overlay { if palette.isSpace { RoundedRectangle(cornerRadius: GingaRadius.md, style: .continuous).strokeBorder(palette.line, lineWidth: 1) } }
        .fixedSize()
    }
}

// MARK: PairingCode

/// The six digits, two groups of three, appearing one by one like stars.
struct GingaPairingCode: View {
    @Environment(\.ginga) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let code: String
    @State private var shown = false

    var body: some View {
        let digits = Array(code)
        HStack(spacing: GingaSpace.s4) {
            ForEach([0, 3], id: \.self) { start in
                HStack(spacing: 2) {
                    ForEach(start..<min(start + 3, digits.count), id: \.self) { index in
                        Text(String(digits[index]))
                            .font(.gingaMono(36, medium: true))
                            .scaleEffect(shown ? 1 : 0.6)
                            .opacity(shown ? 1 : 0)
                            .animation(reduceMotion ? nil : GingaMotion.sheet.delay(Double(index) * 0.06), value: shown)
                    }
                }
            }
        }
        .shadow(color: palette.isSpace ? palette.cobalt.opacity(0.35) : .clear, radius: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Código ", "Code ") + digits.map(String.init).joined(separator: " "))
        .onAppear { shown = true }
    }
}

// MARK: Comet

/// On connecting: a `star` comet with a tail crosses from left to right in `dur-warp` and ends
/// in a ring (flows.md step 4). One shot, only when the window is visible and motion allowed.
struct GingaComet: View {
    @Environment(\.ginga) private var palette
    @Environment(\.gingaAnimates) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Int
    @State private var progress: CGFloat = 1
    @State private var ring: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = width * progress
            let y = geometry.size.height / 2
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [palette.star.opacity(0), palette.star.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 90, height: 3)
                    .position(x: x - 45, y: y)
                GingaStarShape().fill(palette.star).frame(width: 12, height: 12).position(x: x, y: y)
                    .shadow(color: palette.star.opacity(0.7), radius: 6)
                Circle().stroke(palette.star, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .scaleEffect(1 + 2 * ring)
                    .opacity(ring < 1 ? 1 - ring : 0)
                    .position(x: width, y: y)
            }
            .opacity(progress < 1 || ring < 1 ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard animates, !reduceMotion else { return }
            progress = 0
            ring = 1
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: GingaMotion.warp)) { progress = 1 } completion: {
                ring = 0
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42)) { ring = 1 }
            }
        }
    }
}

struct GingaStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        GingaStar.path(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2)
    }
}
