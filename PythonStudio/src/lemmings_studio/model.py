"""Versioned documents and reversible edits, independent of Qt and audio devices."""
from __future__ import annotations
from copy import deepcopy
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable
from uuid import uuid4
import json
import math
import os
import shutil
import tempfile


def identity() -> str:
    return str(uuid4())


def number(value, low: float, high: float, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be numeric")
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"{name} must be between {low} and {high}")
    return float(value)


@dataclass
class Note:
    pitch: int = 60
    start: float = 0
    length: float = .5
    velocity: float = .8
    id: str = field(default_factory=identity)
    extra: dict = field(default_factory=dict)


@dataclass
class Clip:
    name: str = "MIDI clip"
    start: float = 0
    length: float = 4
    file: str = ""
    notes: list[Note] = field(default_factory=list)
    id: str = field(default_factory=identity)
    extra: dict = field(default_factory=dict)


@dataclass
class Track:
    name: str = "MIDI 1"
    kind: str = "midi"
    gain: float = .8
    pan: float = 0
    mute: bool = False
    solo: bool = False
    instrument: str = "sine"
    clips: list[Clip] = field(default_factory=list)
    id: str = field(default_factory=identity)
    extra: dict = field(default_factory=dict)


@dataclass
class Project:
    name: str = "Untitled"
    tempo: float = 120
    sample_rate: int = 48000
    key: str = "C minor"
    tracks: list[Track] = field(default_factory=list)
    legacy_source: dict | None = None
    warnings: list[str] = field(default_factory=list)
    extra: dict = field(default_factory=dict)

    def validate(self) -> None:
        number(self.tempo, 20, 400, "Tempo")
        number(self.sample_rate, 8000, 192000, "Sample rate")
        if int(self.sample_rate) != self.sample_rate:
            raise ValueError("Sample rate must be an integer")
        identifiers: set[str] = set()
        for track in self.tracks:
            if track.kind not in ("audio", "midi"):
                raise ValueError("Unsupported track kind")
            if type(track.mute) is not bool or type(track.solo) is not bool:
                raise ValueError("Mute and solo must be booleans")
            number(track.gain, 0, 4, "Gain")
            number(track.pan, -1, 1, "Pan")
            if track.instrument not in ("sine", "triangle", "saw", "square", "drums"):
                raise ValueError("Unsupported instrument")
            for entity in [track, *track.clips, *(n for c in track.clips for n in c.notes)]:
                if not isinstance(entity.id, str) or not entity.id or entity.id in identifiers:
                    raise ValueError("Document IDs must be unique nonempty strings")
                identifiers.add(entity.id)
            for clip in track.clips:
                number(clip.start, 0, 1_000_000, "Clip start")
                number(clip.length, .00001, 1_000_000, "Clip length")
                for note in clip.notes:
                    number(note.pitch, 0, 127, "Pitch")
                    if int(note.pitch) != note.pitch:
                        raise ValueError("MIDI pitch must be an integer")
                    number(note.start, 0, 1_000_000, "Note start")
                    number(note.length, .00001, 1_000_000, "Note length")
                    number(note.velocity, 0, 1, "Velocity")

    @property
    def end_beat(self) -> float:
        return max((c.start + c.length for t in self.tracks for c in t.clips), default=4)

    @classmethod
    def new(cls) -> Project:
        return cls(tracks=[Track(name="Audio 1", kind="audio"), Track()])

    @classmethod
    def demo(cls) -> Project:
        project = cls.new()
        project.tracks[1].clips.append(Clip(name="Melody", notes=[Note(60+i%4*2, i*.5, .35) for i in range(8)]))
        return project

    def encode(self) -> dict:
        self.validate()
        def note(n):
            return {**deepcopy(n.extra), "id": n.id, "pitch": n.pitch, "start": n.start, "length": n.length, "velocity": n.velocity}
        def clip(c):
            return {**deepcopy(c.extra), "id": c.id, "name": c.name, "start": c.start, "length": c.length, "file": c.file, "notes": [note(n) for n in c.notes]}
        def track(t):
            return {**deepcopy(t.extra), "id": t.id, "name": t.name, "kind": t.kind, "gain": t.gain, "pan": t.pan, "mute": t.mute, "solo": t.solo, "instrument": t.instrument, "clips": [clip(c) for c in t.clips]}
        return {**deepcopy(self.extra), "pythonSchema": 1, "name": self.name, "tempo": self.tempo, "sampleRate": self.sample_rate, "key": self.key, "tracks": [track(t) for t in self.tracks], "legacySource": deepcopy(self.legacy_source), "warnings": list(self.warnings)}

    @classmethod
    def decode(cls, data: dict) -> Project:
        if not isinstance(data, dict):
            raise ValueError("Project must be a JSON object")
        if "pythonSchema" not in data:
            raise ValueError("Use the explicit legacy importer for older projects")
        if type(data["pythonSchema"]) is not int or data["pythonSchema"] != 1:
            raise ValueError("Unsupported Python project version; original file was not modified")
        def fields(d, known):
            if not isinstance(d, dict):
                raise ValueError("Invalid project object")
            return {k: deepcopy(v) for k, v in d.items() if k not in known}
        tracks = []
        for t in data.get("tracks", []):
            clips = []
            for c in t.get("clips", []):
                notes = [Note(pitch=n["pitch"], start=n["start"], length=n["length"], velocity=n["velocity"], id=n["id"], extra=fields(n, {"id", "pitch", "start", "length", "velocity"})) for n in c.get("notes", [])]
                clips.append(Clip(name=c["name"], start=c["start"], length=c["length"], file=c.get("file", ""), notes=notes, id=c["id"], extra=fields(c, {"id", "name", "start", "length", "file", "notes"})))
            tracks.append(Track(name=t["name"], kind=t["kind"], gain=t["gain"], pan=t["pan"], mute=t["mute"], solo=t["solo"], instrument=t["instrument"], clips=clips, id=t["id"], extra=fields(t, {"id", "name", "kind", "gain", "pan", "mute", "solo", "instrument", "clips"})))
        project = cls(name=data["name"], tempo=data["tempo"], sample_rate=data["sampleRate"], key=data.get("key", "C minor"), tracks=tracks, legacy_source=deepcopy(data.get("legacySource")), warnings=list(data.get("warnings", [])), extra=fields(data, {"pythonSchema", "name", "tempo", "sampleRate", "key", "tracks", "legacySource", "warnings"}))
        project.validate()
        return project


