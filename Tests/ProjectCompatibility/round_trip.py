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
