<#
.SYNOPSIS
  Genera los iconos de PhotoCraft para Windows (.ico multitamaño), Linux (.png) y macOS (.icns).

.DESCRIPTION
  Lee cualquier imagen que Windows sepa decodificar (PNG, JPG, BMP, GIF, TIFF, ICO, WebP con la
  extensión WebP de Windows) y detecta su formato real por los primeros bytes, no por la extensión.
  Una imagen que no sea cuadrada se centra en un lienzo cuadrado transparente; una menor de 256 px
  se amplía. En ambos casos el script avisa.

  Sin parámetros usa los originales PNG e ICO de Design System en assets/app-icon.

  Salida: recursos/iconos/ (no toca los originales).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File recursos\generar_iconos.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File recursos\generar_iconos.ps1 -IconoApp iconos\mi_icono.png -IconoPsd iconos\mi_psd.png
#>
param(
  [string] $IconoApp = '',
  [string] $IconoPsd = '',
  [string] $Nombre = 'PhotoCraft'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $PSScriptRoot 'iconos'
New-Item -ItemType Directory -Force $Out | Out-Null
$useAppMaster = -not $IconoApp
$useDocMaster = -not $IconoPsd
if ($useDocMaster) { $IconoPsd = Join-Path $Root 'assets\app-icon\photocraft-document.png' }
if (-not $IconoApp) { $IconoApp = Join-Path $Root 'assets\app-icon\hicolor\512x512\apps\ai.storyteller.photocraft.png' }

function Get-RealFormat([string] $Path) {
  $b = [IO.File]::ReadAllBytes($Path)
  if ($b.Length -ge 12 -and [Text.Encoding]::ASCII.GetString($b, 0, 4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($b, 8, 4) -eq 'WEBP') { return 'webp' }
  if ($b.Length -ge 8 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'png' }
  if ($b.Length -ge 3 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF) { return 'jpg' }
  if ($b.Length -ge 4 -and $b[0] -eq 0 -and $b[1] -eq 0 -and $b[2] -eq 1 -and $b[3] -eq 0) { return 'ico' }
  if ($b.Length -ge 4 -and [Text.Encoding]::ASCII.GetString($b, 0, 4) -eq 'icns') { return 'icns' }
  if ($b.Length -ge 2 -and [Text.Encoding]::ASCII.GetString($b, 0, 2) -eq 'BM') { return 'bmp' }
  if ($b.Length -ge 3 -and [Text.Encoding]::ASCII.GetString($b, 0, 3) -eq 'GIF') { return 'gif' }
  $head = [Text.Encoding]::UTF8.GetString($b, 0, [Math]::Min(512, $b.Length))
  if ($head -match '<svg') { return 'svg' }
  return 'desconocido'
}

# Carga una imagen como BitmapSource (la mayor si es un .ico con varias).
function Read-Image([string] $Path) {
  $fmt = Get-RealFormat $Path
  Write-Host "  $([IO.Path]::GetFileName($Path)): formato real = $fmt"
  if ($fmt -in 'svg', 'icns') { throw "Formato $fmt no soportado por este script: expórtalo a PNG de 512 px o más." }
  $dec = [Windows.Media.Imaging.BitmapDecoder]::Create([Uri](Resolve-Path $Path).Path, 'None', 'OnLoad')
  $frame = $dec.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
  return [Windows.Media.Imaging.FormatConvertedBitmap]::new($frame, [Windows.Media.PixelFormats]::Pbgra32, $null, 0)
}

# Dibuja con un DrawingContext en un lienzo cuadrado transparente de $Size px.
function New-Canvas([int] $Size, [scriptblock] $Draw) {
  $visual = [Windows.Media.DrawingVisual]::new()
  [Windows.Media.RenderOptions]::SetBitmapScalingMode($visual, 'HighQuality')
  $dc = $visual.RenderOpen()
  & $Draw $dc $Size
  $dc.Close()
  $bmp = [Windows.Media.Imaging.RenderTargetBitmap]::new($Size, $Size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
  $bmp.Render($visual)
  return $bmp
}

# Centra la imagen en un cuadrado transparente (sin deformarla) y avisa si hizo falta.
function ConvertTo-Square($Img, [string] $Label) {
  $w = $Img.PixelWidth; $h = $Img.PixelHeight
  if ($w -ne $h) { Write-Warning "$Label no es cuadrado ($w x $h): se centra en un lienzo cuadrado transparente." }
  if ([Math]::Max($w, $h) -lt 256) { Write-Warning "$Label es pequeño ($w x $h): los tamaños grandes se verán borrosos." }
  $side = [Math]::Max($w, $h)
  return New-Canvas $side {
    param($dc, $s)
    $dc.DrawImage($Img, [Windows.Rect]::new(($s - $w) / 2, ($s - $h) / 2, $w, $h))
  }
}

function Resize($Img, [int] $Size) {
  return New-Canvas $Size { param($dc, $s) $dc.DrawImage($Img, [Windows.Rect]::new(0, 0, $s, $s)) }
}

function Get-PngBytes($Img) {
  $enc = [Windows.Media.Imaging.PngBitmapEncoder]::new()
  $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Img))
  $ms = [IO.MemoryStream]::new()
  $enc.Save($ms)
  return $ms.ToArray()
}

# .ico con una entrada PNG por tamaño (Windows Vista+ las lee todas).
function Write-Ico($Img, [string] $Path, [int[]] $Sizes) {
  $pngs = foreach ($s in $Sizes) { , (Get-PngBytes (Resize $Img $s)) }
  $fs = [IO.File]::Create($Path)
  $bw = [IO.BinaryWriter]::new($fs)
  $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$Sizes.Count)
  $offset = 6 + 16 * $Sizes.Count
  for ($i = 0; $i -lt $Sizes.Count; $i++) {
    $s = $Sizes[$i]; $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
  }
  foreach ($p in $pngs) { $bw.Write([byte[]]$p) }
  $bw.Close()
}

