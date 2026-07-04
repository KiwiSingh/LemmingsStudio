# LemmingsStudio Windows — buildfix208 (Claude): auto-install Ollama (like macOS)

macOS bootstraps Ollama with `brew install ollama`. This adds the Windows equivalent so the
app can set Ollama up for the user with one click.

## `OllamaClient.InstallAsync` (new)
1. **winget first** — `winget install --id Ollama.Ollama -e --silent
   --accept-package-agreements --accept-source-agreements` (per-user, the clean noob path;
   handles download, install and PATH).
2. **Direct-download fallback** — if winget is missing/fails, downloads the official
   `OllamaSetup.exe` (using a system-proxy HttpClient for the external URL) and runs it
   `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES`.
3. Then polls the REST port (the Windows installer starts the server itself), nudging
   `ollama serve` if needed. Returns true once 127.0.0.1:11434 answers.

## AI tab wiring
- New **Install Ollama** button.
- **Check Server** now *auto-offers* installation (Yes/No) when Ollama isn't found — the
  "automagic" parity with macOS. Progress streams to the status line and Log tab.

## Notes
- winget ships on Windows 10 2004+/11, so most users get the clean path; the installer
  download is the safety net.
- The official installer auto-starts the Ollama tray server, so models work immediately
  after install without restarting LemmingsStudio.
- Authored on Linux without the .NET toolchain — brace-balanced, standard HttpClient/Process
  APIs; expect at most minor fixups on first Windows build.
