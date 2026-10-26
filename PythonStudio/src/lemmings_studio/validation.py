"""Self-contained bundle smoke test; never opens an audio device or user project."""
from pathlib import Path
from tempfile import TemporaryDirectory
import numpy as np
import soundfile as sf
import sounddevice as sd
from PySide6.QtWidgets import QApplication
from .audio import Renderer
from .model import Project, load_project, save_project


def validate_bundle(app: QApplication) -> dict:
    from .ui import MainWindow
    passed = []
    sd.get_portaudio_version()  # Confirms the bundled PortAudio library loads.
    passed.append("PortAudio native library loads")
    original = Project.demo()
    window = MainWindow(original)
    try:
        window.select_clip(1, original.tracks[1].clips[0].id)
        window.draw_note(2, 72)
        assert window.selected_clip().notes[-1].pitch == 72
        edited = window.document.project.encode()
        window.undo()
        assert window.document.project.encode() == original.encode()
        window.redo()
        assert window.document.project.encode() == edited
        passed.append("workspace edit/undo/redo")
        window.resize(800, 600)
        window.show()
        app.processEvents()
        assert window.arrangement.viewport().width() > 200
        assert window.arrangement.viewport().height() > 100
        passed.append("800x600 workspace layout")
        with TemporaryDirectory(prefix="lemmings-bundle-check-") as temporary:
            folder = Path(temporary)
            project_file = folder / "check.lemmingspy"
            save_project(window.document.project, project_file)
            restored = load_project(project_file)
            assert restored.encode() == edited
            passed.append("project save/reopen")
            renderer = Renderer(restored, folder)
            output = folder / "check.wav"
            renderer.export(output)
            samples, rate = sf.read(output, dtype="float32")
            assert rate == restored.sample_rate
            assert len(samples) == renderer.length
            assert samples.shape[1] == 2
            assert np.max(np.abs(samples)) > .01
            passed.append("native audio decoder and aligned stereo WAV export")
    finally:
        window.document.saved_revision = window.document.revision
        window.close()
        app.processEvents()
    return {"status": "passed", "checks": passed, "audio_device_tested": False}
