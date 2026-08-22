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

    static let panelSize = CGSize(width: 292, height: 352)
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

    var isVisible: Bool { panel?.isVisible == true }

    private init() {}

    // MARK: - Ciclo de vida

    func start() {
        registerHotKey()
    }

    func registerHotKey() {
        hotKey = nil
        let spec = prefs.hotKey
        guard spec.isValid else { return }
        hotKey = GlobalHotKey(spec: spec) {
            Task { @MainActor in PanelController.shared.toggle() }
        }
        ClipDebug.log("atajo: \(spec.display)")
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

        let hosting = NSHostingView(rootView: ClipboardPanelView())
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
        let panel = buildPanel()
        previousApp = NSWorkspace.shared.frontmostApplication

        let store = ClipboardStore.shared
        store.query = ""
        store.selection = 0
        store.presentationID = UUID()

        isPositioning = true
        panel.setFrame(NSRect(origin: origin(for: Self.panelSize), size: Self.panelSize), display: false)
        isPositioning = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            panel.animator().alphaValue = 1
        }

        installMonitors()
        NotificationCenter.default.addObserver(self, selector: #selector(panelResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
    }

    func hide(pasting: Bool) {
        guard let panel, panel.isVisible else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        removeMonitors()

        let target = previousApp
        previousApp = nil
        panel.orderOut(nil)
        ClipboardStore.shared.query = ""
        ClipboardStore.shared.selection = 0

        if let target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
            target.activate()
        } else {
            NSApp.deactivate()
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
            let screen = screenForMouse()
            return CGPoint(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.midY - size.height / 2)
        }

        let screen = screenContaining(anchorRect.origin) ?? screenForMouse()
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

    private func screenForMouse() -> NSScreen {
        screenContaining(NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
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
        case kVK_Delete where command, kVK_ForwardDelete:
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

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9
    ]
}
