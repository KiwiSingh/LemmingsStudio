import os
from pathlib import Path
from uuid import uuid4
import pytest
from lemmings_studio.project_contract import ProjectFile, ProjectContractError


def identity():
    return str(uuid4()).upper()


def fixture():
    a, b, device = identity(), identity(), identity()
    return {'version': 3, 'name': 'संगीत', 'tempo': 120, 'bpm': 120,
            'tracks': [{'id': a, 'name': 'Duplicate', 'kind': 'Drum Machine',
                        'devices': [{'id': device, 'kind': 'Dynamics Compressor',
                                     'sidechainInputTrackID': b, 'params': {'threshold': -12}}],
                        'automationLanes': [{'nodeID': device, 'paramID': 'threshold', 'points': []}],
                        'sequencerPrintTargetTrackID': b},
                       {'id': b, 'name': 'Duplicate', 'kind': 'Future instrument',
                        'externalPluginSlots': [{'id': identity(), 'pluginID': 'missing',
                                                'opaqueState': 'retain byte-for-byte'}]}],
            'groups': [{'id': identity(), 'name': 'Group', 'trackIDs': [a, b]}],
            'future': {'notes': ['not our schema'], 'keep': [1, {'a': True}]}}


def test_shared_round_trip_is_lossless_and_does_not_substitute_unknown_devices(tmp_path):
    doc = ProjectFile(fixture())
    path = tmp_path/'跨平台.lemmingsproject'
    doc.save(path)
    assert ProjectFile.load(path).data == doc.data
    assert not doc.reference_warnings()
    assert doc.data['tracks'][1]['kind'] == 'Future instrument'


def test_identity_is_stable_over_repeated_migration_and_saves(tmp_path):
    raw = {'version': 2, 'tracks': [{'name': 'Old', 'devices': [{'kind': 'Room Space'}]}]}
    doc = ProjectFile(raw).upgraded()
    path = tmp_path/'old.lemmingsproject'
    for _ in range(3):
        doc.save(path)
        assert ProjectFile.load(path).data == doc.data
    assert raw['version'] == 2 and 'id' not in raw['tracks'][0]


def test_lost_legacy_references_are_reported_and_never_guessed(tmp_path):
    doc = ProjectFile({'version': 2, 'tracks': [{'name': 'Duplicate'}, {'name': 'Duplicate'}],
                       'groups': [{'trackIDs': [identity()]}]})
    with pytest.raises(ProjectContractError, match='Unresolved group'):
        doc.save(tmp_path/'broken.lemmingsproject')
    assert not list(tmp_path.iterdir())


def test_save_failure_preserves_destination_and_backup(tmp_path, monkeypatch):
    path = tmp_path/'song.lemmingsproject'
    doc = ProjectFile(fixture()); doc.save(path)
    original = path.read_bytes()
    doc.data['tempo'] = 130; doc.save(path)
    assert path.with_suffix('.lemmingsproject.bak').read_bytes() == original
    current = path.read_bytes()
    def fail(*_):
        raise OSError('disk full')
    monkeypatch.setattr(os, 'replace', fail)
    with pytest.raises(OSError):
        doc.save(path)
    assert path.read_bytes() == current
    assert path.with_suffix('.lemmingsproject.bak').read_bytes() == original
    assert sorted(p.name for p in tmp_path.iterdir()) == ['song.lemmingsproject', 'song.lemmingsproject.bak']


@pytest.mark.parametrize('payload', [b'{"version":4}', b'{"version":true}', b'{"tempo":NaN}',
                                     b'{"version":2,"version":3}', b'{"tracks":{}}',
                                     b'{"version":3,"tracks":[{}]}'])
def test_rejects_malformed_or_future_documents(payload):
    with pytest.raises(ProjectContractError):
        ProjectFile.decode(payload)


def test_duplicate_ids_and_dangling_reference_are_detected():
    raw = fixture(); raw['tracks'][1]['id'] = raw['tracks'][0]['id']
    with pytest.raises(ProjectContractError, match='Duplicate project identity'):
        ProjectFile(raw).encode()
    raw = fixture(); raw['tracks'][0]['devices'][0]['sidechainInputTrackID'] = identity()
    with pytest.raises(ProjectContractError, match='Unresolved sidechain'):
        ProjectFile(raw).upgraded()


def test_swift_fixture_round_trip_when_supplied(tmp_path):
    fixture_path = os.environ.get('LEMMINGS_SWIFT_FIXTURE')
    if not fixture_path:
        pytest.skip('Run the native Swift contract harness first')
    original = ProjectFile.load(Path(fixture_path))
    destination = tmp_path/'python.lemmingsproject'
    original.save(destination)
    assert ProjectFile.load(destination).data == original.data
