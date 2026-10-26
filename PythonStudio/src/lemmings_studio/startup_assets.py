"""Resolve original Mac branding without copying assets into the source package."""
from pathlib import Path
import sys

SUPPORTED_RATES = (60, 75, 90, 120, 144, 165, 240)


def media_root() -> Path:
    if getattr(sys, 'frozen', False):
        return Path(sys._MEIPASS)/'startup-media'
    return Path(__file__).resolve().parents[3]/'Sources/LemmingsStudio/Resources'


def choose_video(root: Path, refresh_rate: float) -> Path | None:
    rate = min(SUPPORTED_RATES, key=lambda x: (abs(x-refresh_rate), x))
    for name in (f'MagmaVancePreSplash_{rate}.mp4', 'MagmaVancePreSplash_60.mp4', 'MagmaVancePreSplash.mp4'):
        path = root/name
        if path.is_file():
            return path
    return None


def choose_voice(root: Path) -> Path | None:
    return next((root/name for name in ('LemmingsStartup.wav', 'startup.wav') if (root/name).is_file()), None)


def video_duration(milliseconds: int) -> int:
    # The Mac bounds the media duration to 1.2–5 s, defaulting to 3.8 s.
    return max(1200, min(5000, milliseconds)) if milliseconds > 0 else 3800
