// Faithful port of Sources/LemmingsStudio/Instruments/Drums.swift: DrumVoice.
#include "drums.h"
#include <cmath>
#include <initializer_list>
#include <numbers>
namespace {
class DrumVoice {
    double sr, t = 0, phase = 0;
    bool active = true;
    std::uint32_t id;
    LSDrumParams p;
    float noiseLP = 0;
    std::uint64_t rng = 0x9E3779B97F4A7C15ULL;
    float noise() noexcept {
        rng = rng * 6364136223846793005ULL + 1442695040888963407ULL;
        const double unit = double(rng >> 33) / double((std::uint64_t(1) << 31)-1);
        return float(unit * 2.0 - 1.0);
    }
    float env(double tau) const noexcept { return float(std::exp(-t/(tau*p.decay))); }
public:
    DrumVoice(std::uint32_t voice, double rate, LSDrumParams params): sr(rate), id(voice), p(params) {}
    float render() noexcept {
        if (!active) return 0;
        const double dt = 1.0/sr, pi = std::numbers::pi;
        float s = 0;
        switch (id) {
        case 0: {
            const double f0 = 52.0*p.tune, pitchEnv = 1.0+6.0*std::exp(-t/0.012);
            phase += 2*pi*f0*pitchEnv*dt;
            s = float(std::sin(phase))*env(0.16);
            s += noise()*env(0.004)*0.6f;
            break;
        }
        case 1:
            phase += 2*pi*(44.0*p.tune)*(1+2*std::exp(-t/0.03))*dt;
            s = float(std::sin(phase))*env(0.5);
            s = std::tanh(s*1.6f*p.drive);
            break;
        case 2: {
            const float body = float(std::sin(2*pi*190*p.tune*t))*env(0.09);
            const float n = noise()*env(0.12);
            s = body*0.5f+n*0.7f;
            break;
        }
        case 3: {
            float c = 0;
            for (double b : {0.0, 0.009, 0.018}) if (t >= b) c += noise()*float(std::exp(-(t-b)/0.012));
            c += noise()*env(0.12)*0.5f;
            s = c*0.6f;
            break;
        }
        case 4: {
            const float tone = float(std::sin(2*pi*1700*t));
            const float n = noise();
            s = (tone+n*0.5f)*env(0.012);
            break;
        }
        case 5: case 6:
            noiseLP = noiseLP*0.5f+noise()*0.5f;
            s = (noise()-noiseLP)*env((id == 5 ? 0.025 : 0.35)*p.tone);
            break;
        case 7:
            phase += 2*pi*(120.0*p.tune)*(1+1.5*std::exp(-t/0.04))*dt;
            s = float(std::sin(phase))*env(0.22);
            break;
        case 8: {
            float r = 0;
            for (double h : {1.0, 1.34, 1.71, 2.4}) r += float(std::sin(2*pi*520*h*t));
            s = (r*0.25f+noise()*0.3f)*env(0.5*p.tone);
            break;
        }
        case 9:
            noiseLP = noiseLP*0.3f+noise()*0.7f;
            s = (noise()-noiseLP*0.5f)*env(0.8*p.tone);
            break;
        }
        s = std::tanh(s*p.drive)*p.level*p.velocity;
        t += dt;
        if ((id == 5 && t > 0.12*p.decay*p.tone) ||
            (id == 6 && t > 0.38*p.decay*p.tone) ||
            (id == 8 && t > 0.55*p.decay*p.tone) ||
            (id == 9 && t > 0.65*p.decay*p.tone)) active = false;
        if (t > 1.25 || (env(0.35) < 1e-4f && t > 0.1)) active = false;
        return s;
    }
};
}
std::uint32_t ls_audio_abi_version() noexcept { return 1; }
int ls_render_drum(std::uint32_t voice, double rate, const LSDrumParams* p,
                   float* output, std::uint32_t frames) noexcept {
    if (!p || !output || voice > 9 || !std::isfinite(rate) || rate < 8000 || rate > 192000) return -1;
    if (!std::isfinite(p->tune) || p->tune <= 0 || p->tune > 16 ||
        !std::isfinite(p->decay) || p->decay <= 0 || p->decay > 16 ||
        !std::isfinite(p->tone) || p->tone <= 0 || p->tone > 16 ||
        !std::isfinite(p->drive) || p->drive < 0 || p->drive > 32 ||
        !std::isfinite(p->level) || p->level < 0 || p->level > 4 ||
        !std::isfinite(p->velocity) || p->velocity < 0 || p->velocity > 1) return -1;
    DrumVoice state(voice, rate, *p);
    for (std::uint32_t i = 0; i < frames; ++i) output[i] = state.render();
    return 0;
}
