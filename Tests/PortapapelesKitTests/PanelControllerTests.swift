import AppKit
import Carbon.HIToolbox
import Testing
@testable import PortapapelesKit

/// Dónde aparece el panel. Es lo más delicado del proyecto: si sale fuera de la
/// pantalla no hay forma de recuperarlo salvo con "Restablecer posición".
struct PanelPlacementTests {

    /// Una pantalla de 1800 × 1130 con el Dock y la barra de menús descontados.
    private static let visible = CGRect(x: 0, y: 25, width: 1800, height: 1050)
    private static let panel = PanelController.panelSize     // 300 × 420
    private static let gap: CGFloat = 6

    private static func origin(anchorAt point: CGPoint) -> CGPoint {
        PanelController.origin(for: panel,
                               anchor: PanelController.mouseRect(at: point),
                               visible: visible, gap: gap)
    }

    @Test("El panel cuelga bajo el cursor de texto")
    func belowTheCaret() {
        let caret = CGRect(x: 500, y: 800, width: 1, height: 18)
        let o = PanelController.origin(for: Self.panel, anchor: caret,
                                       visible: Self.visible, gap: Self.gap)
        #expect(o.x == 500)
        #expect(o.y == 800 - Self.gap - Self.panel.height)
    }

    @Test("Si no cabe abajo, se pone encima")
    func flipsAbove() {
        // Escribiendo en la última línea de la pantalla no hay 420 pt por debajo.
        let caret = CGRect(x: 500, y: 60, width: 1, height: 18)
        let o = PanelController.origin(for: Self.panel, anchor: caret,
                                       visible: Self.visible, gap: Self.gap)
        #expect(o.y == caret.maxY + Self.gap)
    }

    @Test("Si no cabe ni arriba ni abajo, se pega al borde inferior")
    func fallsBackToTheBottom() {
        let alta = CGSize(width: 300, height: 1000)
        let caret = CGRect(x: 500, y: 300, width: 1, height: 18)
        let o = PanelController.origin(for: alta, anchor: caret,
                                       visible: Self.visible, gap: Self.gap)
        #expect(o.y == Self.visible.minY + PanelController.screenMargin)
    }

    @Test("Junto al borde derecho, el panel se recoge para caber entero")
    func staysInsideOnTheRight() {
        let o = Self.origin(anchorAt: CGPoint(x: 1795, y: 800))
        #expect(o.x + Self.panel.width <= Self.visible.maxX)
    }

    @Test("Junto al borde izquierdo, tampoco se sale")
    func staysInsideOnTheLeft() {
        let o = Self.origin(anchorAt: CGPoint(x: -50, y: 800))
        #expect(o.x >= Self.visible.minX)
    }

    @Test("En una pantalla más chica que el panel, se queda dentro igual")
    func narrowScreen() {
        // Con los topes al revés, el panel salía por la izquierda y ya no había
        // forma de agarrarlo con el ratón.
        let chica = CGRect(x: 0, y: 0, width: 200, height: 200)
        let o = PanelController.clamp(CGPoint(x: 150, y: 150), size: Self.panel, visible: chica)
        #expect(o.x >= chica.minX)
        #expect(o.y >= chica.minY)
    }

    @Test("Una posición guardada de un monitor desconectado se trae a la pantalla")
    func savedPositionIsClamped() {
        let o = PanelController.clamp(CGPoint(x: 5000, y: 4000), size: Self.panel,
                                      visible: Self.visible)
        #expect(o.x + Self.panel.width <= Self.visible.maxX)
        #expect(o.y + Self.panel.height <= Self.visible.maxY)
    }

    @Test("Una posición que ya estaba bien no se mueve")
    func goodPositionIsKept() {
        let buena = CGPoint(x: 400, y: 300)
        #expect(PanelController.clamp(buena, size: Self.panel, visible: Self.visible) == buena)
    }

    @Test("Centrado es centrado")
    func centered() {
        let o = PanelController.centered(Self.panel, in: Self.visible)
        #expect(o.x + Self.panel.width / 2 == Self.visible.midX)
        #expect(o.y + Self.panel.height / 2 == Self.visible.midY)
    }

