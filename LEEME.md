# PhotoCraft: compilación, instalador y cambios locales

Esta copia de PhotoCraft (editor de imágenes en Rust, de ArtCraft) lleva cuatro cambios locales y
un instalador de Windows. La copia original está en `..\_backup_original`.

Para publicar en GitHub (`mclsrr/photocraft`) y usar el launcher **Design System**
(`..\design-system`, repositorio `mclsrr/design-system`), sigue [GUIA_GITHUB.md](GUIA_GITHUB.md).

## Instalar (usuario final)

Ejecuta `setup\Setup_PhotoCraft.exe` (es la misma copia que `dist\Setup_PhotoCraft.exe`):

1. Elige el idioma (español o inglés), acepta la licencia (MIT o Apache 2.0) y la carpeta
   (por defecto `C:\Program Files\PhotoCraft`). El asistente también ofrece instalar solo para tu
   usuario, sin permisos de administrador.
2. Opciones: icono en el escritorio y acceso en el menú Inicio (marcadas), y abrir los `.psd` con
   PhotoCraft (sin marcar, para no quitárselos a otro programa sin que lo pidas).
3. Para desinstalar: Configuración › Aplicaciones › PhotoCraft. Se borran el programa, los accesos
   y la asociación de `.psd` (el `.psd` vuelve al programa que tenía antes). Al desinstalar, el
   asistente pregunta si borrar también tus preferencias y pinceles (por defecto, no).

El programa no necesita DLL ni el redistribuible de Visual C++: el runtime de C va enlazado dentro
del ejecutable.

## Compilar y generar el instalador

```powershell
powershell -ExecutionPolicy Bypass -File build_installer.ps1 -InstallTools
```

- `-InstallTools` instala con `winget` lo que falte: Rust (rustup; la versión exacta la fija
  `rust-toolchain.toml`), Visual Studio Build Tools con C++, CMake e Inno Setup 6.
