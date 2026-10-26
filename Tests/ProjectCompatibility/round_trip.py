"""Run Swift -> Python edit/save -> Swift read/save -> Python assertions."""
import os
from pathlib import Path
import subprocess
from lemmings_studio.project_contract import ProjectFile

root = Path(os.environ['LEMMINGS_TEST_OUTPUT'])
doc = ProjectFile.load(root/'swift.lemmingsproject')
doc.data['name'] = 'Windows → macOS संगीत'
doc.data['futureRoot'] = {'preserved': True}
doc.data['tracks'][0]['futureTrack'] = {'notes': ['opaque']}
original_ids = [t['id'] for t in doc.data['tracks']]
doc.save(root/'python.lemmingsproject')
subprocess.run([str(root/'project-contract-check'), str(root/'swift.lemmingsproject'),
                str(root/'python.lemmingsproject'), str(root/'returned.lemmingsproject')], check=True)
returned = ProjectFile.load(root/'returned.lemmingsproject')
assert returned.data['name'] == doc.data['name']
assert returned.data['futureRoot'] == doc.data['futureRoot']
assert returned.data['tracks'][0]['futureTrack'] == doc.data['tracks'][0]['futureTrack']
assert [t['id'] for t in returned.data['tracks']] == original_ids
assert not returned.reference_warnings()
assert returned.data['masterDevices'] == doc.data['masterDevices']
print('PASS: actual Swift → Python → Swift → Python round trip')

# A project created by the Windows workspace, rather than just a Mac fixture edit.
from lemmings_studio.workspace_document import WorkspaceDocument
workspace=WorkspaceDocument();tid=workspace.data['tracks'][1]['id']
clip=workspace.create_clip(tid,4,8);workspace.add_note(tid,clip,0,36,.23,.8)
workspace.toggle_step(tid,36,0);workspace.toggle_step(tid,42,0)
workspace.automation_point(tid,'instrument','master',0,.7)
workspace.data['tracks'][1]['futureWindowsState']={'preserve':True}
ProjectFile(workspace.data).save(root/'windows-created.lemmingsproject')
subprocess.run([str(root/'project-contract-check'),str(root/'swift.lemmingsproject'),
                str(root/'windows-created.lemmingsproject'),str(root/'windows-returned.lemmingsproject')],check=True)
received=ProjectFile.load(root/'windows-returned.lemmingsproject').data
assert received['tracks'][1]['id']==tid
assert received['tracks'][1]['clips'][0]['id']==clip
assert received['tracks'][1]['clips'][0]['notes']==workspace.data['tracks'][1]['clips'][0]['notes']
assert received['tracks'][1]['stepPattern']==workspace.data['tracks'][1]['stepPattern']
assert received['tracks'][1]['automationLanes']==workspace.data['tracks'][1]['automationLanes']
assert received['tracks'][1]['futureWindowsState']=={'preserve':True}
assert received['masterDevices']==workspace.data['masterDevices']
assert received['returnBuses']==workspace.data['returnBuses']
print('PASS: Windows workspace-created project opened/resaved by actual Swift')
