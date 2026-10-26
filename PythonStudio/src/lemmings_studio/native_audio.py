"""Thin native ABI binding. No Python callback enters the audio engine."""
from pathlib import Path
import ctypes as C
import numpy as np


class DrumParameters(C.Structure):
    _fields_ = [('tune', C.c_double), ('decay', C.c_double), ('tone', C.c_double),
                ('drive', C.c_float), ('level', C.c_float), ('velocity', C.c_float)]


class NativeAudio:
    def __init__(self, library: Path):
        self.library = C.CDLL(str(library.resolve()))
        self.library.ls_audio_abi_version.restype = C.c_uint32
        if self.library.ls_audio_abi_version() != 1:
            raise RuntimeError('Unsupported native audio ABI')
        self.library.ls_render_drum.argtypes = [C.c_uint32, C.c_double, C.POINTER(DrumParameters),
                                               C.POINTER(C.c_float), C.c_uint32]
        self.library.ls_render_drum.restype = C.c_int

    def render_drum(self, voice: int, rate: int, frames: int, *, tune=1., decay=1.,
                    tone=1., drive=1., level=1., velocity=.8):
        if type(voice) is not int or not 0 <= voice <= 9:
            raise ValueError('Unknown Mac drum voice')
        if type(frames) is not int or not 0 <= frames <= 192000*10:
            raise ValueError('Offline one-shot render must be at most ten seconds')
        samples = np.zeros(frames, dtype=np.float32)
        params = DrumParameters(tune, decay, tone, drive, level, velocity)
        code = self.library.ls_render_drum(voice, rate, C.byref(params),
                                          samples.ctypes.data_as(C.POINTER(C.c_float)), frames)
        if code:
            raise ValueError('Invalid drum render parameters')
        return samples
