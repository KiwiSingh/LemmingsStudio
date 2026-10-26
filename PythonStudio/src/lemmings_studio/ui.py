"""Cross-platform workspace. Menus and editors share the same document commands."""
from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from pathlib import Path
import sys
from threading import Event
import numpy as np
import soundfile as sf
from PySide6.QtCore import QObject, QRectF, Qt, Signal, QPointF, QTimer
from PySide6.QtGui import QAction, QColor, QKeySequence, QPainter, QPen
from PySide6.QtWidgets import (
    QApplication, QComboBox, QDockWidget, QDoubleSpinBox, QFileDialog, QFormLayout,
    QGraphicsItem, QGraphicsRectItem, QGraphicsScene, QGraphicsView, QHBoxLayout,
    QLabel, QLineEdit, QListWidget, QMainWindow, QMessageBox, QPushButton,
    QScrollArea, QSlider, QTabWidget, QToolBar, QVBoxLayout, QWidget,
)
from .audio import AudioEngine, Renderer
from .model import Clip, Document, Note, Project, Track, identity, load_project, save_project

COLOURS = ["#73dcff", "#bf98ff", "#57f59e", "#ffb778", "#ff8ac1"]
STYLE = """
QMainWindow, QWidget { background: #101725; color: #eff5ff; font-size: 12px; }
QMenuBar, QToolBar, QStatusBar { background: #111b2c; spacing: 6px; padding: 4px; }
QMenu { background: #1c2638; border: 1px solid #39445a; }
QPushButton, QToolButton { background: #28344b; border: 1px solid #43516b; border-radius: 6px; padding: 6px 10px; }
QPushButton:hover, QToolButton:hover { background: #35475f; border-color: #73dcff; }
QPushButton:checked { background: #245546; color: #57f59e; }
QPushButton:disabled { color: #647087; }
QLineEdit, QDoubleSpinBox, QComboBox { background: #111a2b; border: 1px solid #39445a; padding: 5px; border-radius: 5px; }
QDockWidget { border: 1px solid #39445a; }
QDockWidget::title { background: #202c40; padding: 9px; }
QTabWidget::pane { border: 1px solid #39445a; background: #141e2f; }
QTabBar::tab { background: #1c2638; padding: 9px 14px; border-bottom: 2px solid transparent; }
QTabBar::tab:selected { background: #28344b; border-bottom-color: #73dcff; color: #73dcff; }
QListWidget { background: #172132; border: none; padding: 6px; }
QListWidget::item { padding: 8px; }
QListWidget::item:selected { background: #304d64; border-radius: 5px; }
QScrollArea { border: none; }
QSlider::groove:horizontal { background: #39445a; height: 5px; }
QSlider::handle:horizontal { background: #73dcff; width: 13px; margin: -5px 0; border-radius: 6px; }
"""


class Events(QObject):
    position = Signal(int, float)
    audio_finished = Signal(int, str)
    status = Signal(str)
    completed = Signal(object)


class ClipItem(QGraphicsRectItem):
    def __init__(self, window, track_index, clip_index, clip):
        super().__init__(0, 0, max(12, clip.length*44), 62)
        self.window, self.track_index, self.clip_id = window, track_index, clip.id
        self.fixed_y = track_index*82+38
        self.setPos(clip.start*44+150, self.fixed_y)
        self.setBrush(QColor(COLOURS[track_index % len(COLOURS)]).darker(210))
        self.setPen(QPen(QColor(COLOURS[track_index % len(COLOURS)]), 1.5))
        self.setFlags(QGraphicsItem.GraphicsItemFlag.ItemIsMovable | QGraphicsItem.GraphicsItemFlag.ItemIsSelectable | QGraphicsItem.GraphicsItemFlag.ItemSendsGeometryChanges)
        self.setToolTip(f"{clip.name}\nDrag to move; edit start and length in Inspector")

    def itemChange(self, change, value):
        if change == QGraphicsItem.GraphicsItemChange.ItemPositionChange:
            return QPointF(max(150, round((value.x()-150)/11)*11+150), self.fixed_y)
        return super().itemChange(change, value)

    def mousePressEvent(self, event):
        self.window.select_clip(self.track_index, self.clip_id, refresh=False)
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)
        beat = max(0, (self.pos().x()-150)/44)
        clip_id = self.clip_id
        QTimer.singleShot(0, lambda: self.window.change("Move clip", lambda p: setattr(self.window.find_clip(p, clip_id), "start", beat)))