    @Test("Sin cursor de texto se usa uno imaginario bajo el puntero")
    func mouseRect() {
        let r = PanelController.mouseRect(at: CGPoint(x: 100, y: 500))
        #expect(r.minX == 100)
        #expect(r.maxY == 500)
        #expect(r.height == 18)
    }

    @Test("El hover no manda hasta que el ratón se mueve de verdad")
    func hoverNeedsRealMovement() {
        // El panel nace bajo el puntero: sin esto, la tarjeta que queda debajo se
        // selecciona sola y el ⏎ actuaría sobre ella.
        let abrió = CGPoint(x: 100, y: 100)
        #expect(!PanelController.hoverCanSelect(now: abrió, atOpen: abrió))
        #expect(!PanelController.hoverCanSelect(now: CGPoint(x: 102, y: 100), atOpen: abrió))
        #expect(PanelController.hoverCanSelect(now: CGPoint(x: 110, y: 100), atOpen: abrió))
        #expect(PanelController.hoverCanSelect(now: CGPoint(x: 103, y: 103), atOpen: abrió))
    }
}

/// Qué hace cada tecla con el panel abierto.
struct PanelKeyTests {

    private static func action(_ keyCode: Int, command: Bool = false, shift: Bool = false,
                               queryIsEmpty: Bool = true) -> PanelController.PanelKeyAction {
        PanelController.action(keyCode: keyCode, command: command, shift: shift,
                               queryIsEmpty: queryIsEmpty)
    }

    @Test("Las flechas recorren la lista")
    func arrows() {
        #expect(Self.action(kVK_DownArrow) == .move(1))
        #expect(Self.action(kVK_UpArrow) == .move(-1))
    }

    @Test("El tabulador baja, y con mayúsculas sube")
    func tab() {
        #expect(Self.action(kVK_Tab) == .move(1))
        #expect(Self.action(kVK_Tab, shift: true) == .move(-1))
    }

    @Test("Enter pega lo seleccionado, también el del teclado numérico")
    func enter() {
        #expect(Self.action(kVK_Return) == .useSelected)
        #expect(Self.action(kVK_ANSI_KeypadEnter) == .useSelected)
    }

    @Test("Esc limpia la búsqueda antes de cerrar")
    func escape() {
        #expect(Self.action(kVK_Escape, queryIsEmpty: false) == .clearQuery)
        #expect(Self.action(kVK_Escape, queryIsEmpty: true) == .close)
    }

    @Test("Borrar exige ⌘")
    func deleteNeedsCommand() {
        // Sin ⌘, ⌫ tiene que llegar al buscador: si no, borraba el recorte en vez
        // de un carácter de lo que estabas escribiendo.
        #expect(Self.action(kVK_Delete) == .passThrough)
        #expect(Self.action(kVK_ForwardDelete) == .passThrough)
        #expect(Self.action(kVK_Delete, command: true) == .deleteSelected)
        #expect(Self.action(kVK_ForwardDelete, command: true) == .deleteSelected)
    }

    @Test("⌘P ancla y desancla")
    func togglePin() {
        #expect(Self.action(kVK_ANSI_P, command: true) == .togglePin)
        #expect(Self.action(kVK_ANSI_P) == .passThrough)     // escribir una "p"
    }

    @Test("⌘1 a ⌘9 pegan por posición")
    func digits() {
        #expect(Self.action(kVK_ANSI_1, command: true) == .pick(1))
        #expect(Self.action(kVK_ANSI_9, command: true) == .pick(9))
        // También el bloque numérico de un teclado completo.
        #expect(Self.action(kVK_ANSI_Keypad3, command: true) == .pick(3))
        #expect(Self.action(kVK_ANSI_1) == .passThrough)
    }

    @Test("Lo que se escribe llega al buscador")
    func typingPassesThrough() {
        #expect(Self.action(kVK_ANSI_A) == .passThrough)
        #expect(Self.action(kVK_Space) == .passThrough)
    }

    @Test("Los nueve dígitos están mapeados en las dos filas")
    func everyDigitIsMapped() {
        for n in 1...9 {
            let apariciones = PanelController.digitKeys.filter { $0.value == n }
            #expect(apariciones.count == 2)   // fila superior y teclado numérico
        }
    }
}
