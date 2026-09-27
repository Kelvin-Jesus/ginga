import DirectLink
import SwiftUI
import Tab2MacStreaming

/// The main window (design/ginga-design/flows.md, "Janela principal"): the state first, then
/// Conexão, Tablets, one primary action, and Diagnóstico collapsed. Configuring lives in Ajustes.
struct MainWindowView: View {
    @Bindable var model: AppModel
    let showSettings: () -> Void
    @Environment(\.ginga) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDirectSheet = false
    @State private var primarySparks = 0
    @State private var comets = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GingaSpace.s6) {
                header
                if let problem = model.problem { problemBanner(problem) }
                permissions
                connection
                tablets
                actions
                diagnostics
            }
            .padding(GingaSpace.s8)
        }
        // Black espacial: the dithered galaxy in the window's empty bottom-right corner, behind
        // the scrolling content (never behind text); nothing in the other themes.
        .background(alignment: .bottomTrailing) {
            GingaDitherScene(scene: .galaxy, framesPerSecond: 12)
                .frame(width: 260, height: 170)
                .opacity(0.9)
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 560)
        .sheet(isPresented: $showsDirectSheet) { DirectSheet(model: model) }
        .sheet(item: $model.pairingRequest) { request in PairingSheet(request: request) }
    }

    // MARK: Header

    private var header: some View {
        let status = model.connectionState
        return HStack(spacing: GingaSpace.s3) {
            GingaMonogram().frame(width: 34, height: 34)
            Text("Ginga")
                .font(.gingaDisplay(22))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: GingaSpace.s3)
            StatusOrbit(state: status.state, text: status.text)
        }
        .overlay { GingaComet(trigger: comets).padding(.horizontal, 34) }
        .onChange(of: status.state) { old, new in
            if new == .connected, old != .paused { comets += 1 }
        }
    }

    private func problemBanner(_ problem: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GingaSpace.s2) {
            Circle().fill(palette.danger).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(problem).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(tr("Dispensar", "Dismiss")) { model.report(nil) }
                .buttonStyle(GingaButtonStyle(kind: .ghost, small: true))
        }
        .padding(GingaSpace.s3)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: GingaRadius.md, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: GingaRadius.md, style: .continuous).strokeBorder(palette.line) }
    }

    // MARK: Permissions (only when missing)

    @ViewBuilder private var permissions: some View {
        if !model.screenRecordingGranted || !model.inputPermissionGranted {
            VStack(alignment: .leading, spacing: GingaSpace.s2) {
                GingaGroupTitle(text: tr("Permissões", "Permissions"))
                GingaGroup {
                    if !model.screenRecordingGranted {
                        GingaRow(icon: "record.circle", title: tr("Gravação de tela", "Screen Recording"), subtitle: tr("Para enviar a imagem ao tablet.", "To send the picture to the tablet.")) {
                            Button(tr("Permitir…", "Allow…")) { model.requestScreenRecording() }.buttonStyle(GingaButtonStyle(small: true))
                        }
                    }
                    if !model.screenRecordingGranted && !model.inputPermissionGranted { GingaDivider() }
                    if !model.inputPermissionGranted {
                        GingaRow(icon: "hand.point.up.left", title: tr("Acessibilidade", "Accessibility"), subtitle: tr("Para o toque, a S Pen e o teclado do tablet controlarem o Mac.", "So the tablet's touch, S Pen and keyboard control the Mac.")) {
                            Button(tr("Permitir…", "Allow…")) { model.requestInputPermission() }.buttonStyle(GingaButtonStyle(small: true))
                        }
                    }
                }
            }
        }
    }

    // MARK: Conexão

    private var connection: some View {
        VStack(alignment: .leading, spacing: GingaSpace.s2) {
            GingaGroupTitle(text: tr("Conexão", "Connection"))
            GingaGroup {
                GingaRow(icon: "wifi", title: tr("Aceitar tablets por Wi‑Fi", "Accept tablets over Wi‑Fi")) {
                    Toggle("", isOn: Binding(get: { model.wifiEnabled }, set: { model.setWiFi($0) }))
                        .toggleStyle(GingaSwitchStyle()).labelsHidden()
                }
                GingaDivider()
                GingaRow(icon: "cable.connector", title: tr("Aceitar tablet por USB", "Accept a tablet over USB"), subtitle: tr("Sem modo desenvolvedor", "No developer mode")) {
                    Toggle("", isOn: Binding(get: { model.directUSBEnabled }, set: { model.setDirectUSB($0) }))
                        .toggleStyle(GingaSwitchStyle()).labelsHidden()
                }
                GingaDivider()
                Button { showsDirectSheet = true } label: {
                    GingaRow(icon: "antenna.radiowaves.left.and.right", title: tr("Sem roteador", "No router"), subtitle: model.isDirectActive ? model.directStatus : tr("Conectar direto à rede do tablet", "Connect straight to the tablet's network")) {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.inkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Tablets

    private var tablets: some View {
        VStack(alignment: .leading, spacing: GingaSpace.s2) {
            GingaGroupTitle(text: tr("Tablets", "Tablets"))
            GingaGroup {
                let items = model.tablets
                if items.isEmpty {
                    Text(tr("Nenhum tablet pareado ainda.", "No tablets paired yet."))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.inkMuted)
                        .padding(GingaSpace.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { GingaDivider() }
                    GingaDeviceRow(name: item.name, meta: item.meta) {
                        switch item.action {
                        case .approveUSB:
                            Button(tr("Usar este tablet", "Use this tablet")) { model.perform(item.action) }
                                .buttonStyle(GingaButtonStyle(kind: .primary, small: true))
                        case .forget, .revokeUSB:
                            Button(tr("Esquecer", "Forget")) { model.perform(item.action) }
                                .buttonStyle(GingaButtonStyle(kind: .danger, small: true))
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : GingaMotion.sheet, value: model.tablets.map(\.id))
        }
    }

    // MARK: Ações

    private var actions: some View {
        HStack(spacing: GingaSpace.s3) {
            if model.active == nil {
                Button {
                    if !reduceMotion { primarySparks += 1 }
                    Task { await model.createDisplay() }
                } label: {
                    HStack(spacing: GingaSpace.s2) {
                        Canvas { context, size in
                            context.fill(GingaStar.path(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: 5), with: .color(palette.onCobalt))
                        }
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                        Text(tr("Criar display", "Create display"))
                    }
                }
                .buttonStyle(GingaButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .overlay { GingaSpark(trigger: primarySparks) }
            } else {
                Button(tr("Remover display", "Remove display")) { Task { await model.removeDisplay() } }
                    .buttonStyle(GingaButtonStyle(kind: .danger))
            }
            Button(tr("Ajustes…", "Settings…"), action: showSettings)
                .buttonStyle(GingaButtonStyle(kind: .ghost))
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
        }
        .disabled(model.isBusy)
    }

    // MARK: Diagnóstico

    private var diagnostics: some View {
        DisclosureGroup(isExpanded: Binding(get: { model.diagnosticsExpanded }, set: { model.diagnosticsExpanded = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.overlayLines, id: \.self) { Text($0) }
                if model.isStreamingEnabled {
                    Text(model.tabletStatus)
                }
            }
            .font(.gingaMono(11))
            .foregroundStyle(palette.inkMuted)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, GingaSpace.s2)
        } label: {
            Text(tr("Diagnóstico", "Diagnostics")).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.inkMuted)
        }
    }
}

extension PairingRequest: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
