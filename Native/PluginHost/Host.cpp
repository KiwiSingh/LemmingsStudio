#include "Host.h"
#include <juce_audio_utils/juce_audio_utils.h>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
namespace {
void copyText(const juce::String& s,char* out,int n){if(out && n>0)s.copyToUTF8(out,size_t(n));}
struct Clock:juce::AudioPlayHead {
    std::atomic<double> bpm{120},ppq{0};std::atomic<bool> playing{false};int64_t samples=0;double rate=48000;
    juce::Optional<PositionInfo> getPosition() const override {
        PositionInfo p;p.setBpm(bpm.load());p.setPpqPosition(ppq.load());p.setIsPlaying(playing.load());
        p.setTimeInSamples(samples);p.setTimeInSeconds(double(samples)/rate);p.setTimeSignature(TimeSignature{4,4});return p;
    }
};
struct EditorWindow:juce::DocumentWindow {
    EditorWindow(juce::AudioPluginInstance& p):DocumentWindow(p.getName(),juce::Colours::darkgrey,DocumentWindow::allButtons){
        setUsingNativeTitleBar(true);setResizable(true,false);
        auto* editor=p.hasEditor()?p.createEditorIfNeeded():new juce::GenericAudioProcessorEditor(p);
        setContentOwned(editor,true);centreWithSize(editor->getWidth(),editor->getHeight());setVisible(true);
    }
    void closeButtonPressed() override {setVisible(false);}
};
struct MidiSlot { std::atomic<uint64_t> sequence{0};std::array<uint8_t,3> bytes{}; };
}
struct LPHost {
    juce::AudioPluginFormatManager formats;
    std::unique_ptr<juce::AudioPluginInstance> processor;
    std::unique_ptr<EditorWindow> window;
    juce::AudioBuffer<float> buffer;
    juce::MidiBuffer midi;
    Clock clock;
    std::array<MidiSlot,1024> queue;
    std::atomic<uint64_t> enqueue{0};uint64_t dequeue=0;
    int maximum=4096,inputs=0,outputs=2;
    LPHost(){for(uint64_t i=0;i<queue.size();i++)queue[i].sequence.store(i);}
    ~LPHost(){window.reset();if(processor){processor->releaseResources();processor->setPlayHead(nullptr);}}
};
uint32_t lp_abi(){return 1;}
LPHost* lp_open(const char* identifier,int format,double rate,int maximum,char* error,int capacity){
    try {
        if(!identifier || !std::isfinite(rate)||rate<8000||rate>192000||maximum<1||maximum>65536){copyText("Invalid native host configuration",error,capacity);return nullptr;}
        // AppKit owns the application's process lifetime. A shared host library
        // must not tear down JUCE globals from a dylib static destructor after
        // vendor modules/AppKit have started their own shutdown sequence.
        static auto* gui=new juce::ScopedJuceInitialiser_GUI();
        (void)gui;
        if(!juce::MessageManager::getInstance()->isThisTheMessageThread()){copyText("Plugin creation must run on the application main thread",error,capacity);return nullptr;}
        auto host=std::make_unique<LPHost>();juce::addDefaultFormatsToManager(host->formats);
        juce::AudioPluginFormat* chosen=nullptr;
        for(auto* f:host->formats.getFormats())if(f->getName()==(format==1?"VST3":"AudioUnit"))chosen=f;
        if(!chosen){copyText("Requested plugin format is not available",error,capacity);return nullptr;}
        juce::OwnedArray<juce::PluginDescription> found;
        chosen->findAllTypesForFile(found,juce::String::fromUTF8(identifier));
        if(found.isEmpty()){copyText("No loadable plugin found at the selected identifier/path",error,capacity);return nullptr;}
        juce::String message;host->processor=host->formats.createPluginInstance(*found[0],rate,maximum,message);
        if(!host->processor){copyText(message,error,capacity);return nullptr;}
        auto& p=*host->processor;
        auto layout=p.getBusesLayout();
        for(int i=1;i<layout.inputBuses.size();++i)layout.inputBuses.set(i,juce::AudioChannelSet::disabled());
        for(int i=1;i<layout.outputBuses.size();++i)layout.outputBuses.set(i,juce::AudioChannelSet::disabled());
        if(!layout.inputBuses.isEmpty())layout.inputBuses.set(0,p.isMidiEffect()?juce::AudioChannelSet::disabled():juce::AudioChannelSet::stereo());
        if(!layout.outputBuses.isEmpty())layout.outputBuses.set(0,juce::AudioChannelSet::stereo());
        if(!p.setBusesLayout(layout)){
            if(!layout.inputBuses.isEmpty())layout.inputBuses.set(0,juce::AudioChannelSet::mono());
            if(!layout.outputBuses.isEmpty())layout.outputBuses.set(0,juce::AudioChannelSet::mono());
            if(!p.setBusesLayout(layout)){copyText("Plugin does not support the host's mono/stereo configuration",error,capacity);return nullptr;}
        }
        host->inputs=p.getTotalNumInputChannels();host->outputs=p.getTotalNumOutputChannels();
        if(host->inputs>2||host->outputs<1||host->outputs>2){copyText("This plugin requires unsupported multichannel routing",error,capacity);return nullptr;}
        host->maximum=maximum;host->clock.rate=rate;host->buffer.setSize(2,maximum);host->midi.ensureSize(65536);
        p.setPlayHead(&host->clock);p.setRateAndBufferSizeDetails(rate,maximum);p.prepareToPlay(rate,maximum);
        return host.release();
    }catch(const std::exception& e){copyText(e.what(),error,capacity);}catch(...){copyText("Native plugin initialization failed",error,capacity);}return nullptr;
}
void lp_close(LPHost* h){if(!h)return;if(juce::MessageManager::getInstance()->isThisTheMessageThread())delete h;else juce::MessageManager::callAsync([h]{delete h;});}
int lp_midi(LPHost* h,uint8_t status,uint8_t a,uint8_t b){
    if(!h)return -1;uint64_t pos=h->enqueue.load(std::memory_order_relaxed);
    for(;;){auto& slot=h->queue[pos%h->queue.size()];const auto seq=slot.sequence.load(std::memory_order_acquire);const auto delta=int64_t(seq)-int64_t(pos);
        if(delta==0){if(h->enqueue.compare_exchange_weak(pos,pos+1,std::memory_order_relaxed)){slot.bytes={status,a,b};slot.sequence.store(pos+1,std::memory_order_release);return 0;}}
        else if(delta<0)return -2;else pos=h->enqueue.load(std::memory_order_relaxed);
    }
}
int lp_process(LPHost* h,float* left,float* right,int frames,int instrument){
    if(!h||!left||!right||frames<0||frames>h->maximum)return -1;
    juce::ScopedNoDenormals noDenormals;const juce::ScopedTryLock lock(h->processor->getCallbackLock());
    if(!lock.isLocked())return 1;
    auto* l=h->buffer.getWritePointer(0);auto* r=h->buffer.getWritePointer(1);
    if(instrument){juce::FloatVectorOperations::clear(l,frames);juce::FloatVectorOperations::clear(r,frames);}
    else if(h->inputs==1){for(int i=0;i<frames;i++)l[i]=(left[i]+right[i])*.5f;juce::FloatVectorOperations::clear(r,frames);}
    else {juce::FloatVectorOperations::copy(l,left,frames);juce::FloatVectorOperations::copy(r,right,frames);}
    h->midi.clear();
    while(true){auto& slot=h->queue[h->dequeue%h->queue.size()];if(slot.sequence.load(std::memory_order_acquire)!=h->dequeue+1)break;
        h->midi.addEvent(slot.bytes.data(),3,0);slot.sequence.store(h->dequeue+h->queue.size(),std::memory_order_release);++h->dequeue;}
    float* channels[]={l,r};juce::AudioBuffer<float> view(channels,std::max(h->inputs,h->outputs),frames);
    try {h->processor->processBlock(view,h->midi);}catch(...){return -3;}
    for(int i=0;i<frames;i++){if(!std::isfinite(l[i])||!std::isfinite((h->outputs>1?r:l)[i]))return -4;}
    juce::FloatVectorOperations::copy(left,l,frames);juce::FloatVectorOperations::copy(right,h->outputs>1?r:l,frames);
    h->clock.samples+=frames;h->clock.ppq.store(h->clock.ppq.load()+double(frames)/h->clock.rate*h->clock.bpm.load()/60);return 0;
}
int lp_editor(LPHost* h){if(!h||!juce::MessageManager::getInstance()->isThisTheMessageThread())return -1;try{if(!h->window)h->window=std::make_unique<EditorWindow>(*h->processor);h->window->setVisible(true);h->window->toFront(true);return 0;}catch(...){return -2;}}
void lp_hide_editor(LPHost* h){if(h&&h->window)h->window->setVisible(false);}
int lp_editor_visible(LPHost* h){return h&&h->window&&h->window->isVisible()?1:0;}
int lp_param_count(LPHost* h){return h?h->processor->getParameters().size():0;}
int lp_param_info(LPHost* h,int index,char* id,int idCapacity,char* name,int nameCapacity){
    if(!h||!juce::isPositiveAndBelow(index,h->processor->getParameters().size()))return -1;
    auto* p=h->processor->getParameters()[index];
    auto* identified=dynamic_cast<juce::HostedAudioProcessorParameter*>(p);
    copyText(identified?identified->getParameterID():juce::String(index),id,idCapacity);copyText(p->getName(256),name,nameCapacity);return 0;
}
float lp_get(LPHost* h,int index){return h&&juce::isPositiveAndBelow(index,h->processor->getParameters().size())?h->processor->getParameters()[index]->getValue():0;}
int lp_set(LPHost* h,int index,float value){if(!h||!std::isfinite(value)||!juce::isPositiveAndBelow(index,h->processor->getParameters().size()))return -1;h->processor->getParameters()[index]->setValueNotifyingHost(juce::jlimit(0.f,1.f,value));return 0;}
int lp_state(LPHost* h,void* destination,int capacity){if(!h)return -1;const juce::ScopedLock lock(h->processor->getCallbackLock());juce::MemoryBlock data;h->processor->getStateInformation(data);if(data.getSize()>64*1024*1024)return -1;if(destination && capacity>=int(data.getSize()))std::memcpy(destination,data.getData(),data.getSize());return int(data.getSize());}
int lp_restore(LPHost* h,const void* data,int bytes){if(!h||!data||bytes<1||bytes>64*1024*1024)return -1;const juce::ScopedLock lock(h->processor->getCallbackLock());h->processor->setStateInformation(data,bytes);return 0;}
int lp_latency(LPHost* h){return h?h->processor->getLatencySamples():0;}
int lp_is_instrument(LPHost* h){return h&&(h->processor->getPluginDescription().isInstrument)?1:0;}
void lp_transport(LPHost* h,double bpm,double ppq,int playing){if(h&&std::isfinite(bpm)&&std::isfinite(ppq)){h->clock.bpm.store(juce::jlimit(20.,400.,bpm));h->clock.ppq.store(ppq);h->clock.playing.store(playing!=0);}}

extern "C" void lp_set_timeline_seconds(LPHost* h, double seconds) { if (h && std::isfinite(seconds)) h->clock.samples = int64_t(std::llround(seconds * h->clock.rate)); }
