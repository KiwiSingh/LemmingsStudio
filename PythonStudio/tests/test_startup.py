from pathlib import Path
import hashlib
import json
import subprocess
import sys
import os
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtWidgets import QApplication
from lemmings_studio.startup_assets import choose_video, choose_voice, video_duration, media_root


def test_refresh_rate_selection_matches_mac_and_has_original_fallbacks(tmp_path):
    for rate in (60, 120, 144):
        (tmp_path/f'MagmaVancePreSplash_{rate}.mp4').touch()
    assert choose_video(tmp_path, 132).name == 'MagmaVancePreSplash_120.mp4'
    assert choose_video(tmp_path, 144).name == 'MagmaVancePreSplash_144.mp4'
    # Preferred 240 is absent: use the actual Mac's 60 Hz fallback, not a new nearest file.
    assert choose_video(tmp_path, 240).name == 'MagmaVancePreSplash_60.mp4'
    (tmp_path/'MagmaVancePreSplash_60.mp4').unlink()
    (tmp_path/'MagmaVancePreSplash.mp4').touch()
    assert choose_video(tmp_path, 240).name == 'MagmaVancePreSplash.mp4'
    (tmp_path/'MagmaVancePreSplash.mp4').unlink()
    assert choose_video(tmp_path, 240) is None


def test_original_voice_precedence_and_duration_bounds(tmp_path):
    (tmp_path/'startup.wav').touch()
    assert choose_voice(tmp_path).name == 'startup.wav'
    (tmp_path/'LemmingsStartup.wav').touch()
    assert choose_voice(tmp_path).name == 'LemmingsStartup.wav'
    assert [video_duration(x) for x in (0, -1, 100, 3800, 9000)] == [3800, 3800, 1200, 3800, 5000]


def test_staged_media_is_byte_identical_to_pinned_mac_assets(tmp_path):
    root = Path(__file__).resolve().parents[2]
    subprocess.run([sys.executable, str(root/'tools/stage_startup_resources.py'),
                    '--output', str(tmp_path)], check=True)
    manifest = json.loads((tmp_path/'manifest.json').read_text())
    assert len(manifest) == 11
    for name, record in manifest.items():
        assert hashlib.sha256((tmp_path/name).read_bytes()).hexdigest() == record['sha256']
        assert (tmp_path/name).read_bytes() == (root/record['source']).read_bytes()


def test_missing_media_cannot_leave_startup_stuck(tmp_path):
    from lemmings_studio.startup import Startup
    app = QApplication.instance() or QApplication([])
    class Log:
        path = tmp_path/'test.log'
        def mark(self, *_args, **_kwargs):
            pass
    startup = Startup(app, Log(), check_mode=True, root=tmp_path)
    ended = []
    startup.finished.connect(lambda: ended.append(True))
    startup.start()
    startup._video_error('Missing original media')
    assert startup.stage == 'splash'
    startup._next()
    startup._next()
    assert ended == [True]
    assert startup.result()['status'] == 'failed'
    startup.shutdown()
    startup.qml.deleteLater()
    app.processEvents()


def test_launch_log_precedes_optional_imports_and_stays_in_selected_directory(tmp_path, monkeypatch):
    from lemmings_studio.diagnostics import LaunchLog
    monkeypatch.setenv('LEMMINGS_DIAGNOSTICS_DIR', str(tmp_path))
    log = LaunchLog()
    try:
        assert log.path.parent == tmp_path
        assert log.events[0]['phase'] == 'process_entry'
        log.mark('before_audio')
        report = log.write_report(status='testing')
        assert report['events'][-1]['phase'] == 'before_audio'
        assert json.loads(log.report_path.read_text())['status'] == 'testing'
    finally:
        log.close()
