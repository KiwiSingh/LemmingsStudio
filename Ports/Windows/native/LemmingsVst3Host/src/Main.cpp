#include <JuceHeader.h>
#include <atomic>
#include <iostream>
#include <map>
#include <mutex>
#include <thread>

using namespace juce;

namespace
{
static void emitJson (const String& kind, const String& message, const String& slot = {}, const String& requestId = {})
{
    DynamicObject::Ptr obj = new DynamicObject();
    obj->setProperty ("kind", kind);
    obj->setProperty ("message", message);
    if (slot.isNotEmpty()) obj->setProperty ("slotId", slot);
    if (requestId.isNotEmpty()) obj->setProperty ("id", requestId);
    std::cout << JSON::toString (var (obj.get()), false).toStdString() << std::endl;
}

static void emitDataJson (const String& kind, const String& message, const String& slot, const String& requestId, int sampleRate, int channels, int frames, const String& pcmBase64)
{
    DynamicObject::Ptr obj = new DynamicObject();
    obj->setProperty ("kind", kind);
    obj->setProperty ("message", message);
    obj->setProperty ("slotId", slot);
    if (requestId.isNotEmpty()) obj->setProperty ("id", requestId);
    obj->setProperty ("sampleRate", sampleRate);
    obj->setProperty ("channels", channels);
    obj->setProperty ("frames", frames);
    obj->setProperty ("pcm", pcmBase64);
    std::cout << JSON::toString (var (obj.get()), false).toStdString() << std::endl;
}

static void emitDataFileJson (const String& kind, const String& message, const String& slot, const String& requestId, int sampleRate, int channels, int frames, const File& pcmFile)
{
    DynamicObject::Ptr obj = new DynamicObject();
    obj->setProperty ("kind", kind);
    obj->setProperty ("message", message);
    obj->setProperty ("slotId", slot);
    if (requestId.isNotEmpty()) obj->setProperty ("id", requestId);
    obj->setProperty ("sampleRate", sampleRate);
    obj->setProperty ("channels", channels);
    obj->setProperty ("frames", frames);
    obj->setProperty ("pcmFile", pcmFile.getFullPathName());
    std::cout << JSON::toString (var (obj.get()), false).toStdString() << std::endl;
}

static int getInt (const DynamicObject* obj, const Identifier& key, int fallback = 0)
{
    if (obj == nullptr || ! obj->hasProperty (key)) return fallback;
    return static_cast<int> (obj->getProperty (key));
}

static double getDouble (const DynamicObject* obj, const Identifier& key, double fallback = 0.0)
{
    if (obj == nullptr || ! obj->hasProperty (key)) return fallback;
    return static_cast<double> (obj->getProperty (key));
}

static String getRequestId (const DynamicObject* obj)
{
    return obj != nullptr && obj->hasProperty ("id") ? obj->getProperty ("id").toString() : String();
}

static String encodeFloatBuffer (const AudioBuffer<float>& buffer, int frames, int channels)
{
    MemoryBlock mb;
    mb.setSize ((size_t) frames * (size_t) channels * sizeof (float), true);
    auto* dst = static_cast<float*> (mb.getData());
    for (int i = 0; i < frames; ++i)
        for (int ch = 0; ch < channels; ++ch)
            *dst++ = buffer.getSample (jmin (ch, buffer.getNumChannels() - 1), i);
    return mb.toBase64Encoding();
}

static bool decodeFloatMemory (const MemoryBlock& mb, AudioBuffer<float>& out, int frames, int channels)
{
    const auto expected = (size_t) frames * (size_t) channels * sizeof (float);
    if (mb.getSize() < expected)
        return false;
    out.setSize (channels, frames, false, false, true);
    const auto* src = static_cast<const float*> (mb.getData());
    for (int i = 0; i < frames; ++i)
        for (int ch = 0; ch < channels; ++ch)
            out.setSample (ch, i, *src++);
    return true;
}

static bool decodeFloatBuffer (const String& base64, AudioBuffer<float>& out, int frames, int channels)
{
    MemoryBlock mb;
    return mb.fromBase64Encoding (base64) && decodeFloatMemory (mb, out, frames, channels);
}

static bool decodeFloatFile (const String& path, AudioBuffer<float>& out, int frames, int channels)
{
    File f (path);
    MemoryBlock mb;
    return f.existsAsFile() && f.loadFileAsData (mb) && decodeFloatMemory (mb, out, frames, channels);
}

static File writeFloatBufferFile (const AudioBuffer<float>& buffer, int frames, int channels)
{
    auto f = File::getSpecialLocation (File::tempDirectory).getChildFile ("LemmingsStudioVst3_" + Uuid().toString() + ".f32");
    MemoryBlock mb;
    mb.setSize ((size_t) frames * (size_t) channels * sizeof (float), true);
    auto* dst = static_cast<float*> (mb.getData());
    for (int i = 0; i < frames; ++i)
        for (int ch = 0; ch < channels; ++ch)
            *dst++ = buffer.getSample (jmin (ch, buffer.getNumChannels() - 1), i);
    f.replaceWithData (mb.getData(), mb.getSize());
    return f;
}

static String getString (const DynamicObject* obj, const Identifier& key, const String& fallback = {})
{
    if (obj == nullptr || ! obj->hasProperty (key)) return fallback;
    return obj->getProperty (key).toString();
}

static File resolveVst3Module (const String& supplied)
{
    File f (supplied);
    if (f.isDirectory())
    {
        // Standard Windows VST3 bundle layout: Foo.vst3/Contents/x86_64-win/Foo.vst3
        Array<File> candidates;
        f.findChildFiles (candidates, File::findFiles, true, "*.vst3");
        for (auto& c : candidates)
            if (c.getParentDirectory().getFileName().containsIgnoreCase ("x86_64-win") ||
                c.getParentDirectory().getFileName().containsIgnoreCase ("arm64-win"))
                return c;
        if (! candidates.isEmpty()) return candidates.getFirst();
    }
    return f;
}
}

