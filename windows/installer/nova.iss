; NOVA PC app installer (owner decision 2026-10-29): Inno Setup 6, per-user,
; no administrator rights, no code-signing certificate (Windows SmartScreen
; warns once: "More info" > "Run anyway").
;
; Built by .github/workflows/pc-app-windows.yml after `flutter build windows
; --release`:
;   iscc /DAppVersion=0.5.1+19 /DFileVersion=0.5.1-19 /DNumericVersion=0.5.1.19
;        /DWebView2Bootstrapper=<path to MicrosoftEdgeWebview2Setup.exe>
;        windows\installer\nova.iss
;
; Silent mode (the app's own updater, docs/pc-app-windows.md):
;   NOVA-Setup-X.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS
; closes NOVA, replaces it and starts it again.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef FileVersion
  #define FileVersion AppVersion
#endif
#ifndef NumericVersion
  #define NumericVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\windows\installer"
#endif

#define AppExe "nova.exe"
; Also in lib/core/push/windows_push_platform.dart: Windows links the
; notifications to the Start menu shortcut through it.
#define AppUserModelId "NovaElearning.NOVA"

[Setup]
; Never change AppId: it is how Windows knows a new installer updates NOVA.
AppId={{A379F5E4-77B7-4700-8774-7A3B08C9E09A}
AppName=NOVA
AppVersion={#AppVersion}
AppVerName=NOVA {#AppVersion}
AppPublisher=NOVA e-learning
AppPublisherURL=https://nova-elearning.com
AppSupportURL=https://nova-elearning.com
AppUpdatesURL=https://nova-elearning.com
VersionInfoVersion={#NumericVersion}
VersionInfoProductName=NOVA
; Per user: %LOCALAPPDATA%\Programs\NOVA, no UAC prompt.
PrivilegesRequired=lowest
DefaultDirName={autopf}\NOVA
DisableDirPage=yes
DefaultGroupName=NOVA
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 10 and 11.
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=NOVA-Setup-{#FileVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=NOVA
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; A running NOVA is closed before its files are replaced (updates).
CloseApplications=force
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef WebView2Bootstrapper
; Microsoft's Evergreen WebView2 bootstrapper (1-2 MB), run only on a PC
; without the WebView2 Runtime (already part of Windows 11 and updated
; Windows 10). The NOVA player needs it.
Source: "{#WebView2Bootstrapper}"; DestDir: "{tmp}"; DestName: "MicrosoftEdgeWebview2Setup.exe"; Flags: deleteafterinstall; Check: NeedsWebView2
#endif

[Icons]
Name: "{autoprograms}\NOVA"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelId}"
Name: "{autodesktop}\NOVA"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon; AppUserModelID: "{#AppUserModelId}"

[Run]
#ifdef WebView2Bootstrapper
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "WebView2 Runtime..."; Flags: waituntilterminated; Check: NeedsWebView2
#endif
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,NOVA}"; Flags: nowait postinstall skipifsilent
; An update installed silently by NOVA itself starts NOVA again.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: WizardSilent

[UninstallDelete]
; The player's WebView2 data (its cache; the sign-in is kept elsewhere).
Type: filesandordirs; Name: "{localappdata}\NOVA\WebView2"

[Code]
const
  WebView2Client = 'Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

// Microsoft's documented check: the Evergreen Runtime's "pv" value, per
// machine (32-bit registry view) or per user.
function WebView2Installed(const Root: Integer; const Key: String): Boolean;
var
  Version: String;
begin
  Result := RegQueryStringValue(Root, Key, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0');
end;

function NeedsWebView2(): Boolean;
begin
  Result := not (WebView2Installed(HKLM32, 'SOFTWARE\' + WebView2Client) or
                 WebView2Installed(HKCU, 'Software\' + WebView2Client));
end;
