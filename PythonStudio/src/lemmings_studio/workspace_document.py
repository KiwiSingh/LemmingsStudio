"""Qt-independent workspace edits on the actual shared Mac document contract."""
from copy import deepcopy
from uuid import uuid4
import math,json
from pathlib import Path
REFERENCE=json.loads((Path(__file__).parent/'qml/WorkspaceReference.json').read_text(encoding='utf-8'))

def make_device(kind):
    return {'id':identity(),'kind':kind,'bypassed':False,'mono':False,'sidechainEnabled':False,'params':deepcopy(next(d['defaults'] for d in REFERENCE['devices'] if d['kind']==kind))}

from .project_contract import ProjectFile, _entities
from .stock_contract import ANALOG_DEVICES,MAPPED_INSTRUMENT_DEVICES,DEVICE_TRACKS,STEP_KINDS


def identity():
    return str(uuid4()).upper()


def numeric(value, minimum, maximum):
    if isinstance(value, bool):
        raise ValueError('A number is required')
    value = float(value)
    if not math.isfinite(value) or not minimum <= value <= maximum:
        raise ValueError(f'Value must be between {minimum} and {maximum}')
    return value


def make_track(name, kind):
    return {'id':identity(),'name':name,'kind':kind,'colorIndex':0,'clips':[],
            'audioClips':[],'devices':[],'externalPluginSlots':[],'automationLanes':[],
            'sequencerLayers':[],'armed':False,'inputMonitor':False,'useStepSequencer':kind=='Sequencer',
            'volume':.8,'pan':0.,'mute':False,'solo':False,'sends':[],
            'outputBusName':'Master','outputMode':'Master','outputChannelIndex':1,
            'panMode':'Stereo Balance','stereoWidth':1.,'drumGenre':'Tech House',
            'stepPattern':{'stepCount':16,'stepsPerBeat':4,'steps':[{'on':False,'note':36,'velocity':.9,'hits':[]} for _ in range(16)]}}


def new_project():
    tracks = [make_track('Instrument 1','Analog Synth'), make_track('Drum Machine','Drum Machine'),
              make_track('Sequencer 1','Sequencer'), make_track('Audio 1','Audio (Recorded)')]
    for index, track in enumerate(tracks):
        track['colorIndex'] = index
    return {'version':3,'name':'Untitled','tempo':124.,'bpm':124.,'beatsPerBar':4,
            'lengthBars':32,'keyRoot':0,'keyName':'C','scaleName':'Major (Ionian)','keySnapEnabled':True,
            'tempoAutomationEnabled':False,'tempoPoints':[],'sampleRate':48000.,
            'bitDepth':'32-bit Float','channelFormat':'Stereo','swingAmount':0.,'customChannelCount':16,'channelNames':['L','R','C','LFE','Ls','Rs','Lb','Rb'],'groups':[],
            'returnBuses':[{'id':identity(),'name':name,'devices':[make_device(kind)],'volume':.8,'pan':0.,'mute':False} for name,kind in [('A Reverb','Room Space'),('B Delay','Tempo Delay')]],'masterDevices':[make_device('Peak Limiter')],'tracks':tracks}


