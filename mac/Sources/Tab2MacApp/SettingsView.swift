import SwiftUI
import Tab2MacCore
import Tab2MacSession
import VirtualDisplay

/// Ajustes (flows.md): Display · Toque e S Pen · Captura · Energia · Aparência · Avançado.
/// Toggles and input settings apply at once; the display's shape waits for "Aplicar" because it
/// reconfigures the display.
struct SettingsView: View {
    @Bindable var model: AppModel
    let showPreview: () -> Void
    @Environment(\.ginga) private var palette
    @AppStorage(GingaAppearance.storageKey) private var appearance: GingaAppearance = .system
    @AppStorage(GingaLanguage.storageKey) private var language: GingaLanguage = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GingaSpace.s6) {
                Text(tr("Ajustes", "Settings")).font(.gingaDisplay(20)).accessibilityAddTraits(.isHeader)
                display
                input
                capture
                power
                appearanceGroup
                advanced
            }
            .padding(GingaSpace.s8)
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 600)
    }

    // MARK: Display

    private var display: some View {
        section(tr("Display", "Display")) {
            GingaRow(icon: "ipad.landscape", title: tr("Aparelho", "Device"), subtitle: panelLine) {
                Picker("", selection: Binding(get: { model.draft.display.profileID ?? "" }, set: { model.selectProfile($0) })) {
                    ForEach(DeviceProfile.all) { profile in Text(profile.displayName).tag(profile.id) }
                    if model.profile == nil { Text(tr("Personalizado", "Custom")).tag("") }
                }
                .labelsHidden().fixedSize()
            }
            GingaDivider()
            GingaRow(icon: "rectangle.expand.vertical", title: tr("Resolução", "Resolution")) {
                Picker("", selection: $model.draft.display.resolution) {
                    ForEach(resolutionChoices, id: \.self) { size in Text(resolutionLabel(size)).tag(size) }
                }
                .labelsHidden().fixedSize()
            }
            GingaDivider()
            GingaRow(icon: "sparkles.rectangle.stack", title: "HiDPI (Retina)") {
                Toggle("", isOn: $model.draft.display.hiDPI).toggleStyle(GingaSwitchStyle()).labelsHidden()
            }
            GingaDivider()
            GingaRow(icon: "speedometer", title: tr("Taxa de atualização", "Refresh rate"), subtitle: tr("60 Hz gasta cerca de um terço da energia de 120 Hz.", "60 Hz uses about a third of the power of 120 Hz.")) {
                GingaSegmented(selection: $model.draft.display.refreshRate, options: refreshChoices.map { ($0, "\(Int($0)) Hz") })
            }
            if model.draft.display.refreshRate > 60 {
                GingaDivider()
                GingaRow(icon: "battery.50", title: tr("60 Hz na bateria", "60 Hz on battery")) {
                    Toggle("", isOn: Binding(
                        get: { model.draft.power.batteryRefreshRate != nil },
                        set: { model.draft.power.batteryRefreshRate = $0 ? 60 : nil }
                    ))
                    .toggleStyle(GingaSwitchStyle()).labelsHidden()
                }
            }
            GingaDivider()
            GingaRow(icon: "rotate.right", title: tr("Orientação", "Orientation")) {
                GingaSegmented(selection: $model.draft.display.orientation, options: [
                    (.landscape, tr("Paisagem", "Landscape")), (.portrait, tr("Retrato", "Portrait")),
                ])
            }
            GingaDivider()
            GingaRow(icon: "rectangle.split.2x1", title: tr("Posição", "Position")) {
                Picker("", selection: $model.draft.display.arrangement.placement) {
                    Text(tr("Automática", "Automatic")).tag(DisplayArrangement.Placement.automatic)
                    Text(tr("À esquerda", "Left")).tag(DisplayArrangement.Placement.left)
                    Text(tr("À direita", "Right")).tag(DisplayArrangement.Placement.right)
                    Text(tr("Acima", "Above")).tag(DisplayArrangement.Placement.above)
                    Text(tr("Abaixo", "Below")).tag(DisplayArrangement.Placement.below)
                }
                .labelsHidden().fixedSize()
            }
            if model.draft.display.arrangement.placement != .automatic {
                GingaDivider()
                GingaRow(icon: "align.horizontal.center", title: tr("Alinhamento", "Alignment")) {
                    GingaSegmented(selection: $model.draft.display.arrangement.alignment, options: [
                        (.start, tr("Início", "Start")), (.center, tr("Centro", "Center")), (.end, tr("Fim", "End")),
                    ])
                }
            }
        } footer: {
            if model.hasPendingChanges {
                HStack {
                    Text(tr("Alterações no display valem ao aplicar.", "Display changes take effect when applied."))
                        .font(.system(size: 11)).foregroundStyle(palette.inkMuted)
                    Spacer()
                    Button(tr("Reverter", "Revert")) { model.revertChanges() }.buttonStyle(GingaButtonStyle(kind: .ghost, small: true))
                    Button(tr("Aplicar", "Apply")) { Task { await model.applyChanges() } }.buttonStyle(GingaButtonStyle(kind: .primary, small: true))
                }
                .disabled(model.isBusy)
            }
        }
    }

    private var panelLine: String {
        let panel = model.draft.display.panel
        return "\(panel.nativePixels.width)×\(panel.nativePixels.height) · \(tr("até", "up to")) \(Int(panel.maxRefreshRate)) Hz"
    }

    // MARK: Toque e S Pen

    private var input: some View {
        section(tr("Toque e S Pen", "Touch and S Pen")) {
            GingaRow(icon: "hand.tap", title: tr("Um dedo", "One finger")) {
                GingaSegmented(selection: Binding(get: { model.inputSettings.touch }, set: { value in model.setInput { $0.touch = value } }), options: [
                    (.pointer, tr("Aponta e clica", "Points and clicks")), (.gestures, tr("Só rola", "Only scrolls")),
                ])
            }
            GingaDivider()
            GingaRow(icon: "command", title: tr("⌘ no teclado do tablet", "⌘ on the tablet's keyboard")) {
                GingaSegmented(selection: Binding(get: { model.inputSettings.commandKey }, set: { value in model.setInput { $0.commandKey = value } }), options: [
                    (.meta, tr("Tecla Samsung", "Samsung key")), (.control, "Ctrl"),
                ])
            }
            GingaDivider()
            GingaRow(icon: "hand.point.up.left", title: tr("Acessibilidade", "Accessibility"), subtitle: tr("Deixa o tablet controlar o Mac.", "Lets the tablet control the Mac.")) {
                if model.inputPermissionGranted {
                    GingaValue(text: tr("Permitida", "Allowed"))
                } else {
                    Button(tr("Permitir…", "Allow…")) { model.requestInputPermission() }.buttonStyle(GingaButtonStyle(small: true))
                }
            }
        }
    }

    // MARK: Captura, Energia

    private var capture: some View {
        section(tr("Captura", "Capture")) {
            GingaRow(icon: "cursorarrow", title: tr("Cursor dentro do vídeo", "Cursor inside the video"), subtitle: tr("Desligado: o tablet desenha o cursor (menos quadros enviados).", "Off: the tablet draws the pointer (fewer frames sent).")) {
                Toggle("", isOn: $model.draft.capture.showsCursor).toggleStyle(GingaSwitchStyle()).labelsHidden()
            }
            GingaDivider()
            GingaRow(icon: "arrow.down.right.and.arrow.up.left", title: tr("Reduzir à resolução do tablet", "Downscale to the tablet's resolution")) {
                Toggle("", isOn: $model.draft.capture.limitToPanelResolution).toggleStyle(GingaSwitchStyle()).labelsHidden()
            }
        }
    }

    private var power: some View {
        section(tr("Energia", "Power")) {
            GingaRow(icon: "bolt", title: tr("Codificador de vídeo", "Video encoder"), subtitle: tr("Nada é capturado nem enviado com a tela parada ou o tablet sem mostrar.", "Nothing is captured or sent while the screen is still or the tablet isn't showing it.")) {
                Picker("", selection: $model.draft.streaming.encoderPower) {
                    Text(tr("Automático", "Automatic")).tag(EncoderPowerPolicy.automatic)
                    Text(tr("Menor latência", "Lowest latency")).tag(EncoderPowerPolicy.lowestLatency)
                    Text(tr("Menor consumo", "Lowest power")).tag(EncoderPowerPolicy.lowestPower)
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    // MARK: Aparência

    private var appearanceGroup: some View {
        section(tr("Aparência", "Appearance")) {
            GingaRow(icon: "circle.lefthalf.filled", title: tr("Tema", "Theme"), subtitle: appearance == .space ? tr("Preto puro para telas OLED e mini‑LED.", "Pure black for OLED and mini‑LED screens.") : nil) {
                GingaSegmented(selection: $appearance, options: GingaAppearance.allCases.map { ($0, $0.localizedLabel) })
            }
            GingaDivider()
            GingaRow(icon: "globe", title: tr("Idioma", "Language")) {
                GingaSegmented(selection: $language, options: GingaLanguage.allCases.map { ($0, $0.label) })
            }
        }
    }

    // MARK: Avançado

    private var advanced: some View {
        section(tr("Avançado", "Advanced")) {
            GingaRow(icon: "terminal", title: tr("Aceitar tablet por adb", "Accept a tablet over adb"), subtitle: model.isStreamingEnabled ? model.tabletStatus : tr("Precisa da depuração USB no tablet.", "Needs USB debugging on the tablet.")) {
                Toggle("", isOn: Binding(get: { model.isStreamingEnabled }, set: { model.setStreaming($0) })).toggleStyle(GingaSwitchStyle()).labelsHidden()
            }
            GingaDivider()
            GingaRow(icon: "waveform.path", title: tr("Padrão de teste no tablet", "Test pattern on the tablet")) {
                Toggle("", isOn: Binding(get: { model.wantsTestPattern }, set: { model.setTestPattern($0) })).toggleStyle(GingaSwitchStyle()).labelsHidden()
            }
            GingaDivider()
            GingaRow(icon: "eye", title: tr("Prévia de debug", "Debug preview")) {
                Button(tr("Mostrar", "Show"), action: showPreview).buttonStyle(GingaButtonStyle(small: true)).disabled(model.active == nil)
            }
            GingaDivider()
            GingaRow(icon: "macwindow.on.rectangle", title: tr("Janela no tablet", "Window on the tablet")) {
                Button(model.isControlPanelOnVirtualDisplay ? tr("Trazer de volta", "Move back") : tr("Mover", "Move")) { model.toggleControlPanelPlacement() }
                    .buttonStyle(GingaButtonStyle(small: true)).disabled(model.active == nil)
            }
            GingaDivider()
            GingaRow(icon: "display.2", title: tr("Ajustes de Telas do macOS", "macOS Displays settings")) {
                Button(tr("Abrir…", "Open…")) { model.openDisplaysSettings() }.buttonStyle(GingaButtonStyle(kind: .ghost, small: true))
            }
            if !model.savesSettings {
                GingaDivider()
                GingaRow(icon: "doc.badge.gearshape", title: tr("Ajustes de --config", "Settings from --config"), subtitle: tr("Valem só nesta execução e não são salvos.", "They apply to this run only and aren't saved."))
            }
        }
    }

    // MARK: Helpers

    private func section<Content: View, Footer: View>(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: GingaSpace.s2) {
            GingaGroupTitle(text: title)
            GingaGroup { content() }
            footer()
        }
    }

    private var resolutionChoices: [PointSize] {
        var sizes = model.profile?.resolutionOptions ?? model.draft.display.extraResolutions
        if !sizes.contains(model.draft.display.resolution) { sizes.append(model.draft.display.resolution) }
        return sizes
    }

    private var refreshChoices: [Double] {
        var rates = model.profile?.refreshRates ?? [60]
        if !rates.contains(model.draft.display.refreshRate) { rates.append(model.draft.display.refreshRate) }
        return rates.sorted()
    }

    private func resolutionLabel(_ size: PointSize) -> String {
        let panel = model.draft.display.panel.nativePixels
        let pixels = size.pixels(scale: model.draft.display.hiDPI ? 2 : 1)
        let note: String
        if pixels == panel {
            note = tr("nítido", "pixel-exact")
        } else if pixels.width > panel.width {
            note = tr("mais espaço", "more space")
        } else {
            note = tr("texto maior", "larger text")
        }
        return "\(size.width)×\(size.height) · \(note)"
    }
}
