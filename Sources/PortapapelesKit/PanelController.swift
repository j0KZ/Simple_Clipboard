import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Ventana flotante del historial. Aparece junto al cursor y desaparece al elegir o al perder el foco.
final class ClipPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    static let shared = PanelController()

    static let panelSize = CGSize(width: 300, height: 420)
    /// Separación entre el cursor de texto y el panel, como en Windows.
    private let gap: CGFloat = 8

    private var panel: ClipPanel?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var hotKey: GlobalHotKey?
    private let prefs = Prefs.shared
    /// Evita guardar como "posición del usuario" el reposicionamiento que hacemos al abrir.
    private var isPositioning = false
    /// Dónde estaba el puntero al abrir el panel. Ver `hoverCanSelect`.
    private var mouseAtOpen: CGPoint = .zero

    /// El panel aparece junto al cursor de texto, así que muchas veces nace debajo del
    /// puntero. Sin esto, la tarjeta que quede bajo el ratón se selecciona sola y el ⏎,
    /// el ⌘P o el ⌘⌫ actúan sobre ella en vez de sobre la primera. El hover manda solo
    /// después de que el ratón se haya movido de verdad.
    var hoverCanSelect: Bool {
        let now = NSEvent.mouseLocation
        return hypot(now.x - mouseAtOpen.x, now.y - mouseAtOpen.y) > 3
    }

    var isVisible: Bool { panel?.isVisible == true }

    private init() {}

    // MARK: - Ciclo de vida

    func start() {
        registerHotKey()
        if ClipDebug.enabled { observeDebugTrigger() }
    }

    /// Con `CLIP_DEBUG=1` el panel también se abre publicando una notificación distribuida,
    /// para poder revisar la UI sin depender del atajo global:
    ///
    ///     swift tools/TogglePanel.swift
    ///
    /// Fuera del modo depuración el observador ni siquiera se registra.
    private func observeDebugTrigger() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.j0kz.Portapapeles.debugToggle"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ClipDebug.log("disparador: toggle (visible=\(PanelController.shared.isVisible))")
                PanelController.shared.toggle()
            }
        }
        // Preferencias también, para poder probar el abrir/cerrar de la ventana sin clics.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.j0kz.Portapapeles.debugSettings"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ClipDebug.log("disparador: preferencias")
                AppDelegate.shared?.toggleSettings()
            }
        }
        ClipDebug.log("disparador de depuración activo")
    }

    func registerHotKey() {
        hotKey = nil
        let spec = prefs.hotKey
        guard spec.isValid else {
            prefs.hotKeyRegistered = false
            return
        }
        let key = GlobalHotKey(spec: spec) {
            Task { @MainActor in PanelController.shared.toggle() }
        }
        hotKey = key
        // Antes, si otra app ya tenía la combinación, esto fallaba en silencio y el atajo
        // simplemente no hacía nada. Ahora Preferencias lo avisa.
        prefs.hotKeyRegistered = key.isRegistered
        ClipDebug.log("atajo: \(spec.display)\(key.isRegistered ? "" : " — RECHAZADO por el sistema")")
    }

    private func buildPanel() -> ClipPanel {
        if let panel { return panel }
        let panel = ClipPanel(size: Self.panelSize)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        effect.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: ClipboardPanelView(store: .shared))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        panel.contentView = effect
        self.panel = panel
        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
        return panel
    }

    // MARK: - Mostrar / ocultar

    func toggle() {
        if isVisible { hide(pasting: false) } else { show() }
    }

    func show() {
        let t0 = CFAbsoluteTimeGetCurrent()
        let panel = buildPanel()
        let tBuilt = CFAbsoluteTimeGetCurrent()
        previousApp = NSWorkspace.shared.frontmostApplication

        let store = ClipboardStore.shared
        store.query = ""
        store.selection = 0
        store.presentationID = UUID()

        mouseAtOpen = NSEvent.mouseLocation
        isPositioning = true
        let tBeforeOrigin = CFAbsoluteTimeGetCurrent()
        panel.setFrame(NSRect(origin: origin(for: Self.panelSize), size: Self.panelSize), display: false)
        let tPositioned = CFAbsoluteTimeGetCurrent()
        isPositioning = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            panel.animator().alphaValue = 1
        }

        // Con CLIP_DEBUG queda el desglose del coste de abrir: construir la vista la primera
        // vez, y `origin(for:)`, que en modo "cursor de texto" hace consultas de Accesibilidad
        // a la app de delante y es la parte que puede tardar.
        ClipDebug.log(String(format: "abrir: vista %.1f ms · posición %.1f ms · total %.1f ms",
                             (tBuilt - t0) * 1000,
                             (tPositioned - tBeforeOrigin) * 1000,
                             (CFAbsoluteTimeGetCurrent() - t0) * 1000))

        installMonitors()
        // Sin quitarlo antes, un segundo `show()` (el ítem "Abrir el historial" del menú
        // con el panel ya abierto) apilaba observadores sobre la misma ventana.
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(panelResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
    }

    /// `restoringFocus: false` cuando lo que sigue es una ventana nuestra (Preferencias):
    /// devolverle el foco a la app anterior la traería al frente y la enterraría.
    func hide(pasting: Bool, restoringFocus: Bool = true) {
        guard let panel, panel.isVisible else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        removeMonitors()

        let target = previousApp
        previousApp = nil
        panel.orderOut(nil)
        ClipboardStore.shared.query = ""
        ClipboardStore.shared.selection = 0

        if restoringFocus {
            if let target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
                target.activate()
            } else {
                NSApp.deactivate()
            }
        }

        guard pasting, Paster.isTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            Paster.pressCommandV()
        }
    }

    /// Windows recuerda dónde dejaste el panel; nosotros también.
    @objc private func panelMoved() {
        Task { @MainActor in
            guard !self.isPositioning, self.isVisible, let panel = self.panel else { return }
            self.prefs.rememberPanelPosition(panel.frame.origin)
        }
    }

    @objc private func panelResignedKey() {
        // Windows cierra el panel en cuanto pierde el foco.
        Task { @MainActor in
            guard self.isVisible else { return }
            ClipDebug.log("panel: perdió el foco, se cierra")
            self.hide(pasting: false)
        }
    }

    // MARK: - Posición

    private func origin(for size: CGSize) -> CGPoint {
        if prefs.hasPanelPosition {
            let saved = CGPoint(x: prefs.panelX, y: prefs.panelY)
            if let screen = screenContaining(saved) ?? NSScreen.main {
                let visible = screen.visibleFrame
                return CGPoint(x: min(max(saved.x, visible.minX + 8), visible.maxX - size.width - 8),
                               y: min(max(saved.y, visible.minY + 8), visible.maxY - size.height - 8))
            }
        }
        let anchorRect: CGRect
        switch prefs.anchor {
        case .caret:
            anchorRect = CaretLocator.caretRect() ?? mouseRect()
        case .mouse:
            anchorRect = mouseRect()
        case .center:
            guard let screen = screenForMouse() else { return .zero }
            return CGPoint(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.midY - size.height / 2)
        }

        guard let screen = screenContaining(anchorRect.origin) ?? screenForMouse() else { return .zero }
        let visible = screen.visibleFrame

        // Por debajo del cursor; si no cabe, por arriba.
        var y = anchorRect.minY - gap - size.height
        if y < visible.minY {
            let above = anchorRect.maxY + gap
            y = (above + size.height <= visible.maxY) ? above : visible.minY + 8
        }
        var x = anchorRect.minX
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }

    private func mouseRect() -> CGRect {
        let p = NSEvent.mouseLocation
        return CGRect(x: p.x, y: p.y - 18, width: 1, height: 18)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// nil solo si no hay ninguna pantalla conectada; `NSScreen.screens[0]` reventaba ahí.
    private func screenForMouse() -> NSScreen? {
        screenContaining(NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Teclado y clics

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                let consumed = MainActor.assumeIsolated { PanelController.shared.handleKey(event) }
                return consumed ? nil : event
            }
        }
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                Task { @MainActor in PanelController.shared.hide(pasting: false) }
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    /// true si la tecla se consumió; false para que llegue al buscador.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        let store = ClipboardStore.shared
        let command = event.modifierFlags.contains(.command)
        // Solo los atajos con ⌘: registrar cada tecla anotaría también lo que se escribe
        // en el buscador, y eso no tiene por qué acabar en un log.
        if command { ClipDebug.log("atajo en el panel: code=\(event.keyCode)") }
        let shift = event.modifierFlags.contains(.shift)

        switch Int(event.keyCode) {
        case kVK_DownArrow:
            store.move(by: 1); return true
        case kVK_UpArrow:
            store.move(by: -1); return true
        case kVK_Tab:
            store.move(by: shift ? -1 : 1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = store.selectedItem { store.use(item) }
            return true
        case kVK_Escape:
            if !store.query.isEmpty { store.query = "" } else { hide(pasting: false) }
            return true
        // Las dos piden ⌘: sin él, ⌦ borraba el recorte en vez de un carácter del buscador.
        case kVK_Delete where command, kVK_ForwardDelete where command:
            if let item = store.selectedItem { withAnimation(.easeOut(duration: 0.12)) { store.remove(item) } }
            return true
        case kVK_ANSI_P where command:
            if let item = store.selectedItem { withAnimation(.easeOut(duration: 0.12)) { store.togglePin(item) } }
            return true
        default:
            break
        }

        if command, let digit = Self.digitKeys[Int(event.keyCode)] {
            let list = store.visibleItems
            if list.indices.contains(digit - 1) {
                store.selection = digit - 1
                store.use(list[digit - 1])
            }
            return true
        }
        return false
    }

    /// La fila de números y también el teclado numérico: con un teclado completo el ⌘2 del
    /// bloque numérico manda otro código y antes no hacía nada.
    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4,
        kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8,
        kVK_ANSI_Keypad9: 9
    ]
}
