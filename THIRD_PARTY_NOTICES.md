# Third-Party Notices

LemmingsStudio includes, integrates with, or provides optional setup support for third-party software, libraries, frameworks, models, and tools. This file summarizes those third-party components and their licensing/attribution status to the best of the project maintainer’s knowledge.

This notice file is informational and does not replace the license text for each dependency. Please review each upstream project’s own license before redistributing modified builds, packaged binaries, installers, model packs, or release artifacts.

## Core Runtime and Platform Components

### .NET

LemmingsStudio for Windows uses Microsoft .NET for its desktop application runtime and build tooling.

* Project: .NET
* Provider: Microsoft
* License: MIT License
* Website: https://dotnet.microsoft.com/

### Windows Forms

The Windows build uses Windows Forms as part of the .NET desktop application stack.

* Project: Windows Forms
* Provider: Microsoft
* License: MIT License
* Website: https://github.com/dotnet/winforms

### Swift / SwiftUI / AppKit

The macOS build uses Swift, SwiftUI, and AppKit APIs provided by Apple.

* Provider: Apple Inc.
* License / Terms: Apple platform SDK terms apply.
* Website: https://developer.apple.com/

### AVFoundation / CoreAudio / AudioToolbox

The macOS build uses Apple media and audio frameworks for playback, rendering, recording, plug-in hosting, and related audio workflows.

* Provider: Apple Inc.
* License / Terms: Apple platform SDK terms apply.
* Website: https://developer.apple.com/

## Audio, MIDI, and Plug-in Components

### NAudio

The Windows build uses NAudio for audio and MIDI functionality, including playback, recording, device access, WASAPI/WinMM integration, and WAV handling.

* Project: NAudio
* License: MIT License
* Website: https://github.com/naudio/NAudio

### JUCE

The Windows native VST3 helper uses JUCE as an application/audio/plugin-hosting framework.

* Project: JUCE
* Provider: Raw Material Software / PACE Anti-Piracy, Inc.
* License: JUCE is available under GPLv3 and commercial licensing options.
* Website: https://juce.com/

If LemmingsStudio is distributed under GPLv3-compatible terms, the JUCE GPLv3 option may be used where applicable. Commercial distribution or non-GPL-compatible redistribution may require a separate JUCE commercial license.

### Steinberg VST3 SDK

The Windows VST3 host helper and macOS plug-in hosting paths may interface with Steinberg VST3 plug-ins and/or VST3 SDK concepts.

* Project: VST3 SDK
* Provider: Steinberg Media Technologies GmbH
* License: Steinberg VST3 SDK license terms apply.
* Website: https://steinbergmedia.github.io/vst3_dev_portal/

VST, VST3, and related marks are trademarks of Steinberg Media Technologies GmbH. Use of VST3 support in LemmingsStudio does not imply endorsement by Steinberg.

### Carla

LemmingsStudio may optionally integrate with Carla or use Carla as an external plug-in bridge/host where available.

* Project: Carla
* Author: Filipe Coelho / falkTX
* License: GPLv2 or later, with additional licensing details in the Carla project.
* Website: https://github.com/falkTX/Carla

Carla is not required for all builds, but may be used by users as an optional bridge/host depending on their system configuration.

### Element

LemmingsStudio may optionally bridge to Element as an external plug-in host when configured by the user.

* Project: Element
* Website: https://kushview.net/element/

Users should review Element’s own licensing and distribution terms before bundling or redistributing it with LemmingsStudio.

## Media Encoding and Conversion

### FFmpeg

LemmingsStudio may use FFmpeg for media import/export workflows, including formats such as MP3, FLAC, and other encoded audio formats.

* Project: FFmpeg
* License: LGPLv2.1+ or GPLv2+, depending on build configuration and enabled codecs
* Website: https://ffmpeg.org/

Binary builds of FFmpeg can vary significantly in license obligations depending on how FFmpeg was compiled and which codecs/features are enabled. Distributors must verify the license terms of the exact FFmpeg binary they bundle.

If distributing LemmingsStudio installers with FFmpeg included, provide the appropriate FFmpeg license text and, where required, corresponding source or source-offer information for the exact FFmpeg build used.

## Machine Learning / AI / Audio Separation Components

### Python

The Windows backend setup may install or use Python for AI/audio workflows.

* Project: Python
* License: Python Software Foundation License
* Website: https://www.python.org/

### PyTorch

