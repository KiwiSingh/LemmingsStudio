#pragma once
#include <array>
#include <juce_audio_utils/juce_audio_utils.h>
#include <juce_cryptography/juce_cryptography.h>
#include <stdexcept>
namespace ls {
// Files are decoded at load time. Fixed voices and sample-offset MIDI keep the
// audio path bounded.
class Sampler {
  struct Region {
    int note = 60, low = 0, high = 127, choke = 0;
    juce::AudioBuffer<float> audio;
    double rate = 48000;
  };
  struct Voice {
    int region = -1, note = 0;
    double cursor = 0;
    float gain = 0, release = 1;
    bool releasing = false;
  };
  std::vector<Region> regions;
  std::array<Voice, 64> voices{};
  std::array<unsigned, 128> next{};
  double rate = 48000;
  bool drums = false;
  int pedal = 0;
  float bend = 0;

public:
  explicit Sampler(bool drum) : drums(drum) {}
  void prepare(double sr) {
    rate = sr;
    reset();
  }
  void reset() {
    for (auto &v : voices)
      v = Voice{};
    next.fill(0);
    pedal = 0;
    bend = 0;
  }
  void clear() {
    regions.clear();
    reset();
  }
  int regionCount() const { return (int)regions.size(); }
  void load(const juce::File &manifest) {
    auto root = juce::JSON::parse(manifest);
    if (!root.isObject() || (int)root.getProperty("schema", 0) != 1)
      throw std::runtime_error("Unsupported sample pack manifest");
    if (root.getProperty("redistribution", {}).toString() != "approved")
      throw std::runtime_error(
          "Sample pack is not approved for redistribution");
    for (auto field : {"license", "source", "attribution"})
      if (root.getProperty(field, {}).toString().isEmpty())
        throw std::runtime_error("Missing sample provenance");
    auto items = root.getProperty("regions", {});
    if (!items.isArray() || items.size() == 0 || items.size() > 4096)
      throw std::runtime_error("Invalid region list");
    std::vector<Region> loaded;
    juce::AudioFormatManager formats;
    formats.registerBasicFormats();
    juce::int64 total = 0;
    for (auto &item : *items.getArray()) {
      auto relative = item.getProperty("file", {}).toString();
      auto f = manifest.getParentDirectory().getChildFile(relative);
      if (relative.isEmpty() || juce::File::isAbsolutePath(relative) ||
          !f.isAChildOf(manifest.getParentDirectory()))
        throw std::runtime_error("Sample path must be inside the pack");
      // A file hash is required so a replaced or corrupt pack cannot silently
      // enter a release.
      auto expected = item.getProperty("sha256", {}).toString();
      if (expected.length() != 64 || juce::SHA256(f).toHexString() != expected)
        throw std::runtime_error("Sample checksum mismatch");
      std::unique_ptr<juce::AudioFormatReader> reader(
          formats.createReaderFor(f));
      if (!reader || reader->lengthInSamples < 1 ||
          reader->lengthInSamples > 192000 * 60)
        throw std::runtime_error("Invalid or oversized sample");
      total += reader->lengthInSamples * std::min(2u, reader->numChannels) *
               sizeof(float);
      if (total > 512LL * 1024 * 1024)
        throw std::runtime_error("Pack exceeds 512 MB preload budget");
      Region r;
      r.note = (int)item.getProperty("note", 60);
      r.low = (int)item.getProperty("velocityLow", 0);
      r.high = (int)item.getProperty("velocityHigh", 127);
      r.choke = (int)item.getProperty("chokeGroup", 0);
      if (r.note < 0 || r.note > 127 || r.low < 0 || r.high > 127 ||
          r.low > r.high)
        throw std::runtime_error("Invalid sample mapping");
      r.rate = reader->sampleRate;
      r.audio.setSize((int)std::min(2u, reader->numChannels),
                      (int)reader->lengthInSamples);
      reader->read(&r.audio, 0, r.audio.getNumSamples(), 0, true, true);
      loaded.push_back(std::move(r));
    }
    regions = std::move(loaded);
    reset();
  }
  void event(const juce::MidiMessage &m) {
    if (m.isAllNotesOff() || m.isAllSoundOff()) {
      reset();
      return;
    }
    if (m.isPitchWheel()) {
      bend = (m.getPitchWheelValue() - 8192) / 8192.f * 2;
      return;
    }
    if (m.isController() && m.getControllerNumber() == 4) {
      pedal = m.getControllerValue();
      return;
    }
    if (m.isNoteOff()) {
      if (!drums)
        for (auto &v : voices)
          if (v.note == m.getNoteNumber())
            v.releasing = true;
      return;
    }
    if (!m.isNoteOn())
      return;
    int note = m.getNoteNumber();
    if (drums && note == 46 && pedal > 96)
      note = 42;
    std::array<int, 4096> matches{};
    int count = 0;
    for (int i = 0; i < (int)regions.size(); ++i) {
      auto &r = regions[(size_t)i];
      if (r.note == note && m.getVelocity() >= r.low &&
          m.getVelocity() <= r.high)
        matches[(size_t)count++] = i;
    }
    if (count == 0)
      return;
    int selected = matches[next[(size_t)note]++ % (unsigned)count];
    auto &r = regions[(size_t)selected];
    if (r.choke > 0)
      for (auto &v : voices)
        if (v.region >= 0 && regions[(size_t)v.region].choke == r.choke)
          v.releasing = true;
    auto *voice = &voices[0];
    for (auto &v : voices)
      if (v.region < 0) {
        voice = &v;
        break;
      }
    *voice = {selected, note, 0, m.getFloatVelocity(), 1, false};
  }
  void process(juce::AudioBuffer<float> &out, juce::MidiBuffer &midi,
               float gain, float pan) {
    auto iterator = midi.cbegin();
    for (int i = 0; i < out.getNumSamples(); ++i) {
      while (iterator != midi.cend() && (*iterator).samplePosition <= i) {
        event((*iterator).getMessage());
        ++iterator;
      }
      float left = 0, right = 0;
      for (auto &v : voices) {
        if (v.region < 0)
          continue;
        auto &r = regions[(size_t)v.region];
        int n = (int)v.cursor;
        if (n >= r.audio.getNumSamples()) {
          v.region = -1;
          continue;
        }
        int second = std::min(n + 1, r.audio.getNumSamples() - 1);
        float fract = (float)(v.cursor - n);
        auto read = [&](int ch) {
          auto *ptr = r.audio.getReadPointer(
              std::min(ch, r.audio.getNumChannels() - 1));
          return (ptr[n] + fract * (ptr[second] - ptr[n])) * v.gain * v.release;
        };
        left += read(0);
        right += read(1);
        v.cursor += r.rate / rate * std::pow(2., bend / 12);
        if (v.releasing) {
          v.release *= std::exp(-1.f / (float)(rate * .01));
          if (v.release < .0001f)
            v.region = -1;
        }
      }
      out.addSample(0, i, left * gain * std::sqrt((1 - pan) * .5f));
      if (out.getNumChannels() > 1)
        out.addSample(1, i, right * gain * std::sqrt((1 + pan) * .5f));
    }
  }
};
} // namespace ls
