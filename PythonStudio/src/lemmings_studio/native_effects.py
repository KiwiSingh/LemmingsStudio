"""Persistent stereo effect instances with validated, stable stock parameter IDs."""
from pathlib import Path
import ctypes as C
import json,math
import numpy as np
from .stock_contract import EFFECT_FAMILIES,MIDI_DEVICES,RACK_DEVICES

REFERENCE=json.loads((Path(__file__).parent/'qml/WorkspaceReference.json').read_text(encoding='utf-8'))
DEFINITIONS={d['kind']:d for d in REFERENCE['devices']}
class Parameter(C.Structure):
    _fields_=[('id',C.c_char_p),('value',C.c_double)]

class NativeEffect:
    def __init__(self,engine,kind,rate,parameters=None,tempo=124):
        if kind not in EFFECT_FAMILIES:raise ValueError(f'{kind}: native effect unavailable')
        if not math.isfinite(rate) or not 8000<=rate<=192000 or not math.isfinite(tempo) or not 20<=tempo<=400:raise ValueError('Invalid rate/tempo')
        self.kind=kind;self.definition=DEFINITIONS[kind];self.library=engine.library;self.handle=None
        self.parameters=dict(self.definition['defaults'])
        for key,value in (parameters or {}).items():
            self.validate(key,value);self.parameters[key]=value
        # Internal pitch context is explicitly supplied by the host, not stored as an endpoint.
        if kind=='Pitch Corrector':self.parameters.update(keyRoot=0,scaleMask=0b101011010101)
        table=(Parameter*len(self.parameters))(*(Parameter(k.encode(),v) for k,v in self.parameters.items()))
        lib=self.library
        lib.ls_effect_create.argtypes=[C.c_char_p,C.c_double,C.c_double,C.POINTER(Parameter),C.c_uint32];lib.ls_effect_create.restype=C.c_void_p
        lib.ls_effect_destroy.argtypes=[C.c_void_p];lib.ls_effect_destroy.restype=None
        lib.ls_effect_set.argtypes=[C.c_void_p,C.c_char_p,C.c_double];lib.ls_effect_set.restype=C.c_int
        lib.ls_effect_process.argtypes=[C.c_void_p,C.POINTER(C.c_float),C.c_uint32,C.POINTER(C.c_float)];lib.ls_effect_process.restype=C.c_int
        self.handle=lib.ls_effect_create(EFFECT_FAMILIES[kind].encode(),rate,tempo,table,len(table))
        if not self.handle:raise ValueError('Native effect creation failed')
    def validate(self,key,value):
        definition=next((p for p in self.definition['params'] if p['id']==key),None)
        if definition is None or not isinstance(value,(int,float)) or not math.isfinite(value) or not definition['min']<=value<=definition['max']:
            raise ValueError(f'{self.kind}: invalid {key} parameter')
    def get(self,key):
        value=C.c_double();method=self.library.ls_effect_get
        method.argtypes=[C.c_void_p,C.c_char_p,C.POINTER(C.c_double)];method.restype=C.c_int
        if method(self.handle,key.encode(),C.byref(value)):raise ValueError('Invalid parameter or closed effect')
        return value.value
    def set(self,key,value):
        if not self.handle:raise ValueError('Closed native effect')
        self.validate(key,value)
        if self.parameters.get(key)==value:return
        if self.library.ls_effect_set(self.handle,key.encode(),value):raise ValueError('Closed or invalid native effect')
        self.parameters[key]=value
    def reset(self):
        method=self.library.ls_effect_reset;method.argtypes=[C.c_void_p];method.restype=C.c_int
        if method(self.handle):raise ValueError('Closed effect')
    def tempo(self,bpm):
        method=self.library.ls_effect_tempo;method.argtypes=[C.c_void_p,C.c_double];method.restype=C.c_int
        if method(self.handle,bpm):raise ValueError('Invalid effect tempo')
    def context(self,root,mask):
        if self.kind!='Pitch Corrector' or type(root) is not int or not 0<=root<=11 or type(mask) is not int or not 1<=mask<4096:raise ValueError('Invalid pitch context')
        for k,v in [('keyRoot',root),('scaleMask',mask)]:
            if self.library.ls_effect_set(self.handle,k.encode(),v):raise ValueError('Closed native effect')
    def process_into(self,stereo,sidechain=None):
        if stereo.dtype!=np.float32 or stereo.ndim!=2 or stereo.shape[1]!=2 or len(stereo)>65536 or not stereo.flags.c_contiguous or not stereo.flags.writeable:raise ValueError('Expected writable contiguous stereo float32 block')
        if not np.isfinite(stereo).all():raise ValueError('Nonfinite audio')
        if sidechain is not None:
            sidechain=np.ascontiguousarray(sidechain,dtype=np.float32)
            if sidechain.shape!=stereo.shape or not np.isfinite(sidechain).all():raise ValueError('Invalid sidechain')
        ptr=lambda a:a.ctypes.data_as(C.POINTER(C.c_float))
        if self.library.ls_effect_process(self.handle,ptr(stereo),len(stereo),None if sidechain is None else ptr(sidechain)):raise ValueError('Invalid native effect block or closed instance')
    def close(self):
        if self.handle:self.library.ls_effect_destroy(self.handle);self.handle=None
    def __enter__(self):return self
    def __exit__(self,*_):self.close()

def render_effect(engine,kind,stereo,rate,parameters=None,tempo=124,block_size=128,sidechain=None):
    if type(block_size) is not int or not 1<=block_size<=65536:raise ValueError('Invalid effect block size')
    result=np.array(stereo,dtype=np.float32,order='C',copy=True)
    with NativeEffect(engine,kind,rate,parameters,tempo) as effect:
        for start in range(0,len(result),block_size):effect.process_into(result[start:start+block_size],None if sidechain is None else sidechain[start:start+block_size])
    return result
