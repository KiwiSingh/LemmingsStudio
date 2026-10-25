#!/usr/bin/env python3
"""Run every scan in a disposable host, with timeout and persistent quarantine."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def scan(host, plugins, database, timeout=20, retry=False):
    state = json.loads(database.read_text()) if database.exists() else {}
    for name in plugins:
        path = str(Path(name).resolve())
        previous = state.get(path, {})
        if previous.get("quarantined") and not retry:
            continue
        with tempfile.TemporaryDirectory(prefix="lemmings-scan-") as folder:
            result_file = Path(folder) / "descriptions.xml"
            try:
                result = subprocess.run(
                    [str(host), "--scan-vst3", path, str(result_file)],
                    capture_output=True, timeout=timeout, check=False,
                )
                ok = result.returncode == 0 and result_file.exists()
                entry = {"quarantined": not ok, "exitCode": result.returncode}
                if ok:
                    entry["descriptionXml"] = result_file.read_text()
            except subprocess.TimeoutExpired:
                entry = {"quarantined": True, "reason": "scan timed out"}
            state[path] = entry
            database.parent.mkdir(parents=True, exist_ok=True)
            temporary = database.with_suffix(".tmp")
            temporary.write_text(json.dumps(state, indent=2))
            temporary.replace(database)
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", type=Path)
    parser.add_argument("plugins", nargs="+")
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--retry", action="store_true")
    args = parser.parse_args()
    state = scan(args.host.resolve(), args.plugins, args.database, args.timeout, args.retry)
    print(json.dumps(state, indent=2))
    return 1 if any(x.get("quarantined") for x in state.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
