# Cómo seguir en otro chat

Documento de traspaso. Abre un chat nuevo con este repo como carpeta de trabajo y pega
el bloque de "Prompt de arranque" del final.

## Estado actual

Funciona y compila limpio (Swift 6.3, `swift build -c release`, sin warnings).
**Compatibilidad:** el mínimo son macOS 14 (Sonoma) y está declarado en cuatro sitios que
hay que mantener a la vez — `Package.swift` (`.macOS(.v14)`), el `Info.plist` que genera
`build.sh` (`LSMinimumSystemVersion`), `Formula/portapapeles.rb` (`depends_on macos:`) y el
README. No hay ni un `@available` en el código: la garantía la da el compilador, que valida
todo contra el objetivo 14.0. El binario lleva `minos 14.0` grabado y no arranca por debajo.

Ojo con la diferencia entre *compila* y *probada*: **solo se ha ejecutado en macOS 26.6,
Apple Silicon.** Nadie la ha corrido en 14, 15 ni en un Intel. Como se distribuye por fuente,
cada equipo la compila para su propio procesador; el `.app` de `build/` es solo arm64.

**Verificado a mano:** captura de texto / imágenes / archivos, deduplicación, orden,
anclados, tope de recortes, persistencia en JSON compacto, UTF-8 (acentos, kanji, emoji),
registro del atajo global.

**Verificado en pantalla (22-08-2026):** el panel ya se vio renderizado —
lista, tarjeta seleccionada, miniatura de imagen, tarjeta de archivos y estado vacío.
Se corrigieron la doble chincheta, la miniatura descolgada y el tamaño del panel.

**La app es oscura siempre.** `AppDelegate` fija `NSApp.appearance = darkAqua`; no sigue
el tema del sistema. Verificado lanzando con `-AppleInterfaceStyle Light`: la apariencia
efectiva sigue siendo `NSAppearanceNameDarkAqua`. **No hay que diseñar para modo claro.**

**Probado con teclado y ratón sintéticos (22-08-2026), todo pasando:** el atajo ⌥⌘V real,
el panel abriéndose en el cursor de texto, ⏎ pegando solo en la app de destino, ⌘1–⌘9,
⌘P, ⌘⌫, ⌦ sin ⌘ (que ya no borra), el buscador —incluida la búsqueda sin tildes—, clic en
una tarjeta, arrastrar el panel por la cabecera, el menú contextual, el menú `⋯`,
"Restablecer posición", Preferencias desde el panel, el ítem de inicio de sesión, y copiar
y volver a pegar imágenes y varios archivos del Finder.

**Sigue sin verse renderizado:** "Sin resultados" (búsqueda sin coincidencias).

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
| `tools/TogglePanel.swift` | abre el panel por notificación distribuida (solo con `CLIP_DEBUG=1`) |
| `tools/ToggleSettings.swift` | lo mismo para Preferencias |
| `Formula/portapapeles.rb` | fórmula de Homebrew; compila desde el fuente en el equipo del usuario |

### Detalles que importan

- **Activación:** un `LSUIElement` no siempre logra ponerse al frente con `NSApp.activate`.
  macOS se lo concede cuando la acción viene de una interacción del usuario (clic en el ítem
  de la barra, `open` de la app), y se lo niega si nadie tocó nada — por eso los disparadores
  de `tools/` abren la ventana pero no siempre la traen al frente. No es un bug de la app.
- **Distribución por Homebrew:** fórmula, no cask, porque la app no está notarizada y una
  descarga precompilada la rechazaría Gatekeeper (`spctl -a` la da por *rejected*). Al
  compilar en el equipo del usuario no hay atributo de cuarentena y arranca sin fricción.
  La fórmula tiene que pasarle a SwiftPM `--disable-sandbox` (su sandbox no anida dentro del
  de Homebrew) y redirigir `--cache-path` / `--config-path` / `--security-path` / `--scratch-path`
  fuera de `$HOME`. `build.sh` lo recibe todo por la variable `SWIFT_BUILD_FLAGS`.
  Probado de punta a punta con un tap local: instala, `brew test` pasa y la app arranca.
- **El hover no manda hasta que el ratón se mueve** (`PanelController.hoverCanSelect`).
  El panel nace junto al cursor de texto, así que a menudo aparece bajo el puntero; sin
  esa guarda la tarjeta de debajo se seleccionaba sola y ⏎ / ⌘P / ⌘⌫ actuaban sobre ella.
- **El título de la cabecera lleva `allowsHitTesting(false)`**, si no se come el clic y el
  panel solo se podía arrastrar por el hueco de al lado.
- **Al abrir Preferencias hay que cerrar el panel con `restoringFocus: false`.** Si no, el
  panel pierde el foco, `hide()` reactiva la app anterior y ésta entierra Preferencias.

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

1. Ver renderizado el estado "Sin resultados". (La duda del menú contextual quedó
   resuelta: no cierra el panel, comprobado con clic derecho sintético.)
2. No conserva formato: todo se guarda y se pega como texto plano. Faltaría RTF/HTML con un
   "Pegar como texto sin formato" en el menú de la tarjeta.
3. Lista de apps excluidas fija en `ClipboardStore.confidentialApps`; falta UI para editarla.
   Ojo: solo cubre gestores de contraseñas, así que una contraseña copiada desde el navegador
   sí queda guardada en claro en el `history.json`.
4. Sin `NSWindow` de vista previa para imágenes grandes (hoy se recortan a 76 pt de alto).
5. Sin notarizar. No molesta compilando en local, pero cierra la puerta a distribuir un
   binario ya hecho (`spctl -a` la rechaza). Requiere cuenta de desarrollador de pago.
   Nota medida: recompilar **no** revoca Accesibilidad aunque cambie el CDHash — macOS ata
   el permiso a la ruta del bundle. Mover la app de sitio sí lo pierde.
6. Sin tests. `ClipboardStore` es `@MainActor` y toca `NSPasteboard` real; habría que
   inyectar el pasteboard para poder testear la deduplicación y el `trim`.
7. El `history.json` no está cifrado. Si eso importa, el paso siguiente es guardarlo en el
   Llavero o cifrarlo con una clave del Llavero.

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
