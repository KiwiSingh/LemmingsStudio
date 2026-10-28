"""Native WASAPI input. Python drains a ring on a disk worker, never an audio callback."""
from pathlib import Path
import ctypes as C
import numpy as np


class CaptureInfo(C.Structure):
    _fields_=[('rate',C.c_uint32),('channels',C.c_uint32),('capacity',C.c_uint32),
              ('received',C.c_uint64),('dropped',C.c_uint64),('discontinuities',C.c_uint64),
              ('endpoint_latency_seconds',C.c_double),('peak',C.c_float),('error',C.c_int32)]
    def as_dict(self):return {name:getattr(self,name) for name,_ in self._fields_}


class Device(C.Structure):
    _fields_=[('id',C.c_char*1024),('name',C.c_char*512)]


def bind(path):
    lib=C.CDLL(str(Path(path).resolve()))
    lib.ls_capture_abi_version.restype=C.c_uint32
    if lib.ls_capture_abi_version()!=1:raise RuntimeError('Unsupported input engine ABI')
    signatures={
        'ls_capture_device':([C.c_int,C.POINTER(Device)],C.c_int),
        'ls_capture_open':([C.c_char_p],C.c_void_p),
        'ls_capture_test_open':([C.c_uint32,C.c_uint32,C.c_uint32],C.c_void_p),
        'ls_capture_test_push':([C.c_void_p,C.POINTER(C.c_float),C.c_uint32,C.c_uint32],C.c_int),
        'ls_capture_info':([C.c_void_p,C.POINTER(CaptureInfo)],C.c_int),
        'ls_capture_read':([C.c_void_p,C.POINTER(C.c_float),C.c_uint32],C.c_int),
        'ls_capture_stop':([C.c_void_p],None),'ls_capture_destroy':([C.c_void_p],None)}
    for name,(args,result) in signatures.items():
        fn=getattr(lib,name);fn.argtypes=args;fn.restype=result
    return lib


def input_devices(path):
    lib=bind(path);count=lib.ls_capture_device(-1,None)
    if count<0:raise RuntimeError(f'Windows input enumeration failed ({count}); check Windows Audio and microphone permissions')
    devices=[{'id':'','name':'Windows default recording device'}]
    for index in range(count):
        device=Device();result=lib.ls_capture_device(index,C.byref(device))
        if result<0:raise RuntimeError('Input devices changed while enumerating; try again')
        devices.append({'id':device.id.decode('utf-8'),'name':device.name.decode('utf-8')})
    return devices


class NativeCapture:
    def __init__(self,path,endpoint='',*,test_format=None):
        self.lib=bind(path)
        self.handle=(self.lib.ls_capture_test_open(*test_format) if test_format else self.lib.ls_capture_open(endpoint.encode('utf-8')))
        if not self.handle:raise RuntimeError('Could not open Windows input. Check the selected device, microphone privacy permission and Windows Audio; the project was preserved.')
        try:
            self.channels=self.info()['channels']
            self.buffer=np.empty((65536,self.channels),dtype=np.float32)
        except BaseException:
            self.close();raise
    def info(self):
        if not self.handle:raise RuntimeError('Input is closed')
        info=CaptureInfo();self.lib.ls_capture_info(self.handle,C.byref(info));return info.as_dict()
    def read(self):
        if not self.handle:raise RuntimeError('Input is closed')
        count=self.lib.ls_capture_read(self.handle,self.buffer.ctypes.data_as(C.POINTER(C.c_float)),len(self.buffer))
        if count<0:raise RuntimeError('Native input read failed')
        return self.buffer[:count] # owned by this instance, valid until the next read
    def stop(self):
        if self.handle:self.lib.ls_capture_stop(self.handle)
    def close(self):
        if self.handle:self.lib.ls_capture_destroy(self.handle);self.handle=None
    def __enter__(self):return self
    def __exit__(self,*args):self.close()
