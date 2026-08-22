# Cómo seguir en otro chat

Documento de traspaso. Abre un chat nuevo con este repo como carpeta de trabajo y pega
el bloque de "Prompt de arranque" del final.

## Estado actual

Funciona y compila limpio (Swift 6.3, `swift build -c release`, sin warnings).
macOS 26.6, Apple Silicon.

**Verificado a mano:** captura de texto / imágenes / archivos, deduplicación, orden,
anclados, tope de recortes, persistencia en JSON compacto, UTF-8 (acentos, kanji, emoji),
registro del atajo global.

**NO verificado:** el aspecto del panel. La sesión donde se escribió no tenía permiso de
Grabación de Pantalla, así que **nunca se vio la UI renderizada**. Lo primero que conviene
hacer es abrirla con `⌥⌘V` y ajustar tamaños, espaciados y colores a ojo.

## Por qué es un proyecto aparte

Nació como una pestaña dentro de `island_effect` (una app de notch tipo Dynamic Island).
Se separó porque son cosas distintas y se estorbaban. **El código del portapapeles ya se
quitó por completo de `island_effect`** — ese proyecto quedó como estaba antes. No mezclar.

## Arquitectura

Un solo target SwiftPM, sin dependencias. `LSUIElement`, vive en la barra de menús.

| Archivo | Qué hace |
|---|---|
| `main.swift` | arranque, `NSApplication` en modo `.accessory` |
| `AppDelegate.swift` | ítem de la barra de menús, ventana de Preferencias, primera ejecución |
| `Prefs.swift` | preferencias en `UserDefaults` + `ClipDebug` |
| `ClipboardStore.swift` | el modelo: vigila `NSPasteboard`, deduplica, persiste |
| `PanelController.swift` | la ventana flotante: posición, foco, teclado, arrastre |
| `ClipboardPanelView.swift` | la UI SwiftUI del panel |
| `CaretLocator.swift` | API de Accesibilidad para ubicar el cursor de texto |
| `HotKey.swift` | atajo global (Carbon `RegisterEventHotKey`) + `Paster` (⌘V sintético) |
| `SettingsView.swift` | Preferencias + capturador de atajos + ítem de inicio |
| `tools/MakeIcon.swift` | dibuja el icono sin recursos externos |

### Detalles que importan

- **Captura**: `Timer` cada 0.35 s comparando `NSPasteboard.general.changeCount`. No hay API
  de notificación en macOS; el sondeo es la forma estándar.
- **Prioridad al leer**: archivos → imagen → texto. El Finder deja un string junto a las URLs,
  por eso los archivos van primero.
- **Deduplicación** por `digest` (SHA-256 truncado a 12 bytes). El `digest` es también el `id`.
- **Al escribir en el portapapeles** se actualiza `lastChangeCount` para no re-capturar lo propio.
- **Foco**: al abrir se guarda `NSWorkspace.shared.frontmostApplication`, se activa la app y el
  panel se hace key. Al cerrar se le devuelve el foco a la app anterior y recién ahí, 0.14 s
  después, se manda el `⌘V`. Sin ese orden el paste llega a la ventana equivocada.
- **Teclado**: `NSEvent.addLocalMonitorForEvents` en `PanelController.handleKey`, que devuelve
  `true` si consumió la tecla. Devuelve `false` para que lo demás llegue al buscador.
- **Arrastre**: `WindowDragArea` (NSViewRepresentable) de fondo en la cabecera, llama a
  `performDrag`. `NSWindow.didMoveNotification` guarda la posición; el flag `isPositioning`
  evita guardar el reposicionamiento automático de la apertura.

## Deviaciones deliberadas respecto de Windows

- Atajo `⌥⌘V` en vez de `⊞`+`V`. Ojo: en el Finder `⌥⌘V` es "Mover ítem aquí" y el atajo
  global lo eclipsa. Se cambia en Preferencias.
- Windows borra el historial al reiniciar y sólo conserva lo anclado. Acá se guarda todo
  por omisión (`keepHistoryOnRestart`), porque se pidió que quedara en el JSON.
- No hay pestañas de emoji / GIF / kaomoji / símbolos.
- No hay sincronización entre equipos. Es a propósito: todo local.

## Pendientes / ideas

1. **Mirar la UI y ajustarla.** Es lo primero.
2. Recortes de texto enormes inflan el `history.json`. Falta un tope (¿no persistir sobre
   256 KB y mantenerlos sólo en memoria?).
3. No conserva formato: todo se guarda y se pega como texto plano. Faltaría RTF/HTML con un
   "Pegar como texto sin formato" en el menú de la tarjeta.
4. Lista de apps excluidas fija en `ClipboardStore.confidentialApps`; falta UI para editarla.
5. Sin `NSWindow` de vista previa para imágenes grandes (hoy se recortan a 76 pt de alto).
6. Firma ad-hoc ⇒ Accesibilidad se vuelve a pedir en cada rebuild. Con un certificado de
   desarrollador se arregla.
7. Sin tests. `ClipboardStore` es `@MainActor` y toca `NSPasteboard` real; habría que
   inyectar el pasteboard para poder testear la deduplicación y el `trim`.

## Cómo probar

```bash
./build.sh --run                      # compila, relanza y deja corriendo
CLIP_DEBUG=1 ./build/Portapapeles.app/Contents/MacOS/Portapapeles   # con log en stderr
```

Para probar la captura desde la terminal, **usa `LANG`** o los acentos llegan mal
(es un defecto de `pbcopy`, no de la app):

```bash
printf 'más, ñoño, 日本語' | LANG=en_US.UTF-8 pbcopy
```

Estado guardado:

```bash
cat ~/Library/Application\ Support/Portapapeles/history.json
defaults read com.j0kz.Portapapeles
```

Para empezar de cero:

```bash
rm -rf ~/Library/Application\ Support/Portapapeles
defaults delete com.j0kz.Portapapeles
```

## Prompt de arranque para el chat nuevo

> Este repo es Simple Clipboard, una app nativa de macOS que replica el historial del
> portapapeles de Windows (⊞+V). Lee `CONTINUAR.md` y `README.md` antes de tocar nada.
> Compila con `./build.sh --run`. Lo primero que quiero es abrir el panel con ⌥⌘V y
> ajustar la UI, porque nunca se vio renderizada.
