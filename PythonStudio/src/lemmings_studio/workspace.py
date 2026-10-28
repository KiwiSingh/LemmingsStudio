"""Qt Quick workspace controller. Presentation never owns musical state."""
from copy import deepcopy
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event
import json,math,os,time,sys
from PySide6.QtCore import QObject,Signal,Slot,Property,QUrl,QTimer
from PySide6.QtGui import QImage
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication,QFileDialog,QMessageBox,QInputDialog
from .workspace_document import WorkspaceDocument,identity,numeric
from .project_contract import ProjectFile
from .workspace_audio import REFERENCE,Snapshot,WorkspaceRenderer
from .audio import AudioEngine
from .recording import DryRecorder,take_clip,recording_folder
from .native_capture import input_devices
from .workspace_audio import library_path
from .stock_contract import ANALOG_DEVICES,BUILTIN_DEVICES,EFFECT_FAMILIES,MIDI_DEVICES,RACK_DEVICES,STEP_KINDS,DRUM_LANES

WORKSPACES=['Session','Arrangement','Piano Roll','Step Sequencer','Devices','Automation','Mixer']
BROWSER=['Library','Tracks','Splice','Samples','Sounds','Pads','FX/Plugins']
DOCK=['Chat','AI','Sound','Splice','Voices','Fifths','Inspect']
COLOURS=REFERENCE['trackColors']
KINDS=['Analog Synth','Guitar','Drum Machine','Indian Percussion','Bhangra Dhol','Sequencer',
       'Bhangra Architect','2C','Bailaton','Oscillatron','LemmingBass','Dubstep Wrangler','Audio (Recorded)']


