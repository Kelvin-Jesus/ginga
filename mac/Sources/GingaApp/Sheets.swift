import DirectLink
import SwiftUI
import GingaStreaming

/// Pairing (flows.md "Pareamento"): a sheet on the window, not a loose alert. The tablet shows
/// the same code; the question closes by itself if the tablet leaves or times out.
struct PairingSheet: View {
    let request: PairingRequest
    @Environment(\.ginga) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparks = 0

    var body: some View {
        VStack(spacing: GingaSpace.s4) {
            GingaAppIcon().frame(width: 56, height: 56)
            Text(tr("Parear com \(request.tabletName)?", "Pair with \(request.tabletName)?"))
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(tr("O tablet mostra o mesmo código? Pareie só tablets seus.", "Does the tablet show the same code? Only pair tablets you own."))
                .font(.system(size: 13))
                .foregroundStyle(palette.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GingaPairingCode(code: request.code).padding(.vertical, GingaSpace.s2)
            HStack(spacing: GingaSpace.s3) {
                Button(tr("Não parear", "Don’t pair")) { answer(false) }
                    .buttonStyle(GingaButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(tr("Parear", "Pair")) { answer(true) }
                    .buttonStyle(GingaButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .overlay { GingaSpark(trigger: sparks) }
            }
        }
        .padding(GingaSpace.s8)
        .frame(width: 380)
        .background(alignment: .top) {
            GingaDitherScene(scene: .blackHole).frame(height: 120).opacity(0.7)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .center, endPoint: .bottom))
        }
        .background(palette.bg)
    }

    private func answer(_ accepted: Bool) {
        guard !request.isEnded else { return dismiss() }
        if accepted, !reduceMotion {
            sparks += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { request.respond(true) }
        } else {
            request.respond(accepted)
        }
    }
}

/// Mark A on its cobalt tile: the app icon (design/brand/ginga-app-icon.svg).
struct GingaAppIcon: View {
    @Environment(\.ginga) private var palette

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 1024
            context.scaleBy(x: s, y: s)
            context.fill(Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185), with: .color(palette.cobaltBrand))
            context.translateBy(x: 512, y: 512)
            context.scaleBy(x: 5.4, y: 5.4)
            context.translateBy(x: -58.8, y: -53.6)
            GingaOrbitMark.draw(in: &context, outline: .white, tablet: .white, star: Color(red: 1, green: 0.769, blue: 0.239))
        }
        .accessibilityHidden(true)
    }
}

/// No router (flows.md, Conexão): explains that the Mac leaves its Wi‑Fi, then connects only on
/// the button (the user's explicit action; CLAUDE.md "Never do").
struct DirectSheet: View {
    @Bindable var model: AppModel
    @Environment(\.ginga) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: GingaSpace.s4) {
            HStack(spacing: GingaSpace.s3) {
                GingaOrbitMark().frame(width: 36, height: 36)
                Text(tr("Sem roteador", "No router")).font(.system(size: 17, weight: .semibold))
            }
            Text(tr(
                "Para hotel, trem ou sem internet: o tablet cria a própria rede Wi‑Fi e o Mac entra nela. Enquanto isso, o Mac sai da rede Wi‑Fi atual e fica sem internet pelo Wi‑Fi (a não ser que tenha cabo de rede). Ele volta para a sua rede quando você encerrar ou quando o tablet sair.",
                "For a hotel, a train or no internet: the tablet creates its own Wi‑Fi network and the Mac joins it. Meanwhile the Mac leaves its current Wi‑Fi network and has no internet over Wi‑Fi (unless it also has Ethernet). It returns to your network when you end, or when the tablet leaves."
            ))
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
            Text(tr(
                "Antes: conecte o tablet uma vez por USB ou Wi‑Fi (ele recebe a chave) e toque em “Sem roteador” no tablet.",
                "First: connect the tablet once by USB or Wi‑Fi (it receives its key), then tap “No router” on the tablet."
            ))
            .font(.system(size: 12))
            .foregroundStyle(palette.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                StatusOrbit(state: state, text: model.isDirectActive || isFailed ? model.directStatus : tr("Desligado", "Off"))
                Spacer()
            }
            HStack(spacing: GingaSpace.s3) {
                Button(tr("Fechar", "Close")) { dismiss() }
                    .buttonStyle(GingaButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.isDirectActive {
                    Button(tr("Encerrar", "End")) { model.endDirect() }
                        .buttonStyle(GingaButtonStyle(kind: .danger))
                } else {
                    Button(tr("Conectar direto ao tablet", "Connect directly to the tablet")) { model.connectDirectly() }
                        .buttonStyle(GingaButtonStyle(kind: .primary))
                }
            }
        }
        .padding(GingaSpace.s6)
        .frame(width: 440)
        .background(alignment: .topTrailing) {
            // The galaxy (DitherSpace: no-router), only in the title's band: the text stays on plain black.
            GingaDitherScene(scene: .galaxy).frame(width: 220, height: 96).opacity(0.85)
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .background(palette.bg)
    }

    private var isFailed: Bool {
        if case .failed = model.directState { return true }
        return false
    }

    private var state: StatusOrbit.State {
        switch model.directState {
        case .idle: .off
        case .connected: .connected
        case .failed: .error
        case .waitingForTablet: .pairing
        default: .searching
        }
    }
}
