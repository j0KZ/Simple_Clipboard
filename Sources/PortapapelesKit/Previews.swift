#if DEBUG
import SwiftUI

/// Recortes de mentira para las previews. Nunca se lee el historial real.
@MainActor
private enum Sample {
    static func item(_ kind: ClipKind, _ text: String, app: String,
                     minutesAgo: Double, pinned: Bool = false) -> ClipItem {
        ClipItem(kind: kind, text: text, appName: app,
                 date: Date(timeIntervalSinceNow: -minutesAgo * 60),
                 pinned: pinned, digest: text)
    }

    static let items: [ClipItem] = [
        item(.text, "Acuérdate de mandar el informe antes del viernes", app: "Mail", minutesAgo: 2),
        item(.text, "https://developer.apple.com/documentation/swiftui", app: "Safari", minutesAgo: 8),
        item(.files, "/Users/yo/Documentos/contrato.pdf\n/Users/yo/Documentos/anexo.pdf",
             app: "Finder", minutesAgo: 20),
        item(.text, "git rebase -i origin/main", app: "Terminal", minutesAgo: 45, pinned: true),
        item(.text, "Un párrafo largo de ejemplo para ver cómo corta la tarjeta cuando el "
             + "recorte no cabe en las tres líneas que pinta la lista del panel.",
             app: "Notas", minutesAgo: 90)
    ]

    static var store: ClipboardStore { ClipboardStore(sample: items) }
}

#Preview("Panel") {
    ClipboardPanelView(store: Sample.store)
        .frame(width: PanelController.panelSize.width, height: PanelController.panelSize.height)
        .background(.regularMaterial)
}

#Preview("Panel · buscando") {
    let store = Sample.store
    store.query = "pdf"
    return ClipboardPanelView(store: store)
        .frame(width: PanelController.panelSize.width, height: PanelController.panelSize.height)
        .background(.regularMaterial)
}

#Preview("Panel · vacío") {
    ClipboardPanelView(store: ClipboardStore(sample: []))
        .frame(width: PanelController.panelSize.width, height: PanelController.panelSize.height)
        .background(.regularMaterial)
}

#Preview("Tarjetas") {
    VStack(spacing: 6) {
        ClipCard(item: Sample.items[0], selected: false)
        ClipCard(item: Sample.items[1], selected: true)   // seleccionada: enlace
        ClipCard(item: Sample.items[2], selected: false)  // archivos
        ClipCard(item: Sample.items[3], selected: false)  // fijada
    }
    .padding(8)
    .frame(width: PanelController.panelSize.width)
    .background(.regularMaterial)
}

#Preview("Preferencias") {
    SettingsView()
}
#endif
