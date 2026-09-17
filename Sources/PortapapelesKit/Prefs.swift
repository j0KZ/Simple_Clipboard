import Foundation
import Combine

/// Preferencias de la app. Todo en UserDefaults.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d: UserDefaults

    @Published var hotKeyCode: Int { didSet { d.set(hotKeyCode, forKey: K.hotKeyCode) } }
    @Published var hotKeyMods: Int { didSet { d.set(hotKeyMods, forKey: K.hotKeyMods) } }
    @Published var maxItems: Double { didSet { d.set(maxItems, forKey: K.maxItems) } }
    /// Windows borra el historial al reiniciar y solo conserva lo fijado.
    @Published var keepHistoryOnRestart: Bool { didSet { d.set(keepHistoryOnRestart, forKey: K.keepHistoryOnRestart) } }
    @Published var keepImages: Bool { didSet { d.set(keepImages, forKey: K.keepImages) } }
    @Published var ignoreConfidential: Bool { didSet { d.set(ignoreConfidential, forKey: K.ignoreConfidential) } }
    @Published var autoPaste: Bool { didSet { d.set(autoPaste, forKey: K.autoPaste) } }
    @Published var anchorRaw: String { didSet { d.set(anchorRaw, forKey: K.anchor) } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin) } }

    /// No se guarda en disco: dice si el atajo actual pudo registrarse en el sistema.
    /// Preferencias lo muestra para que un atajo ya tomado por otra app no falle mudo.
    @Published var hotKeyRegistered = true

    // Posición donde quedó el panel después de arrastrarlo.
    @Published var hasPanelPosition: Bool { didSet { d.set(hasPanelPosition, forKey: K.hasPanelPosition) } }
    @Published var panelX: Double { didSet { d.set(panelX, forKey: K.panelX) } }
    @Published var panelY: Double { didSet { d.set(panelY, forKey: K.panelY) } }

    func forgetPanelPosition() {
        hasPanelPosition = false
    }

    func rememberPanelPosition(_ origin: CGPoint) {
        panelX = origin.x
        panelY = origin.y
        hasPanelPosition = true
    }

    var hotKey: HotKeySpec { HotKeySpec(keyCode: hotKeyCode, modifiers: hotKeyMods) }
    var anchor: PanelAnchor {
        get { PanelAnchor(rawValue: anchorRaw) ?? .caret }
        set { anchorRaw = newValue.rawValue }
    }

    private enum K {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyMods = "hotKeyMods"
        static let maxItems = "maxItems"
        static let keepHistoryOnRestart = "keepHistoryOnRestart"
        static let keepImages = "keepImages"
        static let ignoreConfidential = "ignoreConfidential"
        static let autoPaste = "autoPaste"
        static let anchor = "anchor"
        static let launchAtLogin = "launchAtLogin"
        static let hasPanelPosition = "hasPanelPosition"
        static let panelX = "panelX"
        static let panelY = "panelY"
    }

    /// Dónde se guardan las preferencias. Se recibe para que las pruebas usen un
    /// dominio aparte y no toquen las del usuario.
    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            K.hotKeyCode: HotKeySpec.defaultShortcut.keyCode,
            K.hotKeyMods: HotKeySpec.defaultShortcut.modifiers,
            K.maxItems: 25.0,            // el mismo tope que Windows
            K.keepHistoryOnRestart: true,  // todo el historial vive en el JSON local
            K.keepImages: true,
            K.ignoreConfidential: true,
            K.autoPaste: true,
            K.anchor: PanelAnchor.caret.rawValue,
            K.launchAtLogin: false,
            K.hasPanelPosition: false,
            K.panelX: 0.0,
            K.panelY: 0.0
        ])
        hotKeyCode = d.integer(forKey: K.hotKeyCode)
        hotKeyMods = d.integer(forKey: K.hotKeyMods)
        maxItems = d.double(forKey: K.maxItems)
        keepHistoryOnRestart = d.bool(forKey: K.keepHistoryOnRestart)
        keepImages = d.bool(forKey: K.keepImages)
        ignoreConfidential = d.bool(forKey: K.ignoreConfidential)
        autoPaste = d.bool(forKey: K.autoPaste)
        anchorRaw = d.string(forKey: K.anchor) ?? PanelAnchor.caret.rawValue
        launchAtLogin = d.bool(forKey: K.launchAtLogin)
        hasPanelPosition = d.bool(forKey: K.hasPanelPosition)
        panelX = d.double(forKey: K.panelX)
        panelY = d.double(forKey: K.panelY)
    }
}

enum PanelAnchor: String, CaseIterable, Identifiable {
    case caret, mouse, center
    var id: String { rawValue }
    /// Clave en inglés; se traduce en el punto de uso con `L.t`.
    var titleKey: String {
        switch self {
        case .caret: return "Where the text cursor is"
        case .mouse: return "Where the pointer is"
        case .center: return "Center of the screen"
        }
    }
}

/// Textos de la interfaz. Las claves son el texto en inglés; la traducción vive en
/// `Resources/*.lproj/Localizable.strings`. Las vistas SwiftUI localizan solas al usar
/// `Text("…")`; esto es para lo que se arma como `String` (AppKit, formatos).
enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    /// El idioma que la app está mostrando de verdad, no la región del sistema. Se usa para
    /// que "hace 5 min" salga en el mismo idioma que el resto de la interfaz.
    static let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
}

/// Registro opcional: exporta CLIP_DEBUG=1 antes de lanzar la app.
enum ClipDebug {
    static let enabled = ProcessInfo.processInfo.environment["CLIP_DEBUG"] == "1"
    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(("[clip] " + message() + "\n").utf8))
    }
}
