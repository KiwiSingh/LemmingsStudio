"""Stage byte-identical Mac branding into an explicit build output directory."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
reference = json.loads((root/'Docs/Parity/mac-reference.json').read_text())
assets = [a for a in reference['assets'] if Path(a['path']).name.startswith('MagmaVancePreSplash')
          or Path(a['path']).name in ('LemmingsSplash.png', 'LemmingsStartup.wav', 'startup.wav')]
args.output.mkdir(parents=True, exist_ok=True)
manifest = {}
for asset in assets:
    source = root/asset['path']
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != asset['sha256']:
        raise SystemExit(f'Original reference asset changed: {source.name}')
    shutil.copyfile(source, args.output/source.name)
    manifest[source.name] = {'sha256': digest, 'source': asset['path']}
(args.output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(f'Staged {len(manifest)} original branding assets with reference checksums')
