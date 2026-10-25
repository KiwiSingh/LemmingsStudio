#pragma once
#include "Session.h"
#include <optional>
#include <stdexcept>
namespace ls {
// AI providers may propose typed edits; only the session controller can apply
// them. A proposal is bound to the exact base state to prevent edits to a stale
// selection.
class Commands {
  struct Proposal {
    juce::String base;
    Session result;
  };
  struct UndoEntry {
    Session before;
    juce::String after;
  };
  std::optional<Proposal> proposal;
  std::vector<UndoEntry> history;
  static juce::String fingerprint(const Session &s) {
    return juce::JSON::toString(s.encode(), true);
  }

public:
  juce::String previewTranspose(const Session &session,
                                const juce::String &trackID, int semitones) {
    proposal.reset();
    if (semitones < -24 || semitones > 24)
      throw std::runtime_error("Transpose must be within two octaves");
    Session result = session;
    int count = 0;
    bool found = false;
    for (auto &track : result.tracks)
      if (track.id == trackID) {
        found = true;
        for (auto &clip : track.clips)
          for (auto &note : clip.notes) {
            if (note.pitch + semitones < 0 || note.pitch + semitones > 127)
              throw std::runtime_error(
                  "An affected note would exceed the MIDI range");
            note.pitch += semitones;
            ++count;
          }
      }
    if (!found || count == 0)
      throw std::runtime_error("Select a track containing MIDI notes");
    proposal = Proposal{fingerprint(session), std::move(result)};
    return "Transpose " + juce::String(count) +
           " notes on the selected track by " + juce::String(semitones) +
           " semitone(s). Apply to commit; Undo restores the previous state.";
  }
  void apply(Session &session) {
    if (!proposal)
      throw std::runtime_error("Preview an edit first");
    if (fingerprint(session) != proposal->base) {
      proposal.reset();
      throw std::runtime_error("Project changed after preview. Preview again.");
    }
    if (history.size() >= 32)
      history.erase(history.begin());
    history.push_back({session, fingerprint(proposal->result)});
    session = std::move(proposal->result);
    proposal.reset();
  }
  void undo(Session &session) {
    if (history.empty())
      throw std::runtime_error("No command to undo");
    if (fingerprint(session) != history.back().after)
      throw std::runtime_error(
          "Project changed outside command history; undo is unavailable");
    session = std::move(history.back().before);
    history.pop_back();
    proposal.reset();
  }
  void clear() {
    proposal.reset();
    history.clear();
  }
};
} // namespace ls
