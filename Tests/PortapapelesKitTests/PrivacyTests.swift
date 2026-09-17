import AppKit
import Testing
@testable import PortapapelesKit

/// Pruebas de lo que nunca debe acabar en el disco.
///
/// Es la parte con más consecuencias del proyecto: si falla, una contraseña
/// termina guardada en el historial.
struct PrivacyTests {

    private static let dictado = Set([ClipboardStore.privateTypes.first!])

    @Test("Lo copiado dentro de un gestor de contraseñas se descarta")
    func confidentialAppsAreDropped() {
        for gestor in ["com.1password.1password", "com.apple.Passwords",
                       "org.keepassxc.keepassxc", "com.bitwarden.desktop"] {
            #expect(ClipboardStore.route(types: [], bundleID: gestor,
                                         ignoreConfidential: true) == .confidential)
        }
    }

    @Test("Un recorte marcado como privado queda en suspenso")
    func privateTypesAreHeld() {
        #expect(ClipboardStore.route(types: Self.dictado, bundleID: "com.apple.Safari",
                                     ignoreConfidential: true) == .privateClip)
    }

    @Test("Una copia normal se guarda")
    func normalClipsAreKept() {
        #expect(ClipboardStore.route(types: ["public.utf8-plain-text"],
                                     bundleID: "com.apple.Safari",
                                     ignoreConfidential: true) == .normal)
    }

    @Test("Con la protección apagada se guarda todo")
    func protectionCanBeTurnedOff() {
        // Es una opción de Preferencias: si el usuario la apaga, manda él.
        #expect(ClipboardStore.route(types: Self.dictado, bundleID: "com.1password.1password",
                                     ignoreConfidential: false) == .normal)
    }

    @Test("Sin saber de qué app viene, se mira cómo está marcado")
    func unknownApp() {
        #expect(ClipboardStore.route(types: [], bundleID: nil, ignoreConfidential: true) == .normal)
        #expect(ClipboardStore.route(types: Self.dictado, bundleID: nil,
                                     ignoreConfidential: true) == .privateClip)
    }

    @Test("La lista de gestores no tiene entradas repetidas ni vacías")
    func confidentialListIsSane() {
        #expect(!ClipboardStore.confidentialApps.contains(""))
        #expect(ClipboardStore.confidentialApps.count > 5)
        #expect(ClipboardStore.privateTypes.contains("org.nspasteboard.ConcealedType"))
    }

    // MARK: - La ventana de restauración

    @Test("Si el portapapeles vuelve enseguida a lo anterior, era un pegado temporal")
    func restorationIsRecognized() {
        // Es lo que hace un dictado: guarda tu portapapeles, pega su texto y lo
        // devuelve. Ese recorte sí se guarda.
        let visto = Date()
        #expect(ClipboardStore.isRestoration(restoresTo: "abc", seenAt: visto,
                                             digest: "abc", now: visto + 0.5))
    }

    @Test("Si tarda demasiado en volver, el recorte se pierde")
    func lateRestorationIsIgnored() {
        let visto = Date()
        #expect(!ClipboardStore.isRestoration(restoresTo: "abc", seenAt: visto,
                                              digest: "abc", now: visto + 5))
    }

    @Test("Si el portapapeles pasa a otra cosa, no era una restauración")
    func differentContentIsNotRestoration() {
        let visto = Date()
        #expect(!ClipboardStore.isRestoration(restoresTo: "abc", seenAt: visto,
                                              digest: "otra-cosa", now: visto + 0.2))
    }

    @Test("El primer recorte de la sesión no restaura nada")
    func nothingToRestoreTo() {
        // Sin recorte anterior no hay a qué volver: una contraseña copiada nada
        // más abrir la app no se guarda por descarte.
        let visto = Date()
        #expect(!ClipboardStore.isRestoration(restoresTo: nil, seenAt: visto,
                                              digest: "abc", now: visto + 0.2))
    }

    @Test("Justo en el límite de la ventana ya no cuenta")
    func exactlyAtTheWindow() {
        let visto = Date()
        #expect(!ClipboardStore.isRestoration(restoresTo: "abc", seenAt: visto, digest: "abc",
                                              now: visto + ClipboardStore.restoreWindow))
    }

    // MARK: - Huella del contenido

    @Test("La huella es estable y corta")
    func digestIsStable() {
        // Identifica el recorte, evita duplicados y da nombre al PNG en disco:
        // si cambiara, se perderían las imágenes guardadas y la deduplicación.
        let huella = ClipboardStore.digest(of: Data("hola".utf8))
        #expect(huella == ClipboardStore.digest(of: Data("hola".utf8)))
        #expect(huella.count == 24)
        #expect(huella.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("Contenidos distintos dan huellas distintas")
    func digestSeparatesContent() {
        #expect(ClipboardStore.digest(of: Data("hola".utf8))
                != ClipboardStore.digest(of: Data("Hola".utf8)))
    }
}
