import AppKit
import Combine
import CryptoKit

enum ClipKind: String, Codable {
    case text = "t", image = "i", files = "f"
}

/// Un recorte. Se serializa con claves de una letra y fecha en segundos para que
/// el JSON del historial pese lo mínimo posible.
struct ClipItem: Identifiable, Codable, Equatable {
    var kind: ClipKind
    /// Texto plano, rutas separadas por salto de línea (archivos) o "800 × 600" (imagen).
    var text: String
    var imageName: String?
    var appName: String?
    var date: Date
    var pinned: Bool = false
    /// Huella del contenido: identifica el recorte y evita duplicados.
    var digest: String

    var id: String { digest }

    private enum CodingKeys: String, CodingKey {
        case kind = "k", text = "t", imageName = "m", appName = "a", date = "d", pinned = "p", digest = "g"
    }

    init(kind: ClipKind, text: String, imageName: String? = nil, appName: String? = nil,
         date: Date, pinned: Bool = false, digest: String) {
        self.kind = kind
        self.text = text
        self.imageName = imageName
        self.appName = appName
        self.date = date
        self.pinned = pinned
        self.digest = digest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(ClipKind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        imageName = try c.decodeIfPresent(String.self, forKey: .imageName)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        date = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .date))
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        digest = try c.decode(String.self, forKey: .digest)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(imageName, forKey: .imageName)
        try c.encodeIfPresent(appName, forKey: .appName)
        try c.encode(Int(date.timeIntervalSince1970), forKey: .date)
        if pinned { try c.encode(true, forKey: .pinned) }   // false no se escribe
        try c.encode(digest, forKey: .digest)
    }

    var urls: [URL] {
        guard kind == .files else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// La tarjeta solo pinta 3 líneas, pero un recorte puede pesar megas. Recortar el texto
    /// *antes* de tocarlo evita que SwiftUI mida y trocee 2 MB para mostrar 3 renglones.
    static let previewLimit = 600

    /// Texto que se muestra en la tarjeta.
    var body: String {
        switch kind {
        case .text: return String(text.prefix(Self.previewLimit))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
        case .files: return urls.map { $0.lastPathComponent }.joined(separator: "\n")
        case .image: return text.isEmpty ? L.t("Image") : String(format: L.t("Image · %@"), text)
        }
    }

    /// El buscador mira el recorte completo, pero sin fabricar una copia en minúsculas de él:
    /// `range(of:options:)` recorre en el sitio. De paso ignora tildes, así "reunion" encuentra "reunión".
    func matches(_ needle: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if text.range(of: needle, options: options) != nil { return true }
        return appName?.range(of: needle, options: options) != nil
    }

    /// Una línea, para el tooltip y la búsqueda.
    var oneLine: String {
        body.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .prefix(300)
            .description
    }

    var isLink: Bool {
        guard kind == .text else { return false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(" "), t.count > 8 else { return false }
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }

    var symbol: String {
        switch kind {
        case .text: return isLink ? "link" : "text.alignleft"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }

    var subtitle: String {
        var parts: [String] = []
        if let appName, !appName.isEmpty { parts.append(appName) }
        parts.append(ClipItem.relative.localizedString(for: date, relativeTo: Date()))
        return parts.joined(separator: " · ")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = L.locale
        f.unitsStyle = .short
        return f
    }()
}

/// Historial del portapapeles: vigila NSPasteboard, guarda lo copiado y lo vuelve a pegar.
@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipItem] = []
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Solo el teclado desplaza la lista. Si el hover también lo hiciera, al centrar la
    /// tarjeta que está bajo el puntero el contenido se movería solo, otra tarjeta quedaría
    /// debajo, y así: la lista se te escapa mientras bajas el ratón.
    @Published var selectionCameFromKeyboard = false
    /// Cambia cada vez que se abre el panel: la vista lo usa para reenfocar el buscador.
    @Published var presentationID = UUID()

    private let prefs = Prefs.shared
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    /// Con un diccionario suelto, cada imagen vista en la sesión se quedaba en RAM para siempre.
    /// `NSCache` pone techo y además suelta lo que sobra cuando el sistema aprieta.
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var saveWork: DispatchWorkItem?

    /// Apps cuyo portapapeles nunca se guarda.
    private static let confidentialApps: Set<String> = [
        "com.agilebits.onepassword7", "com.1password.1password", "com.agilebits.onepassword",
        "com.apple.keychainaccess", "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass", "in.sinew.Enpass-Desktop", "com.keepassium.mac",
        "org.keepassxc.keepassxc", "com.mackieinnovations.strongbox", "com.apple.Passwords"
    ]

    /// Tipos con los que una app pide que su copia no se registre.
    private static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword"
    ]

    private static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Portapapeles", isDirectory: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("images"),
                                                 withIntermediateDirectories: true)
        return base
    }()
    private static var historyFile: URL { dir.appendingPathComponent("history.json") }
    private static var imagesDir: URL { dir.appendingPathComponent("images", isDirectory: true) }

    private init() { load() }

    // MARK: - Vigilancia

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let types = Set((pb.types ?? []).map { $0.rawValue })
        if prefs.ignoreConfidential, !types.isDisjoint(with: Self.privateTypes) { return }

        let app = NSWorkspace.shared.frontmostApplication
        if prefs.ignoreConfidential,
           let bundle = app?.bundleIdentifier, Self.confidentialApps.contains(bundle) { return }

        guard let item = capture(from: pb, app: app) else { return }
        insert(item)
    }

    private func capture(from pb: NSPasteboard, app: NSRunningApplication?) -> ClipItem? {
        let appName = app?.localizedName

        // Archivos primero: el Finder también deja un string junto a las URLs.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map { $0.standardizedFileURL.path }.joined(separator: "\n")
            return ClipItem(kind: .files, text: paths, appName: appName,
                            date: Date(), digest: Self.digest(of: Data(paths.utf8)))
        }

        if prefs.keepImages,
           let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
           let image = NSImage(data: data) {
            let digest = Self.digest(of: data)
            let size = "\(Int(image.size.width)) × \(Int(image.size.height))"
            let name = "\(digest).png"
            let file = Self.imagesDir.appendingPathComponent(name)
            // Volver a copiar la misma imagen no reescribe el archivo: el digest ya lo identifica.
            if !FileManager.default.fileExists(atPath: file.path) {
                // Si el portapapeles ya trae PNG se guardan esos bytes; recodificar era trabajo de más.
                if let png = pb.data(forType: .png) ?? Self.pngData(from: image) {
                    try? png.write(to: file)
                }
            }
            imageCache.setObject(image, forKey: name as NSString, cost: Self.cost(of: image))
            return ClipItem(kind: .image, text: size, imageName: name,
                            appName: appName, date: Date(), digest: digest)
        }

        if let string = pb.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipItem(kind: .text, text: string, appName: appName,
                            date: Date(), digest: Self.digest(of: Data(string.utf8)))
        }

        return nil
    }

    // MARK: - Lista

    private func insert(_ item: ClipItem) {
        if let index = items.firstIndex(where: { $0.digest == item.digest }) {
            var existing = items.remove(at: index)
            existing.date = item.date
            existing.appName = item.appName
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        trim()
        scheduleSave()
        ClipDebug.log("nuevo recorte: \(item.kind.rawValue) · \(item.oneLine.prefix(40))")
    }

    private func trim() {
        let limit = max(5, Int(prefs.maxItems))
        var unpinned = 0
        var kept: [ClipItem] = []
        var dropped: [ClipItem] = []
        for item in items {
            if item.pinned {
                kept.append(item)
            } else if unpinned < limit {
                unpinned += 1
                kept.append(item)
            } else {
                dropped.append(item)
            }
        }
        guard !dropped.isEmpty else { return }
        items = kept
        dropped.forEach(deleteImageFile)
    }

    /// Fijados arriba, después por fecha. Filtrado por el buscador.
    var visibleItems: [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty ? items : items.filter { $0.matches(needle) }
        return matched.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.date > b.date
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        trim()
        scheduleSave()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        deleteImageFile(item)
        clampSelection()
        scheduleSave()
    }

    /// El "Borrar todo" de Windows: se lleva todo menos lo fijado.
    /// Para llevárselo todo, incluido lo anclado, está `purge()`.
    func clear() {
        let removed = items.filter { !$0.pinned }
        items = items.filter { $0.pinned }
        removed.forEach(deleteImageFile)
        clampSelection()
        scheduleSave()
    }

    func clampSelection() {
        let count = visibleItems.count
        selection = count == 0 ? 0 : min(max(0, selection), count - 1)
    }

    func move(by delta: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selectionCameFromKeyboard = true
        selection = (selection + delta + count) % count
    }

    var selectedItem: ClipItem? {
        let list = visibleItems
        guard list.indices.contains(selection) else { return nil }
        return list[selection]
    }

    // MARK: - Pegar

    /// Deja el recorte en el portapapeles del sistema: el ⌘V siguiente lo vuelve a pegar.
    func writeToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text:
            pb.clearContents()
            pb.setString(item.text, forType: .string)
        case .files:
            let urls = item.urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            pb.clearContents()
            if urls.isEmpty {
                pb.setString(item.text, forType: .string)
            } else {
                pb.writeObjects(urls.map { $0 as NSURL })
            }
        case .image:
            // Los bytes del PNG ya están en disco: recodificar la NSImage era trabajo de más.
            // Y si el archivo desapareció, más vale no tocar el portapapeles que vaciarlo.
            guard let name = item.imageName,
                  let png = try? Data(contentsOf: Self.imagesDir.appendingPathComponent(name)) else {
                ClipDebug.log("la imagen del recorte ya no está en disco; el portapapeles queda como estaba")
                return
            }
            pb.clearContents()
            pb.setData(png, forType: .png)
        }
        lastChangeCount = pb.changeCount

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = items.remove(at: index)
            updated.date = Date()
            items.insert(updated, at: 0)
            scheduleSave()
        }
    }

    /// Copia el recorte y cierra el panel pegándolo en la app de adelante.
    func use(_ item: ClipItem) {
        writeToPasteboard(item)
        PanelController.shared.hide(pasting: prefs.autoPaste)
    }

    // MARK: - Imágenes

    func image(for item: ClipItem) -> NSImage? {
        guard let name = item.imageName else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let image = NSImage(contentsOf: Self.imagesDir.appendingPathComponent(name)) else { return nil }
        imageCache.setObject(image, forKey: name as NSString, cost: Self.cost(of: image))
        return image
    }

    private func deleteImageFile(_ item: ClipItem) {
        guard let name = item.imageName else { return }
        imageCache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: Self.imagesDir.appendingPathComponent(name))
    }

    /// Lo que ocupa descomprimida, que es lo que de verdad pesa en RAM.
    private static func cost(of image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func digest(of data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistencia

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.save() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Un solo recorte de 2 MB inflaba el `history.json` a 2 MB y lo releía entero en cada arranque.
    /// Por encima de este tamaño el recorte vive solo en memoria — salvo que lo ancles, que es
    /// la forma de decir "este quiero conservarlo".
    private static let maxPersistedBytes = 256 * 1024

    private func save() {
        // Como en Windows: si no se guarda todo, al menos lo fijado sobrevive.
        var toSave = prefs.keepHistoryOnRestart ? items : items.filter { $0.pinned }
        toSave = toSave.filter { $0.pinned || $0.text.utf8.count <= Self.maxPersistedBytes }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(toSave) else { return }
        try? data.write(to: Self.historyFile, options: .atomic)
        pruneOrphanImages(keeping: toSave)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.historyFile) else { return }
        guard let saved = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = saved.filter { item in
            guard let name = item.imageName else { return true }
            return FileManager.default.fileExists(atPath: Self.imagesDir.appendingPathComponent(name).path)
        }
        // Si bajaste el tope entre sesiones, se aplica ya y no recién en la próxima copia.
        trim()
    }

    /// Guarda ahora mismo lo que estuviera esperando el rebote de 0,6 s.
    /// Sin esto, copiar y salir de la app enseguida perdía el último recorte.
    func flushSave() {
        guard saveWork != nil else { return }
        saveWork?.cancel()
        saveWork = nil
        save()
    }

    /// Borra del disco las imágenes que ya no referencia nadie.
    private func pruneOrphanImages(keeping list: [ClipItem]) {
        let alive = Set(items.compactMap { $0.imageName }).union(list.compactMap { $0.imageName })
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: Self.imagesDir.path) else { return }
        for file in files where !alive.contains(file) {
            try? FileManager.default.removeItem(at: Self.imagesDir.appendingPathComponent(file))
        }
    }

    func purge() {
        items = []
        imageCache.removeAllObjects()
        try? FileManager.default.removeItem(at: Self.imagesDir)
        try? FileManager.default.createDirectory(at: Self.imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: Self.historyFile)
    }
}