class HostedPlugin final
{
public:
    HostedPlugin (String slotIdIn, PluginDescription descIn, std::unique_ptr<AudioPluginInstance> instanceIn)
        : slotId (std::move (slotIdIn)), desc (std::move (descIn)), instance (std::move (instanceIn))
    {
        if (instance != nullptr)
        {
            instance->enableAllBuses();
            // Most instruments want 0 inputs/2 outputs; effects may keep their preferred layout.
            if (instance->getTotalNumOutputChannels() == 0)
                instance->setPlayConfigDetails (0, 2, sampleRate, blockSize);
            else
                instance->setPlayConfigDetails (instance->getTotalNumInputChannels(),
                                                jmax (2, instance->getTotalNumOutputChannels()),
                                                sampleRate, blockSize);
            instance->prepareToPlay (sampleRate, blockSize);
        }
    }

    ~HostedPlugin()
    {
        closeEditor();
        if (instance != nullptr)
            instance->releaseResources();
    }

    void pushMidi (const MidiMessage& msg)
    {
        const ScopedLock sl (midiLock);
        midi.addEvent (msg, 0);
    }

    void process (AudioBuffer<float>& buffer)
    {
        if (instance == nullptr)
        {
            buffer.clear();
            return;
        }

        MidiBuffer incoming;
        {
            const ScopedLock sl (midiLock);
            incoming.swapWith (midi);
        }

        const int requiredChannels = jmax (1, instance->getTotalNumInputChannels(), instance->getTotalNumOutputChannels(), 2);
        if (work.getNumChannels() != requiredChannels || work.getNumSamples() != buffer.getNumSamples())
            work.setSize (requiredChannels, buffer.getNumSamples(), false, false, true);
        work.clear();

        const int copyIn = jmin (buffer.getNumChannels(), work.getNumChannels());
        for (int ch = 0; ch < copyIn; ++ch)
            work.copyFrom (ch, 0, buffer, ch, 0, buffer.getNumSamples());

        instance->processBlock (work, incoming);

        const int copyOut = jmin (buffer.getNumChannels(), work.getNumChannels());
        buffer.clear();
        for (int ch = 0; ch < copyOut; ++ch)
            buffer.copyFrom (ch, 0, work, ch, 0, buffer.getNumSamples());
    }

    void openEditor()
    {
        if (instance == nullptr)
            return;

        if (window != nullptr)
        {
            window->toFront (true);
            return;
        }

        AudioProcessorEditor* editor = nullptr;
        if (instance->hasEditor())
            editor = instance->createEditorIfNeeded();
        else
            editor = new GenericAudioProcessorEditor (*instance);
        if (editor == nullptr)
        {
            emitJson ("error", "Plug-in editor could not be created.", slotId);
            return;
        }

        class PluginWindow final : public DocumentWindow
        {
        public:
            PluginWindow (HostedPlugin& ownerIn, AudioProcessorEditor* editorIn)
                : DocumentWindow (ownerIn.desc.name, Colours::black, DocumentWindow::closeButton), owner (ownerIn)
            {
                setUsingNativeTitleBar (true);
                setResizable (true, false);
                setContentOwned (editorIn, true);
                centreWithSize (jmax (480, editorIn->getWidth()), jmax (320, editorIn->getHeight()));
                setVisible (true);
                toFront (true);
            }
            void closeButtonPressed() override { owner.closeEditor(); }
        private:
            HostedPlugin& owner;
        };

        window.reset (new PluginWindow (*this, editor));
        emitJson ("editor", "Editor opened", slotId);
    }

