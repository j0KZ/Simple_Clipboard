import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dos copias a la vez (la de Homebrew y una compilada a mano, por ejemplo) registran
        // las dos el atajo global sin error, pero solo una lo recibe: el síntoma es que ⌥⌘V
        // "no hace nada". Carbon no avisa, así que la segunda se retira sola.
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != mine }
        if let otra = others.first {
            ClipDebug.log("ya hay otra instancia (pid \(otra.processIdentifier)); esta se retira")
            NSApp.terminate(nil)
            return
        }

        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        // La app es oscura siempre, no sigue el tema del sistema.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        ClipDebug.log("apariencia: \(NSApp.effectiveAppearance.name.rawValue)")
        ClipDebug.log("accesibilidad concedida a ESTA compilación: \(Paster.isTrusted)")

        ClipboardStore.shared.start()
        PanelController.shared.start()
        setupStatusItem()

        // La primera vez abrimos Preferencias: ahí está el atajo y el permiso de Accesibilidad.
        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.showSettings()
                if !Paster.isTrusted { Paster.requestPermission() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardStore.shared.flushSave()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Barra de menús

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                     accessibilityDescription: L.t("Clipboard"))
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        let open = NSMenuItem(title: L.t("Open history"), action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let clear = NSMenuItem(title: L.t("Clear all"), action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: L.t("Settings…"), action: #selector(showSettingsAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.t("Quit Clipboard"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        updateShortcutHint()
    }

    /// Muestra el atajo actual junto a "Abrir el historial".
    func updateShortcutHint() {
        statusItem?.menu?.items.first?.toolTip = String(format: L.t("Shortcut: %@"), Prefs.shared.hotKey.display)
    }

    @objc private func openPanel() {
        Task { @MainActor in PanelController.shared.show() }
    }

    @objc private func clearAll() {
        Task { @MainActor in ClipboardStore.shared.clear() }
    }

    @objc private func showSettingsAction() { showSettings() }

    func showSettings() {
        // Si se pidió desde el menú ⋯ del panel, hay que cerrarlo antes y sin devolverle el
        // foco a la app anterior: si no, esa app vuelve al frente y Preferencias se abre
        // detrás de ella. Parecía que la app se cerraba sola.
        MainActor.assumeIsolated {
            PanelController.shared.hide(pasting: false, restoringFocus: false)
        }
        if settingsWindow == nil {
            // Se rehace cada vez: al cerrarla se suelta y con ella el `ticker` que sondea
            // el permiso de Accesibilidad, que si no seguía latiendo para siempre.
            settingsWindow = SettingsWindowController { [weak self] in
                self?.settingsWindow = nil
                // Vuelve a ser app de barra de menús: si no, el icono queda en el Dock.
                NSApp.setActivationPolicy(.accessory)
            }
        }
        settingsWindow?.show()
    }

    /// Solo la usa el disparador de depuración, para probar el ciclo abrir/cerrar.
    func toggleSettings() {
        if let window = settingsWindow?.window, window.isVisible {
            window.performClose(nil)
        } else {
            showSettings()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
