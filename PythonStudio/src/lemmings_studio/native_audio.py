"""Thin native ABI binding. No Python callback enters the audio engine."""
from pathlib import Path
import ctypes as C
import numpy as np


class DrumParameters(C.Structure):
    _fields_ = [('tune', C.c_double), ('decay', C.c_double), ('tone', C.c_double),
                ('drive', C.c_float), ('level', C.c_float), ('velocity', C.c_float)]


class DrumEvent(C.Structure):
    _fields_ = [('frame',C.c_uint64),('voice',C.c_uint32),('velocity',C.c_float)]


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

    def render_kit(self, rate, frames, events, kit, master=1.):
        if type(frames) is not int or not 0 <= frames <= 192000*600:
            raise ValueError('Render at most ten minutes at a time')
        import math
        if any(type(f) is not int or f<0 or type(v) is not int or not 0<=v<10 or not math.isfinite(g) or not 0<=g<=1 for f,v,g in events):raise ValueError('Invalid drum event')
        table=(DrumParameters*10)(*(DrumParameters(**kit[str(i)],velocity=1.) for i in range(10)))
        messages=(DrumEvent*len(events))(*(DrumEvent(*event) for event in events))
        samples=np.zeros(frames,dtype=np.float32)
        method=self.library.ls_render_drum_kit
        method.argtypes=[C.c_double,C.POINTER(DrumParameters),C.POINTER(DrumEvent),C.c_uint32,C.c_float,C.POINTER(C.c_float),C.c_uint32]
        method.restype=C.c_int
        if method(rate,table,messages,len(events),master,samples.ctypes.data_as(C.POINTER(C.c_float)),frames):
            raise ValueError('Invalid drum kit performance')
        return samples

    def apply_limiter(self,stereo,rate,parameters):
        samples=np.array(stereo,dtype=np.float32,order='C',copy=True)
        if samples.ndim!=2 or samples.shape[1]!=2 or len(samples)>192000*600 or not np.isfinite(samples).all():
            raise ValueError('Expected finite interleaved stereo audio')
        params=(C.c_double*6)(*(parameters[k] for k in ('ceiling','threshold','release','lookahead','softclip','output')))
        method=self.library.ls_apply_limiter
        method.argtypes=[C.POINTER(C.c_float),C.c_uint32,C.c_double,C.POINTER(C.c_double)];method.restype=C.c_int
        if method(samples.ctypes.data_as(C.POINTER(C.c_float)),len(samples),rate,params):raise ValueError('Invalid limiter parameters')
        return samples