    void closeEditor()
    {
        if (window != nullptr)
        {
            window->setVisible (false);
            window.reset();
        }
    }

    void processOffline (AudioBuffer<float>& buffer, MidiBuffer& incoming)
    {
        if (instance == nullptr)
        {
            buffer.clear();
            return;
        }

        const int requiredChannels = jmax (1, instance->getTotalNumInputChannels(), instance->getTotalNumOutputChannels(), 2);
        if (work.getNumChannels() != requiredChannels || work.getNumSamples() != buffer.getNumSamples())
            work.setSize (requiredChannels, buffer.getNumSamples(), false, false, true);
        work.clear();

        const int copyIn = jmin (buffer.getNumChannels(), work.getNumChannels());
        for (int ch = 0; ch < copyIn; ++ch)
            work.copyFrom (ch, 0, buffer, ch, 0, buffer.getNumSamples());

        instance->processBlock (work, incoming);

        const int copyOut = jmin (buffer.getNumChannels(), work.getNumChannels());
        buffer.clear();
        for (int ch = 0; ch < copyOut; ++ch)
            buffer.copyFrom (ch, 0, work, ch, 0, buffer.getNumSamples());
    }

    void setOfflineFormat (double sr, int block)
    {
        if (instance == nullptr) return;
        if (std::abs (sampleRate - sr) < 0.1 && blockSize == block) return;
        instance->releaseResources();
        sampleRate = sr;
        blockSize = block;
        instance->setPlayConfigDetails (instance->getTotalNumInputChannels(),
                                        jmax (2, instance->getTotalNumOutputChannels()),
                                        sampleRate, blockSize);
        instance->prepareToPlay (sampleRate, blockSize);
    }

    void emitInfo (const String& requestId)
    {
        DynamicObject::Ptr obj = new DynamicObject();
        obj->setProperty ("kind", "info");
        obj->setProperty ("message", "Plug-in info");
        obj->setProperty ("slotId", slotId);
        if (requestId.isNotEmpty()) obj->setProperty ("id", requestId);
        obj->setProperty ("latencySamples", instance != nullptr ? instance->getLatencySamples() : 0);
        obj->setProperty ("inputChannels", instance != nullptr ? instance->getTotalNumInputChannels() : 0);
        obj->setProperty ("outputChannels", instance != nullptr ? instance->getTotalNumOutputChannels() : 0);
        obj->setProperty ("supportsEditor", instance != nullptr);
        obj->setProperty ("hasCustomEditor", instance != nullptr && instance->hasEditor());
        obj->setProperty ("layout", String (instance != nullptr ? instance->getTotalNumInputChannels() : 0) + " in / " + String (instance != nullptr ? instance->getTotalNumOutputChannels() : 0) + " out");
        Array<var> inputBuses;
        Array<var> outputBuses;
        if (instance != nullptr)
        {
            for (int i = 0; i < instance->getBusCount (true); ++i)
            {
                if (auto* bus = instance->getBus (true, i))
                {
                    DynamicObject::Ptr item = new DynamicObject();
                    item->setProperty ("index", i);
                    item->setProperty ("name", bus->getName());
                    item->setProperty ("channels", bus->getNumberOfChannels());
                    item->setProperty ("enabled", bus->isEnabled());
                    item->setProperty ("main", i == 0);
                    inputBuses.add (var (item.get()));
                }
            }
            for (int i = 0; i < instance->getBusCount (false); ++i)
            {
                if (auto* bus = instance->getBus (false, i))
                {
                    DynamicObject::Ptr item = new DynamicObject();
                    item->setProperty ("index", i);
                    item->setProperty ("name", bus->getName());
                    item->setProperty ("channels", bus->getNumberOfChannels());
                    item->setProperty ("enabled", bus->isEnabled());
                    item->setProperty ("main", i == 0);
                    outputBuses.add (var (item.get()));
                }
            }
        }
        obj->setProperty ("inputBuses", var (inputBuses));
        obj->setProperty ("outputBuses", var (outputBuses));
        obj->setProperty ("sidechainCapable", inputBuses.size() > 1);
        std::cout << JSON::toString (var (obj.get()), false).toStdString() << std::endl;
    }

