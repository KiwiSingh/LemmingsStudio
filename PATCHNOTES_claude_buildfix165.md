# Lemmings Studio — buildfix165 (Claude): fix the pip spec quoting (one-line follow-up to 164)

buildfix164 added `soundfile` to the Demucs venv but I left the install command quoting wrong:
`pip install "$DEMUCS_PIP_SPEC"` passed `"demucs soundfile"` as a SINGLE requirement, so pip
errored: `Invalid requirement: 'demucs soundfile'`.

Fix (`build.sh`): the Demucs install now uses **unquoted** `$DEMUCS_PIP_SPEC` so the shell
word-splits it into separate package args (`demucs` + `soundfile`) — the same idiom the RVC
install already uses. (MLX's spec is a single package, so it's unchanged.)

Everything else from buildfix164 (the torchaudio→soundfile torchcodec bypass in StemSplitter)
is intact. Rebuild and the venv will install both packages; Stem Split → Auto/Demucs should
then show `[lemmings] torchaudio I/O routed through soundfile` and real per-stem progress.
