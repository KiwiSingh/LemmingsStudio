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

    def instrument(self,kind,rate,parameters=None,seed=0xC0FFEE):
        return NativeInstrument(self.library,kind,rate,parameters,seed)

    def render_instrument(self,kind,rate,frames,events,parameters=None,seed=0xC0FFEE,block_size=512,excitations=None):
        """Events are ordered (frame, type, note, value); block API also serves export."""
        import math
        if type(frames) is not int or not 0<=frames<=rate*600:raise ValueError('Invalid render length')
        if type(block_size) is not int or not 1<=block_size<=65536:raise ValueError('Invalid block size')
        events=list(events)
        if any(type(f) is not int or f<0 or (i and f<events[i-1][0]) for i,(f,_,_,_) in enumerate(events)):
            raise ValueError('Events must have ordered nonnegative frame positions')
        for _,event_type,note,value in events: NativeInstrument.validate_event(event_type,note,value)
        output=np.zeros(frames,dtype=np.float32);index=0;frame=0
        with self.instrument(kind,rate,parameters,seed) as instrument:
            while frame<frames:
                while index<len(events) and events[index][0]==frame:
                    _,event_type,note,value=events[index]
                    if excitations is not None and event_type==1:
                        instrument.excite(note,excitations[index])
                    else:instrument.event(event_type,note,value)
                    index+=1
                end=min(frames,frame+block_size,events[index][0] if index<len(events) else frames)
                instrument.process_into(output[frame:end]);frame=end
        return output


class AnalogParameters(C.Structure):
    _fields_=[(k,C.c_double) for k in ('cutoff','resonance','attack','decay','sustain','release','detune')]+[
        ('mix',C.c_float),('gain',C.c_float),('osc1',C.c_uint32),('osc2',C.c_uint32)]


class NativeInstrument:
    def __init__(self,library,kind,rate,parameters,seed):
        import math
        if kind not in ('Analog Synth','Guitar'):raise ValueError('Unsupported native instrument')
        if not math.isfinite(rate) or not 8000<=rate<=192000:raise ValueError('Unsupported sample rate')
        if type(seed) is not int or not 0<=seed<2**64:raise ValueError('Invalid excitation seed')
        p=dict(cutoff=1800.,resonance=.25,attack=.005,decay=.15,sustain=.7,release=.3,detuneCents=8.,osc2Mix=.5,gain=.5,osc1=2,osc2=2)
        p.update(parameters or {})
        for key in ('osc1','osc2'):
            if not isinstance(p[key],(int,float)) or not math.isfinite(p[key]) or p[key] not in range(4):raise ValueError('Invalid oscillator waveform')
            p[key]=int(p[key])
        params=AnalogParameters(*(p[k] for k in ('cutoff','resonance','attack','decay','sustain','release','detuneCents','osc2Mix','gain','osc1','osc2')))
        self.library=library
        library.ls_instrument_create.argtypes=[C.c_uint32,C.c_double,C.POINTER(AnalogParameters),C.c_uint64]
        library.ls_instrument_create.restype=C.c_void_p
        library.ls_instrument_destroy.argtypes=[C.c_void_p];library.ls_instrument_destroy.restype=None
        library.ls_instrument_event.argtypes=[C.c_void_p,C.c_uint32,C.c_int,C.c_float];library.ls_instrument_event.restype=C.c_int
        library.ls_instrument_process.argtypes=[C.c_void_p,C.POINTER(C.c_float),C.c_uint32];library.ls_instrument_process.restype=C.c_int
        library.ls_guitar_excitation.argtypes=[C.c_void_p,C.c_int,C.POINTER(C.c_float),C.c_uint32];library.ls_guitar_excitation.restype=C.c_int
        self.handle=library.ls_instrument_create(0 if kind=='Analog Synth' else 1,rate,C.byref(params),seed)
        if not self.handle:raise ValueError('Invalid native instrument parameters or allocation failure')

    def __enter__(self):return self
    def __exit__(self,*_):self.close()
    def close(self):
        if self.handle:self.library.ls_instrument_destroy(self.handle);self.handle=None

    @staticmethod
    def validate_event(event_type,note,value):
        import math
        if type(event_type) is not int or not 0<=event_type<=3 or type(note) is not int or not math.isfinite(value):raise ValueError('Invalid instrument event')
        if not (1<=note<=96 and -1<=value<=1 if event_type==2 else 0<=note<=127 and 0<=value<=1):raise ValueError('Invalid instrument event')

    def event(self,event_type,note,value=0.):
        self.validate_event(event_type,note,value)
        if self.library.ls_instrument_event(self.handle,event_type,note,value):raise ValueError('Invalid instrument event')

    def process_into(self,samples):
        if len(samples)>65536 or samples.dtype!=np.float32 or samples.ndim!=1 or not samples.flags.c_contiguous or not samples.flags.writeable:raise ValueError('Expected writable contiguous mono float32 buffer')
        if self.library.ls_instrument_process(self.handle,samples.ctypes.data_as(C.POINTER(C.c_float)),len(samples)):raise ValueError('Invalid instrument block or closed instance')

    def excite(self,note,samples):
        samples=np.ascontiguousarray(samples,dtype=np.float32)
        if samples.ndim!=1 or type(note) is not int or not 0<=note<=127:raise ValueError('Invalid guitar excitation')
        if self.library.ls_guitar_excitation(self.handle,note,samples.ctypes.data_as(C.POINTER(C.c_float)),len(samples)):raise ValueError('Invalid guitar excitation')
