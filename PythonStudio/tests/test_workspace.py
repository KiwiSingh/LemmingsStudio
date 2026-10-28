import os
os.environ.setdefault("QT_QPA_PLATFORM","offscreen")
from PySide6.QtWidgets import QApplication
from lemmings_studio.model import Project
from lemmings_studio.ui import MainWindow


def test_editor_commands_mutate_the_saved_and_rendered_document():
    app = QApplication.instance() or QApplication([])
    window = MainWindow(Project.demo())
    original = window.document.project.encode()
    window.select_clip(1, window.document.project.tracks[1].clips[0].id)
    window.draw_note(2,72)
    assert window.selected_clip().notes[-1].pitch == 72
    window.undo()
    assert window.document.project.encode() == original
    window.redo()
    window.duplicate_clip()
    assert len(window.document.project.tracks[1].clips) == 2
    assert len({c.id for c in window.document.project.tracks[1].clips}) == 2
    window.toggle_step(36,0)
    assert any(n.pitch==36 and n.start==0 for n in window.selected_clip().notes)
    window.toggle_step(36,0)
    assert not any(n.pitch==36 and n.start==0 for n in window.selected_clip().notes)
    window.resize(800,600)
    window.show(); app.processEvents()
    assert window.arrangement.viewport().width() > 200
    assert window.arrangement.viewport().height() > 100
    assert window.minimumWidth() <= 800
    window.document.saved_revision = window.document.revision
    window.close(); app.processEvents()


def test_late_open_does_not_replace_new_user_edits(monkeypatch,tmp_path):
    from PySide6.QtWidgets import QFileDialog
    from lemmings_studio.model import save_project,load_project
    app = QApplication.instance() or QApplication([])
    window = MainWindow(Project.demo())
    path = tmp_path/'incoming.lemmingspy'
    incoming = Project.demo(); incoming.name='Incoming'
    save_project(incoming,path)
    pending = {}
    monkeypatch.setattr(QFileDialog,'getOpenFileName',lambda *a,**k:(str(path),''))
    monkeypatch.setattr(window,'submit',lambda label,job,done:pending.update(job=job,done=done))
    window.open_project()
    window.change('Rename while loading',lambda p:setattr(p,'name','Keep my edit'))
    pending['done'](pending['job']())
    assert window.document.project.name == 'Keep my edit'
    assert window.path is None
    window.document.saved_revision=window.document.revision
    window.close();app.processEvents()


def test_stale_audio_events_do_not_move_stopped_transport():
    app = QApplication.instance() or QApplication([])
    window=MainWindow(Project.demo())
    old_generation=window.engine.generation
    window.stop()
    window.events.position.emit(old_generation,10)
    window.events.audio_finished.emit(old_generation,'Audio error: stale device')
    app.processEvents()
    assert window.cursor_beat==0
    assert window.statusBar().currentMessage()=='Stopped'
    window.close();app.processEvents()
