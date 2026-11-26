; Instalador de PhotoCraft para Windows 10/11 (Inno Setup 6).
;
; No se compila a mano: build_installer.ps1 lo llama con ISCC y le pasa
;   /DAppVersion=<[workspace.package] version de Cargo.toml>
;   /DAppPublisher=<[workspace.metadata.installer] publisher de Cargo.toml>
;   /DAppUrl=<[workspace.metadata.installer] url de Cargo.toml>
;   /DStageDir=<carpeta con PhotoCraft.exe, photocraft-cli.exe y las licencias>
; El resultado es un único dist\Setup_PhotoCraft.exe.
;
; Los binarios enlazan el runtime de C estáticamente (+crt-static), así que no hace falta
; instalar DLL ni el redistribuible de Visual C++.

#define AppName "PhotoCraft"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppPublisher
  #define AppPublisher "PhotoCraft"
#endif
#ifndef AppUrl
  #define AppUrl "https://github.com/storytold/photocraft"
#endif
#ifndef StageDir
  #define StageDir "..\dist\stage"
#endif
#define AppExe "PhotoCraft.exe"
#define PsdProgId "PhotoCraft.psd"

[Setup]
; AppId fijo: identifica la instalación para actualizar y desinstalar. No lo cambies.
AppId={{6C1E9A43-2F0B-4E5D-9A7C-3B8D41F0C2A7}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
VersionInfoCompany={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Program Files pide administrador; el asistente deja elegir "solo para mí" (sin administrador).
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile={#StageDir}\LICENSE.txt
OutputDir=..\dist
OutputBaseFilename=Setup_{#AppName}
SetupIconFile=..\recursos\iconos\PhotoCraft.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=auto

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
es.TaskDesktop=Crear un icono en el &escritorio
en.TaskDesktop=Create a &desktop shortcut
es.TaskStartMenu=Crear un acceso en el menú &Inicio
en.TaskStartMenu=Create a &Start menu shortcut
es.TaskAssocPsd=Abrir los archivos &.psd con {#AppName} (reemplaza el programa actual para .psd)
en.TaskAssocPsd=Open &.psd files with {#AppName} (replaces the current program for .psd)
es.GroupShortcuts=Accesos directos:
en.GroupShortcuts=Shortcuts:
es.GroupFiles=Archivos:
en.GroupFiles=Files:
es.PsdDescription=Documento PSD
en.PsdDescription=PSD Document
es.LaunchApp=Abrir {#AppName}
en.LaunchApp=Launch {#AppName}
es.RemoveUserData=¿Borrar también tus preferencias, pinceles y autoguardados de {#AppName}?%n%nSi vas a reinstalar, elige No para conservarlos.
en.RemoveUserData=Also delete your {#AppName} preferences, brushes and autosaves?%n%nChoose No to keep them if you will reinstall.

[Tasks]
Name: "desktopicon"; Description: "{cm:TaskDesktop}"; GroupDescription: "{cm:GroupShortcuts}"
Name: "startmenuicon"; Description: "{cm:TaskStartMenu}"; GroupDescription: "{cm:GroupShortcuts}"
; Sin marcar por defecto: no se le quita .psd a otro programa sin que el usuario lo pida.
Name: "assocpsd"; Description: "{cm:TaskAssocPsd}"; GroupDescription: "{cm:GroupFiles}"; Flags: unchecked

[Files]
Source: "{#StageDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\photocraft-cli.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\PhotoCraft-PSD.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\LICENSE-MIT"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\LICENSE-APACHE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\NOTICE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageDir}\ATTRIBUTION.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: startmenuicon
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; La asociación vive en HKCU\Software\Classes: no necesita administrador y es del usuario.
Root: HKCU; Subkey: "Software\Classes\{#PsdProgId}"; ValueType: string; ValueName: ""; ValueData: "{cm:PsdDescription}"; Flags: uninsdeletekey; Tasks: assocpsd
Root: HKCU; Subkey: "Software\Classes\{#PsdProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\PhotoCraft-PSD.ico"",0"; Tasks: assocpsd
Root: HKCU; Subkey: "Software\Classes\{#PsdProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: assocpsd
Root: HKCU; Subkey: "Software\Classes\.psd\OpenWithProgids"; ValueType: string; ValueName: "{#PsdProgId}"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assocpsd
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".psd"; ValueData: ""; Flags: uninsdeletekey; Tasks: assocpsd

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Solo lo que PhotoCraft crea junto al ejecutable (modo portable); nunca la carpeta entera, por si
; el usuario instaló en una carpeta con otros archivos.
Type: filesandordirs; Name: "{app}\PhotoCraftData"
Type: dirifempty; Name: "{app}"

[Code]
const
  PsdKey = 'Software\Classes\.psd';
  SavedKey = 'Software\{#AppName}\Installer';

{ Hace de PhotoCraft el programa predeterminado de .psd y guarda el anterior para devolverlo al
  desinstalar. Si Windows guarda una elección del usuario (UserChoice), Windows la respeta: en ese
  caso PhotoCraft queda en "Abrir con" y el usuario lo elige una vez en el diálogo de Windows. }
procedure AssociatePsd();
var
  Previous: String;
begin
  if RegQueryStringValue(HKCU, PsdKey, '', Previous) and (Previous <> '{#PsdProgId}') and (Previous <> '') then
    RegWriteStringValue(HKCU, SavedKey, 'PreviousPsdProgId', Previous);
  RegWriteStringValue(HKCU, PsdKey, '', '{#PsdProgId}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('assocpsd') then
    AssociatePsd();
end;

{ Al desinstalar, .psd vuelve al programa que tenía antes (o a ninguno). }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Current, Previous: String;
begin
  { Los datos del usuario solo se borran si lo confirma (nunca en una desinstalación silenciosa). }
  if (CurUninstallStep = usUninstall) and not UninstallSilent() then
    if MsgBox(CustomMessage('RemoveUserData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    begin
      DelTree(ExpandConstant('{userappdata}\Photocraft'), True, True, True);
      DelTree(ExpandConstant('{localappdata}\Photocraft'), True, True, True);
    end;
  if CurUninstallStep <> usPostUninstall then
    exit;
  if RegQueryStringValue(HKCU, PsdKey, '', Current) and (Current = '{#PsdProgId}') then
  begin
    if RegQueryStringValue(HKCU, SavedKey, 'PreviousPsdProgId', Previous) and (Previous <> '') then
      RegWriteStringValue(HKCU, PsdKey, '', Previous)
    else
      RegDeleteValue(HKCU, PsdKey, '');
  end;
  RegDeleteKeyIncludingSubkeys(HKCU, SavedKey);
  RegDeleteKeyIfEmpty(HKCU, 'Software\{#AppName}');
  RegDeleteKeyIfEmpty(HKCU, PsdKey + '\OpenWithProgids');
  RegDeleteKeyIfEmpty(HKCU, PsdKey);
end;
