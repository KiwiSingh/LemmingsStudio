#include "Session.h"
#include <cmath>
#include <stdexcept>
namespace ls {
static juce::var
object(std::initializer_list<std::pair<juce::Identifier, juce::var>> fields) {
  auto *d = new juce::DynamicObject;
  for (auto &f : fields)
    d->setProperty(f.first, f.second);
  return juce::var(d);
}
static juce::var get(const juce::var &v, const char *lower, const char *upper,
                     juce::var fallback = {}) {
  return v.getProperty(lower, v.getProperty(upper, fallback));
}
static double number(juce::var v, double lo, double hi, const char *field) {
  if (!(v.isDouble() || v.isInt() || v.isInt64()))
    throw std::runtime_error(field);
  double n = (double)v;
  if (!std::isfinite(n) || n < lo || n > hi)
    throw std::runtime_error(field);
  return n;
}
Session Session::demo() {
  Session s;
  Track a;
  a.name = "Audio 1";
  s.tracks.push_back(a);
  Track m;
  m.name = "MIDI 1";
  m.kind = "midi";
  Clip c;
  c.name = "Editable melody";
  for (int i = 0; i < 8; ++i)
    c.notes.push_back({60 + (i % 4) * 2, i * .5, .35, .6f});
  m.clips.push_back(c);
  s.tracks.push_back(m);
  return s;
}
Session Session::decode(const juce::var &root) {
  if (!root.isObject())
    throw std::runtime_error("Project must be a JSON object");
  Session s;
  const bool native = root.hasProperty("nativeSchema");
  if (native && (int)root["nativeSchema"] != 1)
    throw std::runtime_error("Unsupported native project version");
  s.name = get(root, "name", "Name", "Untitled").toString();
  s.tempo = number(get(root, "tempo", "Tempo", 120), 20, 400, "Invalid tempo");
  s.sampleRate = number(get(root, "sampleRate", "SampleRate", 48000), 8000,
                        192000, "Invalid sample rate");
  s.source = native ? root.getProperty("legacySource", {}) : root;
  auto tracks = get(root, "tracks", "Tracks");
  if (!tracks.isArray())
    throw std::runtime_error("Project tracks must be an array");
  for (auto &t : *tracks.getArray()) {
    Track track;
    track.name = get(t, "name", "Name", "Track").toString();
    track.id = get(t, "id", "Id", juce::Uuid().toString()).toString();
    track.kind = get(t, "kind", "Type", "audio").toString().toLowerCase();
    if (track.kind == "1" || track.kind == "2" || track.kind == "instrument")
      track.kind = "midi";
    else if (track.kind == "0")
      track.kind = "audio";
    track.gain =
        (float)number(get(t, "gain", "Volume", t.getProperty("volume", .8)), 0,
                      4, "Invalid track gain");
    track.pan = (float)number(get(t, "pan", "Pan", 0), -1, 1, "Invalid pan");
    track.mute = (bool)get(t, "mute", "Muted", false);
    auto append = [&](const juce::var &clips) {
      if (auto *arr = clips.getArray())
        for (auto &cv : *arr) {
          Clip c;
          c.name = get(cv, "name", "Name", "Clip").toString();
          c.start = number(get(cv, "startBeat", "StartBeat", 0), 0, 1000000,
                           "Invalid clip start");
          c.length = number(get(cv, "lengthBeats", "LengthBeats", 4), .00001,
                            1000000, "Invalid clip length");
          c.file =
              get(cv, "file", "SourcePath", cv.getProperty("sourceURL", {}))
                  .toString();
          auto notes = get(cv, "notes", "Notes");
          if (auto *ns = notes.getArray())
            for (auto &n : *ns) {
              Note note;
              note.pitch = (int)number(get(n, "pitch", "Note", 60), 0, 127,
                                       "Invalid MIDI pitch");
              note.start = number(get(n, "start", "Beat", 0), 0, 1000000,
                                  "Invalid note start");
              note.length = number(get(n, "length", "Length", 1), .00001,
                                   1000000, "Invalid note length");
              note.velocity = (float)number(get(n, "velocity", "Velocity", .8),
                                            0, 127, "Invalid velocity");
              if (n.hasProperty("Velocity") || note.velocity > 1)
                note.velocity /= 127;
              c.notes.push_back(note);
            }
          if (cv.hasProperty("samples"))
            s.warnings.add("Embedded macOS audio retained in legacySource; not "
                           "rendered in native preview.");
          track.clips.push_back(std::move(c));
        }
    };
    append(get(t, "clips", "Clips"));
    if (!native)
      append(t.getProperty("audioClips", {}));
    s.tracks.push_back(std::move(track));
  }
  if (!native)
    s.warnings.add("Legacy import preview: devices, automation, routing, warp "
                   "and embedded audio remain in legacySource but are not "
                   "executed. Original file is unchanged.");
  auto savedWarnings = root.getProperty("warnings", {});
  if (auto *a = savedWarnings.getArray())
    for (auto &w : *a)
      s.warnings.addIfNotAlreadyThere(w.toString());
  return s;
}
juce::var Session::encode() const {
  juce::Array<juce::var> ts;
  for (auto &t : tracks) {
    juce::Array<juce::var> cs;
    for (auto &c : t.clips) {
      juce::Array<juce::var> ns;
      for (auto &n : c.notes)
        ns.add(object({{"pitch", n.pitch},
                       {"start", n.start},
                       {"length", n.length},
                       {"velocity", n.velocity}}));
      cs.add(object({{"name", c.name},
                     {"file", c.file},
                     {"startBeat", c.start},
                     {"lengthBeats", c.length},
                     {"notes", ns}}));
    }
    ts.add(object({{"id", t.id},
                   {"name", t.name},
                   {"kind", t.kind},
                   {"gain", t.gain},
                   {"pan", t.pan},
                   {"mute", t.mute},
                   {"clips", cs}}));
  }
  juce::Array<juce::var> ws;
  for (auto &w : warnings)
    ws.add(w);
  return object({{"nativeSchema", 1},
                 {"name", name},
                 {"tempo", tempo},
                 {"sampleRate", sampleRate},
                 {"tracks", ts},
                 {"legacySource", source},
                 {"warnings", ws}});
}
Session Session::load(const juce::File &f) {
  juce::var v;
  auto r = juce::JSON::parse(f.loadFileAsString(), v);
  if (r.failed())
    throw std::runtime_error(r.getErrorMessage().toStdString());
  auto session = decode(v);
  for (auto &track : session.tracks)
    for (auto &clip : track.clips)
      if (clip.file.isNotEmpty()) {
        if (clip.file.startsWith("file:"))
          clip.file = juce::URL(clip.file).getLocalFile().getFullPathName();
        else if (!juce::File::isAbsolutePath(clip.file))
          clip.file =
              f.getParentDirectory().getChildFile(clip.file).getFullPathName();
      }
  return session;
}
void Session::save(const juce::File &f) const {
  if (f.hasFileExtension("lemmings;lemmingsproject"))
    throw std::runtime_error("Save migrated sessions as .lemmingsnative to "
                             "preserve the legacy original");
  auto data = encode();
  (void)decode(data);
  if (f.getParentDirectory().createDirectory().failed())
    throw std::runtime_error("Cannot create project directory");
  juce::TemporaryFile tmp(f);
  if (!tmp.getFile().replaceWithText(juce::JSON::toString(data)))
    throw std::runtime_error("Cannot write temporary project");
  (void)load(tmp.getFile());
  if (f.existsAsFile() &&
      !f.copyFileTo(f.getSiblingFile(f.getFileName() + ".bak")))
    throw std::runtime_error("Cannot back up existing project");
  if (!tmp.overwriteTargetFileWithTemporary())
    throw std::runtime_error("Cannot replace project");
}
} // namespace ls
