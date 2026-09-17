import Foundation
import Testing
@testable import PortapapelesKit

/// Pruebas de la selección dentro del panel: la lista que se ve es la filtrada,
/// no el historial entero, y es ahí donde se mueve la selección.
@MainActor
struct SelectionTests {

    private static func item(_ text: String, pinned: Bool = false,
                             secondsAgo: TimeInterval = 0) -> ClipItem {
        ClipItem(kind: .text, text: text, date: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
                 pinned: pinned, digest: text)
    }

    /// Un historial de mentira: no lee ni escribe el del usuario.
    private static func store(_ textos: [String]) -> ClipboardStore {
        ClipboardStore(sample: textos.enumerated().map { item($1, secondsAgo: TimeInterval($0)) })
    }

    @Test("Bajar y subir recorre la lista")
    func moving() {
        let store = Self.store(["uno", "dos", "tres"])
        store.move(by: 1)
        #expect(store.selection == 1)
        store.move(by: -1)
        #expect(store.selection == 0)
    }

    @Test("La lista da la vuelta por los dos extremos")
    func movingWraps() {
        let store = Self.store(["uno", "dos", "tres"])
        store.move(by: -1)
        #expect(store.selection == 2)     // desde el primero hacia arriba
        store.move(by: 1)
        #expect(store.selection == 0)     // y desde el último hacia abajo
    }

    @Test("Un salto más largo que la lista no se sale del rango")
    func bigJumpsStayInRange() {
        // `%` en Swift devuelve negativo con operandos negativos: sin la doble
        // vuelta, la selección se iba fuera de la lista.
        let store = Self.store(["uno", "dos", "tres"])
        store.move(by: -10)
        #expect(store.selection >= 0)
        #expect(store.selection < 3)
        store.move(by: 25)
        #expect(store.selection >= 0)
        #expect(store.selection < 3)
    }

    @Test("Con la lista vacía moverse no hace nada")
    func movingOnEmptyList() {
        let store = Self.store([])
        store.move(by: 1)
        #expect(store.selection == 0)
    }

    @Test("Moverse con el teclado sí desplaza la lista")
    func keyboardMovementScrolls() {
        // El hover no debe desplazar; solo el teclado centra la tarjeta.
        let store = Self.store(["uno", "dos"])
        store.selectionCameFromKeyboard = false
        store.move(by: 1)
        #expect(store.selectionCameFromKeyboard)
    }

    @Test("La selección se ajusta si la lista se acorta")
    func clampSelection() {
        let store = Self.store(["uno", "dos", "tres"])
        store.selection = 2
        store.query = "uno"          // ahora solo queda uno visible
        store.clampSelection()
        #expect(store.selection == 0)
    }

    @Test("Sin resultados la selección se va al principio")
    func clampWithNoResults() {
        let store = Self.store(["uno", "dos"])
        store.selection = 1
        store.query = "no existe"
        store.clampSelection()
        #expect(store.selection == 0)
    }

    @Test("Lo seleccionado sale de la lista filtrada, no del historial entero")
    func selectedItemFollowsTheFilter() {
        let store = Self.store(["manzana", "pera", "membrillo"])
        store.query = "m"
        store.selection = 1
        #expect(store.selectedItem?.text == "membrillo")
    }

    @Test("Una selección fuera de rango no devuelve nada")
    func selectedItemOutOfRange() {
        let store = Self.store(["uno"])
        store.selection = 5
        #expect(store.selectedItem == nil)
    }

    @Test("Con el historial vacío no hay nada seleccionado")
    func selectedItemOnEmptyList() {
        #expect(Self.store([]).selectedItem == nil)
    }
}

/// Huecos de la presentación de un recorte que no cubrían los tests anteriores.
struct ClipItemDetailTests {

    @Test("La fecha guardada se redondea al segundo")
    func dateIsTruncatedToSeconds() throws {
        // El historial guarda segundos enteros para pesar menos: el recorte que
        // vuelve del disco no es idéntico al original, y conviene tenerlo claro.
        let original = ClipItem(kind: .text, text: "hola", date: Date(timeIntervalSince1970: 1_700_000_000.75),
                                digest: "abc")
        let vuelto = try JSONDecoder().decode(ClipItem.self, from: JSONEncoder().encode(original))
        #expect(vuelto.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(vuelto.text == original.text)
    }

    @Test("Un historial de una versión anterior se lee igual")
    func legacyJSONDecodes() throws {
        // Sin la marca de anclado: antes no existía.
        let json = #"{"k":"t","t":"hola","d":1700000000,"g":"abc"}"#
        let item = try JSONDecoder().decode(ClipItem.self, from: Data(json.utf8))
        #expect(item.text == "hola")
        #expect(!item.pinned)
        #expect(item.appName == nil)
    }

    @Test("Un historial corrupto no se acepta a medias")
    func brokenJSONThrows() {
        let json = #"{"k":"z","t":"hola","d":1700000000,"g":"abc"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ClipItem.self, from: Data(json.utf8))
        }
    }

    @Test("Una imagen se describe con su tamaño")
    func imageBody() {
        let conTamaño = ClipItem(kind: .image, text: "800 × 600", date: Date(), digest: "i")
        let sinTamaño = ClipItem(kind: .image, text: "", date: Date(), digest: "i")
        #expect(conTamaño.body.contains("800 × 600"))
        #expect(!sinTamaño.body.isEmpty)
        #expect(conTamaño.symbol == "photo")
    }

    @Test("Las rutas con espacios se separan bien")
    func filePathsWithSpaces() {
        let item = ClipItem(kind: .files, text: "/tmp/mi archivo.txt\n/tmp/otro.pdf",
                            date: Date(), digest: "f")
        #expect(item.urls.map(\.lastPathComponent) == ["mi archivo.txt", "otro.pdf"])
        #expect(item.symbol == "doc.on.doc")
    }

    @Test("Un recorte de texto no tiene rutas")
    func textHasNoURLs() {
        #expect(ClipItem(kind: .text, text: "/tmp/algo", date: Date(), digest: "t").urls.isEmpty)
    }
}