LemmingsStudio may use PyTorch for local machine-learning workflows, including optional audio/model features.

* Project: PyTorch
* License: BSD-style license
* Website: https://pytorch.org/

### torchaudio

LemmingsStudio may use torchaudio as part of the PyTorch audio stack.

* Project: torchaudio
* License: BSD-style license
* Website: https://pytorch.org/audio/

### TorchCodec

Some PyTorch/torchaudio versions may optionally use TorchCodec for media encoding/decoding paths.

* Project: TorchCodec
* License: BSD-style license
* Website: https://github.com/pytorch/torchcodec

TorchCodec support may be optional or bypassed depending on platform compatibility and backend configuration.

### Demucs

LemmingsStudio may optionally use Demucs for source separation / stem-splitting workflows.

* Project: Demucs
* Original Provider: Meta / Facebook Research
* License: MIT License
* Website: https://github.com/facebookresearch/demucs

Demucs model weights may have separate licensing or usage terms from the source code. Distributors should verify the license and redistribution terms for any model weights bundled with LemmingsStudio.

### NumPy

LemmingsStudio backend workflows may use NumPy.

* Project: NumPy
* License: BSD License
* Website: https://numpy.org/

### SciPy

LemmingsStudio backend workflows may use SciPy where installed by optional audio/ML dependencies.

* Project: SciPy
* License: BSD License
* Website: https://scipy.org/

### SoundFile / python-soundfile

LemmingsStudio backend workflows may use SoundFile for reading and writing audio files.

* Project: python-soundfile
* License: BSD License
* Website: https://github.com/bastibe/python-soundfile

### libsndfile

SoundFile depends on libsndfile for audio file I/O.

* Project: libsndfile
* License: LGPL
* Website: https://github.com/libsndfile/libsndfile

### soxr / python-soxr

Optional audio resampling workflows may use soxr or python-soxr.

* Project: SoX Resampler / python-soxr
* License: LGPL for libsoxr; python wrapper licensing may vary by package release
* Website: https://github.com/chirlu/soxr
* Website: https://github.com/dofuuz/python-soxr

### librosa

Optional audio analysis workflows may use librosa where supported.

* Project: librosa
* License: ISC License
* Website: https://librosa.org/

### numba

Optional audio analysis dependencies may use numba.

* Project: Numba
* License: BSD License
* Website: https://numba.pydata.org/

### llvmlite

Numba depends on llvmlite.

* Project: llvmlite
* License: BSD License
* Website: https://llvmlite.pydata.org/

## RVC / Voice and Timbre Model Support

LemmingsStudio may include experimental hooks or optional support paths for RVC-style voice/timbre conversion workflows.

RVC model files, including `.pth`, `.index`, embeddings, checkpoints, and derived voice models, may carry separate rights and consent requirements. Do not bundle, redistribute, or publish RVC model weights unless you have clear permission and the model’s license allows redistribution.

If optional RVC model packs are distributed separately, each pack should include its own:

* model source,
* author/creator attribution,
* license,
* consent/usage statement where applicable,
* redistribution permission,
* prohibited-use notes where applicable.

LemmingsStudio’s source-code license does not grant rights to third-party voice models, likenesses, performances, datasets, or training materials.

## Discord Integration

### Discord Rich Presence / Discord Game SDK

LemmingsStudio may include Discord Rich Presence integration.

* Provider: Discord Inc.
* License / Terms: Discord Developer Terms apply.
* Website: https://discord.com/developers/docs/rich-presence/overview

Discord is a trademark of Discord Inc. Use of Discord Rich Presence does not imply endorsement by Discord.

## Splice Integration

LemmingsStudio may include experimental Splice-related workflows, sample workflow helpers, or user-configurable integration points.

* Provider: Splice
* Website: https://splice.com/

Splice, Splice Sounds, and related marks are owned by Splice. Users are responsible for complying with Splice’s terms of service and licensing rules for any samples, loops, sounds, or content they access or use.

LemmingsStudio does not grant rights to redistribute Splice content. Any exported or published work using Splice samples must comply with Splice’s applicable license terms.

## Apple Platform Distribution Notes

macOS builds may use Apple platform APIs, entitlements, hardened runtime, notarization, and signing workflows.

Apple, macOS, Swift, SwiftUI, AppKit, AVFoundation, CoreAudio, Audio Unit, AU, and related names are trademarks of Apple Inc.

Use of Apple SDKs and distribution through Apple-related channels is subject to Apple’s developer agreements and platform terms.

