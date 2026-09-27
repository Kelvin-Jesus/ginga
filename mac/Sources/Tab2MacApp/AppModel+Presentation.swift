import DirectLink
import Foundation
import Tab2MacSecurity
import Tab2MacStreaming
import VirtualDisplay

/// What the Ginga UI shows: one connection state, the tablets, in the brand's words.
extension AppModel {
    /// How a tablet reaches this Mac.
    enum Link: Equatable {
        case wifi, usb, adb

        var label: String {
            switch self {
            case .wifi: "Wi‑Fi"
            case .usb: tr("USB direto", "Direct USB")
            case .adb: "USB (adb)"
            }
        }

        /// From the connection's endpoint: `usb-accessory:…`, the loopback (adb reverse), or the network.
        init(endpoint: String) {
            if endpoint.hasPrefix("usb-accessory") {
                self = .usb
            } else if endpoint.hasPrefix("127.0.0.1") || endpoint.hasPrefix("[::1]") || endpoint.hasPrefix("localhost") {
                self = .adb
            } else {
                self = .wifi
            }
        }
    }

    /// The one StatusOrbit at the top of the window and in the menu bar.
    var connectionState: (state: StatusOrbit.State, text: String) {
        if let connection = streaming.connection {
            let name = Self.friendlyName(connection.clientModel)
            switch connection.phase {
            case .streaming where connection.isPaused:
                return (.paused, tr("Pausado: nada na tela do tablet", "Paused: nothing on the tablet's screen"))
            case .streaming:
                return (.connected, [tr("Conectado", "Connected"), refreshLabel, Link(endpoint: connection.endpoint).label].compactMap { $0 }.joined(separator: " · "))
            case .pairing:
                return (.pairing, tr("Aguardando código · \(name)", "Waiting for the code · \(name)"))
            case .awaitingHello, .preparing:
                return (.searching, tr("Conectando \(name)…", "Connecting \(name)…"))
            case .closed:
                break
            }
        }
        if let problem = problem { return (.error, problem) }
        switch directState {
        case .idle, .failed: break
        case .connected: return (.connected, tr("Conectado direto ao tablet", "Connected directly to the tablet"))
        default: return (.searching, directStatus)
        }
        if wifiEnabled && wifiRunning { return (.searching, tr("Anunciando na rede", "Advertising on the network")) }
        if directUSBEnabled || isStreamingEnabled { return (.searching, tr("Aguardando o cabo USB", "Waiting for the USB cable")) }
        return (.off, tr("Desligado", "Off"))
    }

    /// The cause in words, if something is wrong (details go to Diagnóstico).
    var problem: String? {
        if !backendAvailability.isAvailable { return tr("Este Mac não permite criar o display", "This Mac can't create the display") }
        if let displayFailure { return tr("O display falhou: \(displayFailure)", "The display failed: \(displayFailure)") }
        if let lastError { return lastError }
        return nil
    }

    /// "60 Hz", from the display's current mode.
    var refreshLabel: String? {
        guard let mode = active?.mode else { return nil }
        return "\(Int(mode.refreshRate.rounded())) Hz"
    }

    /// "Galaxy Tab S11" for "SM-X730"; the raw model when unknown.
    /// Also for stored names like "samsung SM-X730" (manufacturer and model).
    static func friendlyName(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return "tablet" }
        let candidates = [model, model.split(separator: " ").last.map(String.init) ?? model]
        for candidate in candidates {
            if let profile = DeviceProfile.matching(model: candidate) { return profile.displayName }
        }
        return model.replacingOccurrences(of: "_", with: "-")
    }

    struct TabletItem: Identifiable {
        enum Action { case forget(PairedTablet), revokeUSB(String), approveUSB(String) }
        let id: String
        let name: String
        let meta: String
        let action: Action
    }

    /// Paired (Wi‑Fi) and approved (USB) tablets, plus USB devices waiting for approval.
    var tablets: [TabletItem] {
        let connection = streaming.connection.flatMap { $0.phase == .streaming ? $0 : nil }
        let connectedName = connection.map { Self.friendlyName($0.clientModel) }
        let connectedLink = connection.map { Link(endpoint: $0.endpoint) }
        let size = connection?.streamSize.map { "\($0.width)×\($0.height)" }
        var items: [TabletItem] = pairedTablets.map { tablet in
            let name = Self.friendlyName(tablet.name)
            let online = connectedLink == .wifi && connectedName == name
            let meta = online ? ["Wi‑Fi · TLS", size].compactMap { $0 }.joined(separator: " · ") : tr("pareado · Wi‑Fi", "paired · Wi‑Fi")
            return TabletItem(id: "wifi-\(tablet.fingerprint)", name: name, meta: meta, action: .forget(tablet))
        }
        for serial in approvedUSBDevices {
            let device = usbCandidates.first { $0.serialNumber == serial }
            let online = connectedLink == .usb
            let name = online ? (connectedName ?? "tablet") : Self.friendlyName(device?.name)
            let meta = online ? [tr("USB direto", "Direct USB"), size].compactMap { $0 }.joined(separator: " · ") : tr("aprovado · USB", "approved · USB") + " · \(serial.suffix(4))"
            items.append(TabletItem(id: "usb-\(serial)", name: name, meta: meta, action: .revokeUSB(serial)))
        }
        for device in usbCandidates {
            guard let serial = device.serialNumber, !approvedUSBDevices.contains(serial) else { continue }
            items.append(TabletItem(id: "new-\(serial)", name: Self.friendlyName(device.name), meta: tr("no cabo · não aprovado", "on the cable · not approved"), action: .approveUSB(serial)))
        }
        return items
    }

    func perform(_ action: TabletItem.Action) {
        switch action {
        case .forget(let tablet): forgetTablet(tablet)
        case .revokeUSB(let serial): revokeUSBDevice(serial)
        case .approveUSB(let serial): approveUSBDevice(serial)
        }
    }

    var isDirectActive: Bool {
        switch directState {
        case .idle, .failed: false
        default: true
        }
    }
}
