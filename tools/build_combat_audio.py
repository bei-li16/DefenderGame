"""Rebuild recorded combat foley; runtime has no Python/network dependency.

Dependencies: numpy, scipy, soundfile. Source credits/hashes: audio_sources/sources.json.
Run from any directory. Outputs mono 44.1 kHz PCM16 WAVs with explicit fades.
"""
from pathlib import Path
from fractions import Fraction
import hashlib
import json
import numpy as np
from scipy import signal
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'tools/audio_sources'
OUTPUT = ROOT / 'Gamematerials/Audio'
REVIEW = ROOT / 'Builds/audio-review'
RATE = 44100


def read(name):
    data, rate = sf.read(SOURCES / name, always_2d=True)
    data = data.mean(axis=1)
    if rate != RATE:
        ratio = Fraction(RATE, rate)
        data = signal.resample_poly(data, ratio.numerator, ratio.denominator)
    return data


def cut(data, start, end):
    return data[round(start * RATE):round(end * RATE)].copy()


def speed(data, factor):
    ratio = Fraction(1 / factor).limit_denominator(1000)
    return signal.resample_poly(data, ratio.numerator, ratio.denominator)


def band(data, low=50, high=9000):
    return signal.sosfilt(signal.butter(2, [low, high], 'bandpass', fs=RATE, output='sos'), data)


def unit(data):
    return data / max(float(np.max(np.abs(data))), 1e-8)


def fade(data, attack=.002, release=.06):
    data = data.copy()
    a, r = min(len(data), round(attack * RATE)), min(len(data), round(release * RATE))
    if a: data[:a] *= np.linspace(0, 1, a)
    if r: data[-r:] *= np.linspace(1, 0, r) ** 1.5
    return data


def mix(duration, *layers):
    result = np.zeros(round(duration * RATE))
    for data, offset, gain in layers:
        offset = round(offset * RATE)
        count = min(len(data), len(result) - offset)
        if count > 0: result[offset:offset + count] += data[:count] * gain
    return result


