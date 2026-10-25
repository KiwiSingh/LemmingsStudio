#include "Sampler.h"
#ifndef LEMMINGS_DRUMS
#define LEMMINGS_DRUMS 0
#endif
class SampleProcessor;
class SampleEditor final : public juce::AudioProcessorEditor {
  SampleProcessor &processor;
  juce::TextButton load{"Load approved sample pack"};
  juce::Label status;
  std::unique_ptr<juce::FileChooser> chooser;
  std::unique_ptr<juce::GenericAudioProcessorEditor> controls;

public:
  explicit SampleEditor(SampleProcessor &);
  void resized() override;
};
class SampleProcessor final : public juce::AudioProcessor {
  ls::Sampler sampler{LEMMINGS_DRUMS != 0};
  juce::AudioProcessorValueTreeState state;
  std::atomic<float> *gain;
  std::atomic<float> *pan;
  juce::String path, packStatus = "No factory samples bundled. Load a cleared "
                                  "pack to play this preview.";

public:
  SampleProcessor()
      : AudioProcessor(BusesProperties().withOutput(
            "Output", juce::AudioChannelSet::stereo(), true)),
        state(*this, nullptr, "SampleDevice",
              {std::make_unique<juce::AudioParameterFloat>(
                   juce::ParameterID{"gain", 1}, "Gain", 0.f, 2.f, .8f),
               std::make_unique<juce::AudioParameterFloat>(
                   juce::ParameterID{"pan", 1}, "Pan", -1.f, 1.f, 0.f)}) {
    gain = state.getRawParameterValue("gain");
    pan = state.getRawParameterValue("pan");
  }
  juce::String loadPack(juce::File file) {
    suspendProcessing(true);
    const juce::ScopedLock lock(getCallbackLock());
    try {
      sampler.load(file);
      path = file.getFullPathName();
      suspendProcessing(false);
      packStatus =
          juce::String(sampler.regionCount()) + " sample regions loaded";
      return packStatus;
    } catch (const std::exception &e) {
      suspendProcessing(false);
      packStatus = e.what();
      return packStatus;
    }
  }
  juce::String status() const { return packStatus; }
  void prepareToPlay(double r, int) override { sampler.prepare(r); }
  void releaseResources() override {}
  void reset() override { sampler.reset(); }
  bool isBusesLayoutSupported(const BusesLayout &l) const override {
    return l.getMainOutputChannelSet() == juce::AudioChannelSet::stereo();
  }
  void processBlock(juce::AudioBuffer<float> &b, juce::MidiBuffer &m) override {
    juce::ScopedNoDenormals guard;
    b.clear();
    sampler.process(b, m, gain->load(), pan->load());
  }
  juce::AudioProcessorEditor *createEditor() override {
    return new SampleEditor(*this);
  }
  bool hasEditor() const override { return true; }
  const juce::String getName() const override {
    return LEMMINGS_DRUMS ? "Lemming Rock Drums Preview"
                          : "Lemming Guitar Preview";
  }
  bool acceptsMidi() const override { return true; }
  bool producesMidi() const override { return false; }
  double getTailLengthSeconds() const override { return 5; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &block) override {
    auto tree = state.copyState();
    tree.setProperty("pack", path, nullptr);
    auto xml = tree.createXml();
    copyXmlToBinary(*xml, block);
  }
  void setStateInformation(const void *data, int size) override {
    auto xml = getXmlFromBinary(data, size);
    if (xml && xml->hasTagName("SampleDevice")) {
      auto tree = juce::ValueTree::fromXml(*xml);
      state.replaceState(tree);
      auto pack = tree.getProperty("pack").toString();
      sampler.clear();
      path.clear();
      if (pack.isNotEmpty())
        loadPack(juce::File(pack));
    }
  }
};
SampleEditor::SampleEditor(SampleProcessor &p)
    : AudioProcessorEditor(p), processor(p) {
  addAndMakeVisible(load);
  addAndMakeVisible(status);
  status.setText(p.status(), juce::dontSendNotification);
  controls = std::make_unique<juce::GenericAudioProcessorEditor>(p);
  addAndMakeVisible(*controls);
  load.onClick = [this] {
    chooser = std::make_unique<juce::FileChooser>("Load pack manifest",
                                                  juce::File{}, "*.json");
    chooser->launchAsync(
        juce::FileBrowserComponent::openMode |
            juce::FileBrowserComponent::canSelectFiles,
        [safe = juce::Component::SafePointer<SampleEditor>(this)](
            const juce::FileChooser &c) {
          if (safe && c.getResult().existsAsFile())
            safe->status.setText(safe->processor.loadPack(c.getResult()),
                                 juce::dontSendNotification);
        });
  };
  setSize(640, 260);
}
void SampleEditor::resized() {
  auto r = getLocalBounds().reduced(10);
  load.setBounds(r.removeFromTop(30));
  status.setBounds(r.removeFromTop(50));
  controls->setBounds(r);
}
juce::AudioProcessor *JUCE_CALLTYPE createPluginFilter() {
  return new SampleProcessor;
}
