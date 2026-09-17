import Foundation
import Testing
@testable import PortapapelesKit

/// Pruebas de cómo se ordena, filtra y recorta el historial.
///
/// Todo se ejerce sobre las funciones puras de `ClipboardStore`, nunca sobre
/// `ClipboardStore.shared`: el singleton lee y escribe el historial de verdad en
/// Application Support, y los tests no tienen por qué tocarlo.
struct ClipboardStoreTests {

    // MARK: - Ayudantes

    private static func item(_ text: String,
                             pinned: Bool = false,
                             app: String? = nil,
                             secondsAgo: TimeInterval = 0,
                             kind: ClipKind = .text) -> ClipItem {
        ClipItem(kind: kind, text: text, appName: app,
                 date: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
                 pinned: pinned, digest: "\(kind.rawValue):\(text)")
    }

    // MARK: - Orden y filtrado

    @Test("Lo fijado va arriba y el resto por fecha")
    func visibleOrder() {
        let list = [Self.item("viejo", secondsAgo: 300),
                    Self.item("nuevo"),
                    Self.item("fijado viejo", pinned: true, secondsAgo: 900)]
        let visible = ClipboardStore.visible(list, query: "")
        #expect(visible.map(\.text) == ["fijado viejo", "nuevo", "viejo"])
    }

    @Test("El buscador ignora mayúsculas y tildes")
    func searchIgnoresAccents() {
        let list = [Self.item("Reunión del lunes"), Self.item("otra cosa")]
        #expect(ClipboardStore.visible(list, query: "reunion").map(\.text) == ["Reunión del lunes"])
        #expect(ClipboardStore.visible(list, query: "REUNIÓN").count == 1)
    }

    @Test("También se busca por el nombre de la app")
    func searchByApp() {
        let list = [Self.item("hola", app: "Safari"), Self.item("chao", app: "Mail")]
        #expect(ClipboardStore.visible(list, query: "safari").map(\.text) == ["hola"])
    }

    @Test("Una búsqueda de solo espacios no filtra nada")
    func blankQueryShowsEverything() {
        let list = [Self.item("uno"), Self.item("dos")]
        #expect(ClipboardStore.visible(list, query: "   ").count == 2)
    }

    // MARK: - Insertar

    @Test("Lo copiado entra arriba")
    func insertGoesFirst() {
        let list = [Self.item("anterior")]
        let result = ClipboardStore.inserting(Self.item("recién copiado"), into: list)
        #expect(result.map(\.text) == ["recién copiado", "anterior"])
    }

    @Test("Copiar algo repetido lo sube en vez de duplicarlo")
    func insertDeduplicates() {
        let viejo = Self.item("repetido", app: "Mail", secondsAgo: 600)
        let list = [Self.item("otra cosa"), viejo]

        let denuevo = Self.item("repetido", app: "Safari")
        let result = ClipboardStore.inserting(denuevo, into: list)

        #expect(result.count == 2)
        #expect(result.first?.text == "repetido")
        // Se queda el recorte que ya estaba, pero con la fecha y la app de ahora.
        #expect(result.first?.date == denuevo.date)
        #expect(result.first?.appName == "Safari")
    }

    @Test("Al repetir un recorte fijado, sigue fijado")
    func insertKeepsPin() {
        let list = [Self.item("importante", pinned: true, secondsAgo: 600)]
        let result = ClipboardStore.inserting(Self.item("importante"), into: list)
        #expect(result.first?.pinned == true)
    }

    // MARK: - Recorte del historial

    @Test("Pasado el límite se descartan los más viejos")
    func trimDropsOldest() {
        let list = (0..<5).map { Self.item("n\($0)", secondsAgo: TimeInterval($0)) }
        let (kept, dropped) = ClipboardStore.trimming(list, limit: 3)
        #expect(kept.map(\.text) == ["n0", "n1", "n2"])
        #expect(dropped.map(\.text) == ["n3", "n4"])
    }

    @Test("Lo fijado nunca se descarta ni ocupa cupo")
    func trimIgnoresPinned() {
        let list = [Self.item("fijado", pinned: true),
                    Self.item("a"), Self.item("b"), Self.item("c")]
        let (kept, dropped) = ClipboardStore.trimming(list, limit: 2)
        #expect(kept.map(\.text) == ["fijado", "a", "b"])
        #expect(dropped.map(\.text) == ["c"])
    }

    @Test("Por debajo del límite no se descarta nada")
    func trimBelowLimit() {
        let list = [Self.item("a"), Self.item("b")]
        let (kept, dropped) = ClipboardStore.trimming(list, limit: 10)
        #expect(kept.count == 2)
        #expect(dropped.isEmpty)
    }
}

/// Pruebas de cómo se presenta cada recorte en la tarjeta.
struct ClipItemTests {

    private static func text(_ value: String, app: String? = nil) -> ClipItem {
        ClipItem(kind: .text, text: value, appName: app, date: Date(), digest: value)
    }

    @Test("El texto de la tarjeta se recorta y viene sin espacios sobrantes")
    func bodyIsTrimmedAndClipped() {
        #expect(Self.text("  hola  ").body == "hola")

        let largo = String(repeating: "a", count: ClipItem.previewLimit + 500)
        #expect(Self.text(largo).body.count == ClipItem.previewLimit)
    }

    @Test("De los archivos solo se muestra el nombre")
    func filesShowNamesOnly() {
        let item = ClipItem(kind: .files, text: "/tmp/uno.txt\n/tmp/dos.pdf",
                            date: Date(), digest: "f")
        #expect(item.body == "uno.txt\ndos.pdf")
        #expect(item.urls.count == 2)
    }

    @Test("Una URL sola se reconoce como enlace")
    func linkDetection() {
        #expect(Self.text("https://ejemplo.cl/pagina").isLink)
        #expect(Self.text("https://ejemplo.cl/pagina").symbol == "link")
        // Una frase que menciona un enlace no es un enlace.
        #expect(!Self.text("mira esto https://ejemplo.cl").isLink)
        #expect(!Self.text("http://a").isLink)
        #expect(Self.text("hola").symbol == "text.alignleft")
    }

    @Test("El tooltip va en una sola línea")
    func oneLineFlattensText() {
        #expect(Self.text("uno\ndos\tt res").oneLine == "uno dos t res")
        #expect(Self.text(String(repeating: "a", count: 500)).oneLine.count == 300)
    }

    @Test("El recorte sobrevive a guardarse y volver a leerse")
    func codableRoundTrip() throws {
        let original = ClipItem(kind: .text, text: "hola", appName: "Safari",
                                date: Date(timeIntervalSince1970: 1_700_000_000),
                                pinned: true, digest: "abc")
        let data = try JSONEncoder().encode(original)
        let vuelto = try JSONDecoder().decode(ClipItem.self, from: data)
        #expect(vuelto == original)
        #expect(vuelto.id == "abc")
    }

    @Test("El historial se guarda con claves de una letra")
    func codableIsCompact() throws {
        let data = try JSONEncoder().encode(Self.text("hola"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"t\""))
        #expect(!json.contains("\"text\""))
        // `pinned` en false no se escribe, para que el JSON pese menos.
        #expect(!json.contains("\"p\""))
    }
}
