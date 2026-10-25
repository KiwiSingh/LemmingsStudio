#pragma once
#include <juce_audio_utils/juce_audio_utils.h>
namespace ls {
struct Note {
  int pitch = 60;
  double start = 0, length = 1;
  float velocity = .8f;
};
struct Clip {
  juce::String name = "Clip", file;
  double start = 0, length = 4;
  std::vector<Note> notes;
};
struct Track {
  juce::String id = juce::Uuid().toString(), name = "Track", kind = "audio";
  float gain = .8f, pan = 0;
  bool mute = false;
  std::vector<Clip> clips;
};
struct Session {
  juce::String name = "Untitled";
  double tempo = 120, sampleRate = 48000;
  std::vector<Track> tracks;
  juce::var source; // Preserve legacy fields verbatim; never claim unsupported
                    // data is playable.
  juce::StringArray warnings;
  static Session demo();
  static Session decode(const juce::var &);
  juce::var encode() const;
  static Session load(const juce::File &);
  void save(const juce::File &) const;
};
} // namespace ls
