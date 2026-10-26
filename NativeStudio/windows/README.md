# Windows preview setup wizard

Inno Setup 6.5.4 builds a self-contained, per-user Windows 11 x64 setup executable.
It provides a modern wizard, component selection, Start menu shortcuts, an optional
desktop shortcut, launch on completion, upgrade in place and an Apps uninstall entry.
It neither requires administrator rights nor changes an external DAW's configuration.
The application uses a static MSVC runtime; the installed application does not invoke
PowerShell or unpack ZIP files at first launch.

The `Windows preview setup wizard` workflow packages the artifact from an explicitly
selected Actions run. It requires that run's Windows native job to have passed and
checks out the exact source revision. It may package a good native build even if the
separate VoxGarden job in the same run failed. VoxGarden is deliberately excluded.
The initial push build uses run `40242042735`; a manual dispatch can select a newer
run after the workflow is available on the repository's default branch.

The full component option includes the three existing native device prototypes in
`Devices/`, with VST3 bundles and standalone applications. Sample packs are absent.
Configure a host's search path manually if it supports custom VST3 locations; this
per-user preview does not install into the system-wide Common Files VST3 folder.

## Build locally

Use Windows x64, PowerShell 7, Git and Inno Setup 6.5.4. Supply an extracted
`native-preview-windows-2022` artifact and a clean checkout of its exact commit:

```powershell
./NativeStudio/windows/build-installer.ps1 `
  -BuildRoot C:/build/artifacts -SourceRoot C:/build/exact-source `
  -StageRoot C:/build/new-stage -OutputRoot C:/build/setup `
  -SourceRun 40242042735 -BuildVersion 0.1.0.1
./NativeStudio/windows/test-installer.ps1 `
  -Installer C:/build/setup/LemmingsStudio-Developer-Preview-0.1.0.1-Windows-x64-Setup.exe `
  -TestRoot C:/build/new-install-test
```

The builder rejects missing files and non-AMD64 PE files. It bundles the matching
native source, full pinned JUCE source, GPL/AGPL notices, build instructions and a
SHA-256 payload manifest. The dependency archives and installer have recorded hashes.
It does not package library build intermediates, neural models or unapproved content.

The smoke test verifies payload hashes, shortcuts, per-user registration, installed
session/audio and VST3 checks, application process startup, reinstall and uninstall.
A simulated user file must survive reinstall and uninstall. There is no recursive
uninstall cleanup of user files. The smoke test only terminates the process it starts.

The output is an unsigned internal preview. Interactive wizard appearance, a clean
VM install, live audio, reboot behavior, recovery from an interrupted upgrade and
release signing remain separate validation gates. Keep the existing manually unpacked
preview until the wizard build is verified. It is not removed automatically.
