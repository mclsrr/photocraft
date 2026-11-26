<#
.SYNOPSIS
  Compila PhotoCraft en modo release y genera el instalador dist\Setup_PhotoCraft.exe.

.DESCRIPTION
  1. Comprueba Rust (rustup), las Build Tools de Visual Studio (C++), CMake e Inno Setup 6; con
     -InstallTools instala con winget lo que falte.
  2. cargo build --release de photocraft y photocraft-cli (runtime de C estático: sin DLL).
  3. Prepara dist\stage (PhotoCraft.exe, CLI, icono .psd, licencias) y ejecuta ISCC sobre
     installer\PhotoCraft.iss con la versión y el editor de Cargo.toml.
  4. Copia el instalador también a setup\ para tenerlo a mano.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File build_installer.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File build_installer.ps1 -InstallTools
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File build_installer.ps1 -SkipBuild   # solo reempaqueta
#>
param(
  [switch] $InstallTools,
  [switch] $SkipBuild,
  [switch] $NoHeif
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
Set-Location $Root

function Step([string] $Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Invoke-Checked([string] $What, [scriptblock] $Block) {
  & $Block
  if ($LASTEXITCODE -ne 0) { throw "$What falló (código $LASTEXITCODE)" }
}

# --- Herramientas -------------------------------------------------------------------------------
# PATH recién leído del registro (lo que winget acaba de instalar), más Rust y CMake donde winget
# los deja aunque no los añada al PATH (el zip de CMake va a WinGet\Packages).
function Update-ToolPath {
  $paths = @("$env:USERPROFILE\.cargo\bin", "$env:ProgramFiles\CMake\bin")
  $paths += Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Kitware.CMake*" -Recurse -Filter cmake.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 | ForEach-Object { $_.DirectoryName }
  $paths += [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = ($paths | Where-Object { $_ }) -join ';'
}
Update-ToolPath
function Find-Iscc {
  foreach ($p in "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") {
    if (Test-Path $p) { return $p }
  }
  return $null
}
function Test-VcTools {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) { return $false }
  return [bool](& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
}
$missing = @()
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { $missing += 'Rustlang.Rustup' }
if (-not (Test-VcTools)) { $missing += 'Microsoft.VisualStudio.2022.BuildTools' }
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { $missing += 'Kitware.CMake' }
if (-not (Find-Iscc)) { $missing += 'JRSoftware.InnoSetup' }
if ($missing) {
  if (-not $InstallTools) { throw "Faltan herramientas: $($missing -join ', '). Vuelve a ejecutar con -InstallTools para instalarlas con winget." }
  foreach ($id in $missing) {
    Step "Instalando $id"
    $extra = @()
    if ($id -like '*BuildTools') { $extra = @('--override', '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621') }
    winget install --id $id -e --accept-package-agreements --accept-source-agreements @extra
  }
  Update-ToolPath
}
$Iscc = Find-Iscc
if (-not $Iscc) { throw 'No se encontró ISCC.exe (Inno Setup 6).' }

# --- Versión y editor desde Cargo.toml ------------------------------------------------------------
function Read-TomlValue([string] $Section, [string] $Key) {
  $in = $false
  foreach ($line in Get-Content (Join-Path $Root 'Cargo.toml')) {
    if ($line -match '^\s*\[') { $in = ($line.Trim() -eq "[$Section]"); continue }
    if ($in -and $line -match "^\s*$Key\s*=\s*`"([^`"]+)`"") { return $Matches[1] }
  }
  throw "No se encontró $Key en [$Section] de Cargo.toml"
}
$Version = Read-TomlValue 'workspace.package' 'version'
$Publisher = Read-TomlValue 'workspace.metadata.installer' 'publisher'
$Url = Read-TomlValue 'workspace.metadata.installer' 'url'
Write-Host "PhotoCraft $Version — $Publisher"

# --- Compilación ----------------------------------------------------------------------------------
$Target = 'x86_64-pc-windows-msvc'
$TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $Root 'target' }
$Bin = Join-Path $TargetDir "$Target\release"
if (-not $SkipBuild) {
  if (-not (Test-Path (Join-Path $Root 'recursos\iconos\PhotoCraft.ico'))) {
    Step 'Generando iconos'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'recursos\generar_iconos.ps1')
  }
  Step "cargo build --release ($Target)"
  $env:PHOTOCRAFT_BUILD_CHANNEL = 'stable'
  $env:PHOTOCRAFT_REQUIRE_WINRES = '1'
  if (-not $env:PHOTOCRAFT_BUILD_DATE) { $env:PHOTOCRAFT_BUILD_DATE = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
  # Runtime de C estático: el instalador no necesita el redistribuible de Visual C++.
  $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS = '-C target-feature=+crt-static'
  $features = if ($NoHeif) { @() } else { @('--features', 'heif') }
  Invoke-Checked 'cargo build' { cargo build --release --locked -p photocraft -p photocraft-cli @features --target $Target }
}
foreach ($exe in 'photocraft.exe', 'photocraft-cli.exe') {
  if (-not (Test-Path (Join-Path $Bin $exe))) { throw "No está ${Bin}\${exe}: compila primero (sin -SkipBuild)." }
}

# --- Preparación ----------------------------------------------------------------------------------
Step 'Preparando dist\stage'
$Stage = Join-Path $Root 'dist\stage'
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force $Stage | Out-Null
Copy-Item (Join-Path $Bin 'photocraft.exe') (Join-Path $Stage 'PhotoCraft.exe')
Copy-Item (Join-Path $Bin 'photocraft-cli.exe') $Stage
Copy-Item (Join-Path $Root 'recursos\iconos\PhotoCraft-PSD.ico') $Stage
foreach ($f in 'LICENSE-MIT', 'LICENSE-APACHE', 'NOTICE', 'ATTRIBUTION.md') { Copy-Item (Join-Path $Root $f) $Stage }
# Página de licencia del asistente: las dos licencias del proyecto (MIT o Apache-2.0, a elegir).
$license = "PhotoCraft se distribuye bajo la licencia MIT o la licencia Apache 2.0, a tu elección.`r`n" +
  "PhotoCraft is licensed under either the MIT license or the Apache License 2.0, at your option.`r`n`r`n" +
  "==================== MIT ====================`r`n`r`n" + (Get-Content (Join-Path $Root 'LICENSE-MIT') -Raw) +
  "`r`n`r`n==================== Apache-2.0 ====================`r`n`r`n" + (Get-Content (Join-Path $Root 'LICENSE-APACHE') -Raw)
[IO.File]::WriteAllText((Join-Path $Stage 'LICENSE.txt'), $license, [Text.UTF8Encoding]::new($true))

# --- Instalador -----------------------------------------------------------------------------------
Step 'ISCC installer\PhotoCraft.iss'
Invoke-Checked 'ISCC' { & $Iscc /Qp "/DAppVersion=$Version" "/DAppPublisher=$Publisher" "/DAppUrl=$Url" "/DStageDir=$Stage" (Join-Path $Root 'installer\PhotoCraft.iss') }
$Setup = Join-Path $Root 'dist\Setup_PhotoCraft.exe'
$SetupDir = Join-Path $Root 'setup'
New-Item -ItemType Directory -Force $SetupDir | Out-Null
Copy-Item $Setup $SetupDir -Force
$size = [Math]::Round((Get-Item $Setup).Length / 1MB, 1)
Write-Host "Listo: $Setup ($size MB), copia en setup\Setup_PhotoCraft.exe" -ForegroundColor Green
