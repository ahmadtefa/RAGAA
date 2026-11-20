; ============================================================================
;  RAGAA (رجاء) — Windows Installer script (Inno Setup 6+)
; ----------------------------------------------------------------------------
;  Build (from the repository root, after `flutter build windows --release`):
;      ISCC.exe installer\ragaa.iss
;  Output:
;      artifacts\RAGAA-Setup.exe
;
;  The installer ships the complete Flutter release bundle (ragaa.exe, all
;  required DLLs including sqlite3.dll, the ICU data file and the assets), so
;  the end user never needs Flutter or Visual Studio installed.
;
;  User accounting data lives outside the install directory
;  (%APPDATA%\..\RAGAA\data\ragaa_accounting.db) and is therefore preserved on
;  upgrade and on a normal uninstall.
; ============================================================================

#define AppName "RAGAA"
#define AppVersion "1.0.0"
#define AppPublisher "RAGAA"
#define AppExeName "ragaa.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{7C1D9B44-2F1E-4B6B-9F0E-5A6E1B7A3C55}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion=1.0.0.0
VersionInfoDescription=RAGAA Central Collection Accounting System (Arabic RTL)
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
; Per-user install by default -> no UAC prompt, data + install both under the user profile.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
AllowNoIcons=yes
DisableProgramGroupPage=yes
OutputDir=..\artifacts
OutputBaseFilename=RAGAA-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName} — نظام تحصيل المنافذ
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no

[Languages]
; English wizard pages only (Inno Setup does not ship an official Arabic .isl).
; The application itself is fully Arabic RTL.
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "إنشاء اختصار على سطح المكتب / Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: checkedonce

[Files]
; Every DLL, the ICU data file, the assets and the executable produced by
; `flutter build windows --release`.
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Usage notes shipped next to the executable.
Source: "..\review\README-Windows.txt"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{group}\إلغاء تثبيت {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "تشغيل RAGAA / Launch RAGAA"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Only files the installer itself created inside the install folder are removed.
; The SQLite database, backups and exports are kept on purpose:
;   %APPDATA%\..\RAGAA\data\ragaa_accounting.db
;   Documents\RAGAA\backups , Documents\RAGAA\exports
Type: filesandordirs; Name: "{app}\data"
