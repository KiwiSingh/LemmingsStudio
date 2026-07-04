# Recording won't capture? Do this first (2 minutes)

Recording has almost certainly been failing because of **ad-hoc code signing**, not the
capture code. macOS binds microphone permission to the app's code signature; an ad-hoc
signature changes every rebuild, so the permission you granted last build no longer applies
and CoreAudio hands the app silence.

## Fix A — make permission persist (recommended, one time)
1. Open **Keychain Access ▸ Certificate Assistant ▸ Create a Certificate…**
   - Name: `LemmingsStudio Local`
   - Identity Type: **Self Signed Root**
   - Certificate Type: **Code Signing**
   - Create it (defaults are fine).
2. Rebuild with `./build.sh`. It auto-detects that cert and signs with a **stable** identity,
   so the mic grant sticks across rebuilds.
3. Launch, press Record once, **Allow** the microphone prompt. Done — it persists now.

(If you have an Apple Developer / Developer ID cert, instead run:
`LEMMINGS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh`.)

## Fix B — if a stale grant is stuck (or you stay on ad-hoc)
```
tccutil reset Microphone com.magmavance.LemmingsStudio
```
Then relaunch and Allow the prompt. On ad-hoc you may have to repeat this after each rebuild —
which is exactly why Fix A is worth the two minutes.

## Confirm it
- System Settings ▸ Privacy & Security ▸ **Microphone** → **LemmingsStudio** is ON.
- Watch the new **status bar** at the bottom of the window when you press Record. It will say
  one of:
  - "Recording…" then a real waveform grows → working.
  - "Microphone access denied…" → do Fix A/B.
  - "Recording created an empty take — discarded it. No input received from <device>…" →
    permission or wrong channel (you had **Ch 2** selected on the Revelator — try **Ch 1**).
  - "Could not bind recorder to <device> … using default input" → device resolution; pick the
    device again or use the default.

Tell me which exact line you see and I can pinpoint anything that remains.
