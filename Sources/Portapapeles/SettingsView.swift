import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var accessibilityGranted = Paster.isTrusted
    @State private var revertingLoginItem = false
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            history.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        // Alto suficiente para que "General" entre completa: con 380 la sección "Pegado"
        // quedaba bajo el borde y el aviso de Accesibilidad solo se veía haciendo scroll.
        .frame(width: 470, height: 580)
        .onReceive(ticker) { _ in
            let trusted = Paster.isTrusted
            if trusted != accessibilityGranted { accessibilityGranted = trusted }
        }
    }

    private var general: some View {
        Form {
            Section("Shortcut") {
                HStack {
                    Text("Open the history")
                    Spacer()
                    HotKeyRecorder(keyCode: $prefs.hotKeyCode, modifiers: $prefs.hotKeyMods) {
                        Task { @MainActor in
                            PanelController.shared.registerHotKey()
                            AppDelegate.shared?.updateShortcutHint()
                        }
                    }
                }
                Text(L.t("It is the Windows ⊞+V. Whatever you pick stays on the clipboard, "
                         + "so a normal ⌘V pastes it again."))
                    .font(.caption).foregroundStyle(.secondary)
                if !prefs.hotKeyRegistered {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(L.t("The system rejected this combination: another app already has it. "
                                 + "Pick a different one."))
                            .font(.caption)
                    }
                }
            }

            Section("Where the panel appears") {
                Picker("Position", selection: Binding(get: { prefs.anchor }, set: { prefs.anchor = $0 })) {
                    ForEach(PanelAnchor.allCases) { Text(L.t($0.titleKey)).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Pasting") {
                Toggle("Paste automatically when picking", isOn: $prefs.autoPaste)
                HStack(spacing: 8) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Text(accessibilityGranted
                         ? LocalizedStringKey("Accessibility granted: it pastes on its own and opens next to the cursor.")
                         : LocalizedStringKey("Without Accessibility it only copies, and the panel opens next to the pointer."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Grant…") {
                            Paster.requestPermission()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
                if !accessibilityGranted {
                    // La confusión clásica: la casilla figura marcada, pero esa entrada es de
                    // otra copia de la app (otra ruta). macOS solo muestra el nombre.
                    Text(L.t("Already granted but still orange? That entry in the list is usually for "
                             + "another copy of the app: macOS shows only the name, not the path. "
                             + "Remove it with «−», add this one again and restart the app."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Open at login", isOn: $prefs.launchAtLogin)
                    .onChange(of: prefs.launchAtLogin) { _, on in
                        // La vuelta atrás dispara este mismo onChange; el flag corta el bucle.
                        guard !revertingLoginItem else { revertingLoginItem = false; return }
                        guard !LoginItem.set(enabled: on) else { return }
                        revertingLoginItem = true
                        prefs.launchAtLogin = !on
                        let alert = NSAlert()
                        alert.messageText = L.t("macOS did not accept the login item")
                        alert.informativeText = L.t("It usually happens when the app is not in "
                                                    + "/Applications. Move it there and try again.")
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
            }
        }
        .formStyle(.grouped)
    }

    private var history: some View {
        Form {
            HStack {
                Text("Maximum clips")
                Slider(value: $prefs.maxItems, in: 10...300, step: 5)
                Text(verbatim: "\(Int(prefs.maxItems))")
                    .monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            Text("Windows keeps 25. Pinned clips do not count toward the cap and are never dropped.")
                .font(.caption).foregroundStyle(.secondary)

            Section {
                Toggle("Keep the whole history on restart", isOn: $prefs.keepHistoryOnRestart)
                Text("Turned off it behaves like Windows: only pinned clips survive a restart.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Save images too", isOn: $prefs.keepImages)
                Toggle("Ignore password managers and clips marked as private",
                       isOn: $prefs.ignoreConfidential)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Delete the whole history", role: .destructive) {
                        Task { @MainActor in
                            // Se lleva también lo anclado y las imágenes del disco: conviene preguntar.
                            let alert = NSAlert()
                            alert.messageText = L.t("Delete the whole history?")
                            alert.informativeText = L.t("Every clip is removed, including pinned ones "
                                                        + "and the saved images. This cannot be undone.")
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: L.t("Delete the whole history"))
                            alert.addButton(withTitle: L.t("Cancel"))
                            if alert.runModal() == .alertFirstButtonReturn {
                                ClipboardStore.shared.purge()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tint)
            Text("Clipboard").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("The Windows clipboard history (⊞+V), for the Mac. Everything stays on this computer.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 7) {
                shortcut(Prefs.shared.hotKey.display, "open or close the history")
                shortcut("↑ ↓ ⇥", "move through the list")
                shortcut("⏎", "paste the selected clip")
                shortcut("⌘1 – ⌘9", "paste the nth one directly")
                shortcut("⌘P", "pin or unpin")
                shortcut("⌘⌫", "remove from the history")
                shortcut("⎋", "close")
            }
            .padding(.top, 6)

            Spacer()

            VStack(spacing: 3) {
                Text("Made by \("j0KZ")")
                    .font(.system(size: 12, weight: .medium))
                Link("github.com/j0KZ/Simple_Clipboard",
                     destination: URL(string: "https://github.com/j0KZ/Simple_Clipboard")!)
                    .font(.system(size: 11))
                Text(verbatim: "MIT")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 18)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// La tecla en una "tapa" con fondo, para que se lea. Antes iba en `.caption` (10 pt)
    /// gris sobre gris y no había manera.
    private func shortcut(_ keys: String, _ what: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 76, alignment: .center)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                )
            Text(what)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// Campo para capturar una combinación de teclas.
struct HotKeyRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: () -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Text(recording
                 ? L.t("Press the combination…")
                 : HotKeySpec(keyCode: keyCode, modifiers: modifiers).display)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 130)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onChange(of: recording) { _, on in on ? start() : stop() }
        .onDisappear { stop() }
        .help("Click and press whatever combination you want")
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { recording = false; return nil }   // esc cancela
            let mods = HotKeySpec.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil }
            keyCode = Int(event.keyCode)
            modifiers = mods
            recording = false
            onChange()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

enum LoginItem {
    /// false si el sistema lo rechazó. Antes esto solo se anotaba en la consola y el
    /// interruptor se quedaba encendido: la UI decía que sí y no era verdad.
    @discardableResult
    static func set(enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            ClipDebug.log("ítem de inicio: \(enabled ? "registrado" : "quitado") "
                          + "(status \(SMAppService.mainApp.status.rawValue))")
            return true
        } catch {
            NSLog("Portapapeles: no se pudo cambiar el ítem de inicio: \(error.localizedDescription)")
            ClipDebug.log("ítem de inicio: FALLÓ — \(error.localizedDescription)")
            return false
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var onClose: (() -> Void)?

    convenience init(onClose: @escaping () -> Void) {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = L.t("Clipboard Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        self.onClose = onClose
        window.delegate = self
    }

    func show() {
        // Con Preferencias abierta la app pasa a ser normal para que tenga menú y Dock;
        // al cerrarla, `windowWillClose` la devuelve a `.accessory`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        onClose = nil
        // `onClose` suelta la última referencia fuerte a este controlador, y con ella a la
        // ventana. Hacerlo aquí mismo la destruye en mitad de su propio aviso de cierre y
        // AppKit se va a negro. Se difiere un ciclo del runloop, con el cierre ya terminado.
        DispatchQueue.main.async(execute: callback ?? {})
    }
}
