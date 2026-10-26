"""Launch diagnostics initialized before Qt, NumPy or audio libraries import."""
from datetime import datetime, timezone
from pathlib import Path
import faulthandler
import json
import logging
import os
import sys
import time
import traceback


class LaunchLog:
    def __init__(self):
        self.started = time.perf_counter()
        self.events = []
        configured = os.environ.get('LEMMINGS_DIAGNOSTICS_DIR')
        if configured:
            folder = Path(configured)
        elif sys.platform == 'win32':
            folder = Path(os.environ.get('LOCALAPPDATA', str(Path.home())))/'LemmingsStudio/Diagnostics'
        else:
            # Source development stays beside the external checkout, not in ~/Library.
            folder = Path(__file__).resolve().parents[3]/'.local/diagnostics'
        folder.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')+f'-{os.getpid()}'
        self.path = folder/f'launch-{stamp}.log'
        self.report_path = folder/f'launch-{stamp}.json'
        self.logger = logging.Logger(f'lemmings.launch.{stamp}')
        handler = logging.FileHandler(self.path, encoding='utf-8')
        handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        self.logger.addHandler(handler)
        self.fault_stream = (folder/f'fault-{stamp}.log').open('w', encoding='utf-8')
        faulthandler.enable(file=self.fault_stream, all_threads=True)
        self.mark('process_entry', frozen=bool(getattr(sys, 'frozen', False)))

    def mark(self, name, **details):
        event = {'phase': name, 'elapsed_ms': round((time.perf_counter()-self.started)*1000, 2), **details}
        self.events.append(event)
        self.logger.info(json.dumps(event, ensure_ascii=False))

    def error(self, name, error):
        self.mark(name, error=str(error))
        self.logger.error(''.join(traceback.format_exception(error)))

    def write_report(self, **details):
        payload = {'events': self.events, 'log': str(self.path), **details}
        self.report_path.write_text(json.dumps(payload, indent=2), encoding='utf-8')
        return payload

    def close(self):
        faulthandler.disable()
        self.fault_stream.close()
        for handler in self.logger.handlers[:]:
            handler.close()
            self.logger.removeHandler(handler)
