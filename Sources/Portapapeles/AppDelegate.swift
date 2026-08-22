import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Barra de menús

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                     accessibilityDescription: "Portapapeles")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        let open = NSMenuItem(title: "Abrir el historial", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Borrar todo", action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferencias…", action: #selector(showSettingsAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de Portapapeles", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        updateShortcutHint()
    }

    /// Muestra el atajo actual junto a "Abrir el historial".
    func updateShortcutHint() {
        statusItem?.menu?.items.first?.toolTip = "Atajo: \(Prefs.shared.hotKey.display)"
    }

    @objc private func openPanel() {
        Task { @MainActor in PanelController.shared.show() }
    }

    @objc private func clearAll() {
        Task { @MainActor in ClipboardStore.shared.clear() }
    }

    @objc private func showSettingsAction() { showSettings() }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.show()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
