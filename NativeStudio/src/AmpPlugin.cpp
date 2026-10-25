#include "Amp.h"
#include <juce_audio_utils/juce_audio_utils.h>
class AmpProcessor final : public juce::AudioProcessor {
  juce::AudioProcessorValueTreeState state;
  ls::Amp amp;
  std::atomic<float> *family, *drive, *tone, *output;

public:
  AmpProcessor()
      : AudioProcessor(
            BusesProperties()
                .withInput("Input", juce::AudioChannelSet::stereo(), true)
                .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
        state(*this, nullptr, "LemmingAmp",
              {std::make_unique<juce::AudioParameterChoice>(
                   juce::ParameterID{"family", 1}, "Amp family",
                   juce::StringArray{"Clean", "Edge", "Vintage", "British",
                                     "Modern", "Experimental"},
                   0),
               std::make_unique<juce::AudioParameterFloat>(
                   juce::ParameterID{"drive", 1}, "Drive (dB)", 0.f, 30.f, 0.f),
               std::make_unique<juce::AudioParameterFloat>(
                   juce::ParameterID{"tone", 1}, "Tone", 0.f, 1.f, .5f),
               std::make_unique<juce::AudioParameterFloat>(
                   juce::ParameterID{"output", 1}, "Output", 0.f, 1.f, .5f)}) {
    family = state.getRawParameterValue("family");
    drive = state.getRawParameterValue("drive");
    tone = state.getRawParameterValue("tone");
    output = state.getRawParameterValue("output");
  }
  void prepareToPlay(double r, int) override { amp.prepare(r); }
  void releaseResources() override {}
  void reset() override { amp.reset(); }
  bool isBusesLayoutSupported(const BusesLayout &l) const override {
    return l.getMainInputChannelSet() == l.getMainOutputChannelSet() &&
           (l.getMainOutputChannelSet() == juce::AudioChannelSet::mono() ||
            l.getMainOutputChannelSet() == juce::AudioChannelSet::stereo());
  }
  void processBlock(juce::AudioBuffer<float> &b, juce::MidiBuffer &) override {
    juce::ScopedNoDenormals guard;
    amp.process(b, (int)family->load(), drive->load(), tone->load(),
                output->load());
  }
  juce::AudioProcessorEditor *createEditor() override {
    return new juce::GenericAudioProcessorEditor(*this);
  }
  bool hasEditor() const override { return true; }
  const juce::String getName() const override { return "Lemming Amp"; }
  bool acceptsMidi() const override { return false; }
  bool producesMidi() const override { return false; }
  double getTailLengthSeconds() const override { return 0; }
  int getNumPrograms() override { return 1; }
  int getCurrentProgram() override { return 0; }
  void setCurrentProgram(int) override {}
  const juce::String getProgramName(int) override { return {}; }
  void changeProgramName(int, const juce::String &) override {}
  void getStateInformation(juce::MemoryBlock &b) override {
    auto xml = state.copyState().createXml();
    copyXmlToBinary(*xml, b);
  }
  void setStateInformation(const void *d, int n) override {
    auto xml = getXmlFromBinary(d, n);
    if (xml && xml->hasTagName("LemmingAmp"))
      state.replaceState(juce::ValueTree::fromXml(*xml));
  }
};
juce::AudioProcessor *JUCE_CALLTYPE createPluginFilter() {
  return new AmpProcessor;
}
