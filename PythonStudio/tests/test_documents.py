from copy import deepcopy
import json
from pathlib import Path
import pytest
from lemmings_studio.model import Document, Project, save_project, load_project


def test_round_trip_retains_ids_and_unknown_fields(tmp_path):
    p = Project.demo()
    p.extra = {"futureExtension": {"keep": [1, 2, 3]}}
    p.tracks[1].extra = {"routing": {"unported": True}}
    p.tracks[1].clips[0].extra = {"warp": {"preserve": True}}
    p.legacy_source = {"devices": [{"opaqueState": "untouched"}]}
    path = tmp_path / "song.lemmingspy"
    save_project(p, path)
    assert load_project(path).encode() == p.encode()


def test_edits_undo_redo_and_failed_edit_are_transactional():
    d = Document(Project.demo())
    original = d.project.encode()
    d.edit("transpose", lambda p: setattr(p.tracks[1].clips[0].notes[0], "pitch", 67))
    edited = d.project.encode()
    assert edited != original
    d.undo()
    assert d.project.encode() == original
    d.redo()
    assert d.project.encode() == edited
    with pytest.raises(ValueError):
        d.edit("bad tempo", lambda p: setattr(p, "tempo", -1))
    assert d.project.encode() == edited
    assert len(d.undo_stack) == 1
    d.undo()
    d.edit("new branch", lambda p: setattr(p, "tempo", 130))
    assert not d.redo_stack


def test_cannot_overwrite_existing_swift_or_windows_files(tmp_path):
    for extension in (".lemmingsproject", ".lemmings", ".json", ".swift"):
        path = tmp_path / ("original"+extension)
        path.write_bytes(b"original bytes")
        with pytest.raises(ValueError):
            save_project(Project.demo(), path)
        assert path.read_bytes() == b"original bytes"


def test_backup_and_failed_save_preserve_existing_project(tmp_path):
    path = tmp_path / "song.lemmingspy"
    original = Project.demo()
    save_project(original, path)
    original_bytes = path.read_bytes()
    changed = deepcopy(original); changed.tempo = 130
    save_project(changed, path)
    assert path.with_suffix(".lemmingspy.bak").read_bytes() == original_bytes
    changed.tempo = float("nan")
    current = path.read_bytes()
    with pytest.raises(ValueError):
        save_project(changed, path)
    assert path.read_bytes() == current
    assert not list(tmp_path.glob("*.tmp"))


@pytest.mark.parametrize("mutate", [
    lambda d: d.update(pythonSchema=100),
    lambda d: d.update(pythonSchema=True),
    lambda d: d.update(tempo=True),
    lambda d: d.update(sampleRate=48000.5),
    lambda d: d["tracks"][0].update(mute="false"),
    lambda d: d["tracks"][1]["clips"][0]["notes"][0].update(pitch=60.5),
    lambda d: d["tracks"][1]["clips"][0]["notes"][0].update(velocity=2),
])
def test_rejects_invalid_or_future_projects(mutate):
    data = Project.demo().encode(); mutate(data)
    with pytest.raises(ValueError):
        Project.decode(data)


def test_undo_to_saved_state_is_not_dirty():
    document=Document(Project.demo())
    document.edit('Tempo',lambda p:setattr(p,'tempo',130))
    assert document.dirty
    document.undo()
    assert not document.dirty
