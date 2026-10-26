#ifndef PayloadDir
  #error PayloadDir must point to the staged Windows package
#endif
#ifndef OutputDir
  #error OutputDir must point to the installer output directory
#endif
#ifndef BuildVersion
  #define BuildVersion "0.1.0.0"
#endif

[Setup]
AppId={{E483DC89-9A5F-4DB3-9AC0-8D25F257B304}
AppName=LemmingsStudio Developer Preview
AppVersion={#BuildVersion}
AppPublisher=KiwiSingh
AppPublisherURL=https://github.com/KiwiSingh/LemmingsStudio
AppSupportURL=https://github.com/KiwiSingh/LemmingsStudio/issues
DefaultDirName={localappdata}\Programs\LemmingsStudioPreview
DefaultGroupName=LemmingsStudio Developer Preview
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.22000
WizardStyle=modern
WizardSizePercent=110
DisableWelcomePage=no
InfoBeforeFile={#PayloadDir}\PREVIEW.txt
OutputDir={#OutputDir}
OutputBaseFilename=LemmingsStudio-Developer-Preview-{#BuildVersion}-Windows-x64-Setup
Compression=lzma2/fast
SolidCompression=yes
UninstallDisplayIcon={app}\LemmingsStudio Native Preview.exe
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Types]
Name: "full"; Description: "Application and preview devices"
Name: "compact"; Description: "Application only"
Name: "custom"; Description: "Choose components"; Flags: iscustom

[Components]
Name: "app"; Description: "LemmingsStudio application, diagnostics and source"; Types: full compact custom; Flags: fixed
Name: "devices"; Description: "Amp, guitar and drum preview devices (no sound packs)"; Types: full

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\App\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: app
Source: "{#PayloadDir}\Diagnostics\*"; DestDir: "{app}\Diagnostics"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: app
Source: "{#PayloadDir}\Devices\*"; DestDir: "{app}\Devices"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: devices
Source: "{#PayloadDir}\Licenses\*"; DestDir: "{app}\Licenses"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: app
Source: "{#PayloadDir}\Source\*"; DestDir: "{app}\Source"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: app
Source: "{#PayloadDir}\PREVIEW.txt"; DestDir: "{app}"; Flags: ignoreversion; Components: app
Source: "{#PayloadDir}\build-manifest.json"; DestDir: "{app}"; Flags: ignoreversion; Components: app

[Icons]
Name: "{group}\LemmingsStudio Developer Preview"; Filename: "{app}\LemmingsStudio Native Preview.exe"; WorkingDir: "{app}"
Name: "{group}\Preview information"; Filename: "{app}\PREVIEW.txt"
Name: "{group}\Uninstall LemmingsStudio Developer Preview"; Filename: "{uninstallexe}"
Name: "{userdesktop}\LemmingsStudio Developer Preview"; Filename: "{app}\LemmingsStudio Native Preview.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\LemmingsStudio Native Preview.exe"; Description: "Launch LemmingsStudio Developer Preview"; Flags: nowait postinstall skipifsilent
