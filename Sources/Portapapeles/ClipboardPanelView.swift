import SwiftUI
import AppKit

/// El panel, calcado del Win+V: cabecera, buscador y tarjetas. Clic en una y se pega.
struct ClipboardPanelView: View {
    @ObservedObject private var store = ClipboardStore.shared
    @ObservedObject private var prefs = Prefs.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            Divider().opacity(0.5)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focusSearch() }
        .onChange(of: store.presentationID) { _, _ in focusSearch() }
        .onChange(of: store.query) { _, _ in store.selection = 0 }
    }

    private func focusSearch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 6) {
            // Sin `allowsHitTesting(false)` el icono y el título se comen el clic y el
            // arrastre solo funcionaba agarrando el hueco de al lado — justo el sitio
            // donde nadie agarra una ventana.
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
                .allowsHitTesting(false)
            Text("Clipboard")
                .font(.system(size: 12, weight: .semibold))
                .allowsHitTesting(false)
            Spacer(minLength: 0)
            Menu {
                Button("Clear all") { withAnimation { store.clear() } }
                    .disabled(store.items.allSatisfy { $0.pinned })
                if prefs.hasPanelPosition {
                    Button("Reset position") { prefs.forgetPanelPosition() }
                }
                Divider()
                Button("Settings…") { AppDelegate.shared?.showSettings() }
                Button("Quit Clipboard") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .help("More options")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // Toda la cabecera es el asa: se arrastra el panel y queda donde lo dejes.
        .background(WindowDragArea())
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($searchFocused)
                .onSubmit { if let item = store.selectedItem { store.use(item) } }
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.7)
        )
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        let items = store.visibleItems
        if items.isEmpty {
            empty
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipCard(item: item, selected: index == store.selection)
                                .id(item.id)
                                .onHover {
                                    guard $0, PanelController.shared.hoverCanSelect else { return }
                                    store.selectionCameFromKeyboard = false
                                    store.selection = index
                                }
                                .onTapGesture { store.use(item) }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: store.selection) { _, _ in
                    // Solo el teclado desplaza: ver `selectionCameFromKeyboard`.
                    guard store.selectionCameFromKeyboard, let id = store.selectedItem?.id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: store.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 26, weight: .thin))
                .foregroundStyle(.tertiary)
            Text(store.query.isEmpty ? LocalizedStringKey("Copy something to see it here")
                                         : LocalizedStringKey("No results"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if store.query.isEmpty {
                Text("Text, images and files will show up in this list")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tarjeta

struct ClipCard: View {
    let item: ClipItem
    let selected: Bool
    @ObservedObject private var store = ClipboardStore.shared
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                preview
                Spacer(minLength: 0)
                controls
            }
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(item.subtitle)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering || selected ? 1 : 0.7))
                // La seleccionada se tiñe además del acento: el borde solo no se lee de un vistazo.
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(selected ? 0.14 : 0))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: selected ? 1.6 : 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Paste") { store.use(item) }
            Button("Copy only") { store.writeToPasteboard(item) }
            if item.isLink, let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Button("Open link") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button(item.pinned ? LocalizedStringKey("Unpin") : LocalizedStringKey("Pin")) { store.togglePin(item) }
            Button("Delete", role: .destructive) { store.remove(item) }
            Button("Clear all") { store.clear() }
        }
        .help(item.oneLine)
        .animation(.easeOut(duration: 0.1), value: hovering)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let image = store.image(for: item) {
                // Miniatura que ocupa todo el ancho de la tarjeta, recortada como en Win+V.
                // Con `.fit` alineado a la izquierda quedaba media tarjeta vacía.
                Color.clear
                    .frame(height: 76)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Text(item.body).font(.system(size: 11.5))
            }
        case .files:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.urls.prefix(3), id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 16, height: 16)
                        Text(url.lastPathComponent)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                    }
                }
                if item.urls.count > 3 {
                    Text("and \(item.urls.count - 3) more")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        case .text:
            Text(item.body)
                .font(.system(size: 11.5))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(item.isLink ? Color.accentColor : Color.primary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        // Ancho fijo pase lo que pase: si los botones aparecieran y desaparecieran con el
        // hover, el texto de la tarjeta se recolocaría y la fila daría un salto al pasar.
        HStack(spacing: 2) {
            // Con el puntero encima manda el botón de anclar; sin él, el chincheta de estado.
            // Mostrar los dos a la vez ponía dos chinchetas seguidas en las tarjetas ancladas.
            if hovering || selected {
                iconButton(item.pinned ? "pin.slash" : "pin", help: item.pinned ? LocalizedStringKey("Unpin") : LocalizedStringKey("Pin")) {
                    withAnimation(.easeOut(duration: 0.12)) { store.togglePin(item) }
                }
                iconButton("xmark", help: "Delete") {
                    withAnimation(.easeOut(duration: 0.12)) { store.remove(item) }
                }
            } else if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 38, alignment: .trailing)
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

/// Zona por la que se arrastra la ventana, como la barra de título de Windows.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
