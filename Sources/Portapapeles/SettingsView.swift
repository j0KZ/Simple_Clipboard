import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var accessibilityGranted = Paster.isTrusted
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            history.tabItem { Label("Historial", systemImage: "clock.arrow.circlepath") }
            about.tabItem { Label("Acerca de", systemImage: "info.circle") }
        }
        .frame(width: 470, height: 380)
        .onReceive(ticker) { _ in
            let trusted = Paster.isTrusted
            if trusted != accessibilityGranted { accessibilityGranted = trusted }
        }
    }

    private var general: some View {
        Form {
            Section("Atajo") {
                HStack {
                    Text("Abrir el historial")
                    Spacer()
                    HotKeyRecorder(keyCode: $prefs.hotKeyCode, modifiers: $prefs.hotKeyMods) {
                        Task { @MainActor in
                            PanelController.shared.registerHotKey()
                            AppDelegate.shared?.updateShortcutHint()
                        }
                    }
                }
                Text("Es el ⊞+V de Windows. Lo que elijas queda en el portapapeles, así que el ⌘V normal lo vuelve a pegar.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Dónde aparece el panel") {
                Picker("Posición", selection: Binding(get: { prefs.anchor }, set: { prefs.anchor = $0 })) {
                    ForEach(PanelAnchor.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Pegado") {
                Toggle("Pegar automáticamente al elegir", isOn: $prefs.autoPaste)
                HStack(spacing: 8) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Text(accessibilityGranted
                         ? "Accesibilidad concedida: pega solo y se abre junto al cursor."
                         : "Sin Accesibilidad solo copia, y el panel se abre junto al puntero.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Conceder…") {
                            Paster.requestPermission()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section {
                Toggle("Abrir al iniciar sesión", isOn: $prefs.launchAtLogin)
                    .onChange(of: prefs.launchAtLogin) { _, on in LoginItem.set(enabled: on) }
            }
        }
        .formStyle(.grouped)
    }

    private var history: some View {
        Form {
            HStack {
                Text("Máximo de recortes")
                Slider(value: $prefs.maxItems, in: 10...300, step: 5)
                Text("\(Int(prefs.maxItems))").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            Text("Windows guarda 25. Lo anclado no cuenta contra el tope y nunca se descarta.")
                .font(.caption).foregroundStyle(.secondary)

            Section {
                Toggle("Conservar todo el historial al reiniciar", isOn: $prefs.keepHistoryOnRestart)
                Text("Apagado se comporta como Windows: al reiniciar solo sobrevive lo anclado.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Guardar también imágenes", isOn: $prefs.keepImages)
                Toggle("Ignorar gestores de contraseñas y copias marcadas como privadas",
                       isOn: $prefs.ignoreConfidential)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Borrar todo el historial", role: .destructive) {
                        Task { @MainActor in ClipboardStore.shared.purge() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tint)
            Text("Portapapeles").font(.title2.weight(.semibold))
            Text("Versión \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("El historial del portapapeles de Windows (⊞+V), para el Mac. Todo se queda en este equipo.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            VStack(alignment: .leading, spacing: 3) {
                shortcut("\(Prefs.shared.hotKey.display)", "abrir o cerrar el historial")
                shortcut("↑ ↓ / ⇥", "moverse por la lista")
                shortcut("⏎", "pegar el recorte elegido")
                shortcut("⌘1 – ⌘9", "pegar directo el enésimo")
                shortcut("⌘P", "anclar o desanclar")
                shortcut("⌘⌫", "eliminar del historial")
                shortcut("⎋", "cerrar")
            }
            .font(.caption)
            .padding(.top, 4)
            Spacer()
        }
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcut(_ keys: String, _ what: String) -> some View {
        HStack(spacing: 6) {
            Text(keys).monospaced().frame(width: 76, alignment: .trailing)
            Text(what).foregroundStyle(.secondary)
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
            Text(recording ? "Presiona la combinación…" : HotKeySpec(keyCode: keyCode, modifiers: modifiers).display)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 130)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onChange(of: recording) { _, on in on ? start() : stop() }
        .onDisappear { stop() }
        .help("Haz clic y presiona la combinación que quieras")
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
    static func set(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Portapapeles: no se pudo cambiar el ítem de inicio: \(error.localizedDescription)")
        }
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Preferencias de Portapapeles"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
