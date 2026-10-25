#include "Amp.h"
#include "Commands.h"
#include "Render.h"
#include "Sampler.h"
#include <iostream>
#include <stdexcept>
static void check(bool pass, const char *message) {
  if (!pass)
    throw std::runtime_error(message);
}
int main(int argc, char **argv) {
  juce::ScopedJuceInitialiser_GUI gui;
  try {
    auto s = ls::Session::demo();
    auto copy = ls::Session::decode(s.encode());
    check(copy.tracks.size() == 2, "track roundtrip");
    check(copy.tracks[1].clips[0].notes.size() == 8, "MIDI roundtrip");
    auto invalid = s.encode();
    invalid.getDynamicObject()->setProperty("tempo", -1);
    bool rejected = false;
    try {
      ls::Session::decode(invalid);
    } catch (...) {
      rejected = true;
    }
    check(rejected, "reject invalid tempo");
    auto legacy = juce::JSON::parse(
        R"({"Name":"Legacy","Tempo":128,"Tracks":[{"Name":"MIDI","Type":2,"Clips":[{"StartBeat":2,"LengthBeats":4,"Notes":[{"Beat":1,"Length":0.5,"Note":67,"Velocity":100}]}]}],"Unrecognized":{"keep":true}})");
    auto imported = ls::Session::decode(legacy);
    check(imported.tracks[0].clips[0].notes[0].pitch == 67,
          "Windows MIDI pitch");
    check(imported.tracks[0].clips[0].notes[0].start == 1,
          "Windows MIDI timing");
    check(imported.encode()["legacySource"]["Unrecognized"]["keep"],
          "preserve unknown legacy data");
    check(!imported.warnings.isEmpty(), "report partial import");
    ls::Commands commands;
    auto original = s.tracks[1].clips[0].notes[0].pitch;
    commands.previewTranspose(s, s.tracks[1].id, 2);
    check(s.tracks[1].clips[0].notes[0].pitch == original,
          "preview does not mutate");
    commands.apply(s);
    check(s.tracks[1].clips[0].notes[0].pitch == original + 2,
          "apply scoped edit");
    commands.undo(s);
    check(s.tracks[1].clips[0].notes[0].pitch == original,
          "undo restores source");
    commands.previewTranspose(s, s.tracks[1].id, 1);
    s.tempo = 121;
    bool stale = false;
    try {
      commands.apply(s);
    } catch (...) {
      stale = true;
    }
    check(stale, "reject stale proposal");
    s.tempo = 120;
    auto dir = juce::File::getSpecialLocation(juce::File::tempDirectory)
                   .getChildFile("lemmings-check-" + juce::Uuid().toString());
    check(dir.createDirectory().wasOk(), "test folder");
    auto file = dir.getChildFile("test.lemmingsnative");
    s.save(file);
    check(ls::Session::load(file).tracks.size() == 2, "atomic save");
    s.name = "Updated";
    s.save(file);
    check(file.getSiblingFile(file.getFileName() + ".bak").existsAsFile(),
          "backup on save");
    ls::Renderer render;
    render.prepare(s);
    juce::AudioBuffer<float> full(2, 1024), blocks(2, 1024);
    full.clear();
    blocks.clear();
    render.process(full, 0, 1024, 0);
    for (int i = 0; i < 1024; i += 128)
      render.process(blocks, i, 128, i);
    check(full.getMagnitude(0, 1024) > .001f, "MIDI audible");
    for (int c = 0; c < 2; ++c)
      for (int i = 0; i < 1024; ++i)
        check(full.getSample(c, i) == blocks.getSample(c, i),
              "block-size independent render");
    auto wav = dir.getChildFile("render.wav");
    render.exportWav(wav);
    juce::AudioFormatManager formats;
    formats.registerBasicFormats();
    std::unique_ptr<juce::AudioFormatReader> reader(
        formats.createReaderFor(wav));
    check(reader && reader->lengthInSamples == render.length(), "WAV duration");
    for (int family = 0; family < 6; ++family) {
      ls::Amp amp;
      amp.prepare(48000);
      juce::AudioBuffer<float> b(2, 4096);
      for (int c = 0; c < 2; ++c)
        for (int i = 0; i < 4096; ++i)
          b.setSample(c, i, i == 0 ? 100.f : .3f);
      amp.process(b, family, 30, .8f, 1);
      for (int c = 0; c < 2; ++c)
        for (int i = 0; i < 4096; ++i)
          check(std::isfinite(b.getSample(c, i)) &&
                    std::abs(b.getSample(c, i)) <= 1,
                "amp finite bounded output");
    }

    // Synthetic test-only pack: no unlicensed recordings are distributed.
    juce::String digest = juce::SHA256(wav).toHexString();
    auto manifest =
        juce::JSON::parse("{\"schema\":1,\"redistribution\":\"approved\","
                          "\"license\":\"test-generated\",\"source\":\"test "
                          "fixture\",\"attribution\":\"test\",\"regions\":[]}");
    juce::Array<juce::var> regions;
    auto *region = new juce::DynamicObject;
    region->setProperty("note", 60);
    region->setProperty("file", "render.wav");
    region->setProperty("sha256", digest);
    regions.add(juce::var(region));
    manifest.getDynamicObject()->setProperty("regions", regions);
    auto pack = dir.getChildFile("pack.json");
    check(pack.replaceWithText(juce::JSON::toString(manifest)),
          "write test pack");
    ls::Sampler sampler(false);
    sampler.prepare(48000);
    sampler.load(pack);
    check(sampler.regionCount() == 1, "load verified region");
    juce::MidiBuffer midi;
    midi.addEvent(juce::MidiMessage::noteOn(1, 60, .8f), 128);
    juce::AudioBuffer<float> sampled(2, 512);
    sampled.clear();
    sampler.process(sampled, midi, 1, 0);
    check(sampled.getMagnitude(0, 128) == 0, "sample-accurate note start");
    check(sampled.getMagnitude(129, 383) > .001, "sample playback audible");
    region->setProperty("sha256", juce::String::repeatedString("0", 64));
    pack.replaceWithText(juce::JSON::toString(manifest));
    bool badHash = false;
    try {
      sampler.load(pack);
    } catch (...) {
      badHash = true;
    }
    check(badHash, "reject corrupted sample");
    check(sampler.regionCount() == 1, "failed load preserves previous pack");

    // Velocity and round-robin behavior use generated constants so expected
    // output is exact.
    auto constantFile = [&](const char *name, float value) {
      auto target = dir.getChildFile(name);
      auto stream = target.createOutputStream();
      juce::WavAudioFormat wav;
      std::unique_ptr<juce::AudioFormatWriter> writer(
          wav.createWriterFor(stream.release(), 48000, 1, 24, {}, 0));
      juce::AudioBuffer<float> data(1, 1024);
      for (int i = 0; i < 1024; ++i)
        data.setSample(0, i, value);
      check(writer && writer->writeFromAudioSampleBuffer(data, 0, 1024),
            "write sampler fixture");
      writer.reset();
      return target;
    };
    auto soft = constantFile("soft.wav", .1f),
         loud = constantFile("loud.wav", .4f);
    juce::Array<juce::var> mapped;
    auto addRegion = [&](int note, juce::File sample, int low, int high,
                         int choke) {
      auto *item = new juce::DynamicObject;
      item->setProperty("note", note);
      item->setProperty("file", sample.getFileName());
      item->setProperty("sha256", juce::SHA256(sample).toHexString());
      item->setProperty("velocityLow", low);
      item->setProperty("velocityHigh", high);
      item->setProperty("chokeGroup", choke);
      mapped.add(juce::var(item));
    };
    addRegion(36, soft, 1, 127, 0);
    addRegion(36, loud, 1, 127, 0);
    addRegion(38, soft, 1, 63, 0);
    addRegion(38, loud, 64, 127, 0);
    addRegion(42, soft, 1, 127, 1);
    addRegion(46, loud, 1, 127, 1);
    manifest.getDynamicObject()->setProperty("regions", mapped);
    pack.replaceWithText(juce::JSON::toString(manifest));
    ls::Sampler drums(true);
    drums.prepare(48000);
    drums.load(pack);
    auto hit = [&](int note, float velocity) {
      juce::AudioBuffer<float> b(2, 2048);
      b.clear();
      juce::MidiBuffer events;
      events.addEvent(juce::MidiMessage::noteOn(1, note, velocity), 0);
      drums.process(b, events, 1, 0);
      return b.getSample(0, 0);
    };
    float first = hit(36, 1), second = hit(36, 1);
    check(second > first * 3.9f, "round-robin alternates recordings");
    check(hit(38, 1) > hit(38, .4f) * 8,
          "velocity layers select distinct recordings");
    drums.event(juce::MidiMessage::controllerEvent(1, 4, 127));
    check(std::abs(hit(46, 1) - first) < .0001f,
          "closed hi-hat pedal selects closed articulation");
    drums.event(juce::MidiMessage::controllerEvent(1, 4, 0));
    check(hit(46, 1) > first * 3.9f, "open hi-hat articulation restored");
    check(dir.deleteRecursively(), "cleanup");
    if (argc > 1) {
      juce::AudioPluginFormatManager manager;
      manager.addFormat(new juce::VST3PluginFormat);
      for (int argument = 1; argument < argc; ++argument) {
        juce::OwnedArray<juce::PluginDescription> descriptions;
        manager.getFormat(0)->findAllTypesForFile(
            descriptions, juce::String::fromUTF8(argv[argument]));
        check(!descriptions.isEmpty(), "discover plugin wrapper");
        juce::String error;
        auto instance =
            manager.createPluginInstance(*descriptions[0], 48000, 512, error);
        check(instance != nullptr, "instantiate plugin wrapper");
        instance->prepareToPlay(48000, 512);
        for (int block = 0; block < 64; ++block) {
          juce::AudioBuffer<float> audio(2, 512);
          for (int c = 0; c < 2; ++c)
            for (int i = 0; i < 512; ++i)
              audio.setSample(c, i, .05f * std::sin((block * 512 + i) * .03));
          juce::MidiBuffer events;
          if (block == 0)
            events.addEvent(juce::MidiMessage::noteOn(1, 60, .8f), 0);
          instance->processBlock(audio, events);
          for (int c = 0; c < 2; ++c)
            for (int i = 0; i < 512; ++i)
              check(std::isfinite(audio.getSample(c, i)),
                    "plugin output remains finite");
        }
        juce::MemoryBlock state;
        instance->getStateInformation(state);
        check(state.getSize() > 0, "plugin state serialized");
        instance->setStateInformation(state.getData(), (int)state.getSize());
        instance->releaseResources();
        std::cout << "Plugin wrapper passed: " << descriptions[0]->name << '\n';
      }
    }
    std::cout << "All native session/audio checks passed\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << '\n';
    return 1;
  }
}