    void emitParameters (const String& requestId)
    {
        DynamicObject::Ptr obj = new DynamicObject();
        obj->setProperty ("kind", "parameters");
        obj->setProperty ("message", "Plug-in parameters");
        obj->setProperty ("slotId", slotId);
        if (requestId.isNotEmpty()) obj->setProperty ("id", requestId);
        Array<var> params;
        if (instance != nullptr)
        {
            auto& list = instance->getParameters();
            for (int i = 0; i < list.size(); ++i)
            {
                auto* parameter = list.getUnchecked (i);
                if (parameter == nullptr) continue;
                DynamicObject::Ptr item = new DynamicObject();
                item->setProperty ("index", i);
                item->setProperty ("name", parameter->getName (96));
                item->setProperty ("value", parameter->getValue());
                item->setProperty ("text", parameter->getText (parameter->getValue(), 96));
                item->setProperty ("automatable", parameter->isAutomatable());
                if (auto* withId = dynamic_cast<AudioProcessorParameterWithID*> (parameter))
                    item->setProperty ("paramId", withId->paramID);
                else
                    item->setProperty ("paramId", "#" + String (i));
                params.add (var (item.get()));
            }
        }
        obj->setProperty ("parameters", var (params));
        std::cout << JSON::toString (var (obj.get()), false).toStdString() << std::endl;
    }

    bool setParameter (const String& paramId, int index, float normalized)
    {
        if (instance == nullptr) return false;
        auto& list = instance->getParameters();
        AudioProcessorParameter* parameter = nullptr;
        if (index >= 0 && index < list.size())
            parameter = list.getUnchecked (index);
        if (parameter == nullptr && paramId.isNotEmpty())
        {
            for (int i = 0; i < list.size(); ++i)
            {
                auto* p = list.getUnchecked (i);
                if (p == nullptr) continue;
                if (auto* withId = dynamic_cast<AudioProcessorParameterWithID*> (p))
                    if (withId->paramID == paramId) { parameter = p; break; }
                if (p->getName (96) == paramId) { parameter = p; break; }
            }
        }
        if (parameter == nullptr) return false;
        const float v = jlimit (0.0f, 1.0f, normalized);
        parameter->beginChangeGesture();
        parameter->setValueNotifyingHost (v);
        parameter->endChangeGesture();
        return true;
    }

    String getStateBase64()
    {
        MemoryBlock state;
        if (instance != nullptr)
            instance->getStateInformation (state);
        return state.toBase64Encoding();
    }

    bool setStateBase64 (const String& b64)
    {
        if (instance == nullptr || b64.isEmpty()) return false;
        MemoryBlock state;
        if (! state.fromBase64Encoding (b64)) return false;
        instance->setStateInformation (state.getData(), (int) state.getSize());
        return true;
    }

    Array<var> automationEventsForBlock (const Array<var>& automation, int blockStart, int blockFrames)
    {
        Array<var> events;
        for (auto& ev : automation)
        {
            auto* e = ev.getDynamicObject();
            if (e == nullptr) continue;
            const int frame = getInt (e, "frame", 0);
            if (frame < blockStart || frame >= blockStart + blockFrames) continue;
            events.add (ev);
        }
        std::sort (events.begin(), events.end(), [] (const var& a, const var& b)
        {
            auto* ao = a.getDynamicObject();
            auto* bo = b.getDynamicObject();
            return getInt (ao, "frame", 0) < getInt (bo, "frame", 0);
        });
        return events;
    }

    void applyAutomationEvent (const DynamicObject* e)
    {
        if (e == nullptr) return;
        setParameter (getString (e, "paramId"), getInt (e, "index", -1), (float) getDouble (e, "value", 0.0));
    }

