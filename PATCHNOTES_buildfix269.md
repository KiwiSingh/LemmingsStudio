# LemmingsStudio buildfix269 — Real visionOS MLX Runtime

Public versions remain unchanged:

- macOS v2.0
- Windows v2.0
- visionOS v1.0

## What landed

### Current MLX Swift LM 3.x integration

The visionOS XcodeGen project now declares the official `mlx-swift-lm` 3.31.4 package plus the Hugging Face downloader/tokenizer integration packages used by the current 3.x API. The target links `MLXVLM`, `MLXLMCommon`, `MLXHuggingFace`, `HuggingFace`, and `Tokenizers`.

### Real local VLM model loading

`VisionMLXLocalRuntime` now loads the selected Hugging Face MLX repository through `VLMModelFactory`, keeps one loaded model container alive for repeated inference, tracks the active repository, and supports explicit unload/release.

The runtime model cache table remains project/UI state, while the underlying package downloader owns model snapshot caching. A model entry is marked available after a successful load.

### Multimodal project context

Local agent prompts now combine:

- user request
- Semantic Project Graph context
- Living Project Memory digest
- current allowed tool scope
- current streamed Mac Host Mode plug-in editor frame when available and screenshot context is enabled

The VLM receives the plug-in editor JPEG as image input instead of merely describing that a screenshot exists.

### Constrained tool-plan parsing

The runtime asks the model for one JSON tool-plan envelope and filters every proposed call through the lane-derived allow-list before it reaches the confirmation UI.

Supported executable tool calls currently include:

- duplicate selected clip
- move selected clip
- track volume
- track pan
- delay mix
- reverb mix
- spatial-object nudging
- Splice search
- project-state explanation/no-op reasoning

Unknown tools are discarded. Numeric arguments are clamped to safe host ranges.

### Confirmation gates

When a tool plan is returned, the runtime enters `Awaiting Confirmation`. The user can:

- Confirm & Execute
- Reject

Confirmed actions are executed by LemmingsStudio code, not by the model directly. Rejections and confirmed runs are written into Living Project Memory.

### Runtime lifecycle

The MLX window now exposes:

- model selection
- memory-budget target
- max output tokens
- model load
- model unload
- real local agent run
- cancellation
- optional unload-after-generation
- raw response inspection
- agent lane selection
- context and confirmation safety toggles

Load and generation work are tracked by cancellable Swift Tasks. The runtime checks cancellation during model loading and generation, and model unload releases the retained container reference.

## Validation

- Whole visionOS Swift tree parser validation passed in the available environment.
- `build-visionos.sh` shell syntax validation passed.
- Public version metadata remains macOS/Windows v2.0 and visionOS v1.0.
- Full package resolution, model download, Metal execution, Xcode build, thermal behavior, and real Vision Pro inference still require macOS/Xcode and Vision Pro hardware.

## Next for full macOS parity

1. buildfix270 — staged Wine ARM64 runtime bring-up, loader/JIT/mmap diagnostics, first ARM64 Windows executable and VST3 probe, DSP callback transport, and editor surface experiments.
2. buildfix271 — final macOS-vs-visionOS parity audit, Xcode compile fixes, Vision Pro and Mac Host Mode latency tests, automation/recording stress tests, memory/thermal profiling, and release packaging.
