"""Original tempo lookup and MIDI-effect rules, evaluated off the audio thread."""
import math
import numpy as np

def rounded(value):return math.floor(value+.5) if value>=0 else math.ceil(value-.5)

class Timeline:
    def __init__(self,data,rate):
        self.rate=rate;self.tempo=data.get('bpm',data.get('tempo',124));self.length=data.get('lengthBars',32)*data.get('beatsPerBar',4)
        if not math.isfinite(self.tempo) or not 20<=self.tempo<=400 or not 0<self.length<=4000:raise ValueError('Invalid session tempo/length')
        points=sorted(data.get('tempoPoints',[]),key=lambda p:p['beat']) if data.get('tempoAutomationEnabled') else []
        if any(not math.isfinite(p['beat']) or not math.isfinite(p['bpm']) or not 20<=p['bpm']<=400 for p in points):raise ValueError('Invalid tempo automation')
        if data.get('tempoAutomationEnabled'):
            self.point_beats=[p['beat'] for p in points] or [0];self.point_bpms=[p['bpm'] for p in points] or [120]
            self.grid=np.arange(math.ceil(max(1,self.length)*16)+1,dtype=np.float64)/16
            mid=(self.grid[:-1]+self.grid[1:])*.5
            values=np.interp(mid,self.point_beats,self.point_bpms)
            self.seconds=np.r_[0,np.cumsum(60/values/16)]
        else:
            self.point_beats=[0];self.point_bpms=[self.tempo];self.grid=np.array([0,self.length]);self.seconds=self.grid*60/self.tempo
    def bpm(self,beat):return float(np.interp(beat,self.point_beats,self.point_bpms))
    def time(self,beat):
        if beat>self.grid[-1]:return float(self.seconds[-1]+(beat-self.grid[-1])*60/self.point_bpms[-1])
        return float(np.interp(beat,self.grid,self.seconds))
    def frame(self,beat):return rounded(self.time(beat)*self.rate)
    def beat(self,frame):
        seconds=frame/self.rate
        if seconds>self.seconds[-1]:return float(self.grid[-1]+(seconds-self.seconds[-1])*self.point_bpms[-1]/60)
        return float(np.interp(seconds,self.seconds,self.grid))

NONPITCHED={'Drum Machine','Sequencer','Indian Percussion','Bhangra Dhol','Bhangra Architect','2C','Bailaton','Dubstep Wrangler'}
def snap(note,track,data,reference):
    if track['kind'] in NONPITCHED or not data.get('keySnapEnabled',True):return note
    scale=next((s for s in reference['scales'] if s['name']==data.get('scaleName','Major (Ionian)')),reference['scales'][0])
    # Workspace reference stores pitch-class intervals directly.
    intervals=scale.get('intervals',scale.get('notes',[]));root=data.get('keyRoot',0)
    if not intervals:return note
    if (note-root)%12 in intervals:return note
    for delta in range(1,7):
        for candidate in (note-delta,note+delta):
            if (candidate-root)%12 in intervals:return max(0,min(127,candidate))
    return note

def midi_plan(base,velocity,length,track,data,reference):
    clamp=lambda n:max(0,min(127,n))
    playable=lambda n:snap(clamp(n),track,data,reference)
    pitches=[playable(base)];vel=np.float32(max(0,min(1,velocity)));duration=max(.02,length)
    for device in track.get('devices',[]):
        if device.get('bypassed'):continue
        kind=device['kind'];p=device.get('params',{})
        if kind=='Pitch Tool':pitches=[clamp(n+rounded(p.get('transpose',0))+12*rounded(p.get('octave',0))) for n in pitches]
        elif kind in ('Pitch Corrector','Scale Mapper') and p.get('amount',1)>=.5:pitches=[playable(n) for n in pitches]
        elif kind=='Velocity Mapper':
            gain=np.float32(p.get('gain',1));comp=np.float32(p.get('compress',0));vel=np.float32(max(.01,min(1,vel*gain)))
            if comp>0:vel=vel*(np.float32(1)-comp)+(np.float32(.72)+(vel-np.float32(.72))*np.float32(.45))*comp
        elif kind=='Note Gate Length':duration=max(p.get('minimum',.08),duration*p.get('gate',.9))
        elif kind=='Chord Builder':
            root=pitches[0] if pitches else base;pitches=[root]+[root+n for key,n,default in [('third',4,1),('fifth',7,1),('seventh',11,0),('octave',12,0)] if p.get(key,default)>=.5];pitches=list(map(clamp,pitches))
        elif kind=='Note Randomizer' and p.get('chance',0)>.001:
            choices=max(1,rounded(p.get('choices',3)));offset=((base*1103515245+choices*12345)&0x7fffffff)%choices;semis=[-12,-7,-5,0,5,7,12][min(6,offset)];pitches=[playable(n+semis) for n in pitches]
        elif kind=='Note Bounce':
            root=pitches[0] if pitches else base;pitches=sorted(set(map(clamp,pitches+[root+n for key,n in [('fifth',7),('octave',12)] if p.get(key,0)>=.5])))
    return pitches,float(vel),duration

def lane_value(lane,beat):
    if not lane.get('enabled',True) or not lane.get('points'):return None
    points=sorted(lane['points'],key=lambda p:p['beat'])
    return float(np.interp(beat,[p['beat'] for p in points],[p['value'] for p in points]))