    void processOfflineAutomated (AudioBuffer<float>& block, MidiBuffer& incoming, const Array<var>& automation, int absoluteBlockStart)
    {
        auto events = automationEventsForBlock (automation, absoluteBlockStart, block.getNumSamples());
        if (events.isEmpty())
        {
            processOffline (block, incoming);
            return;
        }

        AudioBuffer<float> rendered (block.getNumChannels(), block.getNumSamples());
        rendered.clear();
        int cursor = 0;
        int eventIndex = 0;

        while (cursor < block.getNumSamples())
        {
            int next = block.getNumSamples();
            if (eventIndex < events.size())
            {
                auto* e = events.getReference (eventIndex).getDynamicObject();
                const int rel = jlimit (0, block.getNumSamples(), getInt (e, "frame", absoluteBlockStart) - absoluteBlockStart);
                if (rel <= cursor)
                {
                    while (eventIndex < events.size())
                    {
                        auto* now = events.getReference (eventIndex).getDynamicObject();
                        const int nowRel = jlimit (0, block.getNumSamples(), getInt (now, "frame", absoluteBlockStart) - absoluteBlockStart);
                        if (nowRel != rel) break;
                        applyAutomationEvent (now);
                        ++eventIndex;
                    }
                    continue;
                }
                next = rel;
            }

            const int n = next - cursor;
            if (n <= 0) { ++eventIndex; continue; }
            AudioBuffer<float> slice (block.getNumChannels(), n);
            for (int ch = 0; ch < block.getNumChannels(); ++ch)
                slice.copyFrom (ch, 0, block, ch, cursor, n);
            MidiBuffer sliceMidi;
            for (const auto meta : incoming)
            {
                if (meta.samplePosition >= cursor && meta.samplePosition < cursor + n)
                    sliceMidi.addEvent (meta.getMessage(), meta.samplePosition - cursor);
            }
            processOffline (slice, sliceMidi);
            for (int ch = 0; ch < block.getNumChannels(); ++ch)
                rendered.copyFrom (ch, cursor, slice, ch, 0, n);
            cursor = next;
        }

        block.makeCopyOf (rendered, true);
    }

    void emitPrograms (const String& requestId)
    {
        DynamicObject::Ptr obj = new DynamicObject();
        obj->setProperty ("kind", "programs");
        obj->setProperty ("message", "Plug-in programs");
        obj->setProperty ("slotId", slotId);
        if (requestId.isNotEmpty()) obj->setProperty ("id", requestId);
        Array<var> programs;
        if (instance != nullptr)
        {
            const int n = instance->getNumPrograms();
            for (int i = 0; i < n; ++i)
            {
                DynamicObject::Ptr item = new DynamicObject();
                item->setProperty ("index", i);
                item->setProperty ("name", instance->getProgramName (i));
                programs.add (var (item.get()));
            }
            obj->setProperty ("current", instance->getCurrentProgram());
        }
        obj->setProperty ("programs", var (programs));
        std::cout << JSON::toString (var (obj.get()), false).toStdString() << std::endl;
    }

    bool setProgram (int index)
    {
        if (instance == nullptr || index < 0 || index >= instance->getNumPrograms()) return false;
        instance->setCurrentProgram (index);
        return true;
    }


    String slotId;
    PluginDescription desc;
    std::unique_ptr<AudioPluginInstance> instance;
    double sampleRate = 48000.0;
    int blockSize = 512;

private:
    CriticalSection midiLock;
    MidiBuffer midi;
    AudioBuffer<float> work;
    std::unique_ptr<DocumentWindow> window;
};

class HostAudioSource final : public AudioSource
{
public:
    std::function<HostedPlugin*()> getActivePlugin;

    void prepareToPlay (int samplesPerBlockExpected, double sampleRate) override
    {
        bufferSize = samplesPerBlockExpected;
        sr = sampleRate;
        ignoreUnused (bufferSize, sr);
    }

    void releaseResources() override {}

    void getNextAudioBlock (const AudioSourceChannelInfo& info) override
    {
        if (info.buffer == nullptr) return;
        info.buffer->clear (info.startSample, info.numSamples);
        if (auto* p = getActivePlugin ? getActivePlugin() : nullptr)
        {
            AudioBuffer<float> temp (info.buffer->getNumChannels(), info.numSamples);
            temp.clear();
            p->process (temp);
            for (int ch = 0; ch < info.buffer->getNumChannels(); ++ch)
                info.buffer->copyFrom (ch, info.startSample, temp, ch % temp.getNumChannels(), 0, info.numSamples);
        }
    }

private:
    int bufferSize = 512;
    double sr = 48000.0;
};

class StdinThread final : public Thread
{
public:
    explicit StdinThread (std::function<void(String)> onLineIn)
        : Thread ("LemmingsVst3Host stdin"), onLine (std::move (onLineIn)) {}

    void run() override
    {
        std::string line;
        while (! threadShouldExit() && std::getline (std::cin, line))
            onLine (String::fromUTF8 (line.c_str()));
    }

private:
    std::function<void(String)> onLine;
};

class Vst3HostApplication final : public JUCEApplication
{
public:
    const String getApplicationName() override { return "LemmingsVst3Host"; }
    const String getApplicationVersion() override { return "1.1.0"; }
    bool moreThanOneInstanceAllowed() override { return true; }

