#!/usr/bin/env python3
from __future__ import annotations
import argparse, inspect, json, os, pathlib, shutil, sys, traceback

def emit(event, **payload): print(json.dumps({"event":event, **payload}, ensure_ascii=False), flush=True)
def resolve_model(text):
    p=pathlib.Path(text).expanduser().resolve()
    if not p.exists(): raise RuntimeError(f"RVC model path does not exist: {p}")
    if p.is_file() and p.suffix.lower()=='.pth': model=p; folder=p.parent
    else:
        files=[x for x in sorted(p.rglob('*.pth')) if not any(part.lower() in {'pretrained','pretrained_v2','hubert','rmvpe','venv'} for part in x.parts)]
        if not files: raise RuntimeError(f"No RVC .pth model found in: {p}")
        model=files[0]; folder=model.parent
    indexes=sorted(folder.rglob('*.index')) or (sorted(p.rglob('*.index')) if p.is_dir() else [])
    return model, (indexes[0] if indexes else None)
def device(torch):
    wanted=os.getenv('LEMMINGS_RVC_DEVICE','auto').lower()
    if wanted!='auto': return wanted
    return 'mps' if getattr(torch.backends,'mps',None) and torch.backends.mps.is_available() else 'cpu'
def supported(fn, values):
    try: sig=inspect.signature(fn)
    except Exception: return {}
    if any(x.kind==inspect.Parameter.VAR_KEYWORD for x in sig.parameters.values()): return values
    return {k:v for k,v in values.items() if k in sig.parameters}
def verify():
    import numpy, scipy, librosa, soundfile, torch, torchaudio, rvc_python
    from rvc_python.infer import RVCInference
    emit('verified',python=sys.version.split()[0],numpy=numpy.__version__,scipy=scipy.__version__,librosa=librosa.__version__,torch=torch.__version__,torchaudio=torchaudio.__version__,device=device(torch),ffmpeg=shutil.which('ffmpeg'),inference_class=RVCInference.__name__)
def convert(a):
    import torch
    from rvc_python.infer import RVCInference
    inp=pathlib.Path(a.input).expanduser().resolve(); out=pathlib.Path(a.output).expanduser().resolve(); model,index=resolve_model(a.model)
    if not inp.exists(): raise RuntimeError(f"Input audio does not exist: {inp}")
    out.parent.mkdir(parents=True,exist_ok=True); out.unlink(missing_ok=True)
    dev=device(torch); emit('starting',device=dev,model=str(model),index=str(index) if index else None)
    r=RVCInference(device=dev); r.load_model(str(model)); fn=r.infer_file
    vals={'f0_up_key':a.pitch,'pitch':a.pitch,'transpose':a.pitch,'f0_method':a.f0_method,'index_path':str(index) if index else '','file_index':str(index) if index else '','index_rate':a.index_rate if index else 0.0,'filter_radius':a.filter_radius,'rms_mix_rate':a.rms_mix_rate,'protect':a.protect,'output_path':str(out)}
    try: result=fn(str(inp),str(out),**supported(fn,vals))
    except TypeError: result=fn(**supported(fn,{**vals,'input_path':str(inp),'audio_path':str(inp),'input_file':str(inp)}))
    candidates=[out]
    if isinstance(result,(str,os.PathLike)): candidates.append(pathlib.Path(result))
    elif isinstance(result,(list,tuple)): candidates += [pathlib.Path(x) for x in result if isinstance(x,(str,os.PathLike))]
    made=next((x.expanduser().resolve() for x in candidates if x.exists() and x.stat().st_size>44),None)
    if made is None: raise RuntimeError('RVC inference produced no valid WAV')
    if made!=out: shutil.copy2(made,out)
    emit('complete',output=str(out),bytes=out.stat().st_size,device=dev,index_used=bool(index))
def main():
    p=argparse.ArgumentParser(); p.add_argument('--verify',action='store_true'); p.add_argument('--input'); p.add_argument('--model'); p.add_argument('--output'); p.add_argument('--pitch',type=int,default=0); p.add_argument('--f0-method',default='rmvpe'); p.add_argument('--index-rate',type=float,default=.75); p.add_argument('--filter-radius',type=int,default=3); p.add_argument('--rms-mix-rate',type=float,default=.25); p.add_argument('--protect',type=float,default=.33); a=p.parse_args()
    try:
        if a.verify: verify()
        else:
            if not all((a.input,a.model,a.output)): raise RuntimeError('Missing --input, --model, or --output')
            convert(a)
        return 0
    except Exception as e: emit('error',message=str(e)); traceback.print_exc(file=sys.stderr); return 1
if __name__=='__main__': raise SystemExit(main())
