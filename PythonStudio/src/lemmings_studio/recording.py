"""Recoverable dry takes. Native input and the disk/document workers are separate."""
from pathlib import Path
from threading import Event,Thread
from uuid import uuid4
import json,os,time
import numpy as np
import soundfile as sf
from .native_capture import NativeCapture


def recording_folder():
    configured=os.environ.get('LEMMINGS_DIAGNOSTICS_DIR')
    if configured:return Path(configured).parent/'Recordings'
    if os.name=='nt':return Path(os.environ.get('LOCALAPPDATA',str(Path.home())))/'LemmingsStudio/Recordings'
    return Path(__file__).resolve().parents[3]/'.local/Recordings'


def manifest(path,info):
    temporary=path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(info,indent=2),encoding='utf-8')
    os.replace(temporary,path)


class DryRecorder:
    """One take at a time. Stop is asynchronous; finish fires after drain and close."""
    def __init__(self):
        self.thread=None;self.stopped=Event();self.on_progress=lambda info:None;self.on_finished=lambda result:None
    @property
    def running(self):return bool(self.thread and self.thread.is_alive())
    def stop(self):self.stopped.set()
    def start(self,library,endpoint,context,folder=None,*,capture_factory=NativeCapture,max_seconds=600):
        if self.running:raise RuntimeError('A recording is already active')
        self.stopped=Event();stopped=self.stopped
        def run():
            token=uuid4().hex;root=Path(folder or recording_folder()).absolute();path=root/(token+'.wav');sidecar=root/(token+'.json')
            info={**context,'path':str(path),'state':'opening','frames':0,'endpoint':endpoint};error=None
            try:
                root.mkdir(parents=True,exist_ok=True);manifest(sidecar,info)
                with capture_factory(library,endpoint) as capture:
                    stats=capture.info();rate=stats['rate'];channels=stats['channels'];limit=round(max_seconds*rate)
                    info.update(rate=rate,channels=channels,state='recording',native=stats)
                    manifest(sidecar,info);last_flush=time.monotonic();last_progress=0.
                    # Original shared AudioClip stores mono. Keep a full-channel dry
                    # source for recovery; fold to mono only on project insertion.
                    with sf.SoundFile(path,'x',samplerate=rate,channels=channels,format='WAV',subtype='FLOAT') as output:
                        input_error=None
                        while True:
                            if stopped.is_set() or input_error:capture.stop()
                            block=capture.read();remaining=limit-info['frames']
                            if len(block):
                                output.write(block[:remaining]);info['frames']+=min(len(block),remaining)
                            stats=capture.info();info['native']=stats
                            if time.monotonic()-last_progress>=.05:
                                self.on_progress({**info,'seconds':info['frames']/rate});last_progress=time.monotonic()
                            if stats['error']:input_error=f"Native input stopped ({stats['error']}); retained dry take: {path}"
                            if info['frames']>=limit:
                                info['limitReached']=True;capture.stop();break
                            if (stopped.is_set() or input_error) and not len(block):break
                            if time.monotonic()-last_flush>=1:
                                output.flush();manifest(sidecar,info);last_flush=time.monotonic();last_progress=0.
                            if not len(block):stopped.wait(.01)
                        output.flush()
                        if input_error:raise RuntimeError(input_error)
                if not info['frames']:raise RuntimeError('No input frames were recorded; project unchanged')
                if stats['discontinuities']:raise RuntimeError(f"Input reported {stats['discontinuities']} discontinuities; inspect the retained take before importing: {path}")
                info['state']='complete'
            except Exception as failure:
                error=f'{type(failure).__name__}: {failure}';info.update(state='recoverable',error=error)
            finally:
                try:manifest(sidecar,info)
                except Exception as failure:error=(error or '')+f' Recording metadata could not be saved: {failure}'
                self.on_finished({'take':info,'error':error})
        self.thread=Thread(target=run,name='LemmingsDryRecording',daemon=True);self.thread.start()


def take_clip(info):
    """Runs on a document worker. Preserve dry file and embed portable mono audio."""
    from .workspace_document import identity
    path=Path(info['path']);samples,rate=sf.read(path,dtype='float32',always_2d=True)
    if not len(samples) or len(samples)!=info['frames']:raise ValueError('Recording length changed; retained source was not inserted')
    if not np.isfinite(samples).all():raise ValueError('Recording contains invalid audio')
    return {'id':identity(),'startBeat':info['startBeat'],'samples':np.mean(samples,axis=1,dtype=np.float32).tolist(),
            'sampleRate':rate,'devices':[],'externalPluginSlots':[],'warpEnabled':False,'loopEnabled':False,
            'originalTempo':info['bpm'],'displayName':'Recorded take','sourceURL':path.as_uri(),'isActive':True,'gainDB':0}