    void initialise (const String&) override
    {
        formatManager.addDefaultFormats();
        audioSource.getActivePlugin = [this] { return getFirstPlugin(); };
        deviceManager.initialiseWithDefaultDevices (0, 2);
        player.setSource (&audioSource);
        deviceManager.addAudioCallback (&player);

        stdinThread = std::make_unique<StdinThread> ([this] (String line)
        {
            MessageManager::callAsync ([this, line] { handleLine (line); });
        });
        stdinThread->startThread();
        emitJson ("ready", "Native JUCE VST3 host ready");
    }

    void shutdown() override
    {
        if (stdinThread != nullptr)
        {
            stdinThread->signalThreadShouldExit();
            stdinThread->waitForThreadToExit (600);
            stdinThread.reset();
        }
        deviceManager.removeAudioCallback (&player);
        player.setSource (nullptr);
        plugins.clear();
    }

    void systemRequestedQuit() override { quit(); }
    void anotherInstanceStarted (const String&) override {}

private:
    void handleLine (const String& line)
    {
        var parsed = JSON::parse (line);
        auto* obj = parsed.getDynamicObject();
        if (obj == nullptr)
        {
            emitJson ("error", "Invalid JSON command");
            return;
        }

        const auto op = getString (obj, "op");
        const auto slotId = getString (obj, "slotId");

        if (op == "ping") { emitJson ("pong", "ok"); return; }
        if (op == "quit") { quit(); return; }

        if (op == "load")
        {
            loadPlugin (slotId, getString (obj, "path"));
            return;
        }
        if (op == "openEditor")
        {
            if (auto* p = findPlugin (slotId)) p->openEditor();
            else emitJson ("error", "Slot not loaded before openEditor", slotId);
            return;
        }
        if (op == "noteOn")
        {
            if (auto* p = findPlugin (slotId))
                p->pushMidi (MidiMessage::noteOn (jlimit (1, 16, getInt (obj, "channel", 1)),
                                                  jlimit (0, 127, getInt (obj, "note", 60)),
                                                  (uint8) jlimit (1, 127, getInt (obj, "velocity", 100))));
            return;
        }
        if (op == "noteOff")
        {
            if (auto* p = findPlugin (slotId))
                p->pushMidi (MidiMessage::noteOff (jlimit (1, 16, getInt (obj, "channel", 1)),
                                                   jlimit (0, 127, getInt (obj, "note", 60))));
            return;
        }
        if (op == "cc")
        {
            if (auto* p = findPlugin (slotId))
                p->pushMidi (MidiMessage::controllerEvent (jlimit (1, 16, getInt (obj, "channel", 1)),
                                                           jlimit (0, 127, getInt (obj, "controller", 1)),
                                                           jlimit (0, 127, getInt (obj, "value", 0))));
            return;
        }
        if (op == "pitch")
        {
            if (auto* p = findPlugin (slotId))
                p->pushMidi (MidiMessage::pitchWheel (jlimit (1, 16, getInt (obj, "channel", 1)),
                                                      jlimit (0, 16383, getInt (obj, "value", 8192))));
            return;
        }
        if (op == "renderMidi")
        {
            renderMidi (obj, slotId, getRequestId (obj));
            return;
        }
        if (op == "processAudio")
        {
            processAudio (obj, slotId, getRequestId (obj));
            return;
        }
        if (op == "getParameters")
        {
            if (auto* p = findPlugin (slotId)) p->emitParameters (getRequestId (obj));
            else emitJson ("error", "Slot not loaded before getParameters", slotId, getRequestId (obj));
            return;
        }
        if (op == "setParameter")
        {
            if (auto* p = findPlugin (slotId))
            {
                const bool ok = p->setParameter (getString (obj, "paramId"), getInt (obj, "index", -1), (float) getDouble (obj, "value", 0.0));
                emitJson (ok ? "parameter" : "error", ok ? "Parameter set" : "Parameter not found", slotId, getRequestId (obj));
            }
            else emitJson ("error", "Slot not loaded before setParameter", slotId, getRequestId (obj));
            return;
        }
        if (op == "getPrograms")
        {
            if (auto* p = findPlugin (slotId)) p->emitPrograms (getRequestId (obj));
            else emitJson ("error", "Slot not loaded before getPrograms", slotId, getRequestId (obj));
            return;
        }
        if (op == "setProgram")
        {
            if (auto* p = findPlugin (slotId))
            {
                const bool ok = p->setProgram (getInt (obj, "index", -1));
                emitJson (ok ? "program" : "error", ok ? "Program set" : "Program not available", slotId, getRequestId (obj));
            }
            else emitJson ("error", "Slot not loaded before setProgram", slotId, getRequestId (obj));
            return;
        }
        if (op == "getState")
        {
            if (auto* p = findPlugin (slotId))
            {
                DynamicObject::Ptr out = new DynamicObject();
                out->setProperty ("kind", "state");
                out->setProperty ("message", "Plug-in state");
                out->setProperty ("slotId", slotId);
                out->setProperty ("id", getRequestId (obj));
                out->setProperty ("state", p->getStateBase64());
                std::cout << JSON::toString (var (out.get()), false).toStdString() << std::endl;
            }
            else emitJson ("error", "Slot not loaded before getState", slotId, getRequestId (obj));
            return;
        }
        if (op == "setState")
        {
            if (auto* p = findPlugin (slotId))
            {
                const bool ok = p->setStateBase64 (getString (obj, "state"));
                emitJson (ok ? "state" : "error", ok ? "Plug-in state restored" : "Plug-in state restore failed", slotId, getRequestId (obj));
            }
            else emitJson ("error", "Slot not loaded before setState", slotId, getRequestId (obj));
            return;
        }
        if (op == "getInfo")
        {
            if (auto* p = findPlugin (slotId)) p->emitInfo (getRequestId (obj));
            else emitJson ("error", "Slot not loaded before getInfo", slotId, getRequestId (obj));
            return;
        }
        if (op == "panic")
        {
            for (auto& it : plugins)
                for (int ch = 1; ch <= 16; ++ch)
                    it.second->pushMidi (MidiMessage::allNotesOff (ch));
            emitJson ("panic", "All notes off sent", slotId);
            return;
        }

        emitJson ("warning", "Unknown op: " + op, slotId);
    }

