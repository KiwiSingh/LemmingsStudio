"""Lightweight launch entry: logging precedes all GUI/audio dependencies."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from .diagnostics import LaunchLog


def main():
    parser = argparse.ArgumentParser(description='LemmingsStudio Windows parity development build')
    parser.add_argument('--self-test-report', type=Path)
    parser.add_argument('--startup-check-report', type=Path,
                        help='Check original media and real Qt Quick presentation without opening an audio device')
    parser.add_argument('--software-rendering', action='store_true')
    args = parser.parse_args()
    if args.self_test_report:
        os.environ['QT_QPA_PLATFORM'] = 'offscreen'
    if args.software_rendering:
        os.environ['QT_QUICK_BACKEND'] = 'software'
    log = LaunchLog()
    os.environ.setdefault('QML_DISK_CACHE_PATH', str(log.path.parent/'QmlCache'))
    previous_hook = sys.excepthook
    def exception_hook(kind, error, trace):
        log.error('unhandled_exception', error.with_traceback(trace))
        log.write_report(status='failed')
        previous_hook(kind, error, trace)
    sys.excepthook = exception_hook
    previous_qt_handler = None
    handler_installed = False
    try:
        log.mark('qt_import_started')
        from PySide6.QtCore import QObject, Signal, Slot, QTimer, qInstallMessageHandler
        from PySide6.QtWidgets import QApplication, QMessageBox
        log.mark('qt_import_finished')
        app = QApplication([sys.argv[0]])
        app.setApplicationName('LemmingsStudio')
        def qt_message(_kind, _context, message):
            log.logger.warning('Qt: %s', message)
        previous_qt_handler = qInstallMessageHandler(qt_message)
        handler_installed = True
        log.mark('application_created', platform=app.platformName(),
                 graphics=os.environ.get('QT_QUICK_BACKEND', 'automatic'))
        if args.self_test_report:
            from .validation import validate_bundle
            try:
                result = validate_bundle(app)
            except Exception as error:
                log.error('bundle_check_failed', error)
                result = {'status': 'failed', 'error': str(error)}
            args.self_test_report.parent.mkdir(parents=True, exist_ok=True)
            args.self_test_report.write_text(json.dumps(result, indent=2), encoding='utf-8')
            log.write_report(**result)
            return 0 if result['status'] == 'passed' else 1

        class Coordinator(QObject):
            preloaded = Signal()
            preload_failed = Signal(object)

            def __init__(self):
                super().__init__()
                self.window = None
                self.branding_done = False
                self.started_preload = False
                self.exit_code = 0
                self.completed = False
                self.preloaded.connect(self.prepare_workspace)
                self.preload_failed.connect(self.failed)
                from .startup import Startup
                self.startup = Startup(app, log, check_mode=bool(args.startup_check_report))
                self.startup.finished.connect(self.branding_finished)
                self.startup.graphicsFailed.connect(self.graphics_failed)
                self.startup.window.frameSwapped.connect(self.first_frame)
                self.deadline = QTimer(self)
                self.deadline.setSingleShot(True)
                self.deadline.timeout.connect(lambda: self.failed(RuntimeError('Startup exceeded 30 seconds')))
                self.deadline.start(30000)
                app.setQuitOnLastWindowClosed(False)
                app.aboutToQuit.connect(self.startup.shutdown)
                self.startup.start()

            @Slot()
            def first_frame(self):
                if self.started_preload:
                    return
                self.started_preload = True
                log.mark('workspace_preload_started')
                def preload():
                    try:
                        # Qt presentation stays on the GUI thread. Native audio-library
                        # imports happen here, after the first branded frame is visible.
                        from . import audio, model
                        self.preloaded.emit()
                    except Exception as error:
                        self.preload_failed.emit(error)
                threading.Thread(target=preload, name='LemmingsLaunch', daemon=True).start()

            @Slot()
            def prepare_workspace(self):
                if self.completed:
                    return
                try:
                    from .workspace import WorkspaceWindow
                    self.window = WorkspaceWindow(check_mode=bool(args.startup_check_report))
                    log.mark('workspace_constructed')
                    self.handover()
                except Exception as error:
                    self.failed(error)

            @Slot()
            def branding_finished(self):
                self.branding_done = True
                self.startup.waiting_for_workspace()
                self.handover()

            @Slot()
            def complete_check(self):
                result = self.startup.result()
                result['checks']['workspace_visible'] = bool(self.window and self.window.isVisible())
                if not result['checks']['workspace_visible']:
                    result['status'] = 'failed'
                try:
                    from .workspace_checks import verify
                    result['workspace'] = verify(self.window, args.startup_check_report.parent/'workspace-evidence')
                except Exception as error:
                    result['status'] = 'failed'
                    result['workspace_error'] = str(error)
                    log.error('workspace_check_failed', error)
                self.exit_code = 0 if result['status'] == 'passed' else 1
                args.startup_check_report.parent.mkdir(parents=True, exist_ok=True)
                payload = log.write_report(**result)
                args.startup_check_report.write_text(json.dumps(payload, indent=2), encoding='utf-8')
                app.quit()

            def handover(self):
                if self.completed or not self.branding_done or self.window is None:
                    return
                self.completed = True
                self.deadline.stop()
                self.window.show()
                self.startup.hide()
                app.setQuitOnLastWindowClosed(True)
                log.mark('workspace_shown')
                log.write_report(status='workspace_ready', branding=self.startup.result())
                if args.startup_check_report:
                    QTimer.singleShot(250, self.complete_check)

            @Slot(object)
            def failed(self, error):
                if self.completed:
                    return
                self.completed = True
                self.exit_code = 1
                self.deadline.stop()
                log.error('startup_failed', error)
                result = log.write_report(status='failed', error=str(error))
                if args.startup_check_report:
                    args.startup_check_report.parent.mkdir(parents=True, exist_ok=True)
                    args.startup_check_report.write_text(json.dumps(result, indent=2), encoding='utf-8')
                else:
                    QMessageBox.critical(None, 'LemmingsStudio could not finish opening',
                                         f'{error}\n\nLaunch log: {log.path}')
                app.quit()

            @Slot(str)
            def graphics_failed(self, message):
                log.mark('scene_graph_error', error=message)
                if args.software_rendering or args.startup_check_report:
                    self.failed(RuntimeError(message))
                    return
                self.completed = True
                self.deadline.stop()
                command = [sys.executable]
                if not getattr(sys, 'frozen', False):
                    command += ['-m', 'lemmings_studio']
                command += [*sys.argv[1:], '--software-rendering']
                try:
                    subprocess.Popen(command)
                    log.mark('software_renderer_restart_requested')
                except OSError as error:
                    self.completed = False
                    self.failed(error)
                    return
                app.quit()

        coordinator = Coordinator()
        app.exec()
        return coordinator.exit_code
    except Exception as error:
        log.error('launch_failed', error)
        result = log.write_report(status='failed', error=str(error))
        report = args.startup_check_report or args.self_test_report
        if report:
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(json.dumps(result, indent=2), encoding='utf-8')
        else:
            # Qt may be unavailable; still show a useful failure for windowed builds.
            if sys.platform == 'win32':
                import ctypes
                ctypes.windll.user32.MessageBoxW(None, f'{error}\n\nLaunch log: {log.path}',
                                                'LemmingsStudio could not open', 0x10)
        return 1
    finally:
        if handler_installed:
            qInstallMessageHandler(previous_qt_handler)
        sys.excepthook = previous_hook
        log.close()
