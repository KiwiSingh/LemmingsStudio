"""Block renderer and blocking PortAudio worker; no Python real-time callback."""
from __future__ import annotations
from copy import deepcopy
from pathlib import Path
from threading import Event, Thread
from urllib.parse import unquote, urlparse
import math
import os
import tempfile
import numpy as np
import soundfile as sf
from .model import Project


def local_media_path(value: str, base: Path) -> Path:
    parsed = urlparse(value)
    if parsed.scheme == "file":
        if parsed.netloc not in ("", "localhost"):
            raise ValueError("Remote media requires an explicit local copy")
        value = unquote(parsed.path)
        if os.name == "nt" and len(value) > 2 and value[0] == "/" and value[2] == ":":
            value = value[1:]
    elif parsed.scheme and not (len(parsed.scheme) == 1 and len(value) > 1 and value[1] == ":"):
        raise ValueError("Only local audio files are supported")
    if value.startswith(("\\\\", "//")):
        raise ValueError("Remote media requires an explicit local copy")
    path = Path(value).expanduser()
    return path if path.is_absolute() else base / path


class Renderer:
    def __init__(self, project: Project, base: Path | None = None):
        project.validate()
        self.project = deepcopy(project)
        self.rate = int(project.sample_rate)
        self.length = math.ceil(project.end_beat * 60 / project.tempo * self.rate)
        self.sources: dict[str, tuple[np.ndarray, int]] = {}
        base = base or Path.cwd()
        for track in self.project.tracks:
            for clip in track.clips:
                if not clip.file or clip.file in self.sources:
                    continue
                path = local_media_path(clip.file, base)
                info = sf.info(path)
                if info.duration > 600:
                    raise ValueError(f"Streaming for files longer than ten minutes is not ported yet: {path.name}")
                samples, rate = sf.read(path, dtype="float32", always_2d=True)
                if samples.shape[1] == 1:
                    samples = np.repeat(samples, 2, axis=1)
                self.sources[clip.file] = (samples[:, :2], rate)

    def block(self, frame: int, count: int) -> np.ndarray:
        out = np.zeros((count, 2), dtype=np.float32)
        frames = np.arange(frame, frame + count, dtype=np.float64)
        beats = frames / self.rate * self.project.tempo / 60
        any_solo = any(t.solo for t in self.project.tracks)
        for track in self.project.tracks:
            if track.mute or (any_solo and not track.solo):
                continue
            levels = np.asarray([math.sqrt((1-track.pan)/2), math.sqrt((1+track.pan)/2)], dtype=np.float32) * track.gain
            for clip in track.clips:
                clip_mask = (beats >= clip.start) & (beats < clip.start + clip.length)
                if not clip_mask.any():
                    continue
                if clip.file:
                    samples, rate = self.sources[clip.file]
                    positions = (beats - clip.start) * 60 / self.project.tempo * rate
                    mask = clip_mask & (positions < len(samples))
                    positions = positions[mask]
                    indices = positions.astype(np.int64)
                    following = np.minimum(indices + 1, len(samples)-1)
                    fraction = (positions-indices).astype(np.float32)[:, None]
                    out[mask] += (samples[indices] + fraction*(samples[following]-samples[indices])) * levels
                for note in clip.notes:
                    start = clip.start + note.start
                    end = min(clip.start+clip.length, start+note.length)
                    mask = clip_mask & (beats >= start) & (beats < end)
                    if not mask.any():
                        continue
                    age = (beats[mask]-start) * 60 / self.project.tempo
                    remaining = (end-beats[mask]) * 60 / self.project.tempo
                    envelope = np.minimum(1, np.minimum(age/.005, remaining/.02))
                    frequency = 440 * 2**((note.pitch-69)/12)
                    phase = age * frequency
                    cycle = phase % 1
                    if track.instrument == "triangle":
                        wave = 1-4*np.abs(cycle-.5)
                    elif track.instrument == "saw":
                        wave = (cycle*2-1)*.55
                    elif track.instrument == "square":
                        wave = np.where(cycle < .5, .45, -.45)
                    elif track.instrument == "drums":
                        # Original deterministic synthesis; these are not sampled rock kits.
                        hashes = (frames[mask].astype(np.uint64)*747796405 + note.pitch*2891336453) & 0xffffffff
                        noise = ((hashes >> 8).astype(np.float64)/8388607.5)-1
                        if note.pitch in (35, 36):
                            wave = np.sin(2*np.pi*(50*age+3*(1-np.exp(-age*40)))) * np.exp(-age*12)
                        elif note.pitch in (38, 40):
                            wave = (.75*noise+.25*np.sin(2*np.pi*180*age))*np.exp(-age*20)
                        else:
                            wave = noise*np.exp(-age*(8 if note.pitch==46 else 50))
                    else:
                        wave = np.sin(2*np.pi*phase)
                    out[mask] += (wave*envelope*.2*note.velocity).astype(np.float32)[:, None] * levels
        np.clip(out, -1, 1, out=out)
        return out

    def export(self, target: Path, cancelled: Event | None = None) -> None:
        target = target.absolute()
        if target.is_symlink():
            raise ValueError("Export to a regular file, not a symbolic link")
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor, name = tempfile.mkstemp(prefix=".lemmings-export-", suffix=".wav", dir=target.parent)
        os.close(descriptor)
        try:
            with sf.SoundFile(name, mode="w", samplerate=self.rate, channels=2, format="WAV", subtype="PCM_24") as stream:
                for position in range(0, self.length, 2048):
                    if cancelled and cancelled.is_set():
                        raise InterruptedError("Export cancelled; destination preserved")
                    stream.write(self.block(position, min(2048, self.length-position)))
            os.replace(name, target)
        finally:
            if os.path.exists(name):
                os.unlink(name)


class AudioEngine:
    """Device I/O, decoding and mixing stay off the Qt thread. Not low-latency certified."""
    def __init__(self):
        self._thread: Thread | None = None
        self._stop = Event()
        self.generation = 0
        self.on_position = lambda generation, beat: None
        self.on_finished = lambda generation, message: None
        self.output_device: int | None = None

    @property
    def running(self) -> bool:
        return bool(self._thread and self._thread.is_alive() and not self._stop.is_set())

    def stop(self) -> None:
        self._stop.set()
        self.generation += 1

    def play(self, project: Project, base: Path, start_beat: float = 0) -> None:
        old_thread = self._thread
        self._stop.set()
        stopped = Event()
        self._stop = stopped
        self.generation += 1
        generation = self.generation
        snapshot = deepcopy(project)
        device = self.output_device
        def run():
            try:
                if old_thread and old_thread.is_alive():
                    old_thread.join()
                if stopped.is_set():
                    return
                import sounddevice as sd
                renderer = Renderer(snapshot, base)
                position = max(0, round(start_beat*60/snapshot.tempo*renderer.rate))
                with sd.OutputStream(samplerate=renderer.rate, channels=2, dtype="float32", blocksize=2048, latency="high", device=device) as stream:
                    while position < renderer.length and not stopped.is_set():
                        count = min(2048, renderer.length-position)
                        stream.write(renderer.block(position, count))
                        position += count
                        self.on_position(generation, position/renderer.rate*snapshot.tempo/60)
                if not stopped.is_set():
                    self.on_finished(generation, "Playback finished")
            except Exception as error:
                if not stopped.is_set():
                    self.on_finished(generation, f"Audio error: {error}")
        self._thread = Thread(target=run, name="LemmingsAudio", daemon=True)
        self._thread.start()
