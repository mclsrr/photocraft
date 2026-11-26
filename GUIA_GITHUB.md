> Resumen y atajo: `Documentos\Design System\LEEME.md` y `publicar_version.ps1` (publica una versión con un comando). Los repositorios ya están creados; los pasos 1 a 4 quedan como referencia.

# Guía: tus apps en GitHub y el launcher Design System

Cómo funciona, en una frase: **cada app vive en su propio repositorio de GitHub**
(`mclsrr/photocraft`, `mclsrr/otraapp`…), y cada vez que publicas una versión nueva (un *tag*
`v1.2.3`), GitHub la compila y la sube como *release*. **Design System** (`mclsrr/design-system`)
lee esas releases: instala las apps con un clic, avisa de las actualizaciones y también se
actualiza a sí mismo cuando publicas una versión nueva del launcher.

```
mclsrr/design-system  ──release──▶  design-system-<v>-windows-x64.msi   (lo que la gente descarga)
mclsrr/photocraft     ──release──▶  photocraft-<v>-windows-x64.msi      (lo que el launcher instala)
                                    Setup_PhotoCraft.exe                (instalador suelto, opcional)
mclsrr/<otra app>     ──release──▶  <id>-<v>-windows-x64.msi
```

Carpetas en tu PC:

| Carpeta | Repositorio |
|---|---|
| `Documentos\Design System\apps\photocraft` | `mclsrr/photocraft` |
| `Documentos\Design System\launcher` | `mclsrr/design-system` (el launcher) |

Los dos repositorios deben ser **públicos**: el launcher descarga las releases sin iniciar sesión.

---

## 1. Instalar Git y GitHub CLI (una vez)

```powershell
winget install --id Git.Git -e
```
```powershell
winget install --id GitHub.cli -e
```

Cierra y vuelve a abrir PowerShell, y entra en tu cuenta:

```powershell
gh auth login
```
(elige GitHub.com › HTTPS › *Login with a web browser*).

```powershell
git config --global user.name "mclsrr"
```
```powershell
git config --global user.email "TU_CORREO_DE_GITHUB"
```

## 2. Subir PhotoCraft (una vez)

```powershell
cd "$HOME\Documents\Design System\apps\photocraft"
```
```powershell
git init -b main; git add -A; git commit -m "PhotoCraft (mclsrr): ventana flotante, lápiz, instalador"
```
```powershell
gh repo create mclsrr/photocraft --public --source . --push
```

`.gitignore` deja fuera `target\`, `dist\`, `setup\` (los binarios los compila GitHub) e
`iconos\` (los logotipos de Adobe no deben publicarse).

**Workflows heredados de ArtCraft.** El repositorio trae los workflows originales de ArtCraft
(`ci.yml`, `release.yml`, `nightly*.yml`…). Necesitan las máquinas y las claves de firma de ArtCraft,
así que en tu repositorio fallarán. Desactívalos en GitHub › tu repositorio › **Actions** › elige
cada workflow › menú **⋯** › **Disable workflow**. Deja activo solo **Release (Windows)**
(`release-windows.yml`), que es el tuyo. (No los he borrado del código: desactivarlos es decisión
tuya.)

## 3. Publicar la primera versión de PhotoCraft

La versión sale de `Cargo.toml` (`[workspace.package] version`, ahora `0.23.1`). El tag debe
coincidir, con una `v` delante:

```powershell
git tag v0.23.1; git push origin v0.23.1
```

En GitHub › **Actions** verás *Release (Windows)* compilando (tarda entre 30 y 60 minutos). Al
terminar, en **Releases** estarán `photocraft-0.23.1-windows-x64.msi`, el `.zip` portable,
`Setup_PhotoCraft.exe` y `SHA256SUMS.txt`.

## 4. Subir y publicar el launcher (una vez)

```powershell
cd "$HOME\Documents\Design System\launcher"
```
```powershell
git init -b main; git add -A; git commit -m "Design System: launcher de mclsrr"
```
```powershell
gh repo create mclsrr/design-system --public --source . --push
```

Desactiva también aquí los workflows heredados (todos menos **Release (Windows)**) y publica:

```powershell
git tag v0.20.2; git push origin v0.20.2
```

(`0.20.2` es la versión de `Cargo.toml` del launcher; el tag tiene que coincidir.)

**El enlace que compartes** para descargar el launcher es siempre el mismo:
`https://github.com/mclsrr/design-system/releases/latest`, y desde ahí el archivo
`design-system-<versión>-windows-x64.msi`. Se instala sin permisos de administrador, abre
Design System, y en él aparece PhotoCraft con su botón **Instalar**.