class WorkspaceController(QObject):
    changed=Signal()
    transportChanged=Signal()
    completed=Signal(object)
    position=Signal(int,float)
    audioFinished=Signal(int,str)
    recordingProgress=Signal(object)
    recordingFinished=Signal(object)

    def __init__(self,data=None,persist_preferences=True):
        super().__init__()
        self._state_cache=None
        self.document=WorkspaceDocument(data)
        self.track_id=self.document.data['tracks'][0]['id'] if self.document.data['tracks'] else ''
        self.clip_id='';self.note_id='';self.selected_tracks=[self.track_id]
        self.workspace='Session';self.persist_preferences=persist_preferences;self.browser='Library';self.dock='AI';self.detail='Devices'
        self.theme=REFERENCE['themes'][0]['name'];self.status='Ready';self.path=None;self.beat=0.;self.snap=.25
        self.search='';self.scenes=8;self.metronome=True;self.master_gain=1.;self.epoch=0;self.pending=0;self.cancel=Event();self.tap_times=[]
        self.jobs=ThreadPoolExecutor(max_workers=1,thread_name_prefix='LemmingsWorkspace')
        self.completed.connect(self._complete)
        self.engine=AudioEngine()
        self.recorder=DryRecorder();self.record_state='idle';self.record_seconds=0.;self.input_peak=0.
        self.input_endpoint='';self.input_name='Windows default recording device'
        self.recorder.on_progress=self.recordingProgress.emit;self.recorder.on_finished=self.recordingFinished.emit
        self.recordingProgress.connect(self._recording_progress);self.recordingFinished.connect(self._recording_finished)
        self.render_update=QTimer(self);self.render_update.setSingleShot(True);self.render_update.setInterval(120);self.render_update.timeout.connect(self.refresh_playback)
        self.engine.on_position=self.position.emit;self.engine.on_finished=self.audioFinished.emit
        self.position.connect(self._position);self.audioFinished.connect(self._audio_finished)
        self.settings_path=recording_folder().parent/'workspace-settings.json'
        try:
            settings=json.loads(self.settings_path.read_text(encoding='utf-8'))
            if settings.get('theme') in [t['name'] for t in REFERENCE['themes']]: self.theme=settings['theme']
            if settings.get('workspace') in WORKSPACES:self.workspace=settings['workspace']
            self.input_endpoint=str(settings.get('inputEndpoint',''));self.input_name=str(settings.get('inputName','Windows default recording device'))
        except (OSError,ValueError): pass

    def save_preferences(self):
        if self.persist_preferences:
            self.settings_path.parent.mkdir(parents=True,exist_ok=True)
            self.settings_path.write_text(json.dumps({'theme':self.theme,'workspace':self.workspace,'inputEndpoint':self.input_endpoint,'inputName':self.input_name}),encoding='utf-8')

    def _emit_changed(self):
        # QML notify consumers can run before ordinary signal-connected Python
        # slots. Invalidate before emission so every consumer reads this edit.
        self._state_cache=None
        self.changed.emit()

    def track(self,data=None):
        try:return WorkspaceDocument.track(data or self.document.data,self.track_id)
        except StopIteration:raise ValueError('Select a track first')

    def clip(self,data=None):
        try: return WorkspaceDocument.clip(self.track(data),self.clip_id)
        except (StopIteration,KeyError,ValueError): return None

    def message(self,value):
        self.status=str(value);self._emit_changed()

    def notify(self):
        if self.track_id not in [t['id'] for t in self.document.data['tracks']]:
            self.track_id=self.document.data['tracks'][0]['id'] if self.document.data['tracks'] else ''
        ids={t['id'] for t in self.document.data['tracks']}
        self.selected_tracks=[tid for tid in self.selected_tracks if tid in ids] or ([self.track_id] if self.track_id else [])
        clip=self.clip()
        if clip is None:self.clip_id='';self.note_id=''
        elif self.note_id not in {n['id'] for n in clip.get('notes',[])}:self.note_id=''
        self._emit_changed()

    @Property('QVariantMap',notify=changed)
    def palette(self):
        return next(t['palette'] for t in REFERENCE['themes'] if t['name']==self.theme)

    @Property('QVariantMap',notify=transportChanged)
    def transport(self):
        tempo=self.document.data.get('bpm',124)
        return {'beat':self.beat,'playing':self.engine.running,
                'position':f'{int(self.beat//4)+1}:{int(self.beat%4)+1}:{int(self.beat%1*960):03}',
                'time':f'{self.beat*60/tempo:.2f} s'}

    @Property('QVariantMap',notify=changed)
    def state(self):
        if self._state_cache is not None:return self._state_cache
        data=self.document.data;tracks=[]
        for track in data['tracks']:
            row={k:deepcopy(v) for k,v in track.items() if k not in ('clips','audioClips','bounced')}
            row['color']=COLOURS[track.get('colorIndex',0)%len(COLOURS)]
            row['clips']=[]
            for clip in [*track.get('clips',[]),*track.get('audioClips',[])]:
                view={k:deepcopy(v) for k,v in clip.items() if k!='samples'}
                audio='samples' in clip;view['audio']=audio
                view['name']=clip.get('name',clip.get('displayName','Audio Clip'))
                view['lengthBeats']=clip.get('lengthBeats',clip.get('lengthBeatsOverride',len(clip.get('samples',[]))/clip.get('sampleRate',48000)*data['bpm']/60))
                if audio:
                    samples=clip['samples'];hop=max(1,len(samples)//160)
                    view['waveform']=[max(abs(x) for x in samples[i:i+hop]) for i in range(0,len(samples),hop)][:160]
                row['clips'].append(view)
            tracks.append(row)
        selected=next((t for t in tracks if t['id']==self.track_id),{})
        clip=next((c for c in selected.get('clips',[]) if c['id']==self.clip_id),{})
        devices=deepcopy(selected.get('devices',[]))
        for device in devices:
            definition=next((x for x in REFERENCE['devices'] if x['kind']==device['kind']),None)
            device['nativeInstrument']=device['kind'] in BUILTIN_DEVICES
            device['audioStatus']=('Source instrument controls · original Mac parameter mapping' if device['nativeInstrument'] else 'Original native stereo processing · playback and export' if device['kind'] in EFFECT_FAMILIES else 'MIDI scheduling · original Mac rules' if device['kind'] in MIDI_DEVICES else 'Registry rack · pass-through behavior matches the current Mac build' if device['kind'] in RACK_DEVICES else 'External endpoint unavailable · project state preserved')
            device['controls']=deepcopy(definition['params']) if definition else []
            for p in device['controls']: p['value']=device.get('params',{}).get(p['id'],definition['defaults'].get(p['id'],p['min']))
        instrument=next((d for d in REFERENCE['devices'] if d['kind']=={'Analog Synth':'Subtractive Synth','Drum Machine':'Drum Matrix','Sequencer':'Drum Matrix'}.get(selected.get('kind'),selected.get('kind'))),None)
        instrument_params=deepcopy(instrument['params']) if instrument else []
        if selected.get('kind') in ('Drum Machine','Sequencer'):
            instrument_params=[{'id':'master','name':'Master','min':0.,'max':1.5,'log':False}]
            for voice in range(10):
                for param,lo,hi in [('tune',.5,2.),('decay',.2,3.),('level',0.,1.5)]:
                    instrument_params.append({'id':f'{voice}_{param}','name':f'Voice {voice} {param}','min':lo,'max':hi,'log':False})
        nodes=[{'id':'instrument','name':selected.get('kind','Instrument'),'params':instrument_params}]
        nodes.extend({'id':d['id'],'name':d['kind'],'params':deepcopy(d['controls'])+[{'id':'__device_on__','name':'Device On','min':0.,'max':1.,'log':False}]} for d in devices)
        percussion=selected.get('kind') in ('Indian Percussion','Bhangra Dhol','Bhangra Architect')
        step_lanes=deepcopy(REFERENCE.get('percussionLanes',[]) if percussion else DRUM_LANES)
        if percussion and selected.get('kind')!='Bhangra Architect':step_lanes=step_lanes[:12]
        for layer in selected.get('sequencerLayers',[]):
            lane=next((l for l in step_lanes if l['note']==layer['note']),None)
            if lane:lane['name']=layer['name']
            else:step_lanes.append({'name':layer['name'],'note':layer['note']})
        self._state_cache={'lengthBeats':data.get('lengthBars',32)*data.get('beatsPerBar',4),'projectName':data['name'],'dirty':self.document.dirty,'tempo':data['bpm'],
                'keyRoot':data.get('keyRoot',0),'scale':data.get('scaleName','Major'),
                'tracks':tracks,'selected':selected,'clip':clip,'devices':devices,
                'selectedTrack':self.track_id,'selectedClip':self.clip_id,'selectedNote':self.note_id,
                'note':next((n for n in clip.get('notes',[]) if n['id']==self.note_id),{}),'selectedTracks':self.selected_tracks,'workspace':self.workspace,'workspaces':WORKSPACES,
                'browser':self.browser,'browserTabs':BROWSER,'dock':self.dock,'dockTabs':DOCK,
                'detail':self.detail,'status':self.status,'busy':self.pending>0,
                'recordState':self.record_state,'recordSeconds':self.record_seconds,'inputPeak':self.input_peak,'inputName':self.input_name,'nativeInputAvailable':sys.platform=='win32',
                'canUndo':bool(self.document.undo_stack),'canRedo':bool(self.document.redo_stack),
                'themes':[t['name'] for t in REFERENCE['themes']],'theme':self.theme,
                'glyph':next(t['glyph'] for t in REFERENCE['themes'] if t['name']==self.theme),
                'catalog':[d for d in REFERENCE['devices'] if self.search.lower() in d['kind'].lower()],
                'scales':[s['name'] for s in REFERENCE['scales']],'trackKinds':KINDS,'kits':list(REFERENCE['drumKits']),'scenes':self.scenes,
                'stepEditable':selected.get('kind') in STEP_KINDS,'stepLanes':step_lanes,'percussionGrooves':REFERENCE.get('percussionGrooves',[]) if percussion else [],'metronome':self.metronome,'masterGain':self.master_gain,'masterDevices':data.get('masterDevices',[]),'automationNodes':nodes,'tempoPoints':data.get('tempoPoints',[]),'tempoAutomationEnabled':data.get('tempoAutomationEnabled',False),'groups':data.get('groups',[]),'returns':data.get('returnBuses',[]),'snap':self.snap}
        return self._state_cache

    @Slot(str,'QVariantMap')
    def command(self,name,args):
        try:
            before=self.document.revision
            self._command(name,dict(args))
            if self.document.revision!=before or name in ('workspace','masterGain','metronome'):
                self.render_update.start()
            self.notify()
        except Exception as error: self.message(str(error))

    def _command(self,name,a):
        if self.record_state!='idle' and name not in ('stop','record','workspace','browser','dock','detail','search','theme','selectTrack','selectClip','selectNote'):
            raise ValueError('Stop recording and wait for the take to finish before editing the session')
        tid=a.get('track',self.track_id);cid=a.get('clip',self.clip_id)
        if name=='workspace': self.workspace=a['value'] if a['value'] in WORKSPACES else self.workspace;self.save_preferences()
        elif name=='browser': self.browser=a['value'] if a['value'] in BROWSER else self.browser
        elif name=='dock': self.dock=a['value'] if a['value'] in DOCK else self.dock
        elif name=='detail': self.detail=a['value']
        elif name=='search': self.search=a['value']
        elif name=='theme':
            if a['value'] not in [t['name'] for t in REFERENCE['themes']]: raise ValueError('Unknown theme')
            self.theme=a['value'];self.save_preferences()
        elif name=='selectTrack':
            self.track_id=tid;self.clip_id='';self.note_id=''
            if a.get('extend'): self.selected_tracks=list(dict.fromkeys([*self.selected_tracks,tid]))
            else: self.selected_tracks=[tid]
        elif name=='selectClip': self.track_id=tid;self.selected_tracks=[tid];self.clip_id=cid;self.note_id=''
        elif name=='selectNote': self.note_id=a['note']
        elif name=='addTrack': self.track_id=self.document.add_track(a.get('kind','Analog Synth'));self.selected_tracks=[self.track_id];self.clip_id=''
        elif name=='duplicateTrack':self.track_id=self.document.duplicate_track(tid);self.selected_tracks=[self.track_id];self.clip_id=''
        elif name=='splitClip':self.clip_id=self.document.split_clip(tid,cid,self.beat)
        elif name=='deleteTracks': self.document.delete_tracks(self.selected_tracks)
        elif name=='group': self.document.group(self.selected_tracks)
        elif name=='createClip': self.clip_id=self.document.create_clip(tid,a.get('start',0),a.get('length',4));self.track_id=tid
        elif name=='deleteClip': self.document.delete_clip(tid,cid);self.clip_id=''
        elif name=='duplicateClip': self.clip_id=self.document.duplicate_clip(tid,cid)
        elif name=='clip': self.document.edit_clip(tid,cid,a['values'])
        elif name=='moveClip':
            self.document.move_clip(tid,cid,a.get('target',tid),max(0,round(float(a['start'])/self.snap)*self.snap));self.track_id=a.get('target',tid);self.clip_id=cid
        elif name=='addNote': self.note_id=self.document.add_note(tid,cid,round(float(a['beat'])/self.snap)*self.snap,a['pitch'],a.get('length',.5))
        elif name=='note': self.document.edit_note(tid,cid,a['note'],a['values']);self.note_id=a['note']
        elif name=='deleteNote':
            note=a.get('note',self.note_id)
            def remove(data):
                clip=WorkspaceDocument.clip(WorkspaceDocument.track(data,tid),cid)
                clip['notes']=[n for n in clip['notes'] if n['id']!=note]
            self.document.edit('Delete note',remove);self.note_id=''
        elif name=='quantize':
            def quantize(data):
                for note in WorkspaceDocument.clip(WorkspaceDocument.track(data,tid),cid)['notes']:
                    note['start']=round(note['start']/self.snap)*self.snap
                    note['length']=max(self.snap,round(note['length']/self.snap)*self.snap)
            self.document.edit('Quantize notes',quantize)
        elif name=='step': self.document.toggle_step(tid,a['pitch'],a['step'])
        elif name=='percussionGroove':
            groove=next(g for g in REFERENCE['percussionGrooves'] if g['name']==a['name'])
            def load(data):
                track=WorkspaceDocument.track(data,tid)
                if track['kind'] not in ('Indian Percussion','Bhangra Dhol','Bhangra Architect'):raise ValueError('Select an Indian/Bhangra instrument')
                track['kind']='Bhangra Dhol' if track['kind']=='Bhangra Dhol' else 'Bhangra Architect'
                track.pop('pluginTargetID',None);track['externalPluginSlots']=[s for s in track.get('externalPluginSlots',[]) if s.get('role')!='Instrument']
                track['useStepSequencer']=True;track['stepPattern']={'stepCount':16,'stepsPerBeat':4,'steps':[{'on':n>=0,'note':max(0,n),'hits':[n] if n>=0 else [],'velocity':.9} for n in groove['notes']]}
                for indices,note,velocity in [([3,7,11,15],84,.72),([6,14],86,.5)]:
                    for index in indices:
                        step=track['stepPattern']['steps'][index];step['hits']=sorted(set(step['hits']+[note]));step.update(on=True,note=step['hits'][0],velocity=velocity)
                track['sequencerLayers']=[dict(deepcopy(lane),id=identity(),steps=[lane['note'] in s['hits'] for s in track['stepPattern']['steps']]) for lane in REFERENCE['percussionLanes']]
            self.document.edit('Load '+groove['name'],load)
        elif name=='patternLength':
            count=int(numeric(a['value'],4,64))
            def pattern(data):
                p=WorkspaceDocument.track(data,tid)['stepPattern'];p['stepCount']=count
                while len(p['steps'])<count:p['steps'].append({'on':False,'note':36,'velocity':.9,'hits':[]})
                p['steps']=p['steps'][:count]
            self.document.edit('Pattern length',pattern)
        elif name=='clearSteps':
            def clear(data):
                for s in WorkspaceDocument.track(data,tid)['stepPattern']['steps']:s.update(on=False,hits=[])
            self.document.edit('Clear pattern',clear)
        elif name=='audition': self.audition(int(a['pitch']))
        elif name=='chord': self.insert_chord()
        elif name=='printSteps': self.print_steps(tid)
        elif name=='masterGain':self.master_gain=numeric(a['value'],0,1)
        elif name=='addReturn':
            from .workspace_document import make_device
            self.document.edit('Add return bus',lambda d:d['returnBuses'].append({'id':identity(),'name':f'Return {len(d["returnBuses"])+1}','volume':.8,'pan':0.,'mute':False,'devices':[make_device('Room Space')]}))
        elif name=='returnBus':
            key=a['key'];value=a['value']
            if key in ('volume','pan'):value=numeric(value,*((0,4) if key=='volume' else (-1,1)))
            elif key=='mute':value=bool(value)
            elif key=='name':value=str(value)[:256]
            else:raise ValueError('Unsupported return control')
            self.document.edit('Return bus',lambda d:next(b for b in d['returnBuses'] if b['id']==a['bus']).__setitem__(key,value))
        elif name=='send':
            amount=numeric(a['amount'],0,1)
            def send(data):
                sends=WorkspaceDocument.track(data,tid)['sends'];item=next((s for s in sends if s['returnBusID']==a['bus']),None)
                if item is None:sends.append({'id':identity(),'returnBusID':a['bus'],'amount':amount,'preFader':False})
                else:item['amount']=amount
            self.document.edit('Send amount',send)
        elif name=='ungroup':
            def ungroup(data):
                for group in data['groups']:group['trackIDs']=[t for t in group['trackIDs'] if t not in self.selected_tracks]
                for tid in self.selected_tracks:WorkspaceDocument.track(data,tid).pop('groupID',None)
                data['groups']=[g for g in data['groups'] if g['trackIDs']]
            self.document.edit('Ungroup tracks',ungroup)
        elif name=='track': self.document.set_track(tid,a['key'],a['value'])
        elif name=='tempo':
            tempo=numeric(a['value'],20,400);self.document.edit('Tempo',lambda d:d.update(tempo=tempo,bpm=tempo))
        elif name=='key': self.document.edit('Project key',lambda d:d.update(keyRoot=int(numeric(a['root'],0,11)),scaleName=a.get('scale',d['scaleName'])))
        elif name=='snap': self.snap=numeric(a['value'],.03125,4)
        elif name=='addDevice':
            definition=next(d for d in REFERENCE['devices'] if d['kind']==a['kind'])
            self.document.add_device(tid,definition)
        elif name=='deviceParam':
            device=next(d for d in self.track()['devices'] if d['id']==a['device'])
            definition=next(d for d in REFERENCE['devices'] if d['kind']==device['kind'])
            self.document.device_param(tid,a['device'],a['param'],a['value'],definition)
        elif name in ('removeDevice','bypassDevice','monoDevice','moveDevice'):
            def edit(data):
                devices=WorkspaceDocument.track(data,tid)['devices'];device=next(d for d in devices if d['id']==a['device'])
                if name=='removeDevice': devices.remove(device)
                elif name=='bypassDevice': device['bypassed']=not device['bypassed']
                elif name=='monoDevice': device['mono']=not device['mono']
                else:
                    index=devices.index(device);target=max(0,min(len(devices)-1,index+int(a['offset'])))
                    devices.pop(index);devices.insert(target,device)
            self.document.edit('Device chain',edit)
        elif name in ('tempoEnabled','tempoClear','tempoPoint','tempoDelete'):
            def tempo_edit(data):
                if name=='tempoEnabled':data['tempoAutomationEnabled']=bool(a['value'])
                elif name=='tempoClear':data['tempoPoints']=[]
                elif name=='tempoDelete':data['tempoPoints'].pop(int(a['index']))
                else:
                    beat=numeric(a['beat'],0,data['lengthBars']*data['beatsPerBar']);value=numeric(a['value'],20,300)
                    if int(a['index'])>=0:data['tempoPoints'].pop(int(a['index']))
                    data['tempoPoints'].append({'beat':beat,'bpm':value});data['tempoPoints'].sort(key=lambda p:p['beat']);data['tempoAutomationEnabled']=True
            self.document.edit('Global tempo automation',tempo_edit)
        elif name in ('automationLane','automationLaneDelete','automationLaneEnabled','automationEdit'):
            def lane_edit(data):
                lanes=WorkspaceDocument.track(data,tid)['automationLanes']
                if name=='automationLane':
                    if not any(l['nodeID']==a['node'] and l['paramID']==a['param'] for l in lanes):lanes.append({'nodeID':a['node'],'paramID':a['param'],'enabled':True,'points':[]})
                elif name=='automationLaneDelete':lanes.pop(int(a['lane']))
                elif name=='automationLaneEnabled':lanes[int(a['lane'])]['enabled']=bool(a['value'])
                else:
                    lane=lanes[int(a['lane'])];beat=round(numeric(a['beat'],0,data['lengthBars']*data['beatsPerBar'])/self.snap)*self.snap;value=numeric(a['value'],-1e6,1e6)
                    if int(a['index'])>=0:lane['points'].pop(int(a['index']))
                    lane['points']=[p for p in lane['points'] if abs(p['beat']-beat)>.00001]
                    lane['points'].append({'beat':beat,'value':value});lane['points'].sort(key=lambda p:p['beat'])
            self.document.edit('Track automation',lane_edit)
        elif name=='automation': self.document.automation_point(tid,a['node'],a['param'],round(float(a['beat'])/self.snap)*self.snap,a['value'])
        elif name=='deleteAutomationPoint':
            def remove(data):
                lane=WorkspaceDocument.track(data,tid)['automationLanes'][int(a['lane'])]
                lane['points'].pop(int(a['index']))
            self.document.edit('Delete automation point',remove)
        elif name=='undo': self.status=self.document.undo()
        elif name=='redo': self.status=self.document.redo()
        elif name=='play':
            if self.engine.running:self.stop()
            else:self.play()
        elif name=='stop': self.stop()
        elif name=='record':
            if self.record_state!='idle':self.stop()
            else:self.record()
        elif name=='inputDevice':self.choose_input()
        elif name=='return': self.stop();self.beat=0.;self.transportChanged.emit()
        elif name=='seek': self.stop();self.beat=numeric(a['beat'],0,1e6);self.transportChanged.emit()
        elif name=='launchClip':
            self.track_id=tid;self.clip_id=cid;self.beat=WorkspaceDocument.clip(WorkspaceDocument.track(self.document.data,tid),cid)['startBeat'];self.play()
        elif name=='launchScene': self.beat=int(a['scene'])*self.document.data['beatsPerBar']*4;self.play()
        elif name=='scenes': self.scenes=int(numeric(a['value'],4,16))
        elif name=='tap':
            now=time.monotonic();self.tap_times=[t for t in self.tap_times if now-t<3]+[now]
            intervals=[b-a for a,b in zip(self.tap_times,self.tap_times[1:]) if .12<b-a<2]
            if intervals:self._command('tempo',{'value':60/(sum(intervals)/len(intervals))})
            else:self.status='Tap again'
        elif name=='new':
            if self.confirm_discard():self.stop();self.document=WorkspaceDocument();self.track_id=self.document.data['tracks'][0]['id'];self.selected_tracks=[self.track_id];self.clip_id='';self.note_id='';self.path=None;self.epoch+=1
        elif name=='open': self.open_project()
        elif name=='save': self.save_project(a.get('asNew',False))
        elif name=='importAudio': self.import_audio()
        elif name=='recoverRecording':self.import_audio(recording_folder())
        elif name=='export': self.export_audio()
        elif name=='metronome':self.metronome=not self.metronome
        elif name=='freeze':self.freeze_track(tid)
        elif name=='unfreeze':self.document.edit('Unfreeze track',lambda d:WorkspaceDocument.track(d,tid).update(frozen=False,bounced=None))
        elif name=='cancel': self.cancel.set();self.status='Cancelling…'
        else: raise ValueError('This capability awaits its Windows engine/integration port')
        if name not in ('undo','redo','tap','cancel','open','save','importAudio','recoverRecording','export','record','inputDevice','stop'):self.status=name[0].upper()+name[1:]

    def audition(self,pitch):
        if self.track()['kind']=='Audio (Recorded)':raise ValueError('Select an instrument track to audition')
        from .workspace_document import new_project
        data=new_project();data['lengthBars']=1
        track=deepcopy(self.track());track['mute']=False;track['solo']=False;track['groupID']=None;track['sends']=[];track['useStepSequencer']=False
        track['audioClips']=[];track['clips']=[{'id':identity(),'startBeat':0,'isActive':True,'notes':[{'id':identity(),'start':0,'length':.5,'pitch':pitch,'velocity':.9}]}];data['tracks']=[track]
        self.engine.play(Snapshot(data),self.path.parent if self.path else Path.cwd(),0,renderer_factory=WorkspaceRenderer)
        self.transportChanged.emit()

    def insert_chord(self):
        from .workspace_document import make_track
        scale=next((s for s in REFERENCE['scales'] if s['name']==self.document.data['scaleName']),REFERENCE['scales'][0])
        pitches=[60+self.document.data['keyRoot']+scale['intervals'][i] for i in (0,2,4)]
        def insert(data):
            track=WorkspaceDocument.track(data,self.track_id)
            if track['kind']=='Audio (Recorded)':raise ValueError('Select a MIDI instrument track')
            clip={'id':identity(),'name':'Tonic triad','startBeat':self.beat,'lengthBeats':4,'isActive':True,'loopEnabled':True,'loopLengthBeats':4,'notes':[
                {'id':identity(),'pitch':p,'start':0.,'length':4.,'velocity':.8} for p in pitches]}
            track['clips'].append(clip);self.clip_id=clip['id']
        self.document.edit('Insert tonic triad',insert);self.workspace='Piano Roll'

    def print_steps(self,tid):
        track=WorkspaceDocument.track(self.document.data,tid);p=track['stepPattern']
        if track['kind'] not in ('Drum Machine','Sequencer','Indian Percussion','Bhangra Dhol','Bhangra Architect','2C','Bailaton','Dubstep Wrangler'):raise ValueError('Select a step-sequencer track')
        length=p['stepCount']/p['stepsPerBeat'];clip_id=identity()
        start=max(0,round(self.beat/self.snap)*self.snap)
        def op(data):
            target=WorkspaceDocument.track(data,tid)
            clip={'id':clip_id,'name':'Printed Step Pattern','startBeat':start,'lengthBeats':length,'notes':[],
                  'isActive':True,'loopEnabled':True,'loopLengthBeats':length}
            for i,step in enumerate(p['steps']):
                for note in step.get('hits') or ([step['note']] if step.get('on') else []):
                    clip['notes'].append({'id':identity(),'pitch':note,'start':i/p['stepsPerBeat'],'length':.92/p['stepsPerBeat'],'velocity':step['velocity']})
            target['clips'].append(clip);target['useStepSequencer']=False
            data['lengthBars']=max(data['lengthBars'],math.ceil((start+length)/data['beatsPerBar']))
        self.document.edit('Print step pattern',op);self.clip_id=clip_id;self.workspace='Session';self.persist_preferences=persist_preferences;self.detail='Clip'

    def submit(self,label,job,done):
        self.pending+=1;self.cancel.clear();self.status=label;self._emit_changed()
        def work():
            try: result=(done,job(),None)
            except Exception as error: result=(done,None,error)
            self.completed.emit(result)
        self.jobs.submit(work)

    @Slot(object)
    def _complete(self,result):
        done,value,error=result;self.pending-=1
        if error:self.message(error)
        else:
            try:done(value)
            except Exception as failure:self.message(failure)
        self.notify()

    def confirm_discard(self):
        if self.record_state!='idle':
            self.stop();self.message('Finishing the recording; wait for the take before closing or changing projects');return False
        if not self.document.dirty:return True
        answer=QMessageBox.question(None,'Unsaved project','Save your changes before continuing?',QMessageBox.StandardButton.Save|QMessageBox.StandardButton.Discard|QMessageBox.StandardButton.Cancel)
        if answer==QMessageBox.StandardButton.Save:
            self.save_project();return False
        return answer==QMessageBox.StandardButton.Discard

    @Slot(result=bool)
    def requestClose(self):
        if not self.confirm_discard():return False
        self.stop();self.cancel.set();self.epoch+=1;self.jobs.shutdown(wait=False,cancel_futures=True);return True

    def open_project(self):
        if not self.confirm_discard():return
        name,_=QFileDialog.getOpenFileName(None,'Open LemmingsStudio project','','LemmingsStudio (*.lemmingsproject)')
        if not name:return
        epoch=self.epoch;revision=self.document.revision
        def loaded(data):
            if epoch!=self.epoch or revision!=self.document.revision:self.message('Open cancelled because the session changed');return
            self.stop();self.document=WorkspaceDocument(data);self.path=Path(name)
            self.track_id=self.document.data['tracks'][0]['id'] if self.document.data['tracks'] else '';self.selected_tracks=[self.track_id] if self.track_id else [];self.clip_id='';self.note_id='';self.epoch+=1;self.status='Opened '+Path(name).name
        self.submit('Opening project…',lambda:ProjectFile.load(Path(name)).data,loaded)

    def save_project(self,as_new=False):
        path=self.path
        if path is None or as_new:
            name,_=QFileDialog.getSaveFileName(None,'Save LemmingsStudio project',self.document.data['name']+'.lemmingsproject','LemmingsStudio (*.lemmingsproject)')
            if not name:return
            path=Path(name)
            if path.suffix.lower()!='.lemmingsproject':path=Path(str(path)+'.lemmingsproject')
        data=deepcopy(self.document.data);epoch=self.epoch
        base=self.path.parent if self.path else Path.cwd()
        def write():
            portable=ProjectFile(data).portable(base);portable.save(path);return portable.data
        def saved(result):
            if self.epoch!=epoch:return
            if self.document.data==data:self.document.data=deepcopy(result)
            self.document.saved=deepcopy(result);self.path=path;self.status='Saved '+path.name
        self.submit('Saving…',write,saved)

    def import_audio(self,folder=None):
        name,_=QFileDialog.getOpenFileName(None,'Recover retained recording' if folder else 'Import audio',str(folder or ''),'Audio (*.wav *.aif *.aiff *.flac *.ogg)')
        if not name:return
        epoch=self.epoch
        def read():
            import soundfile as sf,numpy as np
            info=sf.info(name)
            if info.duration>600:raise ValueError('Long-file streaming is not yet ported; choose audio under ten minutes')
            samples,rate=sf.read(name,dtype='float32',always_2d=True)
            return np.mean(samples,axis=1).tolist(),rate
        def imported(result):
            if self.epoch!=epoch:return
            samples,rate=result
            if not self.track_id or self.track()['kind']!='Audio (Recorded)':self.track_id=self.document.add_track('Audio (Recorded)')
            clip={'id':identity(),'startBeat':self.beat,'samples':samples,'sampleRate':rate,
                  'devices':[],'externalPluginSlots':[],'warpEnabled':False,'originalTempo':self.document.data['bpm'],
                  'displayName':Path(name).stem,'sourceURL':Path(name).as_uri(),'isActive':True,'gainDB':0}
            self.document.edit('Import audio',lambda d:WorkspaceDocument.track(d,self.track_id)['audioClips'].append(clip))
            self.clip_id=clip['id'];self.status='Imported '+Path(name).name
        self.submit('Reading audio…',read,imported)

    def freeze_track(self,tid):
        original=deepcopy(WorkspaceDocument.track(self.document.data,tid));epoch=self.epoch;data=deepcopy(self.document.data)
        if original.get('frozen'):return
        for track in data['tracks']:track['solo']=track['id']==tid
        ends=[c['startBeat']+c.get('lengthBeats',4) for c in original.get('clips',[]) if c.get('isActive',True)]
        ends += [c['startBeat']+(c.get('lengthBeatsOverride') or len(c.get('samples',[]))/c.get('sampleRate',48000)*data['bpm']/60) for c in original.get('audioClips',[]) if c.get('isActive',True)]
        data['lengthBars']=max(1,math.ceil(max(ends or [data['beatsPerBar']])/data['beatsPerBar']))
        base=self.path.parent if self.path else Path.cwd()
        def render():
            import numpy as np
            audio=WorkspaceRenderer(Snapshot(data,1.,'arrangement',1.),base,cancelled=self.cancel)
            return {'id':identity(),'startBeat':0,'samples':audio.output.mean(axis=1,dtype=np.float32).tolist(),'sampleRate':audio.rate,'displayName':'Frozen '+original['name'],'isActive':True,'loopEnabled':False}
        def frozen(clip):
            if self.epoch!=epoch:return
            if WorkspaceDocument.track(self.document.data,tid)!=original:raise ValueError('Track changed while freezing; source preserved, render discarded')
            self.document.edit('Freeze track',lambda d:WorkspaceDocument.track(d,tid).update(frozen=True,bounced=clip))
            self.status='Frozen '+original['name']
        self.submit('Freezing track…',render,frozen)

    def export_audio(self):
        name,_=QFileDialog.getSaveFileName(None,'Export WAV',self.document.data['name']+'.wav','WAV (*.wav)')
        if not name:return
        snapshot=Snapshot(deepcopy(self.document.data),self.master_gain,'stepSequencer' if self.workspace=='Step Sequencer' else 'arrangement',1.,self.metronome);target=Path(name);base=self.path.parent if self.path else Path.cwd()
        self.submit('Rendering WAV…',lambda:WorkspaceRenderer(snapshot,base,cancelled=self.cancel).export(target,self.cancel),lambda _:self.message('Exported '+target.name))

    def refresh_playback(self):
        if self.engine.running:
            scope='stepSequencer' if self.workspace=='Step Sequencer' else 'pianoRoll' if self.workspace=='Piano Roll' else 'arrangement'
            self.engine.replace(Snapshot(deepcopy(self.document.data),self.master_gain,scope,0.,self.metronome),self.path.parent if self.path else Path.cwd(),WorkspaceRenderer)

    def play(self):
        scope='stepSequencer' if self.workspace=='Step Sequencer' else 'pianoRoll' if self.workspace=='Piano Roll' else 'arrangement'
        self.engine.play(Snapshot(deepcopy(self.document.data),self.master_gain,scope,0.,self.metronome),self.path.parent if self.path else Path.cwd(),self.beat,renderer_factory=WorkspaceRenderer)
        self.transportChanged.emit()

    def stop(self):
        self.engine.stop()
        if self.record_state in ('opening','recording'):
            self.record_state='finishing';self.recorder.stop();self.status='Finishing recorded take…';self._emit_changed()
        self.transportChanged.emit()

    def choose_input(self):
        if sys.platform!='win32':raise ValueError('Native Windows input is available in the Windows build')
        def selected(devices):
            labels=[f"{i+1}. {d['name']}" for i,d in enumerate(devices)]
            choice,ok=QInputDialog.getItem(None,'Recording input','Choose a Windows recording device',labels,0,False)
            if ok:
                device=devices[labels.index(choice)];self.input_endpoint=device['id'];self.input_name=device['name'];self.save_preferences();self.status='Input: '+self.input_name
        self.submit('Finding Windows input devices…',lambda:input_devices(library_path()),selected)

    def record(self):
        if sys.platform!='win32':raise ValueError('Native Windows recording must be run in the Windows build')
        if self.pending:raise ValueError('Wait for the current file operation before recording')
        track=self.track()
        if track['kind']!='Audio (Recorded)' or not track.get('armed'):
            raise ValueError('Select an Audio (Recorded) track and enable Arm before recording')
        if track.get('frozen'):raise ValueError('Unfreeze the track before recording')
        self.engine.stop();self.render_update.stop()
        context={'trackID':track['id'],'epoch':self.epoch,'startBeat':self.beat,'bpm':self.document.data['bpm']}
        self.record_state='opening';self.record_seconds=0.;self.input_peak=0.
        self.status='Opening '+self.input_name+' · dry capture; monitoring and overdubbing are not enabled'
        try:self.recorder.start(library_path(),self.input_endpoint,context)
        except Exception:
            self.record_state='idle';raise
        self._emit_changed();self.transportChanged.emit()

    @Slot(object)
    def _recording_progress(self,info):
        if self.record_state=='idle':return
        if self.record_state=='opening':
            self.record_state='recording';self.status='Recording dry input · '+self.input_name+' · Stop to insert the take'
        self.record_seconds=info['seconds'];self.input_peak=info['native']['peak'];self._emit_changed()

    @Slot(object)
    def _recording_finished(self,result):
        info=result['take'];self.input_peak=0.
        if result['error']:
            self.record_state='idle';self.message(result['error']);return
        self.record_state='finishing'
        def prepare():
            try:return take_clip(info),None
            except Exception as error:return None,str(error)
        def insert(prepared):
            self.record_state='idle';clip,error=prepared
            if error:self.message(f"Recording retained at {info['path']}: {error}");return
            if info['epoch']!=self.epoch or not any(t['id']==info['trackID'] for t in self.document.data['tracks']):
                self.message('Session changed; recording retained at '+info['path']);return
            def commit(data):
                track=WorkspaceDocument.track(data,info['trackID']);track['audioClips'].append(clip)
                end=info['startBeat']+info['frames']/info['rate']*info['bpm']/60
                data['lengthBars']=max(data['lengthBars'],math.ceil(end/data['beatsPerBar']))
            self.document.edit('Record audio',commit);self.track_id=info['trackID'];self.clip_id=clip['id']
            self.record_seconds=info['frames']/info['rate']
            self.status=f"Recorded {self.record_seconds:.2f} s · dry source retained"+(' · ten-minute take limit reached' if info.get('limitReached') else '')
        self.submit('Preparing recorded take…',prepare,insert)

    @Slot(int,float)
    def _position(self,generation,beat):
        if generation==self.engine.generation:self.beat=beat;self.transportChanged.emit()

    @Slot(int,str)
    def _audio_finished(self,generation,message):
        if generation==self.engine.generation:self.message(message);self.transportChanged.emit()


class WorkspaceWindow(QObject):
    def __init__(self,check_mode=False):
        super().__init__()
        self.controller=WorkspaceController(persist_preferences=not check_mode)
        self.qml=QQmlApplicationEngine()
        self.warnings=[]
        self.qml.warnings.connect(lambda errors:self.warnings.extend(e.toString() for e in errors))
        self.qml.rootContext().setContextProperty('studio',self.controller)
        self.qml.load(QUrl.fromLocalFile(str(Path(__file__).parent/'qml/Workspace.qml')))
        if not self.qml.rootObjects():raise RuntimeError('The workspace interface failed to load')
        self.window=self.qml.rootObjects()[0]
        geometry=QApplication.primaryScreen().availableGeometry()
        self.window.resize(min(1600,geometry.width()-40),min(960,geometry.height()-60))
        self.window.setX(geometry.x()+(geometry.width()-self.window.width())//2)
        self.window.setY(geometry.y()+(geometry.height()-self.window.height())//2)
    def show(self):self.window.show()
    def isVisible(self):return self.window.isVisible()
    def close(self):self.window.close()
