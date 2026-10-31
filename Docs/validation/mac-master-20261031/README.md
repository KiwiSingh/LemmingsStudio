# Master inserts and gain-reduction metering

Both mixer layouts expose a Master strip with an Inserts rack, stock effects, AU/VST3 effect menus, browser-drop targeting, editor opening, bypass, removal and ordering controls. The rack explicitly orders external plugin inserts before stock inserts; the default stock limiter therefore remains last. The Master fader follows the insert chain. Unsupported/missing master plugins retain their state and report a load error.

A registered in-process AUAudioUnit pull-through node processes the summed audio before output and in offline renders. The metronome uses a separate downstream monitor mixer and stays excluded from exports. Master output metering measures the actual processed stereo signal. Master plugin slots, bypass, state and the fader value persist in optional version-3 project fields; older projects continue to load.

Compressor, Glue Bus Compressor and Peak Limiter publish positive detector gain reduction, excluding makeup/output gain and returning zero when bypassed. Device cards and Master inserts display these values in dB. The Master summary is labelled Stock GR; third-party reduction remains available in each vendor's editor rather than presenting an inferred output-level difference as gain reduction.

Validation uses actual master audio rendering, a known constant-level compressor calculation, limiter attenuation, master bypass, Neutron 5 AU/VST3 loading/state reload and metronome exclusion. Early editor probes passed on real Neutron instances. Final probes use --headless-validation to avoid interfering with the user's active test window. UI accessibility inspection confirmed the Master Inserts sheet, Add Plugin/Add Stock FX controls, parameter sliders and dB reduction readouts. Physical audio-device performance and plugin delay compensation are not certified here.

Diagnostic commands: `LemmingsStudio --validate-master OUTPUT [--format-au] [--headless-validation]`; existing export/grid diagnostics are rerun. Diagnostics suppress physical audio start, MIDI setup, startup media and recovery writes. The user's existing test build remains open and its files are not replaced.
