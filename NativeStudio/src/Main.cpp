#include "Amp.h"
#include "Commands.h"
#include "Render.h"
#include <atomic>
class Studio final : public juce::AudioAppComponent, private juce::Timer {
  ls::Commands commands;
  juce::ComboBox selection;
  juce::TextButton previewEdit{"Preview transpose +1"}, applyEdit{"Apply edit"},
      undoEdit{"Undo edit"};
  ls::Session session = ls::Session::demo();
  ls::Renderer renderer;
  ls::Amp amp;
  std::atomic<bool> playing{false};
  std::atomic<juce::int64> position{0};
  juce::TextButton play{"Play"}, stop{"Stop"}, open{"Open"}, save{"Save as"},
      importAudio{"Import WAV"}, bounce{"Export WAV"},
      settings{"Audio settings"}, vox{"Open VoxGarden VST3"},
      record{"Record dry input"};
  juce::ToggleButton ampEnabled{"Amp preview"}, monitor{"Monitor dry input"};
  juce::Slider tempo;
  juce::Label title, status;
  juce::TextEditor tracks;
  juce::File projectFile;
  std::unique_ptr<juce::FileChooser> chooser;
  juce::AudioFormatManager formats;
  juce::AudioPluginFormatManager pluginFormats;
  std::unique_ptr<juce::AudioPluginInstance> plugin;
  std::unique_ptr<juce::DocumentWindow> pluginWindow;
  juce::AudioBuffer<float> scratch;
  std::atomic<double> currentRate{48000};
  double recordingRate = 48000;
  std::atomic<bool> recordingNeedsFinalize{false};
  int maxBlock = 512;
  std::atomic<bool> useAmp{false}, monitorInput{false};
  juce::TimeSliceThread diskThread{"Recording disk writer"};
  std::unique_ptr<juce::AudioFormatWriter::ThreadedWriter> writer;
  std::atomic<juce::AudioFormatWriter::ThreadedWriter *> activeWriter{nullptr};
  juce::File recordingFile;
  std::atomic<bool> recordOverflow{false};
  juce::int64 recordedFrames = 0;
  std::atomic<juce::int64> recordingLength{0};
  std::unique_ptr<juce::ScopedLock> editLock;
  void halt() {
    playing = false;
    editLock = std::make_unique<juce::ScopedLock>(
        deviceManager.getAudioCallbackLock());
  }
  void resume() { editLock.reset(); }
  void refresh() {
    renderer.prepare(session, projectFile == juce::File{}
                                  ? juce::File::getCurrentWorkingDirectory()
                                  : projectFile.getParentDirectory());
    juce::String text;
    for (auto &t : session.tracks) {
      text += t.name + "  [" + t.kind + "]\n";
      for (auto &c : t.clips)
        text += "   " + c.name + "  beat " + juce::String(c.start) +
                "  length " + juce::String(c.length) + "\n";
    }
    tracks.setText(text);
    auto old = selection.getSelectedId();
    selection.clear();
    for (size_t i = 0; i < session.tracks.size(); ++i)
      selection.addItem(session.tracks[i].name, (int)i + 1);
    selection.setSelectedId(old > 0 && old <= (int)session.tracks.size() ? old
                                                                         : 1);
    title.setText("LemmingsStudio · Native preview · " + session.name,
                  juce::dontSendNotification);
  }
  void report(const juce::String &text) {
    status.setText(text, juce::dontSendNotification);
  }
  void choose(const juce::String &label, const juce::String &filter, int flags,
              std::function<void(juce::File)> action) {
    chooser = std::make_unique<juce::FileChooser>(label, juce::File{}, filter);
    chooser->launchAsync(flags,
                         [safe = juce::Component::SafePointer<Studio>(this),
                          action](const juce::FileChooser &c) {
                           if (safe && c.getResult() != juce::File{}) {
                             try {
                               action(c.getResult());
                             } catch (const std::exception &e) {
                               safe->resume();
                               safe->report(e.what());
                             }
                           }
                         });
  }
  void stopRecording() {
    activeWriter = nullptr;
    halt();
    writer.reset();
    resume();
    if (recordingFile.existsAsFile() && recordingLength > 0) {
      ls::Track t;
      t.name = "Recorded audio";
      ls::Clip c;
      c.name = recordingFile.getFileName();
      c.file = recordingFile.getFullPathName();
      c.length =
          (double)recordingLength.load() / recordingRate * session.tempo / 60;
      t.clips.push_back(c);
      halt();
      session.tracks.push_back(t);
      refresh();
      resume();
    }
    recordingFile = juce::File{};
    record.setButtonText("Record dry input");
    report(
        recordOverflow
            ? "Recording stopped: disk writer overflow; check take before use."
            : "Dry take retained on disk and added to the session.");
  }
  void toggleRecording() {
    if (writer) {
      stopRecording();
      return;
    }
    choose("Save dry recording", "*.wav",
           juce::FileBrowserComponent::saveMode |
               juce::FileBrowserComponent::warnAboutOverwriting,
           [this](juce::File f) {
             f = f.withFileExtension("wav");
             if (f.existsAsFile())
               throw std::runtime_error("Choose a new recording filename; "
                                        "existing takes are never overwritten");
             auto stream = f.createOutputStream();
             if (!stream)
               throw std::runtime_error("Cannot create take");
             juce::WavAudioFormat wav;
             auto *w =
                 wav.createWriterFor(stream.get(), currentRate, 1, 24, {}, 0);
             if (!w)
               throw std::runtime_error("Cannot create recording writer");
             stream.release();
             halt();
             writer = std::make_unique<juce::AudioFormatWriter::ThreadedWriter>(
                 w, diskThread, 32768);
             recordingFile = f;
             recordingRate = currentRate.load();
             recordOverflow = false;
             recordingLength = 0;
             activeWriter = writer.get();
             resume();
             record.setButtonText("Stop recording");
             report("Recording dry channel 1. Playback is stopped; monitoring "
                    "is optional.");
           });
  }
  void loadPlugin(juce::File file) {
    if (activeWriter.load())
      throw std::runtime_error("Stop recording before changing plugins");
    halt();
    pluginWindow.reset();
    plugin.reset();
    juce::OwnedArray<juce::PluginDescription> found;
    pluginFormats.getFormat(0)->findAllTypesForFile(found,
                                                    file.getFullPathName());
    if (found.isEmpty()) {
      resume();
      throw std::runtime_error("No VST3 processor found");
    }
    juce::String error;
    plugin = pluginFormats.createPluginInstance(*found[0], currentRate,
                                                maxBlock, error);
    if (!plugin) {
      resume();
      throw std::runtime_error(error.toStdString());
    }
    plugin->setPlayConfigDetails(2, 2, currentRate, maxBlock);
    plugin->prepareToPlay(currentRate, maxBlock);
    if (auto *editor = plugin->createEditorIfNeeded()) {
      pluginWindow = std::make_unique<juce::DocumentWindow>(
          "VoxGarden", juce::Colours::darkgrey,
          juce::DocumentWindow::minimiseButton);
      pluginWindow->setUsingNativeTitleBar(true);
      pluginWindow->setContentOwned(editor, true);
      pluginWindow->centreWithSize(editor->getWidth(), editor->getHeight());
      pluginWindow->setVisible(true);
    }
    resume();
    report("Plugin loaded. Preview host is in-process; do not use untrusted "
           "plugins.");
  }

public:
  Studio() {
    formats.registerBasicFormats();
    pluginFormats.addFormat(new juce::VST3PluginFormat);
    diskThread.startThread();
    for (auto *c : std::initializer_list<juce::Component *>{
             &play, &stop, &open, &save, &importAudio, &bounce, &settings, &vox,
             &record, &ampEnabled, &monitor, &tempo, &title, &status, &tracks,
             &selection, &previewEdit, &applyEdit, &undoEdit})
      addAndMakeVisible(c);
    tracks.setMultiLine(true);
    tracks.setReadOnly(true);
    tempo.setRange(20, 400, .1);
    tempo.setValue(session.tempo);
    tempo.setTextBoxStyle(juce::Slider::TextBoxLeft, false, 65, 24);
    previewEdit.onClick = [this] {
      try {
        int index = selection.getSelectedId() - 1;
        if (index < 0)
          throw std::runtime_error("Select a track");
        report(commands.previewTranspose(session,
                                         session.tracks[(size_t)index].id, 1));
      } catch (const std::exception &e) {
        report(e.what());
      }
    };
    applyEdit.onClick = [this] {
      try {
        if (activeWriter.load())
          throw std::runtime_error("Stop recording before editing");
        halt();
        commands.apply(session);
        refresh();
        resume();
        report("Applied previewed edit");
      } catch (const std::exception &e) {
        resume();
        report(e.what());
      }
    };
    undoEdit.onClick = [this] {
      try {
        if (activeWriter.load())
          throw std::runtime_error("Stop recording before editing");
        halt();
        commands.undo(session);
        refresh();
        resume();
        report("Edit undone");
      } catch (const std::exception &e) {
        resume();
        report(e.what());
      }
    };
    play.onClick = [this] {
      if (activeWriter.load()) {
        report("Stop dry recording before playback");
        return;
      }
      position = 0;
      playing = true;
    };
    stop.onClick = [this] {
      playing = false;
      position = 0;
      if (activeWriter.load())
        stopRecording();
    };
    tempo.onValueChange = [this] {
      if (activeWriter.load())
        return;
      halt();
      session.tempo = tempo.getValue();
      refresh();
      resume();
    };
    ampEnabled.onClick = [this] { useAmp = ampEnabled.getToggleState(); };
    monitor.onClick = [this] { monitorInput = monitor.getToggleState(); };
    record.onClick = [this] { toggleRecording(); };
    open.onClick = [this] {
      if (activeWriter.load())
        return;
      choose("Open session",
             "*.lemmingsnative;*.lemmings;*.lemmingsproject;*.json",
             juce::FileBrowserComponent::openMode |
                 juce::FileBrowserComponent::canSelectFiles,
             [this](juce::File f) {
               auto next = ls::Session::load(f);
               halt();
               session = std::move(next);
               commands.clear();
               session.sampleRate = currentRate;
               projectFile = f;
               tempo.setValue(session.tempo, juce::dontSendNotification);
               refresh();
               resume();
               report(session.warnings.joinIntoString(" | "));
             });
    };
    save.onClick = [this] {
      choose("Save native session", "*.lemmingsnative",
             juce::FileBrowserComponent::saveMode |
                 juce::FileBrowserComponent::warnAboutOverwriting,
             [this](juce::File f) {
               session.save(f.withFileExtension("lemmingsnative"));
               report("Saved native session. Legacy originals preserved.");
             });
    };
    importAudio.onClick = [this] {
      if (activeWriter.load())
        return;
      choose("Import audio", "*.wav;*.aif;*.flac",
             juce::FileBrowserComponent::openMode |
                 juce::FileBrowserComponent::canSelectFiles,
             [this](juce::File f) {
               std::unique_ptr<juce::AudioFormatReader> r(
                   formats.createReaderFor(f));
               if (!r)
                 throw std::runtime_error("Unsupported audio file");
               ls::Track t;
               t.name = f.getFileNameWithoutExtension();
               ls::Clip c;
               c.name = f.getFileName();
               c.file = f.getFullPathName();
               c.length = (double)r->lengthInSamples / r->sampleRate *
                          session.tempo / 60;
               t.clips.push_back(c);
               halt();
               session.tracks.push_back(t);
               refresh();
               resume();
               report("Imported audio at beat zero.");
             });
    };
    bounce.onClick = [this] {
      choose("Export dry session (preview effects excluded)", "*.wav",
             juce::FileBrowserComponent::saveMode |
                 juce::FileBrowserComponent::warnAboutOverwriting,
             [this](juce::File f) {
               renderer.exportWav(f.withFileExtension("wav"));
               report("Exported dry session. Amp and VoxGarden preview effects "
                      "are not printed in this foundation build.");
             });
    };
    settings.onClick = [this] {
      juce::DialogWindow::LaunchOptions o;
      o.content.setOwned(new juce::AudioDeviceSelectorComponent(
          deviceManager, 0, 2, 2, 2, true, true, true, false));
      o.content->setSize(600, 450);
      o.dialogTitle = "Audio and MIDI devices";
      o.useNativeTitleBar = true;
      o.launchAsync();
    };
    vox.onClick = [this] {
      choose("Select installed VoxGarden VST3", "*.vst3",
             juce::FileBrowserComponent::openMode |
                 juce::FileBrowserComponent::canSelectFiles |
                 juce::FileBrowserComponent::canSelectDirectories,
             [this](juce::File f) { loadPlugin(f); });
    };
    setSize(1080, 650);
    setAudioChannels(1, 2);
    refresh();
    report("Foundation preview. MIDI uses a reference sine voice; no "
           "guitar/drum samples bundled.");
    startTimerHz(10);
  }
  ~Studio() override {
    activeWriter = nullptr;
    shutdownAudio();
    writer.reset();
    diskThread.stopThread(5000);
    pluginWindow.reset();
    if (plugin)
      plugin->releaseResources();
  }
  void prepareToPlay(int n, double r) override {
    currentRate = r;
    maxBlock = std::max(n, 8192);
    scratch.setSize(2, maxBlock);
    session.sampleRate = r;
    renderer.prepare(session);
    amp.prepare(r);
    if (plugin)
      plugin->prepareToPlay(r, maxBlock);
  }
  void releaseResources() override {
    if (activeWriter.exchange(nullptr) != nullptr)
      recordingNeedsFinalize = true;
  }
  void getNextAudioBlock(const juce::AudioSourceChannelInfo &info) override {
    juce::ScopedNoDenormals guard;
    auto *out = info.buffer;
    auto *w = activeWriter.load();
    if (w && out->getNumChannels() > 0) {
      const float *input[]{out->getReadPointer(0, info.startSample)};
      if (!w->write(input, info.numSamples))
        recordOverflow = true;
      recordingLength += info.numSamples;
    }
    if (monitorInput && out->getNumChannels() > 0) {
      scratch.clear();
      for (int c = 0; c < 2; ++c)
        scratch.copyFrom(c, 0, *out, 0, info.startSample,
                         std::min(maxBlock, info.numSamples));
    }
    info.clearActiveBufferRegion();
    if (playing) {
      renderer.process(*out, info.startSample, info.numSamples, position);
      position += info.numSamples;
      if (position >= renderer.length())
        playing = false;
    }
    if (monitorInput)
      for (int c = 0; c < std::min(2, out->getNumChannels()); ++c)
        out->addFrom(c, info.startSample, scratch, c, 0,
                     std::min(maxBlock, info.numSamples));
    // Process a bounded preallocated block so callbacks never allocate or touch
    // files.
    for (int offset = 0; offset < info.numSamples; offset += maxBlock) {
      int count = std::min(maxBlock, info.numSamples - offset);
      float *ptrs[]{out->getWritePointer(0, info.startSample + offset),
                    out->getWritePointer(std::min(1, out->getNumChannels() - 1),
                                         info.startSample + offset)};
      juce::AudioBuffer<float> block(ptrs, 2, count);
      if (useAmp)
        amp.process(block, 2, 6, .5f, .5f);
      if (plugin) {
        juce::MidiBuffer midi;
        plugin->processBlock(block, midi);
      }
    }
  }
  void timerCallback() override {
    if (recordingNeedsFinalize.exchange(false))
      stopRecording();
    repaint();
  }
  void paint(juce::Graphics &g) override {
    g.fillAll(juce::Colour(0xff141d23));
    g.setColour(juce::Colour(0xff81dfb1));
    g.drawText("Position " + juce::String(position.load() / currentRate, 2) +
                   " s",
               20, 605, 600, 25, juce::Justification::left);
  }
  void resized() override {
    auto r = getLocalBounds().reduced(20);
    title.setBounds(r.removeFromTop(34));
    auto row = r.removeFromTop(35);
    for (auto *b : {&play, &stop, &record, &open, &save, &importAudio, &bounce})
      b->setBounds(row.removeFromLeft(140).reduced(2));
    auto row2 = r.removeFromTop(40);
    settings.setBounds(row2.removeFromLeft(150));
    vox.setBounds(row2.removeFromLeft(210));
    tempo.setBounds(row2.removeFromLeft(210));
    ampEnabled.setBounds(row2.removeFromLeft(150));
    monitor.setBounds(row2.removeFromLeft(170));
    auto editRow = r.removeFromTop(40);
    selection.setBounds(editRow.removeFromLeft(220));
    previewEdit.setBounds(editRow.removeFromLeft(200));
    applyEdit.setBounds(editRow.removeFromLeft(130));
    undoEdit.setBounds(editRow.removeFromLeft(130));
    status.setBounds(r.removeFromBottom(70));
    tracks.setBounds(r.removeFromTop(350));
  }
};
class App final : public juce::JUCEApplication {
  struct Window : juce::DocumentWindow {
    Window()
        : DocumentWindow("LemmingsStudio Native Preview", juce::Colours::black,
                         allButtons) {
      setUsingNativeTitleBar(true);
      setContentOwned(new Studio, true);
      centreWithSize(1080, 650);
      setResizable(true, true);
      setVisible(true);
    }
    void closeButtonPressed() override {
      juce::JUCEApplication::getInstance()->systemRequestedQuit();
    }
  };
  std::unique_ptr<Window> window;

public:
  const juce::String getApplicationName() override {
    return "LemmingsStudio Native Preview";
  }
  const juce::String getApplicationVersion() override { return "0.1.0"; }
  void initialise(const juce::String &args) override {
    // Scanner runs in a disposable process, separate from the editing session.
    auto tokens = juce::StringArray::fromTokens(args, true);
    if (tokens.size() == 3 && tokens[0] == "--scan-vst3") {
      juce::VST3PluginFormat format;
      juce::OwnedArray<juce::PluginDescription> descriptions;
      format.findAllTypesForFile(descriptions, tokens[1].unquoted());
      juce::XmlElement root("PLUGINS");
      for (auto *d : descriptions)
        root.addChildElement(d->createXml().release());
      bool ok = root.writeTo(juce::File(tokens[2].unquoted()));
      setApplicationReturnValue(ok && !descriptions.isEmpty() ? 0 : 1);
      quit();
      return;
    }
    window = std::make_unique<Window>();
  }
  void shutdown() override { window.reset(); }
};
START_JUCE_APPLICATION(App)
