#define MyAppName "LemmingsStudio"
#define MyAppPublisher "MagmaVance LLC"
#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#ifndef Backend
  #define Backend "directml"
#endif
#ifndef Runtime
  #define Runtime "win-x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\artifacts\publish-win-x64-directml"
#endif
#ifndef OutputDir
  #define OutputDir "..\artifacts\installer"
#endif

[Setup]
AppId={{7C497365-B7B3-4C6B-B15E-A09B940D0F01}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\LemmingsStudio
DefaultGroupName=LemmingsStudio
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename=LemmingsStudio-{#AppVersion}-{#Runtime}-{#Backend}-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\LemmingsStudio.exe
VersionInfoVersion=2.0.0.0
VersionInfoCompany=MagmaVance LLC
VersionInfoDescription=LemmingsStudio Windows beta installer
VersionInfoProductName=LemmingsStudio

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "backendsetup"; Description: "Open backend setup after installation"; GroupDescription: "First-run setup:"; Flags: checkedonce

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\LemmingsStudio"; Filename: "{app}\LemmingsStudio.exe"
Name: "{group}\Backend Setup"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\setup-backend.ps1"" -Backend ""{#Backend}"" -Runtime ""{#Runtime}"""; WorkingDir: "{app}\scripts"
Name: "{commondesktop}\LemmingsStudio"; Filename: "{app}\LemmingsStudio.exe"; Tasks: desktopicon


[Code]
function BundledVCRedistExists(): Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\redist\vc_redist.x64.exe'));
end;

[Run]
Filename: "{app}\redist\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Description: "Install Microsoft Visual C++ runtime required by PyTorch/Demucs"; Flags: runhidden waituntilterminated skipifsilent; Check: BundledVCRedistExists
Filename: "{app}\LemmingsStudio.exe"; Description: "Launch LemmingsStudio"; Flags: nowait postinstall skipifsilent
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\setup-backend.ps1"" -Backend ""{#Backend}"" -Runtime ""{#Runtime}"""; Description: "Install / repair LemmingsStudio backend now"; Flags: postinstall skipifsilent; Tasks: backendsetup
