import os
from pathlib import Path
import numpy as np
import pytest
from lemmings_studio.native_audio import NativeAudio


@pytest.fixture(scope='module')
def engine():
    path = os.environ.get('LEMMINGS_NATIVE_LIBRARY')
    if not path:
        pytest.skip('Native ABI tests require the compiled library')
    return NativeAudio(Path(path))


@pytest.mark.parametrize('rate', [44100, 48000, 96000])
@pytest.mark.parametrize('voice', range(10))
@pytest.mark.parametrize('profile', [0, 1])
def test_actual_swift_drum_voice_parity(engine, rate, voice, profile):
    root = os.environ.get('LEMMINGS_SWIFT_DRUM_REFERENCE')
    if not root:
        pytest.skip('Numerical comparisons require the actual Swift reference renderer')
    reference = np.fromfile(Path(root)/f'{rate}-{profile}-{voice}.f32', dtype='<f4')
    params = {} if profile == 0 else dict(tune=.83, decay=.7, tone=1.2, drive=1.7, level=.6)
    native = engine.render_drum(voice, rate, len(reference), **params)
    np.testing.assert_allclose(native, reference, atol=2e-6, rtol=2e-5)
    assert np.isfinite(native).all()
    assert np.max(np.abs(native)) > .01
    if voice in (5, 6, 8, 9):
        assert np.max(np.abs(native[-100:])) == 0


def test_native_parameters_reject_invalid_values(engine):
    for params in [dict(tune=0), dict(decay=float('nan')), dict(velocity=2)]:
        with pytest.raises(ValueError):
            engine.render_drum(0, 48000, 128, **params)
    with pytest.raises(ValueError):
        engine.render_drum(10, 48000, 128)


def test_kick_and_sub_are_distinct_native_voices(engine):
    kick = engine.render_drum(0, 48000, 48000)
    sub = engine.render_drum(1, 48000, 48000)
    assert not np.array_equal(kick, sub)
    assert np.mean(kick[24000:]**2) < np.mean(sub[24000:]**2)


@pytest.mark.parametrize('rate',[44100,48000,96000])
def test_actual_swift_kit_retrigger_parity(engine,rate):
    from lemmings_studio.workspace_audio import REFERENCE
    root=os.environ.get('LEMMINGS_SWIFT_DRUM_REFERENCE')
    if not root:pytest.skip('Requires real Swift kit reference')
    reference=np.fromfile(Path(root)/f'kit-{rate}.f32',dtype='<f4')
    events=[(i*int(rate*.007),i%10,.5+(i%5)*.1) for i in range(80)]
    result=engine.render_kit(rate,len(reference),events,REFERENCE['drumKits']['Rock'])
    np.testing.assert_allclose(result,reference,atol=3e-6,rtol=3e-5)


@pytest.mark.parametrize('rate',[44100,48000,96000])
@pytest.mark.parametrize('profile',[0,1])
def test_original_master_limiter(engine,rate,profile):
    root=os.environ.get('LEMMINGS_SWIFT_DRUM_REFERENCE')
    if not root:pytest.skip('Requires real Swift limiter reference')
    root=Path(root)
    signal=np.fromfile(root/f'limiter-input-{rate}.f32',dtype='<f4').reshape(-1,2)
    reference=np.fromfile(root/f'limiter-{rate}-{profile}.f32',dtype='<f4').reshape(-1,2)
    params=dict(ceiling=-.3,threshold=-1,release=90,lookahead=3,softclip=.15,output=0)
    if profile:params.update(ceiling=-2,threshold=-8,release=120,lookahead=5,softclip=.7,output=-1)
    result=engine.apply_limiter(signal,rate,params)
    np.testing.assert_allclose(result,reference,atol=3e-6,rtol=3e-5)