## Microsoft Platform Distribution Notes

Windows builds may use Microsoft platform APIs, .NET, Windows Forms, WASAPI, WinMM, and related Windows functionality.

Microsoft, Windows, .NET, Visual Studio, and related names are trademarks of Microsoft Corporation.

Use of Microsoft SDKs, redistributables, and build tools is subject to their respective license terms.

## Visual C++ Redistributable

The Windows installer may download, invoke, or bundle the Microsoft Visual C++ Redistributable where required by native dependencies such as PyTorch or native helper components.

* Provider: Microsoft
* Website: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

Redistribution of Microsoft runtime components must comply with Microsoft’s applicable redistributable terms.

## Build Tools and Installers

### Inno Setup

The Windows installer may be built using Inno Setup.

* Project: Inno Setup
* Author: Jordan Russell and contributors
* License: Inno Setup License
* Website: https://jrsoftware.org/isinfo.php

### CMake

The Windows native helper build may use CMake.

* Project: CMake
* Provider: Kitware
* License: BSD 3-Clause License
* Website: https://cmake.org/

### Git

The build scripts may invoke Git to fetch third-party source trees such as JUCE, where configured.

* Project: Git
* License: GPLv2
* Website: https://git-scm.com/

## Fonts, Images, Audio, and Branding Assets

LemmingsStudio includes original branding, splash screens, icons, startup audio, and related visual/audio assets created for the project unless otherwise noted.

The following project-owned assets are not necessarily licensed under the same terms as the source code unless explicitly stated:

* LemmingsStudio logo and splash artwork
* MagmaVance pre-splash video assets
* Startup sound assets
* App icons
* Branding graphics
* Marketing images

The name “LemmingsStudio,” the MagmaVance name, logos, splash artwork, and associated branding assets may be subject to trademark and brand-use restrictions. Reuse of the source code under the project license does not automatically grant permission to represent modified forks as official LemmingsStudio or MagmaVance releases.

## Model Weights and Large Optional Assets

Some functionality may rely on optional model weights or large downloadable assets, including but not limited to:

* Demucs models
* RVC models
* voice/timbre conversion models
* future AI assistant models
* audio analysis models
* optional model packs

These assets may be distributed separately from the source code. Their licenses may differ from the LemmingsStudio source-code license. Do not assume that a model’s availability for download means it can be redistributed inside installers, GitHub releases, mirrors, or third-party builds.

## User-Supplied Content

LemmingsStudio may allow users to import, record, process, separate, transform, or export audio and MIDI content.

Users are responsible for ensuring they have the rights to use any audio, MIDI, samples, loops, stems, recordings, plug-ins, presets, models, or other content they load into the application.

The LemmingsStudio project does not grant rights to third-party songs, samples, stems, plug-ins, presets, datasets, voices, likenesses, or model weights.

## Trademarks

All trademarks, product names, company names, and logos are the property of their respective owners.

References to Ableton Live, FL Studio, Logic Pro, Studio One, Splice, Discord, Apple, Microsoft, Steinberg, VST3, JUCE, PyTorch, Demucs, FFmpeg, and other third-party products are for compatibility, attribution, or descriptive purposes only.

No endorsement, sponsorship, or affiliation is implied unless explicitly stated.

## License Texts

Where required, full license texts for bundled third-party components should be included in the repository or release package, typically under:

```text
Licenses/
ThirdPartyLicenses/
NOTICE/
```

Recommended files/folders:

```text
LICENSE
THIRD_PARTY_NOTICES.md
ThirdPartyLicenses/FFmpeg-LICENSE.txt
ThirdPartyLicenses/JUCE-LICENSE.txt
ThirdPartyLicenses/NAudio-LICENSE.txt
ThirdPartyLicenses/PyTorch-LICENSE.txt
ThirdPartyLicenses/Demucs-LICENSE.txt
ThirdPartyLicenses/InnoSetup-LICENSE.txt
```

If binary builds include FFmpeg, JUCE-linked binaries, PyTorch, Demucs, model weights, or Microsoft redistributables, ensure the corresponding license texts and notices are included in the distributed package.

## Disclaimer

This notice file may be incomplete. Dependency trees can change over time, especially for Python, machine-learning, plug-in-hosting, and media-encoding packages.

Before publishing official releases, installers, DMGs, EXEs, model packs, or mirrors, maintainers should audit the final dependency list and update this file accordingly.

Last updated: 2026-07-04
