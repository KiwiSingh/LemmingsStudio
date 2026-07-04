# Buildfix 214 — Inno Setup PowerShell Parameter Quote Fix

Fixes the Windows installer compile failure from Inno Setup:

```text
Mismatched or misplaced quotes on parameter "Parameters"
```

## Root cause

The `.iss` script used C-style escaped quotes inside an Inno Setup quoted string:

```iss
Parameters: "-ExecutionPolicy Bypass -File \"{app}\scripts\setup-backend.ps1\" -Backend {#Backend}"
```

Inno Setup strings do not treat `\"` as the correct way to quote nested arguments. They require doubled quotes (`""...""`) inside a quoted parameter string.

## Fix

Updated both Backend Setup shortcut and postinstall run command to use Inno-safe doubled quotes:

```iss
Parameters: "-ExecutionPolicy Bypass -File ""{app}\scripts\setup-backend.ps1"" -Backend ""{#Backend}"""
```

This preserves paths with spaces, including install paths and local source folders such as `ls204 2`.

## Changed files

- `Ports/Windows/installer/LemmingsStudio.iss`