def load_project(path: Path) -> Project:
    data = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(f"Invalid number: {x}")))
    return Project.decode(data)


def save_project(project: Project, path: Path) -> None:
    """Write only the new format; never overwrite a Swift or WinForms project."""
    if path.suffix.lower() != ".lemmingspy":
        raise ValueError("Save the rewrite to a separate .lemmingspy project")
    payload = json.dumps(project.encode(), ensure_ascii=False, indent=2, allow_nan=False)
    path = path.absolute()
    if path.is_symlink():
        raise ValueError("Save to a regular file, not a symbolic link")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        # Verify before replacing either the backup or the destination.
        load_project(Path(temporary))
        if path.exists():
            backup = path.with_suffix(path.suffix + ".bak")
            if backup.is_symlink():
                raise ValueError("Backup path must not be a symbolic link")
            shutil.copy2(path, backup)
        os.replace(temporary, path)
        if os.name != "nt":
            directory = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Document:
    def __init__(self, project: Project | None = None):
        self.project = project or Project.new()
        self.project.validate()
        self.undo_stack: list[tuple[str, Project]] = []
        self.redo_stack: list[tuple[str, Project]] = []
        self.revision = 0
        self._saved_revision = 0
        self._saved_document = self.project.encode()

    @property
    def dirty(self) -> bool:
        return self.project.encode() != self._saved_document

    @property
    def saved_revision(self) -> int:
        return self._saved_revision

    @saved_revision.setter
    def saved_revision(self, value: int) -> None:
        self._saved_revision = value
        if value == self.revision:
            self._saved_document = self.project.encode()

    def edit(self, label: str, operation: Callable[[Project], None]) -> bool:
        candidate = deepcopy(self.project)
        operation(candidate)
        candidate.validate()
        if candidate.encode() == self.project.encode():
            return False
        self.undo_stack.append((label, self.project))
        self.undo_stack = self.undo_stack[-100:]
        self.redo_stack.clear()
        self.project = candidate
        self.revision += 1
        return True

    def undo(self) -> str:
        if not self.undo_stack:
            return "Nothing to undo"
        label, previous = self.undo_stack.pop()
        self.redo_stack.append((label, self.project))
        self.project = previous
        self.revision += 1
        return "Undid " + label

    def redo(self) -> str:
        if not self.redo_stack:
            return "Nothing to redo"
        label, next_project = self.redo_stack.pop()
        self.undo_stack.append((label, self.project))
        self.project = next_project
        self.revision += 1
        return "Redid " + label
