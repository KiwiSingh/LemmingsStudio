from threading import Event
import numpy as np
import pytest
import soundfile as sf
from lemmings_studio.audio import Renderer, local_media_path
from lemmings_studio.model import Clip, Project, Track


def test_block_render_matches_one_pass_and_export_alignment(tmp_path):
    p = Project.demo()
    r = Renderer(p)
    expected = r.block(0, r.length)
    actual = np.concatenate([r.block(i, min(513,r.length-i)) for i in range(0,r.length,513)])
    np.testing.assert_allclose(actual, expected, atol=1e-7)
    assert np.max(np.abs(actual)) > .01
    path = tmp_path / "mix.wav"; r.export(path)
    exported, rate = sf.read(path, dtype="float32")
    assert rate == p.sample_rate and len(exported) == r.length
    np.testing.assert_allclose(exported, actual, atol=2e-7)


def test_audio_resampling_pan_mute_solo_and_source_unchanged(tmp_path):
    path = tmp_path / "source.wav"
    wave = np.sin(np.arange(22050)*2*np.pi*440/22050).astype("float32")*.2
    sf.write(path, wave, 22050, subtype="FLOAT")
    original = path.read_bytes()
    p = Project(tracks=[Track(kind="audio",pan=-1,clips=[Clip(file=str(path),start=1,length=2)])])
    r = Renderer(p)
    block = r.block(0,r.length)
    assert np.max(np.abs(block[:24000])) == 0
    assert np.max(np.abs(block[:,1])) == 0
    assert np.max(np.abs(block[24000:,0])) > .1
    p.tracks[0].mute = True
    assert not Renderer(p).block(0,r.length).any()
    p.tracks[0].mute = False
    p.tracks.append(Track(solo=True))
    assert not Renderer(p).block(0,r.length).any()
    assert path.read_bytes() == original


def test_cancelled_export_keeps_destination(tmp_path):
    path = tmp_path / "mix.wav"; path.write_bytes(b"keep existing mix")
    cancelled = Event(); cancelled.set()
    with pytest.raises(InterruptedError):
        Renderer(Project.demo()).export(path,cancelled)
    assert path.read_bytes() == b"keep existing mix"
    assert len(list(tmp_path.iterdir())) == 1


@pytest.mark.parametrize("url", ["https://example.com/audio.wav", "file://server/share.wav", "\\\\server\\share.wav", "//server/share.wav"])
def test_project_media_never_fetches_remote_sources(url,tmp_path):
    with pytest.raises(ValueError):
        local_media_path(url,tmp_path)