class NoteItem(QGraphicsRectItem):
    def __init__(self, window, note):
        super().__init__(0, 0, max(5, note.length*70), 12)
        self.window, self.note_id = window, note.id
        self.setPos(note.start*70+58, (84-note.pitch)*14+30)
        self.setBrush(QColor("#bf98ff")); self.setPen(QPen(QColor("#d9c2ff")))
        self.setFlags(QGraphicsItem.GraphicsItemFlag.ItemIsMovable | QGraphicsItem.GraphicsItemFlag.ItemIsSelectable | QGraphicsItem.GraphicsItemFlag.ItemSendsGeometryChanges)

    def itemChange(self, change, value):
        if change == QGraphicsItem.GraphicsItemChange.ItemPositionChange:
            return QPointF(max(58, round((value.x()-58)/17.5)*17.5+58), min(1206, max(30, round((value.y()-30)/14)*14+30)))
        return super().itemChange(change, value)

    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)
        note_id, beat, pitch = self.note_id, max(0, (self.pos().x()-58)/70), 84-round((self.pos().y()-30)/14)
        def move(p):
            clip = self.window.selected_clip(p)
            note = next(n for n in clip.notes if n.id == note_id)
            note.start = min(beat, clip.length-.0625)
            note.pitch = max(0, min(127, pitch))
        QTimer.singleShot(0, lambda: self.window.change("Move note", move))


class Timeline(QGraphicsView):
    def __init__(self, window, piano=False):
        super().__init__()
        self.window, self.piano = window, piano
        self.setScene(QGraphicsScene(self))
        self.setRenderHint(QPainter.RenderHint.Antialiasing)
        self.setBackgroundBrush(QColor("#131d2e"))
        self.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        self.setDragMode(QGraphicsView.DragMode.RubberBandDrag)

    def mouseDoubleClickEvent(self, event):
        position = self.mapToScene(event.position().toPoint())
        if self.piano:
            if position.x() >= 58:
                self.window.draw_note(max(0, (position.x()-58)/70), max(0, min(127, 84-int((position.y()-30)/14))))
        else:
            item = self.itemAt(event.position().toPoint())
            while item and not isinstance(item, ClipItem):
                item = item.parentItem()
            if isinstance(item, ClipItem):
                self.window.select_clip(item.track_index, item.clip_id)
                self.window.tabs.setCurrentIndex(1)
            else:
                index = int((position.y()-38)/82)
                if 0 <= index < len(self.window.document.project.tracks):
                    self.window.track_index = index
                    self.window.create_clip(max(0, round((position.x()-150)/176)*4))
        event.accept()

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key.Key_Delete, Qt.Key.Key_Backspace):
            selected = self.scene().selectedItems()
            notes = {i.note_id for i in selected if isinstance(i, NoteItem)}
            clips = {i.clip_id for i in selected if isinstance(i, ClipItem)}
            if notes:
                self.window.change("Delete notes", lambda p: setattr(self.window.selected_clip(p), "notes", [n for n in self.window.selected_clip(p).notes if n.id not in notes]))
            elif clips:
                def remove(p):
                    for t in p.tracks:
                        t.clips = [c for c in t.clips if c.id not in clips]
                self.window.change("Delete clips", remove)
            return
        super().keyPressEvent(event)


