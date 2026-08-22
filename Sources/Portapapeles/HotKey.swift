import AppKit
import Carbon.HIToolbox

/// Combinación de teclas guardada en preferencias (código de tecla + modificadores Carbon).
struct HotKeySpec: Equatable {
    var keyCode: Int
    var modifiers: Int

    static let defaultShortcut = HotKeySpec(keyCode: kVK_ANSI_V, modifiers: optionKey | cmdKey)

    var isValid: Bool { modifiers != 0 }

    var display: String {
        var out = ""
        if modifiers & controlKey != 0 { out += "⌃" }
        if modifiers & optionKey != 0 { out += "⌥" }
        if modifiers & shiftKey != 0 { out += "⇧" }
        if modifiers & cmdKey != 0 { out += "⌘" }
        out += HotKeySpec.name(for: keyCode)
        return out
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var mods = 0
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        return mods
    }

    static func name(for keyCode: Int) -> String {
        if let special = specialNames[keyCode] { return special }
        return literalNames[keyCode] ?? String(format: L.t("Key %lld"), keyCode)
    }

    private static let specialNames: [Int: String] = [
        kVK_Space: L.t("Space"), kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    private static let literalNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Grave: "`"
    ]
}

/// Atajo global registrado con Carbon: funciona en cualquier app y no pide permisos.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    /// false si el sistema rechazó la combinación, normalmente porque otra app ya la tiene.
    private(set) var isRegistered = false

    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var handlerInstalled = false

    init(spec: HotKeySpec, action: @escaping () -> Void) {
        GlobalHotKey.installHandlerIfNeeded()
        id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.handlers[id] = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: id) // 'CLIP'
        let status = RegisterEventHotKey(UInt32(spec.keyCode),
                                         UInt32(spec.modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        isRegistered = (status == noErr)
        if !isRegistered {
            ClipDebug.log("no se pudo registrar el atajo \(spec.display) (status \(status))")
            GlobalHotKey.handlers[id] = nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        GlobalHotKey.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr, let action = GlobalHotKey.handlers[hotKeyID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async(execute: action)
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Simula ⌘V para pegar en la app que está adelante. Necesita permiso de Accesibilidad.
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Abre el diálogo del sistema para conceder Accesibilidad.
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Espera a que sueltes los modificadores antes de mandar el ⌘V. Si el ⌥ del atajo sigue
    /// apretado, el sistema fusiona las teclas y lo que llega es ⌥⌘V — es decir, el propio
    /// atajo otra vez, y el panel se reabre en vez de pegar.
    static func pressCommandV(retries: Int = 8) {
        guard isTrusted else { return }
        let held = NSEvent.modifierFlags.intersection([.option, .control, .shift])
        if !held.isEmpty, retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pressCommandV(retries: retries - 1) }
            return
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Ignora los modificadores que el usuario todavía tenga apretados del atajo.
        source.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                          state: .eventSuppressionStateSuppressionInterval)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
