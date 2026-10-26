"""Reproduce the source inventory; implemented/verified status is never inferred."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

root = Path(__file__).resolve().parents[1]
base = '4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc'
def source(path):
    return subprocess.check_output(['git', 'show', f'{base}:{path}'], cwd=root)
paths = subprocess.check_output(['git','ls-tree','-r','--name-only',base,'Sources/LemmingsStudio'],cwd=root,text=True).splitlines()
assets = []
for path in paths:
    if '/Resources/' in path:
        blob = source(path)
        assets.append({'path':path,'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest(),'rights':'review pending','packaged_on_windows':False})
swift = {}
for path in paths:
    if path.endswith('.swift'):
        text = source(path).decode()
        swift[path] = {'sha256':hashlib.sha256(text.encode()).hexdigest(),
                       'types':re.findall(r'^(?:public |private |@Observable public )*(?:final )?(?:class|struct|enum) (\w+)',text,re.M),
                       'functions':re.findall(r'^\s*(?:public |private |static |@discardableResult )*func (\w+)',text,re.M),
                       'runtime_validation':'pending'}
registry = source('Sources/LemmingsStudio/Effects/Effects.swift').decode().split('public enum DeviceRole:')[0]
devices = [{'key':key,'name':name,'windows_dsp':'not verified','visual_parity':'pending','project_state':'pending'}
           for key,name in re.findall(r'^\s*case (\w+)\s*=\s*"([^"]+)"',registry,re.M)]
result={'baseline':base,'evidence':'source inventory only; not observed executable behavior','assets':assets,'devices':devices,'sources':swift}
(root/'Docs/Parity/mac-reference.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
print(f'Inventoried {len(swift)} Swift sources, {len(devices)} device entries and {len(assets)} resources')