- El script ejecuta `cargo build --release` de `photocraft` y `photocraft-cli` (con `--features heif`,
  como las versiones oficiales; `-NoHeif` lo quita), prepara `dist\stage`, ejecuta `ISCC` sobre
  `installer\PhotoCraft.iss` y deja `dist\Setup_PhotoCraft.exe` (con una copia en `setup\`).
- `-SkipBuild` solo vuelve a empaquetar los binarios ya compilados.
- La versión del instalador sale de `[workspace.package] version` y el editor y la web, de
  `[workspace.metadata.installer]`, ambos en `Cargo.toml`.
- La primera compilación release tarda bastante (LTO y `codegen-units = 1`).

Iconos: `powershell -ExecutionPolicy Bypass -File recursos\generar_iconos.ps1` regenera
`recursos\iconos\` (`.ico` de 16 a 256 px, `.png` para Linux, `.icns` para macOS, y el icono de
documento `.psd`). Acepta `-IconoApp` y `-IconoPsd` con cualquier imagen (PNG, JPG, WebP, ICO…):
detecta el formato real y, si no es cuadrada o es pequeña, la centra en un lienzo transparente y
avisa.

## Qué cambió en cada tarea

### Tarea 1: la ventana flotante queda detrás de la principal

**Causa.** *Ventana › Nueva ventana para el documento* (y *Flotar en ventana*, y los paneles
flotantes) abren un viewport de egui que winit crea como ventana de nivel superior *sin
propietario*. Para Windows es una ventana independiente, así que al hacer clic en la principal esta
pasa por delante.

**Arreglo.** Cada 250 ms, PhotoCraft busca las ventanas visibles de su propio hilo y de la misma
clase que la principal que aún no tienen propietario, y las hace *owned* por la principal
(`SetWindowLongPtrW(GWLP_HWNDPARENT)`). Una ventana owned queda siempre encima de su
propietario, se minimiza y se restaura con él, y **no** se pone por encima de otras aplicaciones ni
de la barra de tareas (no es "siempre visible"). Los diálogos del sistema (abrir archivo, etc.)
tienen otra clase y no se tocan.

- `apps/photocraft/src/window_frame.rs`: `owner_service` y `both`.
- `apps/photocraft/src/main.rs`: lo instala junto al servicio del marco de ventana.
- `crates/tablet/src/windows.rs`: `set_window_owner` (la única llamada `unsafe`; el repositorio
  solo permite `unsafe` en este módulo).

### Tarea 2: el botón del lápiz XPPen como clic derecho

**Causa.** Con Windows Ink, winit convierte la entrada del lápiz (`WM_POINTER*`) en eventos
*táctiles*, y egui emula **siempre un clic principal** para el primer contacto. El gancho de
`photocraft-tablet` ya detectaba el botón del lápiz (`PEN_FLAG_BARREL` o
`POINTER_FLAG_SECONDBUTTON`), pero solo lo guardaba: nadie lo usaba para decidir el botón. Las
demás aplicaciones de Windows reciben el clic derecho porque dejan que Windows convierta el lápiz en
ratón (barril + contacto = clic derecho); winit no lo hace.

**Arreglo.** El gancho guarda, en el propio `WM_POINTERDOWN`, si ese contacto empezó con el botón
del lápiz pulsado (así sirve aunque el toque termine antes del siguiente fotograma). Antes de cada
fotograma, la interfaz cambia el clic principal emulado de ese contacto (y su liberación) por un
clic **secundario**. El lienzo lo trata igual que el clic derecho del ratón y abre el selector de
pinceles. La punta sigue pintando; los clics reales del ratón no se tocan.

- `crates/tablet/src/windows.rs`: `CONTACT_BARREL`, `take_barrel_contact`, registro de mensajes.
- `crates/tablet/src/input_log.rs`: registro opcional (ver abajo).
- `crates/ui-egui/src/input/stylus.rs`: `BarrelPresses::rewrite` y `log_input`.
- `crates/ui-egui/src/app.rs`, `services.rs`, `lib.rs`: el servicio `pen_barrel_press`.
- `apps/photocraft/src/tablet.rs`, `main.rs`: lo conectan en Windows.
- Tests: `a_barrel_contact_outlives_its_release_and_is_read_once` (tablet) y
  `a_pen_contact_with_the_barrel_held_is_a_right_click` (ui-egui).

Si el driver de XPPen está en modo WinTab (Windows Ink desactivado), el driver mueve el cursor
como un ratón y envía el clic derecho como un `WM_RBUTTONDOWN` normal, que ya funcionaba.

### Tarea 3: iconos

- Los archivos de `iconos\` (`Icono_App.webp`, 960×936, y `PSD_file_icon.webp`, 500×615) son WebP
  no cuadrados y **son el logotipo "Ps" de Adobe Photoshop**. La propia tarea (y las reglas del
  repositorio) prohíben usar logotipos o iconos de Adobe, así que **no se han usado**. Los iconos
  generados salen del arte propio de PhotoCraft (`assets\app-icon`), y el de `.psd` es un documento
  original dibujado por el script. Si tienes iconos propios, pásalos con `-IconoApp`/`-IconoPsd`.
- `recursos\iconos\PhotoCraft.ico` es el icono del `.exe` (`build_channel.rs`), de los accesos
  directos y del instalador; `PhotoCraft-256.png` es el de la ventana (`app_icon.rs`);
  `PhotoCraft-PSD.ico` es el de los `.psd` asociados (lo pone el instalador).

### Tarea 4: nombre

El nombre visible ya era PhotoCraft (título, menús, Acerca de, `ProductName`, `FileDescription`).
Cambios: el instalador copia el ejecutable como `PhotoCraft.exe` (en Windows es el mismo archivo
que `photocraft.exe`, sin distinguir mayúsculas), `OriginalFilename = PhotoCraft.exe`, y cuatro
textos de la interfaz que nombraban Photoshop ahora usan una redacción neutra (por ejemplo, "High
Memory PSD Document"). No se cambió por "PhotoCraft", porque el texto quedaría falso: el formato
PSD no es de PhotoCraft. Los comentarios del código que citan Photoshop como referencia de
comportamiento no se tocaron. Los nombres de crates y de las API internas siguen igual.

### Tarea 5: instalador

`installer\PhotoCraft.iss` (Inno Setup 6) y `build_installer.ps1`, descritos arriba. La asociación
de `.psd` usa `HKCU\Software\Classes` (no pide administrador), guarda el programa anterior y lo
restaura al desinstalar.

## Probar el arreglo del lápiz (en el PC con la tableta)

1. En el driver de XPPen, deja el botón del lápiz como *Clic derecho* y Windows Ink activado.
2. Abre PhotoCraft con el registro activado:
   ```powershell
   $env:PHOTOCRAFT_INPUT_LOG = "1"; & "C:\Program Files\PhotoCraft\PhotoCraft.exe"
   ```
   (`1` escribe en `%TEMP%\photocraft-input.log`; cualquier otro valor es la ruta del archivo).
3. Elige el Pincel. Toca el lienzo con la punta: debe pintar. Mantén el botón del lápiz y toca:
   debe abrirse el selector de pinceles, como con el clic derecho del ratón. Prueba también el clic
   derecho de un ratón normal.
4. En el registro verás las líneas `os posted WM_POINTERDOWN … barrel=true` del lápiz y
   `ui PointerButton Secondary pressed=true`. Con el ratón verás `WM_RBUTTONDOWN`. Si con el botón
   del lápiz aparece `barrel=false` y `PointerButton Primary`, el driver no está avisando del botón
   a Windows: revisa la asignación en el driver o prueba el modo WinTab
   (Preferencias › Herramientas › Tableta).
5. El registro está desactivado por defecto; sin la variable no se escribe nada.

## Probar la ventana flotante

Abre un documento, *Ventana › Disposición › Nueva ventana para el documento*. Mueve la ventana
nueva, haz clic en la principal: la nueva debe seguir delante. Cambia a otra aplicación: esa
aplicación debe tapar a las dos. Minimiza PhotoCraft: la flotante se minimiza con él.
