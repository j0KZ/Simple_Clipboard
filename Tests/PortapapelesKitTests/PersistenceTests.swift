import Foundation
import Testing
@testable import PortapapelesKit

/// Pruebas de qué se guarda en disco, qué sobrevive al reinicio y qué se borra.
struct PersistenceTests {

    private static func item(_ text: String, pinned: Bool = false,
                             image: String? = nil) -> ClipItem {
        ClipItem(kind: image == nil ? .text : .image, text: text, imageName: image,
                 date: Date(timeIntervalSince1970: 1_000_000), pinned: pinned, digest: text)
    }

    // MARK: - Qué llega al disco

    @Test("Con el historial desactivado solo sobrevive lo anclado")
    func onlyPinnedWhenHistoryIsOff() {
        // Como Windows: al reiniciar se limpia todo menos lo que anclaste.
        let list = [Self.item("suelto"), Self.item("anclado", pinned: true)]
        let saved = ClipboardStore.persistable(list, keepAll: false, maxBytes: 1000)
        #expect(saved.map(\.text) == ["anclado"])
    }

    @Test("Un recorte enorme no se guarda")
    func hugeClipsAreNotPersisted() {
        // Un recorte de 2 MB inflaba el historial y se releía entero en cada
        // arranque; se queda en memoria mientras la app viva.
        let grande = Self.item(String(repeating: "a", count: 5000))
        let saved = ClipboardStore.persistable([grande], keepAll: true, maxBytes: 1000)
        #expect(saved.isEmpty)
    }

    @Test("Pero si lo anclaste, se guarda aunque sea enorme")
    func pinnedHugeClipsArePersisted() {
        // Anclar es justo la forma de decir "este quiero conservarlo".
        let grande = Self.item(String(repeating: "a", count: 5000), pinned: true)
        #expect(ClipboardStore.persistable([grande], keepAll: true, maxBytes: 1000).count == 1)
    }

    @Test("El tamaño se mide en bytes, no en letras")
    func sizeIsMeasuredInBytes() {
        // Un texto de emoji ocupa cuatro veces más de lo que aparenta.
        let emoji = Self.item(String(repeating: "🎉", count: 100))   // 400 bytes
        #expect(ClipboardStore.persistable([emoji], keepAll: true, maxBytes: 200).isEmpty)
        #expect(ClipboardStore.persistable([emoji], keepAll: true, maxBytes: 500).count == 1)
    }

    @Test("El tope real de la app deja pasar un recorte corriente")
    func normalClipsFitTheRealLimit() {
        let normal = Self.item("una ruta o un párrafo cualquiera")
        #expect(ClipboardStore.persistable([normal], keepAll: true,
                                           maxBytes: ClipboardStore.maxPersistedBytes).count == 1)
    }

    // MARK: - Qué se recupera al arrancar

    @Test("Un recorte de imagen sin su archivo no vuelve")
    func imagesWithoutFileAreDropped() {
        let list = [Self.item("texto"),
                    Self.item("captura", image: "abc.png"),
                    Self.item("otra", image: "perdida.png")]
        let vivos = ClipboardStore.surviving(list) { $0 == "abc.png" }
        #expect(vivos.map(\.text) == ["texto", "captura"])
    }

    @Test("Los recortes de texto siempre vuelven")
    func textAlwaysSurvives() {
        let list = [Self.item("uno"), Self.item("dos")]
        #expect(ClipboardStore.surviving(list) { _ in false }.count == 2)
    }

    // MARK: - Limpieza de imágenes

    @Test("Se borran las imágenes que ya no usa ningún recorte")
    func orphansAreDeleted() {
        let borrables = ClipboardStore.orphans(files: ["a.png", "b.png", "c.png"],
                                               alive: ["b.png"])
        #expect(borrables.sorted() == ["a.png", "c.png"])
    }

    @Test("No se borra nada si todas siguen en uso")
    func nothingToDelete() {
        #expect(ClipboardStore.orphans(files: ["a.png"], alive: ["a.png", "b.png"]).isEmpty)
    }

    // MARK: - Tope del historial

    @Test("El tope es el de Preferencias")
    func limitComesFromPrefs() {
        #expect(ClipboardStore.effectiveLimit(25) == 25)
        #expect(ClipboardStore.effectiveLimit(300) == 300)
    }

    @Test("Un tope corrupto no deja el historial en nada")
    func limitHasAFloor() {
        // Un 0 heredado o escrito a mano dejaría de guardar recortes sin avisar.
        #expect(ClipboardStore.effectiveLimit(0) == 5)
        #expect(ClipboardStore.effectiveLimit(-10) == 5)
        #expect(ClipboardStore.effectiveLimit(2.9) == 5)
    }
}

/// Preferencias de Portapapeles: valores de fábrica y persistencia.
struct PrefsTests {

    private static func scratchDefaults() -> UserDefaults {
        let suite = "clip-tests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("Una instalación nueva trae los valores de fábrica")
    func factoryDefaults() {
        let prefs = Prefs(defaults: Self.scratchDefaults())
        #expect(prefs.maxItems == 25)
        #expect(prefs.keepHistoryOnRestart)
        #expect(prefs.keepImages)
        #expect(prefs.ignoreConfidential)      // la protección viene puesta
        #expect(prefs.autoPaste)
        #expect(prefs.anchor == .caret)
        #expect(!prefs.launchAtLogin)
        #expect(!prefs.hasPanelPosition)
        #expect(prefs.hotKey == .defaultShortcut)
    }

    @Test("Lo que se cambia sigue ahí al reabrir la app")
    func changesPersist() {
        let defaults = Self.scratchDefaults()
        let antes = Prefs(defaults: defaults)
        antes.maxItems = 120
        antes.ignoreConfidential = false
        antes.anchorRaw = PanelAnchor.center.rawValue

        let despues = Prefs(defaults: defaults)
        #expect(despues.maxItems == 120)
        #expect(!despues.ignoreConfidential)
        #expect(despues.anchor == .center)
    }

    @Test("Un ajuste de posición desconocido cae en el de fábrica")
    func unknownAnchorFallsBack() {
        let defaults = Self.scratchDefaults()
        defaults.set("desde-otra-version", forKey: "anchor")
        #expect(Prefs(defaults: defaults).anchor == .caret)
    }

    @Test("Olvidar la posición del panel lo devuelve junto al cursor")
    func forgetPanelPosition() {
        let prefs = Prefs(defaults: Self.scratchDefaults())
        prefs.rememberPanelPosition(CGPoint(x: 400, y: 300))
        #expect(prefs.hasPanelPosition)

        prefs.forgetPanelPosition()
        #expect(!prefs.hasPanelPosition)
    }
}
