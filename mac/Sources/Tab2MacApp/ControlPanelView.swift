import DirectLink
import SwiftUI
import Tab2MacCore
import Tab2MacSession
import VirtualDisplay

struct ControlPanelView: View {
    @Bindable var model: AppModel
    let showPreview: () -> Void

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Backend") {
                    Text(model.backendAvailability.isAvailable ? "Private CGVirtualDisplay (verified)" : model.backendAvailability.summary)
                        .foregroundStyle(model.backendAvailability.isAvailable ? Color.secondary : Color.red)
                }
                LabeledContent("Virtual display", value: model.displayStatus)
                LabeledContent("Capture", value: model.captureStatus)
                if !model.screenRecordingGranted {
                    LabeledContent("Screen Recording") {
                        Button("Grant…") { model.requestScreenRecording() }
                    }
                }
                if let error = model.lastError {
                    Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                }
                if !model.savesSettings {
                    Text("Settings come from --config: changes apply to this run and aren't saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tablet (USB)") {
                Toggle("Accept the tablet over USB", isOn: Binding(get: { model.isStreamingEnabled }, set: { model.setStreaming($0) }))
                LabeledContent("Connection", value: model.tabletStatus)
                if model.isStreamingEnabled {
                    ForEach(model.streamLines, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)) }
                }
                Toggle("Direct USB — no developer mode (recommended)", isOn: Binding(get: { model.directUSBEnabled }, set: { model.setDirectUSB($0) }))
                ForEach(model.usbCandidates, id: \.entryID) { device in
                    LabeledContent("\(device.name ?? "Android device") · \(device.serialNumber ?? "no serial")") {
                        if let serial = device.serialNumber {
                            if model.approvedUSBDevices.contains(serial) {
                                Button("Forget") { model.revokeUSBDevice(serial) }
                            } else {
                                Button("Use this tablet") { model.approveUSBDevice(serial) }
                            }
                        }
                    }
                }
                if model.directUSBEnabled {
                    Text("Approved tablets switch to USB accessory mode when plugged in; Android asks once to open Tab2Mac. No USB debugging or adb needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show an animated test pattern on the tablet display", isOn: Binding(get: { model.wantsTestPattern }, set: { model.setTestPattern($0) }))
                Picker("One finger", selection: Binding(get: { model.inputSettings.touch }, set: { value in model.setInput { $0.touch = value } })) {
                    Text("Points and clicks").tag(InputSettings.TouchMode.pointer)
                    Text("Only scrolls (like Sidecar; point with the S Pen)").tag(InputSettings.TouchMode.gestures)
                }
                Picker("⌘ on the tablet's keyboard", selection: Binding(get: { model.inputSettings.commandKey }, set: { value in model.setInput { $0.commandKey = value } })) {
                    Text("⊞ / Samsung key").tag(InputSettings.CommandKey.meta)
                    Text("Ctrl").tag(InputSettings.CommandKey.control)
                }
                if !model.inputPermissionGranted {
                    LabeledContent("Touch & S Pen control") {
                        Button("Grant…") { model.requestInputPermission() }
                    }
                }
            }

            Section("Tablet (Wi‑Fi, beta)") {
                Toggle("Accept paired tablets over Wi‑Fi", isOn: Binding(get: { model.wifiEnabled }, set: { model.setWiFi($0) }))
                if model.wifiEnabled {
                    LabeledContent("Status", value: model.wifiRunning ? "Advertising on the local network (port \(model.wifiPort.map(String.init) ?? "?"))" : "Starting…")
                    Text("Encrypted with TLS. A new tablet pairs by comparing a 6-digit code on both screens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.pairedTablets, id: \.fingerprint) { tablet in
                    LabeledContent(tablet.name) {
                        Button("Forget") { model.forgetTablet(tablet) }
                    }
                }
            }

            Section("No router (direct)") {
                Text("For a hotel, a train or no internet: the tablet creates its own Wi‑Fi network and the Mac joins it. While connected directly, this Mac is off its current Wi‑Fi network, so it has no internet over Wi‑Fi unless it also has Ethernet. It returns to your network when you end, or when the tablet leaves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Status", value: model.directStatus)
                HStack {
                    Button("Connect directly to the tablet") { model.connectDirectly() }
                        .disabled(model.directState != .idle && !isFailed(model.directState))
                    Button("End direct connection") { model.endDirect() }
                        .disabled(model.directState == .idle || isFailed(model.directState))
                }
                Text("First: connect the tablet once by USB or Wi‑Fi (it receives its key), then tap “Direct connection” on the tablet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Device") {
                Picker("Profile", selection: Binding(get: { model.draft.display.profileID ?? "" }, set: { model.selectProfile($0) })) {
                    ForEach(DeviceProfile.all) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                    if model.profile == nil { Text("Custom").tag("") }
                }
                LabeledContent("Panel", value: "\(model.draft.display.panel.nativePixels.width)×\(model.draft.display.panel.nativePixels.height) px, up to \(Int(model.draft.display.panel.maxRefreshRate)) Hz")
            }

            Section("Display") {
                Picker("Resolution", selection: $model.draft.display.resolution) {
                    ForEach(resolutionChoices, id: \.self) { size in
                        Text(resolutionLabel(size)).tag(size)
                    }
                }
                Toggle("HiDPI (Retina)", isOn: $model.draft.display.hiDPI)
                Picker("Refresh rate", selection: $model.draft.display.refreshRate) {
                    ForEach(refreshChoices, id: \.self) { rate in
                        Text(refreshLabel(rate)).tag(rate)
                    }
                }
                if model.draft.display.refreshRate > 60 {
                    Toggle("Use 60 Hz on battery", isOn: Binding(
                        get: { model.draft.power.batteryRefreshRate != nil },
                        set: { model.draft.power.batteryRefreshRate = $0 ? 60 : nil }
                    ))
                }
                Picker("Orientation", selection: $model.draft.display.orientation) {
                    Text("Landscape").tag(DisplayOrientation.landscape)
                    Text("Portrait").tag(DisplayOrientation.portrait)
                }
                .pickerStyle(.segmented)
                Picker("Position", selection: $model.draft.display.arrangement.placement) {
                    Text("Automatic (as arranged in System Settings)").tag(DisplayArrangement.Placement.automatic)
                    Text("Left of main display").tag(DisplayArrangement.Placement.left)
                    Text("Right of main display").tag(DisplayArrangement.Placement.right)
                    Text("Above main display").tag(DisplayArrangement.Placement.above)
                    Text("Below main display").tag(DisplayArrangement.Placement.below)
                }
                Picker("Alignment", selection: $model.draft.display.arrangement.alignment) {
                    Text("Start").tag(DisplayArrangement.Alignment.start)
                    Text("Center").tag(DisplayArrangement.Alignment.center)
                    Text("End").tag(DisplayArrangement.Alignment.end)
                }
                .disabled(model.draft.display.arrangement.placement == .automatic)
            }

            Section("Capture") {
                Toggle("Draw cursor into the stream", isOn: $model.draft.capture.showsCursor)
                Toggle("Downscale to the tablet's native resolution", isOn: $model.draft.capture.limitToPanelResolution)
            }

            Section("Power") {
                Picker("Video encoder", selection: $model.draft.streaming.encoderPower) {
                    Text("Automatic — lowest latency on power adapter, efficient on battery").tag(EncoderPowerPolicy.automatic)
                    Text("Lowest latency").tag(EncoderPowerPolicy.lowestLatency)
                    Text("Lowest power (≈40% less encoder power, +6 ms)").tag(EncoderPowerPolicy.lowestPower)
                }
                Text("60 Hz uses about a third of the power of 120 Hz for the same 60 fps stream. Nothing is captured or sent while the screen is still or the tablet isn't showing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if model.active == nil {
                        Button("Create Display") { Task { await model.createDisplay() } }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Remove Display") { Task { await model.removeDisplay() } }
                    }
                    Button("Apply Changes") { Task { await model.applyChanges() } }
                        .disabled(!model.hasPendingChanges)
                    Button("Revert") { model.revertChanges() }
                        .disabled(!model.hasPendingChanges)
                    Spacer()
                    if model.isBusy { ProgressView().controlSize(.small) }
                }
                .disabled(model.isBusy)
                HStack {
                    Button("Show Debug Preview", action: showPreview)
                        .disabled(model.active == nil)
                    Button(model.isControlPanelOnVirtualDisplay ? "Move This Window Back" : "Move This Window to the Tablet Display") {
                        model.toggleControlPanelPlacement()
                    }
                    .disabled(model.active == nil)
                    Button("Displays Settings…") { model.openDisplaysSettings() }
                }
            }

            Section("Diagnostics") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.overlayLines, id: \.self) { Text($0) }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 700)
    }

    private var resolutionChoices: [PointSize] {
        var sizes = model.profile?.resolutionOptions ?? model.draft.display.extraResolutions
        if !sizes.contains(model.draft.display.resolution) { sizes.append(model.draft.display.resolution) }
        return sizes
    }

    private var refreshChoices: [Double] {
        var rates = model.profile?.refreshRates ?? [60]
        if !rates.contains(model.draft.display.refreshRate) { rates.append(model.draft.display.refreshRate) }
        return rates
    }

    private func refreshLabel(_ rate: Double) -> String {
        switch rate {
        case 60: "60 Hz — efficient"
        case 120: "120 Hz — smoother, more power"
        default: "\(Int(rate)) Hz"
        }
    }

    private func resolutionLabel(_ size: PointSize) -> String {
        let panel = model.draft.display.panel.nativePixels
        let pixels = size.pixels(scale: model.draft.display.hiDPI ? 2 : 1)
        let note: String
        if pixels == panel {
            note = "pixel-exact"
        } else if pixels.width > panel.width {
            note = "more space, downsampled"
        } else {
            note = "larger text"
        }
        return "Looks like \(size.width) × \(size.height) (\(note))"
    }

    private func isFailed(_ state: DirectLinkSession.State) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
