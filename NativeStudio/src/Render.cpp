#include "Render.h"
#include <cmath>
#include <stdexcept>
namespace ls {
juce::StringArray Renderer::prepare(const Session &s, const juce::File &base) {
  audio.clear();
  tones.clear();
  duration = 0;
  rate = s.sampleRate;
  juce::StringArray warnings = s.warnings;
  juce::AudioFormatManager formats;
  formats.registerBasicFormats();
  for (auto &t : s.tracks) {
    if (t.mute)
      continue;
    float left = t.gain * std::sqrt((1 - t.pan) * .5f),
          right = t.gain * std::sqrt((1 + t.pan) * .5f);
    for (auto &c : t.clips) {
      duration =
          std::max(duration, (juce::int64)std::ceil((c.start + c.length) * 60 /
                                                    s.tempo * rate));
      if (c.file.isNotEmpty()) {
        juce::File file = juce::File::isAbsolutePath(c.file)
                              ? juce::File(c.file)
                              : base.getChildFile(c.file);
        if (c.file.startsWith("file:"))
          file = juce::URL(c.file).getLocalFile();
        std::unique_ptr<juce::AudioFormatReader> r(
            formats.createReaderFor(file));
        if (!r) {
          warnings.add("Missing or unreadable audio: " + c.file);
          continue;
        }
        // Preload a bounded source clip, never a whole-song mixed buffer.
        if (r->lengthInSamples > rate * 60 * 10) {
          warnings.add(
              "Audio longer than ten minutes needs streaming support: " +
              c.file);
          continue;
        }
        Audio a;
        a.samples.setSize((int)std::min(2u, r->numChannels),
                          (int)r->lengthInSamples);
        r->read(&a.samples, 0, a.samples.getNumSamples(), 0, true, true);
        a.rate = r->sampleRate;
        a.start = c.start * 60 / s.tempo;
        a.length = c.length * 60 / s.tempo;
        a.left = left;
        a.right = right;
        audio.push_back(std::move(a));
      }
      for (auto &n : c.notes) {
        double start = (c.start + n.start) * 60 / s.tempo,
               end =
                   std::min(c.start + c.length, c.start + n.start + n.length) *
                   60 / s.tempo;
        if (end <= start)
          continue;
        tones.push_back({(juce::int64)std::llround(start * rate),
                         (juce::int64)std::llround(end * rate),
                         440 * std::pow(2., (n.pitch - 69) / 12.), n.velocity,
                         left, right});
      }
    }
  }
  return warnings;
}
void Renderer::process(juce::AudioBuffer<float> &out, int offset, int frames,
                       juce::int64 position) const noexcept {
  for (int i = 0; i < frames; ++i) {
    auto frame = position + i;
    double time = frame / rate;
    float l = 0, r = 0;
    for (auto &a : audio) {
      double p = (time - a.start) * a.rate;
      if (p < 0 || time >= a.start + a.length || p >= a.samples.getNumSamples())
        continue;
      int n = (int)p, next = std::min(n + 1, a.samples.getNumSamples() - 1);
      float fraction = (float)(p - n);
      auto read = [&](int ch) {
        auto *data = a.samples.getReadPointer(
            std::min(ch, a.samples.getNumChannels() - 1));
        return data[n] + fraction * (data[next] - data[n]);
      };
      l += read(0) * a.left;
      r += read(1) * a.right;
    }
    for (auto &n : tones)
      if (frame >= n.start && frame < n.end) {
        double age = (frame - n.start) / rate,
               remaining = (n.end - frame) / rate;
        double env = std::min({1., age / .005, remaining / .02});
        float sample =
            (float)(std::sin(juce::MathConstants<double>::twoPi * n.hz * age) *
                    env * .2 * n.velocity);
        l += sample * n.left;
        r += sample * n.right;
      }
    out.addSample(0, offset + i, l);
    if (out.getNumChannels() > 1)
      out.addSample(1, offset + i, r);
  }
}
void Renderer::exportWav(const juce::File &file) const {
  juce::TemporaryFile tmp(file);
  auto stream = tmp.getFile().createOutputStream();
  if (!stream)
    throw std::runtime_error("Cannot create export");
  juce::WavAudioFormat wav;
  std::unique_ptr<juce::AudioFormatWriter> writer(
      wav.createWriterFor(stream.get(), rate, 2, 24, {}, 0));
  if (!writer)
    throw std::runtime_error("Cannot create WAV writer");
  stream.release();
  juce::AudioBuffer<float> block(2, 512);
  for (juce::int64 p = 0; p < duration; p += 512) {
    block.clear();
    int n = (int)std::min<juce::int64>(512, duration - p);
    process(block, 0, n, p);
    if (!writer->writeFromAudioSampleBuffer(block, 0, n))
      throw std::runtime_error("Export write failed");
  }
  writer.reset();
  if (!tmp.overwriteTargetFileWithTemporary())
    throw std::runtime_error("Cannot finalize export");
}
} // namespace ls