## 5. Actualizar una app (lo de siempre)

1. Cambia el código en `Documentos\Design System\apps\photocraft`.
2. Sube la versión en `Cargo.toml` (`0.23.1` → `0.23.2`).
3. Publica:
   ```powershell
   git add -A; git commit -m "Lo que cambiaste"; git push
   ```
   ```powershell
   git tag v0.23.2; git push origin v0.23.2
   ```

Cuando GitHub termina la release, Design System muestra **Actualizar** junto a PhotoCraft (revisa
GitHub cada hora; el botón de recargar lo comprueba al momento). PhotoCraft también avisa desde
*Ayuda › Buscar actualizaciones*, porque ahora mira `mclsrr/photocraft`.

## 6. Actualizar el launcher

Igual que una app, en `design-system`: sube `version` en su `Cargo.toml`, commit, y tag
`v<versión>`. Los launchers instalados se actualizan solos al detectar la release nueva.

## 7. Añadir otra app al launcher

Las apps de ArtCraft (VectorCraft, FilmCraft, DesignCraft, WordCraft…) tienen la misma estructura
que PhotoCraft, así que el proceso es igual:

1. **Código.** Descarga la app (por ejemplo `https://github.com/storytold/vectorcraft` › *Code* ›
   *Download ZIP*), descomprímela en `Documentos\Design System\apps\vectorcraft` y haz tus cambios.
2. **Workflow.** Copia `apps\pdfcraft\.github\workflows\release-windows.yml` a
   `vectorcraft\.github\workflows\` y cambia `Setup_PhotoCraft.exe`/`build_installer.ps1` por lo
   que tenga esa app. Si no quieres un instalador suelto, borra el paso *Inno Setup installer* y la
   línea `$files += Get-Item dist\Setup_PhotoCraft.exe`: el launcher solo necesita el `.msi` y
   `SHA256SUMS.txt`, que salen de su `packaging\windows\package.ps1`.
3. **Repositorio.** Como en el paso 2: `git init`, `gh repo create mclsrr/vectorcraft --public
   --source . --push`, desactiva los workflows heredados y publica un tag `v<versión>`.
4. **Catálogo del launcher.** En `design-system\crates\core\catalog.toml` copia el bloque
   `[[apps]]` de PhotoCraft y cambia `id`, `name`, `tagline`, colores, `repo = "mclsrr/vectorcraft"`,
   `site` y los textos de `[apps.details]`. Si el `id` es de una app de ArtCraft, su icono ya está en
   `assets\app-icons\`. Si es una app nueva, pon allí su `<id>.png` de 128 px.
5. **Publica el launcher** (paso 6). Todos los launchers instalados se actualizan y muestran la app
   nueva.

`msi_publisher` del catálogo es el *Manufacturer* que pone el MSI de esa app. Las apps de ArtCraft
usan `Learning Machines LLC` en su `packaging\windows\*.wxs`; si lo cambias allí, cámbialo también
en el catálogo.

## Notas

- **Sin firma de código.** Las releases no están firmadas (no hay certificado), así que Windows
  SmartScreen puede avisar la primera vez: *Más información › Ejecutar de todas formas*. Un
  certificado de firma de código lo evita; los scripts `sign.ps1` lo usan si configuras sus
  secretos.
- **Límite de GitHub.** Sin iniciar sesión, GitHub permite unas 60 consultas por hora y por red.
  El launcher lo tiene en cuenta (usa rutas que no gastan cuota y espera si hace falta).
- **Probar antes de publicar.** `build_installer.ps1` (en `apps\photocraft`) compila y genera
  `Setup_PhotoCraft.exe` en tu PC sin tocar GitHub.
