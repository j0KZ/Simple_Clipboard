import AppKit
import Carbon.HIToolbox
import Testing
@testable import PortapapelesKit

/// Pruebas del atajo global: cómo se guarda, cómo se lee y cómo se muestra.
struct HotKeyTests {

    @Test("El atajo de fábrica es ⌥⌘V")
    func defaultShortcut() {
        #expect(HotKeySpec.defaultShortcut.display == "⌥⌘V")
        #expect(HotKeySpec.defaultShortcut.isValid)
    }

    @Test("Los modificadores se muestran siempre en el mismo orden")
    func modifierOrder() {
        // ⌃⌥⇧⌘ es el orden de Apple; da igual cómo se guarden los bits.
        let todos = HotKeySpec(keyCode: kVK_ANSI_V,
                               modifiers: cmdKey | shiftKey | optionKey | controlKey)
        #expect(todos.display == "⌃⌥⇧⌘V")
    }

    @Test("Un atajo sin modificadores no sirve")
    func modifiersAreRequired() {
        // Sin ⌘ o similar, el atajo se comería la tecla en cualquier app.
        #expect(!HotKeySpec(keyCode: kVK_ANSI_V, modifiers: 0).isValid)
    }

    @Test("Las teclas con símbolo se muestran con su símbolo")
    func specialKeyNames() {
        #expect(HotKeySpec.name(for: kVK_Return) == "↩")
        #expect(HotKeySpec.name(for: kVK_Escape) == "⎋")
        #expect(HotKeySpec.name(for: kVK_Delete) == "⌫")
        #expect(HotKeySpec.name(for: kVK_LeftArrow) == "←")
        #expect(HotKeySpec.name(for: kVK_F5) == "F5")
    }

    @Test("Las letras y los números se muestran tal cual")
    func literalKeyNames() {
        #expect(HotKeySpec.name(for: kVK_ANSI_A) == "A")
        #expect(HotKeySpec.name(for: kVK_ANSI_7) == "7")
        #expect(HotKeySpec.name(for: kVK_ANSI_Slash) == "/")
    }

    @Test("Una tecla desconocida se muestra por su número")
    func unknownKeyName() {
        // No se queda en blanco: en Preferencias se vería un atajo vacío.
        #expect(HotKeySpec.name(for: 999).contains("999"))
    }

    @Test("Los modificadores del teclado se traducen a los de Carbon")
    func carbonModifiers() {
        #expect(HotKeySpec.carbonModifiers(from: [.command]) == cmdKey)
        #expect(HotKeySpec.carbonModifiers(from: [.command, .option]) == (cmdKey | optionKey))
        #expect(HotKeySpec.carbonModifiers(from: []) == 0)
    }

    @Test("Los modificadores que no son atajo se ignoran")
    func irrelevantModifiersAreDropped() {
        // Bloq Mayús o la tecla fn no forman parte de un atajo.
        #expect(HotKeySpec.carbonModifiers(from: [.capsLock, .function, .numericPad]) == 0)
        #expect(HotKeySpec.carbonModifiers(from: [.command, .capsLock]) == cmdKey)
    }

    @Test("Un atajo guardado se relee igual")
    func roundTrip() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let spec = HotKeySpec(keyCode: kVK_ANSI_K,
                              modifiers: HotKeySpec.carbonModifiers(from: flags))
        #expect(spec.display == "⇧⌘K")
        #expect(spec == HotKeySpec(keyCode: kVK_ANSI_K, modifiers: shiftKey | cmdKey))
    }
}

/// Dónde aparece el panel: es un `rawValue` que se guarda en preferencias, así
/// que cambiarlo perdería el ajuste de quien ya lo tenía puesto.
struct PanelAnchorTests {

    @Test("Los valores guardados no cambian")
    func rawValues() {
        #expect(PanelAnchor.caret.rawValue == "caret")
        #expect(PanelAnchor.mouse.rawValue == "mouse")
        #expect(PanelAnchor.center.rawValue == "center")
    }

    @Test("Un valor desconocido no rompe nada")
    func unknownRawValue() {
        #expect(PanelAnchor(rawValue: "loquesea") == nil)
    }
}
