import AppKit
import ApplicationServices

/// Busca dónde está el cursor de texto en la app de adelante, para abrir el panel ahí
/// (es lo que hace el Win+V de Windows). Necesita permiso de Accesibilidad.
enum CaretLocator {

    /// Rectángulo del cursor en coordenadas Cocoa (origen abajo-izquierda), o nil.
    static func caretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        guard let focused = focusedElement() else { return nil }

        guard let rect = normalize(selectionBounds: boundsOfSelection(in: focused),
                                   elementFrame: frame(of: focused)) else { return nil }
        return flip(rect)
    }

    /// Elige el rectángulo del cursor y descarta lo que no tiene sentido.
    ///
    /// Algunas apps (las hechas con Electron o Java, sobre todo) reportan medidas
    /// absurdas; sin este filtro el panel aparecía en cualquier parte. Si no hay
    /// cursor de texto se usa la esquina superior izquierda del control enfocado.
    static func normalize(selectionBounds: CGRect?, elementFrame: CGRect?) -> CGRect? {
        if let rect = selectionBounds, rect.width < 10_000, rect.height < 10_000,
           rect.width >= 0, rect.height > 0 {
            return rect
        }
        if let rect = elementFrame, rect.height > 0 {
            return CGRect(x: rect.minX, y: rect.minY, width: 1, height: min(rect.height, 24))
        }
        return nil
    }

    /// Estas consultas van a la app de delante y son síncronas sobre el hilo principal. Si esa
    /// app está ocupada o colgada, abrir el panel se quedaría esperando. Con un tope corto, en
    /// el peor caso perdemos la posición del cursor y caemos junto al puntero — que es el
    /// comportamiento sin permiso de Accesibilidad, y el panel sigue apareciendo al instante.
    /// Puesto sobre el elemento del sistema, vale como valor por omisión para todos los demás.
    private static let boundedTimeout: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }()

    private static func focusedElement() -> AXUIElement? {
        _ = boundedTimeout
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func boundsOfSelection(in element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &rangeRef) == .success, let range = rangeRef else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element,
                                                         kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &boundsRef) == .success,
              let bounds = boundsRef, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = positionRef, let s = sizeRef,
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Accesibilidad usa el origen arriba-izquierda de la pantalla principal; Cocoa, abajo-izquierda.
    private static func flip(_ rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return flip(rect, primaryHeight: primary?.frame.height ?? 0)
    }

    /// El volteo en sí. Un error aquí manda el panel al borde contrario de la
    /// pantalla, y eso no se ve sin un monitor delante.
    static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