# .icns con entradas PNG (ic07 128, ic08 256, ic09 512, ic10 1024).
function Write-Icns($Img, [string] $Path) {
  $entries = @(@('ic07', 128), @('ic08', 256), @('ic09', 512), @('ic10', 1024))
  $chunks = foreach ($e in $entries) { , @($e[0], (Get-PngBytes (Resize $Img $e[1]))) }
  $total = 8; foreach ($c in $chunks) { $total += 8 + $c[1].Length }
  $fs = [IO.File]::Create($Path)
  $bw = [IO.BinaryWriter]::new($fs)
  $be = { param([uint32] $v) $b = [BitConverter]::GetBytes($v); [Array]::Reverse($b); $bw.Write($b) }
  $bw.Write([Text.Encoding]::ASCII.GetBytes('icns')); & $be $total
  foreach ($c in $chunks) { $bw.Write([Text.Encoding]::ASCII.GetBytes($c[0])); & $be (8 + $c[1].Length); $bw.Write([byte[]]$c[1]) }
  $bw.Close()
}

$IcoSizes = 16, 24, 32, 48, 64, 128, 256
Write-Host "Icono de la aplicación:"
$app = ConvertTo-Square (Read-Image $IconoApp) 'ICONO_APP'
if ($useAppMaster) { Copy-Item (Join-Path $Root 'assets\app-icon\photocraft.ico') (Join-Path $Out "$Nombre.ico") } else { Write-Ico $app (Join-Path $Out "$Nombre.ico") $IcoSizes }
foreach ($s in 16, 24, 32, 48, 64, 128, 256, 512) {
  [IO.File]::WriteAllBytes((Join-Path $Out "$Nombre-$s.png"), (Get-PngBytes (Resize $app $s)))
}
Write-Icns $app (Join-Path $Out "$Nombre.icns")

Write-Host "Icono de archivos .psd:"
$psd = ConvertTo-Square (Read-Image $IconoPsd) 'ICONO_PSD'
if ($useDocMaster) { Copy-Item (Join-Path $Root 'assets\app-icon\photocraft-document.ico') (Join-Path $Out "$Nombre-PSD.ico") } else { Write-Ico $psd (Join-Path $Out "$Nombre-PSD.ico") $IcoSizes }
[IO.File]::WriteAllBytes((Join-Path $Out "$Nombre-PSD-256.png"), (Get-PngBytes (Resize $psd 256)))

Write-Host "Listo: $Out"
Get-ChildItem $Out | Select-Object Name, Length | Format-Table -AutoSize