    void renderMidi (const DynamicObject* obj, const String& slotId, const String& requestId)
    {
        auto* p = findPlugin (slotId);
        if (p == nullptr)
        {
            emitJson ("error", "Slot not loaded before renderMidi", slotId, requestId);
            return;
        }

        const int sr = jlimit (8000, 384000, getInt (obj, "sampleRate", 44100));
        const int channels = jlimit (1, 8, getInt (obj, "channels", 2));
        const int frames = jlimit (1, sr * 600, getInt (obj, "frames", sr));
        const int blockSize = jlimit (32, 8192, getInt (obj, "blockSize", 512));
        p->setOfflineFormat ((double) sr, blockSize);

        AudioBuffer<float> output (channels, frames);
        output.clear();

        MidiBuffer allMidi;
        if (obj != nullptr && obj->hasProperty ("events"))
        {
            auto* arr = obj->getProperty ("events").getArray();
            if (arr != nullptr)
            {
                for (auto& ev : *arr)
                {
                    auto* e = ev.getDynamicObject();
                    if (e == nullptr) continue;
                    const int frame = jlimit (0, frames - 1, getInt (e, "frame", 0));
                    const int ch = jlimit (1, 16, getInt (e, "channel", 1));
                    const int note = jlimit (0, 127, getInt (e, "note", 60));
                    const int vel = jlimit (0, 127, getInt (e, "velocity", 100));
                    const auto type = getString (e, "type");
                    if (type == "on") allMidi.addEvent (MidiMessage::noteOn (ch, note, (uint8) jmax (1, vel)), frame);
                    else if (type == "off") allMidi.addEvent (MidiMessage::noteOff (ch, note), frame);
                    else if (type == "cc") allMidi.addEvent (MidiMessage::controllerEvent (ch, jlimit (0, 127, getInt (e, "controller", 1)), vel), frame);
                    else if (type == "pitch") allMidi.addEvent (MidiMessage::pitchWheel (ch, jlimit (0, 16383, vel)), frame);
                }
            }
        }

        Array<var> automation;
        if (obj != nullptr && obj->hasProperty ("automation"))
            if (auto* a = obj->getProperty ("automation").getArray()) automation = *a;

        AudioBuffer<float> block (channels, blockSize);
        for (int pos = 0; pos < frames; pos += blockSize)
        {
            const int n = jmin (blockSize, frames - pos);
            block.setSize (channels, n, false, false, true);
            block.clear();
            MidiBuffer blockMidi;
            for (const auto meta : allMidi)
            {
                const int sample = meta.samplePosition;
                if (sample >= pos && sample < pos + n)
                    blockMidi.addEvent (meta.getMessage(), sample - pos);
            }
            p->processOfflineAutomated (block, blockMidi, automation, pos);
            for (int ch = 0; ch < channels; ++ch)
                output.copyFrom (ch, pos, block, ch, 0, n);
        }

        if (getString (obj, "responseMode") == "file")
            emitDataFileJson ("pcm", "renderMidi complete", slotId, requestId, sr, channels, frames, writeFloatBufferFile (output, frames, channels));
        else
            emitDataJson ("pcm", "renderMidi complete", slotId, requestId, sr, channels, frames, encodeFloatBuffer (output, frames, channels));
    }

