"""Original branding in Qt Quick, with CPU video presentation for VM safety."""
from pathlib import Path
from PySide6.QtCore import QObject, Property, Signal, Slot, QTimer, QUrl, Qt
from PySide6.QtGui import QImage
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider
from .startup_assets import media_root, choose_video, choose_voice, video_duration


class VideoFrames(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Image)
        self.image = QImage()

    def requestImage(self, _identity, size, _requested):
        size.setWidth(self.image.width()); size.setHeight(self.image.height())
        return self.image.copy()


class Startup(QObject):
    changed = Signal()
    finished = Signal()
    graphicsFailed = Signal(str)

    def __init__(self, app, log, *, check_mode=False, root=None):
        super().__init__()
        self.app, self.log, self.check_mode = app, log, check_mode
        self.root = Path(root) if root else media_root()
        self._stage, self._frames, self._status = 'video', 0, 'loading the chaos engine…'
        self._scale = 1.
        self._finished = False
        self.first_frame = False
        self.phase_history = []
        self.errors = []
        self.voice_decoded_frames = 0
        self.voice_decoder = None
        self.artwork = self.root/'LemmingsSplash.png'
        self._artwork_ok = not QImage(str(self.artwork)).isNull()
        self._artwork_url = QUrl.fromLocalFile(str(self.artwork)).toString() if self._artwork_ok else ''
        self.frames = VideoFrames()
        self.qml = QQmlApplicationEngine()
        self.qml.addImageProvider('magma', self.frames)
        self.qml.rootContext().setContextProperty('startup', self)
        self.qml.warnings.connect(lambda errors: self.log.mark('qml_warning', messages=[e.toString() for e in errors]))
        self.qml.load(QUrl.fromLocalFile(str(Path(__file__).parent/'qml/Startup.qml')))
        if not self.qml.rootObjects():
            raise RuntimeError('The original startup interface could not be loaded')
        self.window = self.qml.rootObjects()[0]
        self.window.frameSwapped.connect(self._presented)
        self.window.sceneGraphError.connect(lambda _code, message: self.graphicsFailed.emit(message))
        self.window.widthChanged.connect(self._center)
        self.window.heightChanged.connect(self._center)
        self.timer = QTimer(self); self.timer.setSingleShot(True)
        self.timer.setTimerType(Qt.TimerType.PreciseTimer)
        self.timer.timeout.connect(self._next)
        self.load_timeout = QTimer(self); self.load_timeout.setSingleShot(True)
        self.load_timeout.timeout.connect(lambda: self._video_error('Video decoder did not become ready'))
        self.player = None
        self.voice = None
        self._media_loading = False

    stage = Property(str, lambda self: self._stage, notify=changed)
    frameNumber = Property(int, lambda self: self._frames, notify=changed)
    displayScale = Property(float, lambda self: self._scale, notify=changed)
    artworkUrl = Property(str, lambda self: self._artwork_url, notify=changed)
    statusText = Property(str, lambda self: self._status, notify=changed)

    def _geometry(self):
        screen = self.window.screen() or self.app.primaryScreen()
        return screen.availableGeometry()

    @Slot()
    def _center(self):
        geometry = self._geometry()
        self.window.setX(geometry.x()+(geometry.width()-self.window.width())//2)
        self.window.setY(geometry.y()+(geometry.height()-self.window.height())//2)

    def _resize(self):
        geometry = self._geometry()
        width, height = (360, 640) if self._stage == 'video' else (460, 548)
        self._scale = max(.1, min(1., (geometry.width()-40)/width, (geometry.height()-60)/height))
        self.changed.emit()
        self._center()

    def _presented(self):
        if not self.first_frame:
            self.first_frame = True
            self.log.mark('first_startup_frame')
            QTimer.singleShot(0, self._load_media)

    def start(self):
        self._resize()
        self.window.show()
        self.log.mark('branding_window_shown')
        self.phase_history.append('video')

    @Slot()
    def _load_media(self):
        try:
            self._initialize_media()
        except Exception as error:
            self.log.mark('multimedia_initialization_error', error=str(error))
            self._video_error(str(error))

    def _initialize_media(self):
        if self._media_loading or self._finished:
            return
        self._media_loading = True
        self.log.mark('multimedia_initialization_started')
        from PySide6.QtMultimedia import QMediaPlayer, QVideoSink, QAudioOutput, QAudioDecoder
        self.player = QMediaPlayer(self)
        self.sink = QVideoSink(self)
        self.player.setVideoSink(self.sink)
        self.sink.videoFrameChanged.connect(self._video_frame)
        self.player.mediaStatusChanged.connect(self._media_status)
        self.player.errorOccurred.connect(lambda _code, message: self._video_error(message))
        if not self.check_mode:
            self.voice = QMediaPlayer(self)
            self.voice_output = QAudioOutput(self)
            self.voice_output.setVolume(.9)
            self.voice.setAudioOutput(self.voice_output)
            self.voice.errorOccurred.connect(lambda _code, message: self.log.mark('opening_sound_error', error=message))
        self.log.mark('multimedia_initialization_finished')
        sound = choose_voice(self.root)
        if sound and not self.check_mode:
            self.voice.setSource(QUrl.fromLocalFile(str(sound)))
            self.voice.play()
            self.log.mark('opening_sound_requested', asset=sound.name)
        elif sound and self.check_mode:
            self.voice_decoder = QAudioDecoder(self)
            self.voice_decoder.bufferReady.connect(self._voice_buffer)
            self.voice_decoder.error.connect(lambda *_: self._voice_decode_error())
            self.voice_decoder.setSource(QUrl.fromLocalFile(str(sound)))
            self.voice_decoder.start()
        elif not sound:
            self.log.mark('opening_sound_missing')
            self.errors.append('Original opening WAV is missing')
        if not self._artwork_ok:
            self.errors.append('Original splash artwork is missing or invalid')
            self.log.mark('splash_artwork_missing')
        screen = self.window.screen() or self.app.primaryScreen()
        video = choose_video(self.root, screen.refreshRate() or 60.)
        if video:
            self.log.mark('video_selected', asset=video.name)
            self.load_timeout.start(5000)
            self.player.setSource(QUrl.fromLocalFile(str(video)))
        else:
            self._video_error('Original MagmaVance video is missing')

    def _voice_buffer(self):
        buffer = self.voice_decoder.read()
        if buffer.isValid():
            first = self.voice_decoded_frames == 0
            self.voice_decoded_frames += buffer.frameCount()
            if first:
                self.log.mark('opening_wav_decoded')

    def _voice_decode_error(self):
        message = self.voice_decoder.errorString()
        self.errors.append(message)
        self.log.mark('opening_wav_decode_error', error=message)

    def _media_status(self, status):
        if self._stage != 'video' or self._finished:
            return
        if status == self.player.MediaStatus.LoadedMedia and not self.timer.isActive():
            self.load_timeout.stop()
            duration = video_duration(self.player.duration())
            self.log.mark('video_playback_started', duration_ms=duration)
            self.player.play()
            self.timer.start(duration)
        elif status == self.player.MediaStatus.InvalidMedia:
            self._video_error('Original MagmaVance video could not be decoded')

    def _video_frame(self, frame):
        if self._stage != 'video' or not frame.isValid():
            return
        image = frame.toImage()
        if image.isNull():
            return
        # QImage presentation works with both accelerated and software Qt Quick.
        self.frames.image = image.scaled(720, 1280, Qt.AspectRatioMode.KeepAspectRatio,
                                         Qt.TransformationMode.FastTransformation)
        self._frames += 1
        if self._frames == 1:
            self.log.mark('first_video_frame')
            if self.check_mode:
                QTimer.singleShot(min(1500, max(0, self.timer.remainingTime()//2)), lambda: self._capture('video'))
        self.changed.emit()

    def _video_error(self, message):
        if self._stage != 'video' or self._finished:
            return
        self.errors.append(message)
        self.log.mark('video_error', error=message)
        self._next()

    @Slot()
    def _next(self):
        if self._finished:
            return
        self.timer.stop(); self.load_timeout.stop()
        if self._stage == 'video':
            if not self._frames and not self.errors:
                self.errors.append('Video produced no visible decoded frames')
            self._stage = 'splash'
            if self.player:
                self.player.stop()
            self.phase_history.append('splash')
            self.log.mark('lemmings_splash_started')
            self._resize()
            self.timer.start(1550)
            if self.check_mode:
                QTimer.singleShot(100, lambda: self._capture('splash'))
        else:
            self._finished = True
            self.phase_history.append('finished')
            self.log.mark('branding_finished', decoded_frames=self._frames)
            self.finished.emit()

    def _capture(self, phase):
        image = self.window.grabWindow()
        path = self.log.path.with_name(self.log.path.stem+'-'+phase+'.png')
        if not image.isNull() and image.save(str(path)):
            self.log.mark('presentation_capture', phase_name=phase, file=path.name)
        else:
            self.errors.append(f'{phase} presentation capture failed')

    def waiting_for_workspace(self):
        self._status = 'Preparing workspace…'
        self.changed.emit()

    def result(self):
        passed = self._artwork_ok and self.first_frame and self._frames > 0 and not self.errors and self._finished
        if self.check_mode and not self.voice_decoded_frames:
            passed = False
        return {'status': 'passed' if passed else 'failed', 'checks': {
            'original_artwork_loaded': self._artwork_ok, 'qt_quick_presented': self.first_frame,
            'original_video_frames_decoded': self._frames, 'original_wav_frames_decoded': self.voice_decoded_frames, 'sequence': self.phase_history},
            'errors': self.errors, 'audio_device_tested': False}

    def hide(self):
        self.window.hide()

    def shutdown(self):
        self.timer.stop(); self.load_timeout.stop()
        if self.player:
            self.player.stop()
        if self.voice:
            self.voice.stop()
        if self.voice_decoder:
            self.voice_decoder.stop()
        self.window.hide()
