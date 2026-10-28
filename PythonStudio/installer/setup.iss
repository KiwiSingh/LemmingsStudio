#ifndef BundleRoot
  #error Supply BundleRoot
#endif
#ifndef ExtraRoot
  #error Supply ExtraRoot
#endif
#ifndef OutputRoot
  #error Supply OutputRoot
#endif
#ifndef BuildVersion
  #define BuildVersion "0.1.0.0"
#endif
[Setup]
AppId={{DA561E1D-BE12-4C74-92A4-5671D020A391}
AppName=LemmingsStudio Windows Python Preview
AppVersion={#BuildVersion}
AppPublisher=KiwiSingh
AppPublisherURL=https://github.com/KiwiSingh/LemmingsStudio
AppSupportURL=https://github.com/KiwiSingh/LemmingsStudio/issues
DefaultDirName={localappdata}\Programs\LemmingsStudioPythonPreview
DefaultGroupName=LemmingsStudio Python Preview
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
; Windows 11 is the desktop target. Server 2022 is allowed for CI lifecycle checks.
MinVersion=10.0.20348
WizardStyle=modern
DisableWelcomePage=no
InfoBeforeFile={#ExtraRoot}\Preview-Information.txt
OutputDir={#OutputRoot}
OutputBaseFilename=LemmingsStudio-Windows-Python-Preview-{#BuildVersion}-Setup
Compression=lzma2/fast
SolidCompression=yes
UninstallDisplayIcon={app}\LemmingsStudio Windows Preview.exe
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
[Files]
Source: "{#BundleRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ExtraRoot}\Matching-Source.zip"; DestDir: "{app}\Source"; Flags: ignoreversion
Source: "{#ExtraRoot}\dependency-license-metadata.json"; DestDir: "{app}\Source"; Flags: ignoreversion
Source: "{#ExtraRoot}\build-manifest.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ExtraRoot}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ExtraRoot}\Preview-Information.txt"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\LemmingsStudio Python Preview"; Filename: "{app}\LemmingsStudio Windows Preview.exe"; WorkingDir: "{app}"
Name: "{group}\Preview information"; Filename: "{app}\Preview-Information.txt"
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"
Name: "{userdesktop}\LemmingsStudio Python Preview"; Filename: "{app}\LemmingsStudio Windows Preview.exe"; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{app}\LemmingsStudio Windows Preview.exe"; Description: "Launch LemmingsStudio Python Preview"; Flags: nowait postinstall skipifsilent