    void processAudio (const DynamicObject* obj, const String& slotId, const String& requestId)
    {
        auto* p = findPlugin (slotId);
        if (p == nullptr)
        {
            emitJson ("error", "Slot not loaded before processAudio", slotId, requestId);
            return;
        }

        const int sr = jlimit (8000, 384000, getInt (obj, "sampleRate", 44100));
        const int channels = jlimit (1, 8, getInt (obj, "channels", 2));
        const int frames = jlimit (1, sr * 600, getInt (obj, "frames", sr));
        const int blockSize = jlimit (32, 8192, getInt (obj, "blockSize", 512));
        const String pcm = getString (obj, "pcm");
        const String pcmFile = getString (obj, "pcmFile");
        p->setOfflineFormat ((double) sr, blockSize);

        AudioBuffer<float> input;
        if (! (pcmFile.isNotEmpty() ? decodeFloatFile (pcmFile, input, frames, channels) : decodeFloatBuffer (pcm, input, frames, channels)))
        {
            emitJson ("error", "processAudio received invalid PCM payload", slotId, requestId);
            return;
        }

        AudioBuffer<float> output (channels, frames);
        output.clear();
        Array<var> automation;
        if (obj != nullptr && obj->hasProperty ("automation"))
            if (auto* a = obj->getProperty ("automation").getArray()) automation = *a;
        AudioBuffer<float> block (channels, blockSize);
        MidiBuffer emptyMidi;
        for (int pos = 0; pos < frames; pos += blockSize)
        {
            const int n = jmin (blockSize, frames - pos);
            block.setSize (channels, n, false, false, true);
            for (int ch = 0; ch < channels; ++ch)
                block.copyFrom (ch, 0, input, ch, pos, n);
            emptyMidi.clear();
            p->processOfflineAutomated (block, emptyMidi, automation, pos);
            for (int ch = 0; ch < channels; ++ch)
                output.copyFrom (ch, pos, block, ch, 0, n);
        }

        if (getString (obj, "responseMode") == "file")
            emitDataFileJson ("pcm", "processAudio complete", slotId, requestId, sr, channels, frames, writeFloatBufferFile (output, frames, channels));
        else
            emitDataJson ("pcm", "processAudio complete", slotId, requestId, sr, channels, frames, encodeFloatBuffer (output, frames, channels));
    }

    void loadPlugin (const String& slotId, const String& path)
    {
        if (slotId.isEmpty() || path.isEmpty())
        {
            emitJson ("error", "load requires slotId and path", slotId);
            return;
        }
        if (plugins.find (slotId) != plugins.end())
        {
            emitJson ("loaded", "Already loaded", slotId);
            return;
        }

        const auto moduleFile = resolveVst3Module (path);
        if (! moduleFile.exists())
        {
            emitJson ("error", "VST3 file not found: " + path, slotId);
            return;
        }

        OwnedArray<PluginDescription> found;
        for (auto* format : formatManager.getFormats())
            if (format != nullptr && format->getName().containsIgnoreCase ("VST3"))
                format->findAllTypesForFile (found, moduleFile.getFullPathName());

        if (found.isEmpty())
        {
            emitJson ("error", "No VST3 plug-in classes found in " + moduleFile.getFullPathName(), slotId);
            return;
        }

        PluginDescription desc = *found[0];
        String error;
        std::unique_ptr<AudioPluginInstance> instance (formatManager.createPluginInstance (desc, 48000.0, 512, error));
        if (instance == nullptr)
        {
            emitJson ("error", "Could not instantiate VST3: " + error, slotId);
            return;
        }

        plugins[slotId] = std::make_unique<HostedPlugin> (slotId, desc, std::move (instance));
        emitJson ("loaded", "Loaded " + desc.name + " by " + desc.manufacturerName, slotId);
    }

    HostedPlugin* findPlugin (const String& slotId)
    {
        auto it = plugins.find (slotId);
        return it == plugins.end() ? nullptr : it->second.get();
    }

    HostedPlugin* getFirstPlugin()
    {
        if (plugins.empty()) return nullptr;
        return plugins.begin()->second.get();
    }

    AudioPluginFormatManager formatManager;
    AudioDeviceManager deviceManager;
    HostAudioSource audioSource;
    AudioSourcePlayer player;
    std::unique_ptr<StdinThread> stdinThread;
    std::map<String, std::unique_ptr<HostedPlugin>> plugins;
};

START_JUCE_APPLICATION (Vst3HostApplication)