class WorkspaceDocument:
    def __init__(self, data=None):
        self.data = ProjectFile(deepcopy(data if data is not None else new_project())).upgraded().data
        defaults=new_project()
        for key,value in defaults.items():self.data.setdefault(key,deepcopy(value))
        for track in self.data['tracks']:
            base=make_track(track.get('name','Track'),track.get('kind','Analog Synth'))
            for key,value in base.items():track.setdefault(key,deepcopy(value))
        self.saved = deepcopy(self.data)
        self.undo_stack = []
        self.redo_stack = []
        self.revision = 0

    @property
    def dirty(self):
        return self.data != self.saved

    def edit(self, label, operation):
        candidate = deepcopy(self.data)
        operation(candidate)
        ProjectFile(candidate).validate()
        if warnings := ProjectFile(candidate).reference_warnings():
            raise ValueError('; '.join(warnings))
        if candidate == self.data:
            return False
        self.undo_stack.append((label,self.data))
        self.undo_stack = self.undo_stack[-100:]
        self.redo_stack.clear()
        self.data = candidate
        self.revision += 1
        return True

    def undo(self):
        if not self.undo_stack:
            return 'Nothing to undo'
        label, data = self.undo_stack.pop()
        self.redo_stack.append((label,self.data)); self.data = data; self.revision += 1
        return 'Undid '+label

    def redo(self):
        if not self.redo_stack:
            return 'Nothing to redo'
        label, data = self.redo_stack.pop()
        self.undo_stack.append((label,self.data)); self.data = data; self.revision += 1
        return 'Redid '+label

    @staticmethod
    def track(data, track_id):
        return next(t for t in data['tracks'] if t['id']==track_id)

    @staticmethod
    def clip(track, clip_id):
        return next(c for c in [*track['clips'],*track['audioClips']] if c['id']==clip_id)

    def add_track(self, kind):
        track = make_track(f'{kind} {len(self.data["tracks"])+1}',kind)
        track['colorIndex'] = len(self.data['tracks']) % 8
        self.edit('Add track',lambda d:d['tracks'].append(track))
        return track['id']

    def create_clip(self, track_id, start=0, length=4):
        start, length = numeric(start,0,1e6),numeric(length,.0625,1e6)
        if self.track(self.data,track_id)['kind']=='Audio (Recorded)':
            raise ValueError('Import or record audio on an audio track')
        clip={'id':identity(),'name':'MIDI Clip','startBeat':start,'lengthBeats':length,
              'notes':[],'isActive':True,'loopEnabled':True,'loopLengthBeats':length}
        self.edit('Create MIDI clip',lambda d:self.track(d,track_id)['clips'].append(clip))
        return clip['id']

    def add_note(self, track_id, clip_id, beat, pitch, length=.5, velocity=.9):
        beat, pitch = numeric(beat,0,1e6),int(numeric(pitch,0,127))
        note={'id':identity(),'pitch':pitch,'start':beat,'length':numeric(length,.0625,1e6),
              'velocity':numeric(velocity,0,1)}
        self.edit('Draw note',lambda d:self.clip(self.track(d,track_id),clip_id)['notes'].append(note))
        return note['id']

    def edit_note(self,track_id,clip_id,note_id,values):
        clean={}
        for key,value in values.items():
            limits={'pitch':(0,127),'start':(0,1e6),'length':(.0625,1e6),'velocity':(0,1)}
            if key not in limits: raise ValueError('Unsupported note field')
            clean[key]=numeric(value,*limits[key])
            if key=='pitch': clean[key]=int(clean[key])
        def op(data):
            note=next(n for n in self.clip(self.track(data,track_id),clip_id)['notes'] if n['id']==note_id)
            note.update(clean)
        self.edit('Edit note',op)

    def toggle_step(self,track_id,pitch,step):
        step=int(numeric(step,0,63));pitch=int(numeric(pitch,0,127))
        def op(data):
            track=self.track(data,track_id)
            if track['kind'] not in STEP_KINDS:
                raise ValueError('Choose a step-sequencer instrument track')
            track['useStepSequencer']=True
            pattern=track['stepPattern']
            while len(pattern['steps'])<=step:
                pattern['steps'].append({'on':False,'note':36,'velocity':.9,'hits':[]})
            item=pattern['steps'][step]
            hits=list(item.get('hits') or ([item['note']] if item['on'] else []))
            if pitch in hits: hits.remove(pitch)
            else: hits.append(pitch)
            hits.sort();item.update(hits=hits,on=bool(hits),note=hits[0] if hits else pitch)
        self.edit('Toggle drum step',op)

    def set_track(self,track_id,key,value):
        if key in ('volume','pan','stereoWidth'):
            value=numeric(value,*{'volume':(0,4),'pan':(-1,1),'stereoWidth':(0,2)}[key])
        elif key in ('mute','solo','armed','useStepSequencer'):
            if type(value) is not bool: raise ValueError('A boolean is required')
        elif key in ('name','drumGenre','outputBusName','outputMode','audioInputMonitorMode','panMode'):
            value=str(value)[:256]
        else: raise ValueError('Unsupported track property')
        self.edit('Change '+key,lambda d:self.track(d,track_id).__setitem__(key,value))

    def edit_clip(self,track_id,clip_id,values):
        clean={}
        for key,value in values.items():
            if key in ('name','displayName'): clean[key]=str(value)[:256]
            elif key in ('isActive','loopEnabled'): clean[key]=bool(value)
            else:
                ranges={'startBeat':(0,1e6),'lengthBeats':(.0625,1e6),'lengthBeatsOverride':(.0625,1e6),
                        'trimStartBeats':(0,1e6),'gainDB':(-60,24),'pitchSemitones':(-48,48),
                        'pitchCents':(-100,100),'loopLengthBeats':(.0625,1e6)}
                if key not in ranges: raise ValueError('Unsupported clip property')
                clean[key]=numeric(value,*ranges[key])
        def edit(data):
            clip=self.clip(self.track(data,track_id),clip_id)
            if 'lengthBeats' in clean and 'samples' not in clip:
                length=clean['lengthBeats'];source=clip.get('loopLengthBeats',clip['lengthBeats'])
                if not .03125<source<=clip['lengthBeats']+.0001:source=clip['lengthBeats']
                if clip.get('loopEnabled') and length>source+.000001:
                    seeds=[deepcopy(n) for n in clip['notes'] if -.000001<=n['start']<source-.000001]
                    if math.ceil(length/source)*len(seeds)>100000:raise ValueError('Loop would create too many MIDI notes')
                    notes=[];offset=0.
                    while seeds and offset<length-.000001:
                        for seed in seeds:
                            note=deepcopy(seed);start=offset+max(0,seed['start'])
                            if start>=min(length,offset+source)-.000001:continue
                            note['start']=start;note['length']=min(seed['length'],source-max(0,seed['start']),length-start)
                            if offset:note['id']=identity()
                            notes.append(note)
                        offset+=source
                    clip['notes']=notes;clip['loopLengthBeats']=source
                else:
                    clip['notes']=[{**n,'length':min(n['length'],length-n['start'])} for n in clip['notes'] if n['start']<length]
            clip.update(clean)
        self.edit('Edit clip',edit)

    def move_clip(self,track_id,clip_id,target_id,start):
        start=numeric(start,0,1e6)
        def op(data):
            source=self.track(data,track_id);target=self.track(data,target_id)
            clip=self.clip(source,clip_id);audio='samples' in clip
            if audio != (target['kind']=='Audio (Recorded)'):
                raise ValueError('Audio and MIDI clips require matching track types')
            key='audioClips' if audio else 'clips'
            source[key].remove(clip);clip['startBeat']=start;target[key].append(clip)
        self.edit('Move clip',op)

    def delete_clip(self,track_id,clip_id):
        def op(data):
            track=self.track(data,track_id)
            for key in ('clips','audioClips'): track[key]=[c for c in track[key] if c['id']!=clip_id]
        self.edit('Delete clip',op)

    def duplicate_clip(self,track_id,clip_id):
        result=[]
        def op(data):
            track=self.track(data,track_id);clip=deepcopy(self.clip(track,clip_id))
            clip['id']=identity()
            for obj in [*clip.get('notes',[]),*clip.get('devices',[]),*clip.get('externalPluginSlots',[])]: obj['id']=identity()
            clip['startBeat']+=clip.get('lengthBeats',clip.get('lengthBeatsOverride',4))
            track['audioClips' if 'samples' in clip else 'clips'].append(clip);result.append(clip['id'])
        self.edit('Duplicate clip',op)
        return result[0]

    def group(self,track_ids):
        if len(set(track_ids))<2: raise ValueError('Select at least two tracks to group')
        group_id=identity()
        def op(data):
            for existing in data['groups']:
                existing['trackIDs']=[x for x in existing['trackIDs'] if x not in track_ids]
            data['groups'].append({'id':group_id,'name':'Group','trackIDs':list(track_ids),'devices':[],
                                   'volume':1.,'pan':0.,'mute':False,'solo':False,'automationLanes':[]})
            for tid in track_ids: self.track(data,tid)['groupID']=group_id
        self.edit('Group tracks',op)
        return group_id

    def delete_tracks(self,track_ids):
        def op(data):
            data['tracks']=[t for t in data['tracks'] if t['id'] not in track_ids]
            for group in data['groups']: group['trackIDs']=[x for x in group['trackIDs'] if x not in track_ids]
            for obj in _entities(data):
                for key in ('sidechainInputTrackID','sequencerPrintSourceTrackID','sequencerPrintTargetTrackID'):
                    if obj.get(key) in track_ids: obj.pop(key)
        self.edit('Delete tracks',op)

    def add_device(self,track_id,definition):
        device={'id':identity(),'kind':definition['kind'],'bypassed':False,'mono':False,
                'params':deepcopy(definition['defaults'])}
        def add(data):
            track=self.track(data,track_id)
            if device['kind'] in DEVICE_TRACKS:
                track['kind']=DEVICE_TRACKS[device['kind']];track['useStepSequencer']=track['kind'] in ('Drum Machine','Bhangra Architect','2C','Bailaton','Dubstep Wrangler')
                track['devices']=[d for d in track['devices'] if d['kind'] not in MAPPED_INSTRUMENT_DEVICES]
                track['devices'].insert(0,device)
            else:track['devices'].append(device)
        self.edit('Add '+device['kind'],add)
        return device['id']

    def device_param(self,track_id,device_id,param,value,definition):
        info=next(p for p in definition['params'] if p['id']==param)
        value=numeric(value,info['min'],info['max'])
        def op(data):
            device=next(x for x in self.track(data,track_id)['devices'] if x['id']==device_id)
            device['params'][param]=value
        self.edit('Adjust '+info['name'],op)

    def automation_point(self,track_id,node,param,beat,value):
        beat,value=numeric(beat,0,1e6),numeric(value,-1e6,1e6)
        def op(data):
            lanes=self.track(data,track_id)['automationLanes']
            lane=next((x for x in lanes if x['nodeID']==node and x['paramID']==param),None)
            if lane is None:
                lane={'nodeID':node,'paramID':param,'enabled':True,'points':[]};lanes.append(lane)
            lane['points']=[p for p in lane['points'] if abs(p['beat']-beat)>.00001]
            lane['points'].append({'beat':beat,'value':value});lane['points'].sort(key=lambda x:x['beat'])
        self.edit('Edit automation',op)

    def duplicate_track(self,track_id):
        duplicate=deepcopy(self.track(self.data,track_id));mapping={}
        for item in _entities({'tracks':[duplicate]}):
            old=item['id'];item['id']=identity();mapping[old]=item['id']
        for item in _entities({'tracks':[duplicate]}):
            for key in ('sidechainInputTrackID','sequencerPrintSourceTrackID','sequencerPrintTargetTrackID'):
                if item.get(key) in mapping:item[key]=mapping[item[key]]
            for lane in item.get('automationLanes',[]):lane['nodeID']=mapping.get(lane['nodeID'],lane['nodeID'])
        duplicate['name']+=' Copy'
        def op(data):
            index=next(i for i,t in enumerate(data['tracks']) if t['id']==track_id)
            data['tracks'].insert(index+1,duplicate)
            for group in data['groups']:
                if track_id in group['trackIDs']:group['trackIDs'].append(duplicate['id'])
        self.edit('Duplicate track',op);return duplicate['id']

    def split_clip(self,track_id,clip_id,beat):
        result=[]
        def op(data):
            track=self.track(data,track_id);clip=self.clip(track,clip_id);audio='samples' in clip
            length=clip.get('lengthBeats',clip.get('lengthBeatsOverride',len(clip.get('samples',[]))/clip.get('sampleRate',48000)*data['bpm']/60))
            offset=numeric(beat-clip['startBeat'],.0625,length-.0625)
            right=deepcopy(clip);right['id']=identity();right['startBeat']=beat
            key='lengthBeatsOverride' if audio else 'lengthBeats';right[key]=length-offset;clip[key]=offset
            if audio:
                right['trimStartBeats']=clip.get('trimStartBeats',0)+offset
                for entity in [*right.get('devices',[]),*right.get('externalPluginSlots',[])]:entity['id']=identity()
            else:
                clip['notes']=[];right['notes']=[]
                for note in self.clip(self.track(self.data,track_id),clip_id)['notes']:
                    if note['start']<offset:
                        left=deepcopy(note);left['length']=min(note['length'],offset-note['start']);clip['notes'].append(left)
                    if note['start']+note['length']>offset:
                        part=deepcopy(note);part['id']=identity();part['start']=max(0,note['start']-offset);part['length']=min(note['length'],note['start']+note['length']-offset);right['notes'].append(part)
            track['audioClips' if audio else 'clips'].append(right);result.append(right['id'])
        self.edit('Split clip',op);return result[0]
