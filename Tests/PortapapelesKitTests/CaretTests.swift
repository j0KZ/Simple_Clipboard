import AppKit
import Testing
@testable import PortapapelesKit

/// Pruebas de cómo se ubica el cursor de texto de la otra app. El resto de
/// `CaretLocator` es API de Accesibilidad y necesita permiso y una app enfocada.
struct CaretLocatorTests {

    @Test("Las coordenadas de Accesibilidad se voltean a las de la pantalla")
    func flip() {
        // Accesibilidad cuenta desde arriba; Cocoa, desde abajo. Un error aquí
        // manda el panel al borde contrario y no se ve sin un monitor delante.
        let arriba = CGRect(x: 100, y: 0, width: 1, height: 20)
        #expect(CaretLocator.flip(arriba, primaryHeight: 1000).minY == 980)

        let abajo = CGRect(x: 100, y: 980, width: 1, height: 20)
        #expect(CaretLocator.flip(abajo, primaryHeight: 1000).minY == 0)
    }

    @Test("Voltear dos veces devuelve el original")
    func flipIsReversible() {
        let r = CGRect(x: 100, y: 300, width: 1, height: 20)
        #expect(CaretLocator.flip(CaretLocator.flip(r, primaryHeight: 1000), primaryHeight: 1000) == r)
    }

    @Test("El cursor de texto manda")
    func selectionWins() {
        let cursor = CGRect(x: 200, y: 400, width: 1, height: 18)
        let control = CGRect(x: 0, y: 0, width: 500, height: 300)
        #expect(CaretLocator.normalize(selectionBounds: cursor, elementFrame: control) == cursor)
    }

    @Test("Sin cursor se usa la esquina del control enfocado")
    func fallsBackToTheElement() {
        let control = CGRect(x: 50, y: 80, width: 500, height: 300)
        let r = CaretLocator.normalize(selectionBounds: nil, elementFrame: control)
        #expect(r?.minX == 50)
        #expect(r?.minY == 80)
        #expect(r?.width == 1)
        #expect(r?.height == 24)      // un control alto no da un cursor gigante
    }

    @Test("Una medida absurda se descarta")
    func absurdBoundsAreRejected() {
        // Las apps hechas con Electron o Java a veces reportan cualquier cosa; sin
        // este filtro el panel aparecía en mitad de la nada.
        let absurdo = CGRect(x: 0, y: 0, width: 50_000, height: 50_000)
        let control = CGRect(x: 10, y: 20, width: 300, height: 100)
        let r = CaretLocator.normalize(selectionBounds: absurdo, elementFrame: control)
        #expect(r?.minX == 10)        // se cayó al control
    }

    @Test("Un cursor de altura cero tampoco vale")
    func zeroHeightIsRejected() {
        let plano = CGRect(x: 0, y: 0, width: 1, height: 0)
        #expect(CaretLocator.normalize(selectionBounds: plano, elementFrame: nil) == nil)
    }

    @Test("Sin nada que medir, no hay posición")
    func nothingToMeasure() {
        #expect(CaretLocator.normalize(selectionBounds: nil, elementFrame: nil) == nil)
    }
}

/// Pruebas de la espera antes de pegar.
struct PasterTests {

    @Test("Con el ⌥ del atajo todavía apretado hay que esperar")
    func waitsForModifiers() {
        // Si se manda el ⌘V con el ⌥ puesto, el sistema fusiona las teclas y llega
        // ⌥⌘V: el propio atajo otra vez, y el panel se reabre en vez de pegar.
        #expect(Paster.shouldDefer(held: [.option, .command], retries: 8))
        #expect(Paster.shouldDefer(held: [.control], retries: 3))
        #expect(Paster.shouldDefer(held: [.shift], retries: 1))
    }

    @Test("El ⌘ solo no cuenta: es el del propio pegado")
    func commandAloneIsFine() {
        #expect(!Paster.shouldDefer(held: [.command], retries: 8))
        #expect(!Paster.shouldDefer(held: [], retries: 8))
    }

    @Test("Agotada la espera se pega igual")
    func givesUpEventually() {
        // Mejor pegar con un modificador puesto que no pegar nunca.
        #expect(!Paster.shouldDefer(held: [.option], retries: 0))
    }
}