class MainWindow(QMainWindow):
    def __init__(self, project: Project | None = None):
        super().__init__()
        self.document = Document(project)
        self.path: Path | None = None
        self.track_index = 1
        self.clip_id: str | None = None
        self.cursor_beat = 0.0
        self.epoch = 0
        self._updating = False
        self.jobs = ThreadPoolExecutor(max_workers=1, thread_name_prefix="LemmingsJob")
        self.cancel_export = Event()
        self.events = Events()
        self.engine = AudioEngine()
        self.engine.on_position = self.events.position.emit
        self.engine.on_finished = self.events.audio_finished.emit
        self.events.status.connect(self.show_status)
        self.events.position.connect(lambda generation, beat: self.update_position(beat) if generation == self.engine.generation else None)
        self.events.audio_finished.connect(lambda generation, message: self.show_status(message) if generation == self.engine.generation else None)
        self.events.completed.connect(self.complete_job)
        self.setStyleSheet(STYLE)
        self.setMinimumSize(480, 320)
        screen = QApplication.primaryScreen().availableGeometry()
        self.resize(min(1380, screen.width()-40), min(850, screen.height()-60))
        self.setWindowTitle("LemmingsStudio Windows · Python rewrite")
        self.make_actions()
        self.make_transport()
        self.tabs = QTabWidget()
        self.arrangement, self.piano = Timeline(self), Timeline(self, piano=True)
        self.steps, self.mixer = QWidget(), QWidget()
        self.tabs.addTab(self.arrangement, "Arrangement")
        self.tabs.addTab(self.piano, "Piano Roll")
        self.tabs.addTab(self.steps, "Sequencer")
        self.tabs.addTab(self.mixer, "Mixer")
        self.setCentralWidget(self.tabs)
        self.make_browser()
        self.make_inspector()
        self.statusBar().showMessage("Experimental branch · existing macOS and Windows builds are unchanged")
        if screen.width() < 1150:
            self.inspector.hide()
        if screen.width() < 850:
            self.browser.hide()
        self.refresh()

    def action(self, label, callback, shortcut=None):
        action = QAction(label, self)
        action.triggered.connect(lambda checked=False: callback())
        if shortcut:
            action.setShortcut(shortcut)
        return action

    def make_actions(self):
        file = self.menuBar().addMenu("File")
        self.new_action = self.action("New", self.new_project, QKeySequence.StandardKey.New)
        self.open_action = self.action("Open Python project…", self.open_project, QKeySequence.StandardKey.Open)
        self.save_action = self.action("Save", self.save, QKeySequence.StandardKey.Save)
        self.save_as_action = self.action("Save as…", lambda: self.save(as_new=True), QKeySequence.StandardKey.SaveAs)
        self.import_action = self.action("Import audio…", self.import_audio)
        self.export_action = self.action("Export WAV…", self.export_audio)
        file.addActions([self.new_action, self.open_action, self.save_action, self.save_as_action])
        file.addSeparator(); file.addActions([self.import_action, self.export_action])
        edit = self.menuBar().addMenu("Edit")
        self.undo_action = self.action("Undo", self.undo, QKeySequence.StandardKey.Undo)
        self.redo_action = self.action("Redo", self.redo, QKeySequence.StandardKey.Redo)
        edit.addActions([self.undo_action, self.redo_action])
        edit.addAction(self.action("Duplicate clip", self.duplicate_clip, QKeySequence("Ctrl+D")))
        edit.addAction(self.action("Delete selected clip", self.delete_clip))
        track = self.menuBar().addMenu("Track")
        track.addAction(self.action("Add audio track", lambda: self.add_track("audio")))
        track.addAction(self.action("Add MIDI track", lambda: self.add_track("midi")))
        track.addAction(self.action("Create MIDI clip", self.create_clip))
        self.view_menu = self.menuBar().addMenu("View")
        help_menu = self.menuBar().addMenu("Help")
        help_menu.addAction(self.action("Rewrite status", lambda: QMessageBox.information(self, "Python rewrite", "This branch is not feature-complete. Existing projects and builds remain the reference.\n\nImplemented: native Python projects, arrangement and MIDI editing, sequencer, mixer, playback and WAV export.\n\nPending: full legacy project migration, recording, plugin hosting, effects, AI, routing and the remaining macOS workflows.")))

    def make_transport(self):
        bar = QToolBar("Transport", self)
        bar.setMovable(False)
        self.addToolBar(bar)
        brand = QLabel("  LEMMINGS STUDIO  ")
        brand.setStyleSheet("color:#73dcff; font-weight:700; padding:8px;")
        bar.addWidget(brand)
        self.play_button = QPushButton("Play")
        self.play_button.clicked.connect(self.play)
        bar.addWidget(self.play_button)
        stop = QPushButton("Stop"); stop.clicked.connect(self.stop); bar.addWidget(stop)
        rewind = QPushButton("Return"); rewind.clicked.connect(self.return_to_start); bar.addWidget(rewind)
        bar.addSeparator(); bar.addWidget(QLabel(" BPM "))
        self.tempo = QDoubleSpinBox(); self.tempo.setRange(20, 400); self.tempo.setDecimals(1); self.tempo.setKeyboardTracking(False)
        self.tempo.valueChanged.connect(lambda value: None if self._updating else self.change("Change tempo", lambda p: setattr(p, "tempo", value)))
        bar.addWidget(self.tempo)
        self.position = QLabel("  1:1  ·  0.00 s  "); bar.addWidget(self.position)
        self.audio_action = self.action("Audio device…", self.choose_audio_device)
        bar.addAction(self.audio_action)
        self.play_action = self.action("Play / stop", self.play, QKeySequence(Qt.Key.Key_Space))
        self.addAction(self.play_action)

    def make_browser(self):
        self.browser = QDockWidget("LIBRARY", self)
        body = QWidget(); box = QVBoxLayout(body)
        self.search = QLineEdit(); self.search.setPlaceholderText("Search tracks"); self.search.textChanged.connect(self.refresh_library); box.addWidget(self.search)
        self.track_list = QListWidget(); self.track_list.currentRowChanged.connect(self.select_track); box.addWidget(self.track_list)
        for text, command in (("+ Audio track", lambda: self.add_track("audio")), ("+ MIDI track", lambda: self.add_track("midi")), ("Import audio…", self.import_audio)):
            button = QPushButton(text); button.clicked.connect(command); box.addWidget(button)
        self.browser.setWidget(body); self.addDockWidget(Qt.DockWidgetArea.LeftDockWidgetArea, self.browser)
        self.view_menu.addAction(self.browser.toggleViewAction())

    def make_inspector(self):
        self.inspector = QDockWidget("INSPECTOR", self)
        scroll = QScrollArea(); scroll.setWidgetResizable(True)
        body = QWidget(); form = QFormLayout(body)
        self.track_name = QLineEdit(); self.track_name.editingFinished.connect(self.rename_track)
        form.addRow("Track", self.track_name)
        self.voice = QComboBox(); self.voice.addItems(["sine", "triangle", "saw", "square", "drums"])
        self.voice.currentTextChanged.connect(lambda value: None if self._updating else self.change("Choose instrument", lambda p: setattr(p.tracks[self.track_index], "instrument", value)))
        form.addRow("Instrument", self.voice)
        self.gain = QDoubleSpinBox(); self.gain.setRange(0, 4); self.gain.setSingleStep(.05); self.gain.setKeyboardTracking(False)
        self.gain.valueChanged.connect(lambda value: None if self._updating else self.change("Track gain", lambda p: setattr(p.tracks[self.track_index], "gain", value)))
        form.addRow("Gain", self.gain)
        self.pan = QDoubleSpinBox(); self.pan.setRange(-1, 1); self.pan.setSingleStep(.05); self.pan.setKeyboardTracking(False)
        self.pan.valueChanged.connect(lambda value: None if self._updating else self.change("Track pan", lambda p: setattr(p.tracks[self.track_index], "pan", value)))
        form.addRow("Pan", self.pan)
        self.clip_name = QLineEdit(); self.clip_name.editingFinished.connect(self.rename_clip); form.addRow("Clip", self.clip_name)
        self.clip_start = QDoubleSpinBox(); self.clip_start.setRange(0, 1_000_000); self.clip_start.setKeyboardTracking(False)
        self.clip_start.valueChanged.connect(lambda value: None if self._updating else self.change("Move clip", lambda p: setattr(self.selected_clip(p), "start", value)))
        form.addRow("Start beat", self.clip_start)
        self.clip_length = QDoubleSpinBox(); self.clip_length.setRange(.25, 1_000_000); self.clip_length.setSingleStep(.25); self.clip_length.setKeyboardTracking(False)
        self.clip_length.valueChanged.connect(lambda value: None if self._updating else self.change("Resize clip", lambda p: setattr(self.selected_clip(p), "length", value)))
        form.addRow("Length", self.clip_length)
        for name, command in (("Duplicate clip", self.duplicate_clip), ("Delete clip", self.delete_clip), ("Add C4 note", lambda: self.draw_note(0, 60))):
            button = QPushButton(name); button.clicked.connect(command); form.addRow(button)
        scroll.setWidget(body); self.inspector.setWidget(scroll); self.addDockWidget(Qt.DockWidgetArea.RightDockWidgetArea, self.inspector)
        self.view_menu.addAction(self.inspector.toggleViewAction())

    def selected_track(self, project=None):
        project = project or self.document.project
        if not 0 <= self.track_index < len(project.tracks):
            raise ValueError("Select a track first")
        return project.tracks[self.track_index]

    def selected_clip(self, project=None):
        return next((c for c in self.selected_track(project).clips if c.id == self.clip_id), None)

    @staticmethod
    def find_clip(project, clip_id):
        return next(c for t in project.tracks for c in t.clips if c.id == clip_id)

    def change(self, label, operation):
        if self._updating:
            return
        try:
            changed = self.document.edit(label, operation)
            if changed:
                self.engine.stop()
                self.show_status(label)
                self.refresh()
        except Exception as error:
            self.show_status(str(error))

    def add_track(self, kind):
        self.change("Add track", lambda p: p.tracks.append(Track(name=f"{kind.title()} {len(p.tracks)+1}", kind=kind)))
        self.track_index = len(self.document.project.tracks)-1
        self.clip_id = None; self.refresh()

    def create_clip(self, start=0):
        if not self.document.project.tracks or self.selected_track().kind != "midi":
            self.show_status("Select a MIDI track before drawing a clip")
            return
        new_clip = Clip(start=float(start))
        self.change("Create MIDI clip", lambda p: p.tracks[self.track_index].clips.append(new_clip))
        self.clip_id = new_clip.id; self.refresh()

    def draw_note(self, beat, pitch):
        if not self.selected_clip() or self.selected_track().kind != "midi":
            self.show_status("Select or create a MIDI clip first")
            return
        beat = min(max(0, round(beat*4)/4), self.selected_clip().length-.0625)
        self.change("Draw note", lambda p: self.selected_clip(p).notes.append(Note(pitch=pitch, start=beat)))

    def duplicate_clip(self):
        if not self.selected_clip():
            self.show_status("Select a clip first"); return
        def duplicate(p):
            c = deepcopy(self.selected_clip(p)); c.id = identity(); c.start += c.length
            for n in c.notes:
                n.id = identity()
            self.selected_track(p).clips.append(c)
        self.change("Duplicate clip", duplicate)

    def delete_clip(self):
        if not self.selected_clip():
            self.show_status("Select a clip first"); return
        self.change("Delete clip", lambda p: setattr(self.selected_track(p), "clips", [c for c in self.selected_track(p).clips if c.id != self.clip_id]))
        self.clip_id = None; self.refresh()

    def rename_track(self):
        if not self._updating:
            value = self.track_name.text()
            self.change("Rename track", lambda p: setattr(self.selected_track(p), "name", value))

    def rename_clip(self):
        if not self._updating and self.selected_clip():
            value = self.clip_name.text()
            self.change("Rename clip", lambda p: setattr(self.selected_clip(p), "name", value))

    def select_track(self, row):
        if self._updating or row < 0:
            return
        self.track_index = self.filtered_tracks[row]
        self.clip_id = None
        self.refresh()

    def select_clip(self, track, clip_id, refresh=True):
        self.track_index, self.clip_id = track, clip_id
        self.refresh_inspector()
        if refresh:
            self.refresh()

    def refresh_library(self):
        previous = self._updating; self._updating = True
        self.filtered_tracks = [i for i, t in enumerate(self.document.project.tracks) if self.search.text().lower() in t.name.lower()]
        self.track_list.clear()
        for i in self.filtered_tracks:
            self.track_list.addItem(self.document.project.tracks[i].name)
        if self.track_index in self.filtered_tracks:
            self.track_list.setCurrentRow(self.filtered_tracks.index(self.track_index))
        self._updating = previous

    def refresh_inspector(self):
        previous = self._updating; self._updating = True
        try:
            track = self.selected_track()
            self.track_name.setText(track.name); self.voice.setCurrentText(track.instrument)
            self.voice.setEnabled(track.kind == "midi"); self.gain.setValue(track.gain); self.pan.setValue(track.pan)
            clip = self.selected_clip()
            for field in (self.clip_name, self.clip_start, self.clip_length):
                field.setEnabled(clip is not None)
            self.clip_name.setText(clip.name if clip else "")
            if clip:
                self.clip_start.setValue(clip.start); self.clip_length.setValue(clip.length)
        except ValueError:
            pass
        self._updating = previous

    def refresh(self):
        self._updating = True
        self.track_index = max(0, min(self.track_index, len(self.document.project.tracks)-1))
        project = self.document.project
        self.tempo.setValue(project.tempo)
        self.undo_action.setEnabled(bool(self.document.undo_stack)); self.redo_action.setEnabled(bool(self.document.redo_stack))
        self.refresh_library(); self.refresh_inspector()
        self.setWindowTitle(f"{'* ' if self.document.dirty else ''}{project.name} — LemmingsStudio Windows Python rewrite")
        self.paint_arrangement(); self.paint_piano(); self.paint_steps(); self.paint_mixer()
        self._updating = False

    def paint_arrangement(self):
        scene = self.arrangement.scene(); scene.clear()
        project = self.document.project
        width = max(900, (project.end_beat+8)*44+150)
        height = max(320, len(project.tracks)*82+40)
        scene.setSceneRect(0, 0, width, height)
        for beat in range(int((width-150)/44)):
            x = beat*44+150
            scene.addLine(x, 28, x, height, QPen(QColor("#35415a" if beat%4==0 else "#202c40")))
            if beat%4==0:
                text = scene.addText(str(beat//4+1)); text.setDefaultTextColor(QColor("#aab4ca")); text.setPos(x+4, 0)
        for i, track in enumerate(project.tracks):
            y = i*82+36
            scene.addRect(0, y, 145, 78, QPen(QColor("#35415a")), QColor("#202c40"))
            name = scene.addText(track.name); name.setDefaultTextColor(QColor(COLOURS[i%len(COLOURS)])); name.setPos(8, y+8)
            kind = scene.addText(track.kind.upper()); kind.setDefaultTextColor(QColor("#aab4ca")); kind.setPos(8, y+35)
            for ci, clip in enumerate(track.clips):
                item = ClipItem(self, i, ci, clip); scene.addItem(item)
                text = scene.addText(clip.name); text.setDefaultTextColor(QColor("#eff5ff")); text.setParentItem(item); text.setPos(5, 2)
                for n in clip.notes:
                    note = QGraphicsRectItem(n.start*44, 48-(n.pitch-48)*.65, max(2, n.length*44-1), 3, item)
                    note.setBrush(QColor(COLOURS[i%len(COLOURS)])); note.setPen(QPen(Qt.PenStyle.NoPen))
        self.playhead = scene.addLine(150+self.cursor_beat*44, 28, 150+self.cursor_beat*44, height, QPen(QColor("#57f59e"), 2))

    def paint_piano(self):
        scene = self.piano.scene(); scene.clear()
        clip = self.selected_clip()
        if not clip or self.selected_track().kind != "midi":
            text = scene.addText("Select a MIDI clip. Double-click its arrangement clip to open this editor."); text.setDefaultTextColor(QColor("#aab4ca"))
            return
        width = max(600, clip.length*70+90)
        scene.setSceneRect(0, 0, width, 720)
        for row, pitch in enumerate(range(84, 35, -1)):
            y = row*14+30; black = pitch%12 in (1, 3, 6, 8, 10)
            scene.addRect(0, y, width, 14, QPen(QColor("#28344b")), QColor("#172132" if black else "#243149"))
            scene.addRect(0, y, 54, 14, QPen(Qt.PenStyle.NoPen), QColor("#101725" if black else "#aab4ca"))
            if pitch%12==0:
                text = scene.addText(f"C{pitch//12-1}"); text.setDefaultTextColor(QColor("#101725")); text.setPos(2, y-4)
        for step in range(int(clip.length*4)+1):
            x = 58+step*17.5
            scene.addLine(x, 30, x, 716, QPen(QColor("#50617d" if step%4==0 else "#303d55")))
        for note in clip.notes:
            scene.addItem(NoteItem(self, note))
        self.piano.centerOn(200, (84-60)*14+30)

    def replace_page_layout(self, page):
        old = page.layout()
        if old:
            while old.count():
                item = old.takeAt(0)
                if item.widget():
                    item.widget().deleteLater()
            return old
        return QVBoxLayout(page)

    def paint_steps(self):
        box = self.replace_page_layout(self.steps)
        clip = self.selected_clip()
        title = QLabel("16-STEP SEQUENCER  ·  Select Drum synth for percussion playback")
        box.addWidget(title)
        if not clip or self.selected_track().kind != "midi":
            box.addWidget(QLabel("Select or create a MIDI clip first.")); box.addStretch(); return
        for name, pitch in (("Kick", 36), ("Snare", 38), ("Closed hat", 42), ("Open hat", 46)):
            row_widget = QWidget(); row = QHBoxLayout(row_widget); row.addWidget(QLabel(name))
            for step in range(16):
                button = QPushButton(str(step+1)); button.setMinimumWidth(25); button.setCheckable(True)
                button.setChecked(any(n.pitch==pitch and abs(n.start-step*.25)<.01 for n in clip.notes))
                button.clicked.connect(lambda checked, pitch=pitch, step=step: self.toggle_step(pitch, step))
                row.addWidget(button)
            box.addWidget(row_widget)
        box.addStretch()

    def toggle_step(self, pitch, step):
        def operation(p):
            clip = self.selected_clip(p)
            existing = next((n for n in clip.notes if n.pitch==pitch and abs(n.start-step*.25)<.01), None)
            if existing:
                clip.notes.remove(existing)
            else:
                clip.notes.append(Note(pitch=pitch, start=step*.25, length=.2))
        self.change("Toggle sequencer step", operation)

    def paint_mixer(self):
        box = self.replace_page_layout(self.mixer)
        for index, track in enumerate(self.document.project.tracks):
            widget = QWidget(); row = QHBoxLayout(widget); row.addWidget(QLabel(track.name))
            gain = QSlider(Qt.Orientation.Horizontal); gain.setRange(0, 150); gain.setValue(round(track.gain*100))
            gain.sliderReleased.connect(lambda index=index, slider=gain: self.change("Mixer gain", lambda p: setattr(p.tracks[index], "gain", slider.value()/100)))
            row.addWidget(gain)
            for field, text in (("mute", "Mute"), ("solo", "Solo")):
                button = QPushButton(text); button.setCheckable(True); button.setChecked(getattr(track, field))
                button.clicked.connect(lambda checked, index=index, field=field: self.change("Mixer "+field, lambda p: setattr(p.tracks[index], field, checked)))
                row.addWidget(button)
            box.addWidget(widget)
        box.addStretch()

    def undo(self):
        self.engine.stop(); self.show_status(self.document.undo()); self.refresh()

    def redo(self):
        self.engine.stop(); self.show_status(self.document.redo()); self.refresh()

    def discard_allowed(self):
        if not self.document.dirty:
            return True
        result = QMessageBox.question(self, "Unsaved changes", "Save your changes first, or discard them to continue.", QMessageBox.StandardButton.Discard | QMessageBox.StandardButton.Cancel, QMessageBox.StandardButton.Cancel)
        return result == QMessageBox.StandardButton.Discard

    def new_project(self):
        if self.discard_allowed():
            self.stop(); self.epoch += 1; self.document = Document(); self.path = None; self.clip_id = None; self.refresh()

    def submit(self, label, function, done):
        epoch = self.epoch
        self.show_status(label)
        future = self.jobs.submit(function)
        def completed(f):
            try:
                result = (epoch, done, f.result(), None)
            except Exception as error:
                result = (epoch, done, None, str(error))
            try:
                self.events.completed.emit(result)
            except RuntimeError:
                pass
        future.add_done_callback(completed)

    def complete_job(self, result):
        epoch, callback, value, error = result
        if epoch != self.epoch:
            return
        if error:
            self.show_status(error)
        else:
            callback(value)

    def open_project(self):
        if not self.discard_allowed():
            return
        name, _ = QFileDialog.getOpenFileName(self, "Open Python project", "", "Python projects (*.lemmingspy)")
        if not name:
            return
        self.stop()
        requested_revision = self.document.revision
        def loaded(project):
            if self.document.revision != requested_revision:
                self.show_status("Open cancelled: the current project changed while the file was loading")
                return
            self.epoch += 1; self.document = Document(project); self.path = Path(name); self.clip_id = None; self.refresh(); self.show_status("Opened "+Path(name).name)
        self.submit("Opening project…", lambda: load_project(Path(name)), loaded)

    def save(self, as_new=False):
        path = self.path
        if as_new or not path:
            name, _ = QFileDialog.getSaveFileName(self, "Save Python project", self.document.project.name+".lemmingspy", "Python projects (*.lemmingspy)")
            if not name:
                return
            path = Path(name)
            if path.suffix.lower() != ".lemmingspy":
                path = Path(str(path)+".lemmingspy")
                if path.exists() and QMessageBox.question(self, "Replace project?", f"Replace {path.name}? A backup will be kept.", QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No, QMessageBox.StandardButton.No) != QMessageBox.StandardButton.Yes:
                    return
        snapshot, revision = deepcopy(self.document.project), self.document.revision
        def saved(_):
            self.path = path
            if self.document.revision == revision:
                self.document.saved_revision = revision
            self.refresh(); self.show_status("Saved "+path.name)
        self.submit("Saving…", lambda: save_project(snapshot, path), saved)

    def import_audio(self):
        name, _ = QFileDialog.getOpenFileName(self, "Import audio", "", "Audio (*.wav *.aiff *.aif *.flac *.ogg)")
        if not name:
            return
        def read_metadata():
            info = sf.info(name)
            return (info.duration, Clip(name=Path(name).stem, file=str(Path(name).absolute())))
        def imported(result):
            duration, clip = result
            clip.length = duration*self.document.project.tempo/60
            def operation(p):
                track = Track(name=clip.name, kind="audio", clips=[clip]); p.tracks.append(track)
            self.change("Import audio", operation); self.track_index = len(self.document.project.tracks)-1; self.clip_id = clip.id; self.refresh()
        self.submit("Reading audio…", read_metadata, imported)

    def export_audio(self):
        name, _ = QFileDialog.getSaveFileName(self, "Export WAV", "Mix.wav", "WAV (*.wav)")
        if not name:
            return
        snapshot, base = deepcopy(self.document.project), self.path.parent if self.path else Path.cwd()
        self.cancel_export.clear()
        self.submit("Rendering WAV…", lambda: Renderer(snapshot, base).export(Path(name), self.cancel_export), lambda _: self.show_status("Exported "+Path(name).name))

    def play(self):
        if self.engine.running:
            self.stop(); return
        if self.cursor_beat >= self.document.project.end_beat:
            self.update_position(0)
        self.play_button.setText("Stop")
        self.show_status("Preparing playback…")
        self.engine.play(self.document.project, self.path.parent if self.path else Path.cwd(), self.cursor_beat)

    def return_to_start(self):
        was_running = self.engine.running
        self.engine.stop()
        self.update_position(0)
        if was_running:
            self.play()

    def stop(self):
        self.engine.stop(); self.play_button.setText("Play"); self.update_position(0); self.show_status("Stopped")

    def choose_audio_device(self):
        def devices():
            import sounddevice as sd
            return [(i, d["name"]) for i, d in enumerate(sd.query_devices()) if d["max_output_channels"] >= 2]
        def choose(entries):
            if not entries:
                self.show_status("No stereo output device found"); return
            menu = QComboBox(); menu.addItems([name for _, name in entries])
            from PySide6.QtWidgets import QDialog, QDialogButtonBox
            dialog = QDialog(self); dialog.setWindowTitle("Audio output"); layout = QVBoxLayout(dialog); layout.addWidget(menu)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel); buttons.accepted.connect(dialog.accept); buttons.rejected.connect(dialog.reject); layout.addWidget(buttons)
            if dialog.exec():
                self.engine.output_device = entries[menu.currentIndex()][0]
                self.show_status("Audio output: "+entries[menu.currentIndex()][1])
        self.submit("Finding audio devices…", devices, choose)

    def update_position(self, beat):
        self.cursor_beat = beat
        seconds = beat*60/self.document.project.tempo
        self.position.setText(f"  {int(beat//4)+1}:{int(beat%4)+1}  ·  {seconds:.2f} s  ")
        if hasattr(self, "playhead"):
            line = self.playhead.line(); line.setP1(QPointF(150+beat*44, line.y1())); line.setP2(QPointF(150+beat*44, line.y2())); self.playhead.setLine(line)

    def show_status(self, message):
        self.statusBar().showMessage(message)
        if message == "Playback finished" or message.startswith("Audio error"):
            self.play_button.setText("Play")

    def closeEvent(self, event):
        if not self.discard_allowed():
            event.ignore(); return
        self.engine.on_position = lambda *_: None; self.engine.on_finished = lambda *_: None
        self.engine.stop(); self.cancel_export.set(); self.jobs.shutdown(wait=False, cancel_futures=True)
        event.accept()


def main():
    import argparse
    import json
    import os
    parser = argparse.ArgumentParser(description="LemmingsStudio Windows Python rewrite")
    parser.add_argument("--self-test-report", type=Path, help="Run isolated bundle checks and write a JSON report")
    args = parser.parse_args()
    if args.self_test_report:
        os.environ["QT_QPA_PLATFORM"] = "offscreen"
    app = QApplication([sys.argv[0]])
    app.setApplicationName("LemmingsStudio Windows Python Rewrite")
    if args.self_test_report:
        try:
            from .validation import validate_bundle
            result = validate_bundle(app)
            code = 0
        except Exception as error:
            import traceback
            result = {"status": "failed", "error": str(error), "traceback": traceback.format_exc()}
            code = 1
        args.self_test_report.parent.mkdir(parents=True, exist_ok=True)
        args.self_test_report.write_text(json.dumps(result, indent=2), encoding="utf-8")
        return code
    window = MainWindow()
    window.show()
    return app.exec()