def finish(data, peak, release=.08, attack=.001):
    # A gentle offline crest reduction preserves foley body without hard clipping.
    data = band(data, 35, 10000)
    data = np.tanh(unit(data) * 1.2)
    data = fade(data, attack, release)
    data = unit(data) * peak
    data[0] = data[-1] = 0
    return data


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    bow = read('crossbow_dryshot.flac')
    target = read('crossbow_shot_and_hit.flac')
    flame = read('flame.ogg')
    torch = read('waving-torch.wav')
    crackle = read('fire-crackle.wav')
    cold = read('icespells-ice.wav')
    snap = read('icespells-coldsnap.wav')
    thunder = read('thunderclap.mp3')
    ice_names = ['IceShatters-LedasLuzta.ogg', 'IceShatters-LedasLuzta33.ogg', 'IceShatters-LedasLuzta4.ogg']
    results = {}
    for variant in range(3):
        # Only the dry release: never embed a target hit into the firing cue.
        release = unit(band(speed(cut(bow, .023, .215), [.87, .92, .98][variant]), 95, 6800))
        results[f'shot-{variant + 1:02}'] = finish(release, .54, .055, .0006)
        # Actual bolt hitting the target starts after the separate string transient.
        impact = unit(band(speed(cut(target, .108, .40), [.94, 1.0, 1.06][variant]), 110, 5800))
        results[f'hit-{variant + 1:02}'] = finish(impact, .46, .085)

        wind_start = [1.97, 3.53, .28][variant]
        wind = unit(band(cut(torch, wind_start, wind_start + .38), 90, 6500))
        ignition = unit(speed(flame, [.98, 1.04, 1.09][variant]))
        launch = mix(.40, (fade(wind, .01, .08), 0, .8), (fade(ignition, .04, .14), 0, .20))
        results[f'fire_launch-{variant + 1:02}'] = finish(launch, .40, .07, .006)
        roar = unit(band(speed(cut(torch, [2.12, 3.68, 2.16][variant], [2.73, 4.26, 2.78][variant]), .70), 55, 5200))
        burn = unit(cut(crackle, [.42, .77, 1.55][variant], [1.52, 1.87, 2.65][variant]))
        burn *= np.exp(-np.arange(len(burn)) / RATE * 2.4)
        blast = mix(1.08, (fade(roar, .002, .25), 0, .85), (fade(ignition, .002, .15), 0, .42), (burn, .06, .21))
        results[f'fire-{variant + 1:02}'] = finish(blast, .64, .22)

        # Crystalline friction on approach, then irregular recorded fractures.
        grow = unit(band(speed(cut(cold, .05 + variant * .015, .35 + variant * .015)[::-1], 1.0), 750, 9000))
        results[f'ice_launch-{variant + 1:02}'] = finish(fade(grow, .035, .06), .32, .06, .025)
        shards = read(ice_names[variant])
        start = [0, .057, .067][variant]
        shards = unit(band(speed(cut(shards, start, start + .82), [.96, 1.02, .98][variant]), 140, 8800))
        fragments = unit(band(cut(cold, .23, .86), 750, 7800))
        fracture = mix(.88, (fade(shards, .0006, .14), 0, .84), (fade(unit(cut(snap, 0, .13)), .0006, .045), 0, .18), (fade(fragments, .025, .20), .11, .13))
        results[f'ice-{variant + 1:02}'] = finish(fracture, .57, .15, .0007)

        # A short broadband leader before contact; no oscillators/chirped notes.
        leader = unit(band(cut(thunder, [.91, 1.06, 1.43][variant], [1.07, 1.22, 1.59][variant]), 1500, 10000))
        results[f'lightning_launch-{variant + 1:02}'] = finish(fade(leader, .02, .035), .28, .045, .014)
        strike_start = [2.139, 1.275, 3.365][variant]
        strike = unit(band(cut(thunder, strike_start, strike_start + .34), 150, 9500))
        rolling = unit(band(cut(thunder, strike_start + .045, strike_start + 1.4), 40, 1500))
        rolling *= np.exp(-np.arange(len(rolling)) / RATE * 2.4)
        bolt = mix(1.38, (fade(strike, .0006, .11), 0, .80), (fade(rolling, .016, .35), .016, .64))
        results[f'lightning-{variant + 1:02}'] = finish(bolt, .68, .30, .0006)

    report = []
    for name, data in sorted(results.items()):
        path = OUTPUT / (name + '.wav')
        sf.write(path, data, RATE, subtype='PCM_16')
        import_path = path.with_suffix('.wav.import')
        if import_path.exists():
            # Keep the bow snap/ice transients as PCM, not Godot's default QOA.
            metadata = import_path.read_text(encoding='utf-8')
            metadata = metadata.replace('compress/mode=2', 'compress/mode=0').replace('compress/mode=1', 'compress/mode=0')
            import_path.write_text(metadata, encoding='utf-8')
        report.append(dict(file=path.name, seconds=round(len(data) / RATE, 4), peak_db=round(20 * np.log10(np.max(np.abs(data))), 2), rms_db=round(20 * np.log10(np.sqrt(np.mean(data * data))), 2), bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    (REVIEW / 'asset-analysis.json').write_text(json.dumps(report, indent=2) + '\n')
    # A concise dry audition: bow/target, fire, ice, lightning. No music masks timbre.
    reel = np.zeros(RATE * 11)
    timeline = [('shot', .3), ('hit', .6), ('shot', 1.1), ('hit', 1.4), ('fire_launch', 2.1), ('fire', 2.7), ('ice_launch', 4.55), ('ice', 5.15), ('lightning_launch', 6.85), ('lightning', 7.1833), ('lightning', 8.8)]
    for i, (kind, seconds) in enumerate(timeline):
        clip = results[f'{kind}-{i % 3 + 1:02}']
        offset = round(seconds * RATE)
        reel[offset:offset + len(clip)] += clip * .80
    sf.write(REVIEW / 'new-combat-foley.wav', reel, RATE, subtype='PCM_16')
    print(json.dumps({'clips': len(report), 'pcm_bytes': sum(item['bytes'] for item in report), 'output': str(OUTPUT)}, indent=2))


if __name__ == '__main__':
    build()
