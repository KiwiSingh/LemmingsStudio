#pragma once
#include "Session.h"
#include <atomic>
namespace ls {
class Renderer {
  struct Audio {
    juce::AudioBuffer<float> samples;
    double rate = 48000, start = 0, length = 0;
    float left = 1, right = 1;
  };
  struct Tone {
    juce::int64 start = 0, end = 0;
    double hz = 440;
    float velocity = .5f, left = 1, right = 1;
  };
  std::vector<Audio> audio;
  std::vector<Tone> tones;
  double rate = 48000;
  juce::int64 duration = 0;

public:
  juce::StringArray prepare(const Session &, const juce::File &base = {});
  void process(juce::AudioBuffer<float> &, int offset, int frames,
               juce::int64 position) const noexcept;
  juce::int64 length() const { return duration; }
  double sampleRate() const { return rate; }
  void exportWav(const juce::File &) const;
};
} // namespace ls
