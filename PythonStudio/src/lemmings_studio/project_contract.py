"""Lossless .lemmingsproject document boundary shared with the Swift application.

This is deliberately independent of the preview's renderer. Unsupported devices
remain data, never an instruction to substitute a generic sound.
"""
from __future__ import annotations
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from uuid import UUID, uuid4
import json
import math
import os
import tempfile


class ProjectContractError(ValueError):
    pass


def _uuid(value):
    try:
        if not isinstance(value, str):
            raise ValueError()
        return str(UUID(value)).upper()
    except (ValueError, AttributeError) as error:
        raise ProjectContractError(f"Invalid project identity: {value!r}") from error


def _finite(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ProjectContractError("Project contains a non-finite number")
    if isinstance(value, dict):
        for item in value.values():
            _finite(item)
    elif isinstance(value, list):
        for item in value:
            _finite(item)


def _entities(data):
    """Only schema-owned collections; extension objects are opaque."""
    yield from (data.get('masterDevices') or [])
    for group in (data.get('groups') or []):
        yield group
        yield from group.get('devices', [])
    for bus in (data.get('returnBuses') or []):
        yield bus
        yield from bus.get('devices', [])
    for track in data.get('tracks', []):
        yield track
        for key in ('devices', 'externalPluginSlots', 'sequencerLayers', 'sends'):
            yield from (track.get(key) or [])
        for clip in track.get('clips', []):
            yield clip
            yield from clip.get('notes', [])
        for clip in track.get('audioClips', []):
            yield clip
            yield from clip.get('devices', [])
            yield from clip.get('externalPluginSlots', [])


@dataclass
class ProjectFile:
    data: dict

    @classmethod
    def decode(cls, payload: bytes) -> 'ProjectFile':
        def invalid(value):
            raise ProjectContractError(f"Invalid JSON number: {value}")
        def pairs(items):
            result = {}
            for key, value in items:
                if key in result:
                    raise ProjectContractError(f"Duplicate JSON field: {key}")
                result[key] = value
            return result
        try:
            data = json.loads(payload, parse_constant=invalid, object_pairs_hook=pairs)
        except (ValueError, UnicodeError) as error:
            raise ProjectContractError(str(error)) from error
        document = cls(data)
        document.validate()
        return document

    def validate(self):
        if not isinstance(self.data, dict) or 'pythonSchema' in self.data:
            raise ProjectContractError('Expected a .lemmingsproject document, not a preview project')
        version = self.data.get('version', 1)
        if type(version) is not int or version not in (1, 2, 3):
            raise ProjectContractError('Unsupported project version; original was not modified')
        _finite(self.data)
        if not isinstance(self.data.get('tracks', []), list):
            raise ProjectContractError('Tracks must be an array')
        # Walk schema-owned collections only. Extension payloads stay opaque.
        children = {
            'project': {'tracks': 'track', 'groups': 'group', 'returnBuses': 'bus', 'masterDevices': 'device', 'tempoPoints': 'point'},
            'track': {'devices': 'device', 'externalPluginSlots': 'plugin', 'sequencerLayers': 'layer', 'sends': 'send', 'clips': 'clip', 'audioClips': 'audio', 'automationLanes': 'lane'},
            'group': {'devices': 'device', 'automationLanes': 'lane'},
            'bus': {'devices': 'device'}, 'clip': {'notes': 'note'},
            'audio': {'devices': 'device', 'externalPluginSlots': 'plugin'},
            'lane': {'points': 'point'},
        }
        def walk(obj, role):
            for key, child_role in children.get(role, {}).items():
                items = obj.get(key, [])
                if items is None:
                    continue
                if not isinstance(items, list) or any(not isinstance(x, dict) for x in items):
                    raise ProjectContractError(f'{key} must contain objects')
                for item in items:
                    walk(item, child_role)
        walk(self.data, 'project')
        seen = set()
        for obj in _entities(self.data):
            if obj.get('id') is not None:
                identity = _uuid(obj['id'])
                if identity in seen:
                    raise ProjectContractError(f'Duplicate project identity: {identity}')
                seen.add(identity)
            elif version == 3:
                raise ProjectContractError('Version 3 entities require stable IDs')

    def reference_warnings(self) -> list[str]:
        tracks = {_uuid(t['id']) for t in self.data.get('tracks', []) if t.get('id')}
        buses = {_uuid(t['id']) for t in (self.data.get('returnBuses') or []) if t.get('id')}
        warnings = []
        for group in (self.data.get('groups') or []):
            for ref in group.get('trackIDs', []):
                if _uuid(ref) not in tracks:
                    warnings.append(f'Unresolved group track: {ref}')
        for obj in _entities(self.data):
            for key in ('sidechainInputTrackID', 'sequencerPrintSourceTrackID', 'sequencerPrintTargetTrackID'):
                if obj.get(key) and _uuid(obj[key]) not in tracks:
                    warnings.append(f'Unresolved {key}: {obj[key]}')
            if obj.get('returnBusID') and _uuid(obj['returnBusID']) not in buses:
                warnings.append(f"Unresolved send return: {obj['returnBusID']}")
        return warnings

    def upgraded(self) -> 'ProjectFile':
        self.validate()
        result = ProjectFile(deepcopy(self.data))
        for obj in _entities(result.data):
            if not obj.get('id'):
                obj['id'] = str(uuid4()).upper()
        result.data['version'] = 3
        result.validate()
        # Lost v1/v2 identities cannot safely be inferred from track names/order.
        if warnings := result.reference_warnings():
            raise ProjectContractError('; '.join(warnings))
        return result

    def encode(self) -> bytes:
        self.validate()
        return (json.dumps(self.data, ensure_ascii=False, indent=2, allow_nan=False)+'\n').encode('utf-8')

    @classmethod
    def load(cls, path: Path) -> 'ProjectFile':
        return cls.decode(path.read_bytes())

    def save(self, path: Path):
        if path.suffix.lower() != '.lemmingsproject':
            raise ProjectContractError('Use the shared .lemmingsproject extension')
        payload = self.upgraded().encode()
        path = path.absolute()
        if path.is_symlink():
            raise ProjectContractError('Destination must not be a symbolic link')
        path.parent.mkdir(parents=True, exist_ok=True)
        backup = path.with_suffix(path.suffix+'.bak')
        if backup.is_symlink():
            raise ProjectContractError('Backup must not be a symbolic link')
        # Both replacement and backup are fully written before atomic rename.
        def stage(content):
            fd, name = tempfile.mkstemp(prefix='.'+path.name+'.', dir=path.parent)
            try:
                with os.fdopen(fd, 'wb') as stream:
                    stream.write(content)
                    stream.flush()
                    os.fsync(stream.fileno())
            except BaseException:
                Path(name).unlink(missing_ok=True)
                raise
            return Path(name)
        temporary = stage(payload)
        backup_temp = None
        try:
            ProjectFile.load(temporary)
            if path.exists():
                backup_temp = stage(path.read_bytes())
                os.replace(backup_temp, backup)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)
            if backup_temp:
                backup_temp.unlink(missing_ok=True)
