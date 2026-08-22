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
            history.tabItem { Label("Historial", systemImage: "clock.arrow.circlepath") }
            about.tabItem { Label("Acerca de", systemImage: "info.circle") }
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
                if !prefs.hotKeyRegistered {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("El sistema rechazó esta combinación: otra app ya la tiene. Elige otra.")
                            .font(.caption)
                    }
                }
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
                if !accessibilityGranted {
                    // La confusión clásica: la casilla figura marcada, pero esa entrada es de
                    // otra copia de la app (otra ruta). macOS solo muestra el nombre, así que
                    // las dos se ven iguales.
                    Text("¿Ya lo concediste y sigue en naranja? Esa entrada de la lista suele ser "
                         + "de otra copia de la app: macOS muestra solo el nombre y no la ruta. "
                         + "Quítala con «−», vuelve a agregar esta y reinicia la app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Abrir al iniciar sesión", isOn: $prefs.launchAtLogin)
                    .onChange(of: prefs.launchAtLogin) { _, on in
                        // La vuelta atrás dispara este mismo onChange; el flag corta el bucle.
                        guard !revertingLoginItem else { revertingLoginItem = false; return }
                        guard !LoginItem.set(enabled: on) else { return }
                        revertingLoginItem = true
                        prefs.launchAtLogin = !on
                        let alert = NSAlert()
                        alert.messageText = "macOS no aceptó el ítem de inicio"
                        alert.informativeText = "Suele pasar cuando la app no está en /Aplicaciones. "
                            + "Muévela ahí y vuelve a intentarlo."
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
                        Task { @MainActor in
                            // Se lleva también lo anclado y las imágenes del disco: conviene preguntar.
                            let alert = NSAlert()
                            alert.messageText = "¿Borrar todo el historial?"
                            alert.informativeText = "Se eliminan todos los recortes, incluidos los anclados "
                                + "y las imágenes guardadas. No se puede deshacer."
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "Borrar todo")
                            alert.addButton(withTitle: "Cancelar")
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
        window.title = "Preferencias de Portapapeles"
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
