#pragma once
#include <juce_dsp/juce_dsp.h>
namespace ls {
// Original circuit-inspired waveshaping prototype; no third-party captures or
// IRs.
class Amp {
  double rate = 48000;
  float low[2]{}, dc[2]{}, previous[2]{};

public:
  void prepare(double sr) {
    rate = sr;
    reset();
  }
  void reset() {
    for (int c = 0; c < 2; ++c)
      low[c] = dc[c] = previous[c] = 0;
  }
  void process(juce::AudioBuffer<float> &b, int family, float drive, float tone,
               float output) noexcept {
    constexpr float gains[]{1.1f, 2.f, 4.f, 7.f, 12.f, 18.f};
    family = juce::jlimit(0, 5, family);
    float gain = gains[family] * std::pow(10.f, drive / 20.f);
    float alpha = 1 - std::exp(-2 * juce::MathConstants<float>::pi *
                               (800 + tone * 6500) / (float)rate);
    for (int c = 0; c < std::min(2, b.getNumChannels()); ++c)
      for (int i = 0; i < b.getNumSamples(); ++i) {
        float x = b.getSample(c, i);
        if (!std::isfinite(x))
          x = 0;
        float y = std::tanh(x * gain + (family == 5 ? .2f : 0.f));
        low[c] += alpha * (y - low[c]);
        float hp = low[c] - previous[c] + .995f * dc[c];
        previous[c] = low[c];
        dc[c] = hp;
        b.setSample(c, i, std::tanh(hp * output));
      }
  }
};
} // namespace ls
