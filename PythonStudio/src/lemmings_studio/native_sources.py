"""Native drum and sample-layer state; loading/decoding is outside audio processing."""
import ctypes as C
from pathlib import Path
import math
import numpy as np
import soundfile as sf
from .native_audio import DrumParameters,NativeInstrument
from .audio import local_media_path

class NativeKit:
    def __init__(self,engine,rate,kit):
        lib=self.library=engine.library
        lib.ls_kit_create.argtypes=[C.c_double,C.POINTER(DrumParameters)];lib.ls_kit_create.restype=C.c_void_p
        lib.ls_kit_destroy.argtypes=[C.c_void_p];lib.ls_kit_destroy.restype=None
        lib.ls_kit_event.argtypes=[C.c_void_p,C.c_uint32,C.c_int,C.c_float];lib.ls_kit_event.restype=C.c_int
        lib.ls_kit_set.argtypes=[C.c_void_p,C.c_char_p,C.c_double];lib.ls_kit_set.restype=C.c_int
        lib.ls_kit_process.argtypes=[C.c_void_p,C.POINTER(C.c_float),C.c_uint32];lib.ls_kit_process.restype=C.c_int
        table=(DrumParameters*10)(*(DrumParameters(**kit[str(i)],velocity=1.) for i in range(10)))
        self.handle=lib.ls_kit_create(rate,table)
        if not self.handle:raise ValueError('Invalid native drum kit')
    def event(self,event_type,note,value=0.):
        NativeInstrument.validate_event(event_type,note,value)
        if event_type==2:return # original drum kit ignores bend
        if self.library.ls_kit_event(self.handle,event_type,note,value):raise ValueError('Invalid drum event')
    def set(self,key,value):
        if not math.isfinite(value) or self.library.ls_kit_set(self.handle,key.encode(),value):raise ValueError('Invalid drum parameter')
    def process_into(self,mono):
        if mono.dtype!=np.float32 or mono.ndim!=1 or len(mono)>65536 or not mono.flags.c_contiguous or not mono.flags.writeable:raise ValueError('Invalid drum buffer')
        if self.library.ls_kit_process(self.handle,mono.ctypes.data_as(C.POINTER(C.c_float)),len(mono)):raise ValueError('Closed drum kit')
    def close(self):
        if self.handle:self.library.ls_kit_destroy(self.handle);self.handle=None
    def __enter__(self):return self
    def __exit__(self,*_):self.close()

def load_layer(layer,base):
    # Embedded mono data is also used by the paired Swift document reader.
    if layer.get('embeddedSamples') is not None:
        samples=np.asarray(layer['embeddedSamples'],dtype=np.float32)
    else:
        path=local_media_path(layer['samplePath'],base)
        info=sf.info(path)
        if info.frames>192000*600:raise ValueError('Sample exceeds ten-minute decode limit')
        audio,_=sf.read(path,dtype='float32',always_2d=True)
        samples=np.sum(audio,axis=1,dtype=np.float32)/np.float32(audio.shape[1])
    if samples.ndim!=1 or len(samples)>192000*600 or not len(samples) or not np.isfinite(samples).all():raise ValueError('Missing or invalid sample-layer audio')
    # Original Mac sample-layer instrument intentionally plays source frames
    # directly, without resampling. Do not silently change one-shot pitch here.
    return np.ascontiguousarray(samples)

class NativeSamples:
    def __init__(self,engine,layers,base,max_voices):
        self.handle=None;lib=self.library=engine.library;self.notes=set()
        lib.ls_samples_create.argtypes=[C.c_uint32];lib.ls_samples_create.restype=C.c_void_p
        lib.ls_samples_destroy.argtypes=[C.c_void_p];lib.ls_samples_destroy.restype=None
        lib.ls_samples_load.argtypes=[C.c_void_p,C.c_int,C.POINTER(C.c_float),C.c_uint32,C.c_float];lib.ls_samples_load.restype=C.c_int
        lib.ls_samples_event.argtypes=[C.c_void_p,C.c_uint32,C.c_int,C.c_float];lib.ls_samples_event.restype=C.c_int
        lib.ls_samples_process.argtypes=[C.c_void_p,C.POINTER(C.c_float),C.c_uint32];lib.ls_samples_process.restype=C.c_int
        self.handle=lib.ls_samples_create(max_voices)
        if not self.handle:raise ValueError('Cannot create sample mixer')
        try:
            for layer in layers:
                if not layer.get('samplePath') and layer.get('embeddedSamples') is None:continue
                samples=load_layer(layer,base);note=layer['note'];level=layer.get('velocity',.9)
                if type(note) is not int or not 0<=note<=127 or not math.isfinite(level) or not 0<=level<=1:raise ValueError('Invalid sample layer')
                if lib.ls_samples_load(self.handle,note,samples.ctypes.data_as(C.POINTER(C.c_float)),len(samples),level):raise ValueError('Cannot load sample layer')
                self.notes.add(note)
        except BaseException:self.close();raise
    def event(self,event_type,note,value=0.):
        NativeInstrument.validate_event(event_type,note,value)
        if event_type==2:return
        if self.library.ls_samples_event(self.handle,event_type,note,value):raise ValueError('Invalid sample event')
    def process_into(self,mono):
        if mono.dtype!=np.float32 or mono.ndim!=1 or len(mono)>65536 or not mono.flags.c_contiguous or not mono.flags.writeable:raise ValueError('Invalid sample buffer')
        if self.library.ls_samples_process(self.handle,mono.ctypes.data_as(C.POINTER(C.c_float)),len(mono)):raise ValueError('Closed sample mixer')
    def close(self):
        if self.handle:self.library.ls_samples_destroy(self.handle);self.handle=None
    def __enter__(self):return self
    def __exit__(self,*_):self.close()

def warp(engine,samples,ratio,mode):
    if mode not in ('Beat','Complex','Complex Pro') or not math.isfinite(ratio) or not .03125<=ratio<=32:raise ValueError('Invalid warp settings')
    samples=np.ascontiguousarray(samples,dtype=np.float32)
    if samples.ndim!=1 or len(samples)>192000*600 or not np.isfinite(samples).all():raise ValueError('Invalid warp source')
    length=len(samples) if len(samples)<=4096 else int(len(samples)*ratio)+2048
    if length>192000*600:raise ValueError('Warped audio exceeds ten minutes')
    result=np.zeros(length,dtype=np.float32)
    method=engine.library.ls_warp;method.argtypes=[C.POINTER(C.c_float),C.c_uint32,C.c_double,C.c_uint32,C.POINTER(C.c_float),C.c_uint32];method.restype=C.c_int
    if method(samples.ctypes.data_as(C.POINTER(C.c_float)),len(samples),ratio,('Beat','Complex','Complex Pro').index(mode),result.ctypes.data_as(C.POINTER(C.c_float)),length):raise ValueError('Native warp failed')
    return result
