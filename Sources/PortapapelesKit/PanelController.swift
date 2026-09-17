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
    var hoverCanSelect: Bool { Self.hoverCanSelect(now: NSEvent.mouseLocation, atOpen: mouseAtOpen) }

    /// El ratón tiene que haberse movido de verdad, no un pixel de temblor.
    nonisolated static func hoverCanSelect(now: CGPoint, atOpen: CGPoint, threshold: CGFloat = 3) -> Bool {
        hypot(now.x - atOpen.x, now.y - atOpen.y) > threshold
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
                return Self.clamp(saved, size: size, visible: screen.visibleFrame)
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
            return Self.centered(size, in: screen.visibleFrame)
        }

        guard let screen = screenContaining(anchorRect.origin) ?? screenForMouse() else { return .zero }
        return Self.origin(for: size, anchor: anchorRect, visible: screen.visibleFrame, gap: gap)
    }

    /// Margen que se deja siempre contra el borde de la pantalla.
    nonisolated static let screenMargin: CGFloat = 8

    /// Mete el panel dentro de la pantalla.
    ///
    /// El tope de arriba se calcula con `max`: en una pantalla más angosta que el
    /// panel, el límite superior queda por debajo del inferior y encajarlo al
    /// revés mandaba el panel fuera por la izquierda, sin forma de recuperarlo
    /// salvo con "Restablecer posición".
    nonisolated static func clamp(_ point: CGPoint, size: CGSize, visible: CGRect,
                      margin: CGFloat = screenMargin) -> CGPoint {
        let minX = visible.minX + margin
        let minY = visible.minY + margin
        let maxX = max(minX, visible.maxX - size.width - margin)
        let maxY = max(minY, visible.maxY - size.height - margin)
        return CGPoint(x: min(max(point.x, minX), maxX),
                       y: min(max(point.y, minY), maxY))
    }

    /// Debajo del cursor de texto; si no cabe, encima; y si tampoco, pegado abajo.
    nonisolated static func origin(for size: CGSize, anchor: CGRect, visible: CGRect, gap: CGFloat) -> CGPoint {
        var y = anchor.minY - gap - size.height
        if y < visible.minY {
            let above = anchor.maxY + gap
            y = (above + size.height <= visible.maxY) ? above : visible.minY + screenMargin
        }
        return clamp(CGPoint(x: anchor.minX, y: y), size: size, visible: visible)
    }

    /// El panel centrado en la pantalla.
    nonisolated static func centered(_ size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
    }

    private func mouseRect() -> CGRect { Self.mouseRect(at: NSEvent.mouseLocation) }

    /// Un cursor de texto imaginario bajo el puntero, para colocar el panel igual
    /// que cuando sí se sabe dónde está el cursor de verdad.
    nonisolated static func mouseRect(at point: CGPoint) -> CGRect {
        CGRect(x: point.x, y: point.y - 18, width: 1, height: 18)
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

        switch Self.action(keyCode: Int(event.keyCode), command: command, shift: shift,
                           queryIsEmpty: store.query.isEmpty) {
        case .move(let delta):
            store.move(by: delta)
        case .useSelected:
            if let item = store.selectedItem { store.use(item) }
        case .clearQuery:
            store.query = ""
        case .close:
            hide(pasting: false)
        case .deleteSelected:
            if let item = store.selectedItem { withAnimation(.easeOut(duration: 0.12)) { store.remove(item) } }
        case .togglePin:
            if let item = store.selectedItem { withAnimation(.easeOut(duration: 0.12)) { store.togglePin(item) } }
        case .pick(let position):
            let list = store.visibleItems
            if list.indices.contains(position - 1) {
                store.selection = position - 1
                store.use(list[position - 1])
            }
        case .passThrough:
            return false
        }
        return true
    }

    /// Qué hace cada tecla mientras el panel está abierto.
    enum PanelKeyAction: Equatable {
        case move(Int)
        case useSelected
        case clearQuery
        case close
        case deleteSelected
        case togglePin
        /// Pegar el recorte que ocupa esa posición de la lista (⌘1…⌘9).
        case pick(Int)
        /// No es un atajo del panel: la tecla sigue su camino hasta el buscador.
        case passThrough
    }

    nonisolated static func action(keyCode: Int, command: Bool, shift: Bool,
                                   queryIsEmpty: Bool) -> PanelKeyAction {
        switch keyCode {
        case kVK_DownArrow: return .move(1)
        case kVK_UpArrow: return .move(-1)
        case kVK_Tab: return .move(shift ? -1 : 1)
        case kVK_Return, kVK_ANSI_KeypadEnter: return .useSelected
        // Esc limpia la búsqueda primero; solo cierra si ya no había nada escrito.
        case kVK_Escape: return queryIsEmpty ? .close : .clearQuery
        // Las dos piden ⌘: sin él, ⌦ borraba el recorte en vez de un carácter del buscador.
        case kVK_Delete where command, kVK_ForwardDelete where command: return .deleteSelected
        case kVK_ANSI_P where command: return .togglePin
        default:
            if command, let digit = digitKeys[keyCode] { return .pick(digit) }
            return .passThrough
        }
    }

    /// La fila de números y también el teclado numérico: con un teclado completo el ⌘2 del
    /// bloque numérico manda otro código y antes no hacía nada.
    nonisolated static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4,
        kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8,
        kVK_ANSI_Keypad9: 9
    ]
}
