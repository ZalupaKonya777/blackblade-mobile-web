#!/usr/bin/env python3
"""Rebuild the compact BLACKBLADE battle bank from two pinned CC0 Kenney packs.

Requires Python 3, numpy, scipy, ffmpeg. In this workspace:
  PYTHONDONTWRITEBYTECODE=1 /root/.venvs/analysis/bin/python -B tools/build_battle_audio.py

Downloads, decoded intermediates and previews stay in .runtime/audio_work/.
The music, creature voice, air movement and resonators are original synthesis.
No game recordings, speech, pretrained music models or proprietary libraries.
"""

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import subprocess
import urllib.request
import wave
import zipfile

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/battle"
WORK = ROOT / ".runtime/audio_work"
REPORT = ROOT / "artifacts/audio_bank.json"
SR = 32000
SEED = 20261023
SYNTH = "Original procedural synthesis and arrangement (CC0-1.0)"
PACKS = {
    "impact": {
        "title": "Kenney Impact Sounds 1.0",
        "page": "https://kenney.nl/assets/impact-sounds",
        "url": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
        "sha256": "029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8",
    },
    "rpg": {
        "title": "Kenney RPG Audio",
        "page": "https://kenney.nl/assets/rpg-audio",
        "url": "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
        "sha256": "6dbeaf8544da958d8f2adcb4a4a4b76c1ade34a05f8ab9edccd327da7375f38b",
    },
}
CACHE = {}
SOURCES = set()
RNG = np.random.default_rng(SEED)


def run(args, data=None):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", TMPDIR=str(WORK))
    p = subprocess.run(args, input=data, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, env=env, check=False)
    if p.returncode:
        raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout


def ensure_sources():
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for key, spec in PACKS.items():
        archive = WORK / (key + ".zip")
        if not archive.exists():
            data = urllib.request.urlopen(spec["url"], timeout=60).read()
            archive.write_bytes(data)
        data = archive.read_bytes()
        if hashlib.sha256(data).hexdigest() != spec["sha256"]:
            raise RuntimeError("Source checksum changed: " + key)
        folder = WORK / "raw" / key
        folder.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for name in z.namelist():
                if name.startswith("Audio/") and name.endswith(".ogg"):
                    path = folder / Path(name).name
                    if not path.exists():
                        path.write_bytes(z.read(name))
            (folder / "License.txt").write_bytes(z.read("License.txt"))


def decode(path, channels=1):
    data = run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path),
                "-ac", str(channels), "-ar", str(SR), "-f", "f32le", "pipe:1"])
    a = np.frombuffer(data, dtype="<f4").astype(np.float64)
    return a if channels == 1 else a.reshape(-1, channels)


def db(x):
    return float(20 * np.log10(max(float(x), 1e-12)))


def metrics(x):
    return {"peak_dbfs": round(db(np.max(np.abs(x))), 3),
            "rms_dbfs": round(db(np.sqrt(np.mean(x * x))), 3),
            "dc_dbfs": round(db(abs(np.mean(x))), 3)}


def true_peak(x):
    return db(np.max(np.abs(signal.resample_poly(x, 4, 1, axis=0))))


def lp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, fs=SR, output="sos"), x, axis=0)


def hp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, fs=SR, btype="highpass", output="sos"), x, axis=0)


def bp(x, low, high):
    return lp(hp(x, low), high)


def fade(x, attack=.002, release=.018):
    x = x.copy()
    na = min(int(attack * SR), len(x) // 2)
    nr = min(int(release * SR), len(x) // 2)
    dims = (slice(None),) + (None,) * (x.ndim - 1)
    if na:
        x[:na] *= (np.sin(np.linspace(0, np.pi / 2, na)) ** 2)[dims]
    if nr:
        x[-nr:] *= (np.sin(np.linspace(np.pi / 2, 0, nr)) ** 2)[dims]
    return x


def speed(x, ratio):
    if ratio == 1:
        return x.copy()
    # This operation intentionally changes both timing and pitch, like playback.
    count = max(2, int(len(x) / ratio))
    return signal.resample(x, count)


def source(pack, name, ratio=1):
    SOURCES.add(PACKS[pack]["title"] + "/Audio/" + name + ".ogg")
    key = (pack, name)
    if key not in CACHE:
        x = hp(decode(WORK / "raw" / pack / (name + ".ogg")), 35)
        peak = np.max(np.abs(x))
        ids = np.flatnonzero(np.abs(x) > peak * .002)
        if len(ids):
            x = x[max(0, ids[0] - 128):min(len(x), ids[-1] + 1 + 320)]
        # Decode to float first: the original Vorbis files can overshoot 0 dBFS.
        x = fade(x / max(peak, 1e-9), .001, .012)
        CACHE[key] = x
    return speed(CACHE[key], ratio)


def mix(*layers):
    """Layers are (mono waveform, offset in seconds, linear gain)."""
    n = max(int(round(t * SR)) + len(x) for x, t, gain in layers)
    out = np.zeros(n, dtype=np.float64)
    for x, t, gain in layers:
        k = int(round(t * SR))
        out[k:k + len(x)] += x * gain
    return out


def room(x, wet=.13, scale=1):
    taps = [(0.023, .55), (.047, .32), (.079, .21), (.127, .12), (.189, .07)]
    dull = lp(x, 4600)
    return mix((x, 0, 1), *[(dull, t * scale, wet * gain) for t, gain in taps])


def noise(duration, low=100, high=5000):
    SOURCES.add(SYNTH)
    return bp(RNG.normal(0, 1, int(duration * SR)), low, high)


def whoosh(duration=.36, heavy=1):
    t = np.arange(int(duration * SR)) / SR
    u = t / duration
    env = np.sin(np.pi * u) ** 1.7
    air = noise(duration, 280 / heavy, min(9200, 6800 / heavy))
    body = noise(duration, 70, 650 / math.sqrt(heavy))
    return fade((air * (.3 + .7 * u) + .6 * heavy * body) * env, .004, .03)


def thud(duration=.32, base=88):
    SOURCES.add(SYNTH)
    t = np.arange(int(duration * SR)) / SR
    f = base + base * .95 * np.exp(-t * 34)
    phase = np.cumsum(f) * (2 * np.pi / SR)
    env = (1 - np.exp(-t * 900)) * np.exp(-t * (11 / max(.7, duration / .3)))
    tone = np.sin(phase) + .3 * np.sin(phase * 2.01)
    grit = noise(duration, 100, 1200) * np.exp(-t * 38)
    return fade((tone + .3 * grit) * env, .0015, .03)


def ring(duration=.55, hz=1250):
    SOURCES.add(SYNTH)
    t = np.arange(int(duration * SR)) / SR
    x = np.zeros(len(t))
    for k, (ratio, gain) in enumerate([(1, 1), (1.47, .45), (2.09, .25), (2.71, .15)]):
        x += gain * np.sin(2 * np.pi * hz * ratio * t) * np.exp(-t * (6 + k * 3))
    return fade(x, .001, .05)


def water(duration=.7):
    t = np.arange(int(duration * SR)) / SR
    x = noise(duration, 500, 6200) * .06
    for at, hz, length in [(.02, 710, .10), (.17, 610, .13), (.34, 900, .09), (.45, 570, .16)]:
        tt = np.arange(int(length * SR)) / SR
        f = hz * np.exp(-tt * 4.5)
        pulse = np.sin(np.cumsum(f) * 2 * np.pi / SR) * np.sin(np.pi * tt / length) ** 2
        k = int(at * SR)
        x[k:k + len(pulse)] += pulse * .24
    return fade(x, .015, .06)


def creature(duration=1.65, variant=0):
    SOURCES.add(SYNTH)
    t = np.arange(int(duration * SR)) / SR
    f = (78 + variant * 7) * (1.16 - .4 * t / duration)
    f *= 1 + .027 * np.sin(2 * np.pi * 7.3 * t) + .018 * lp(RNG.normal(0, 1, len(t)), 30)
    phase = np.cumsum(f) * 2 * np.pi / SR
    throat = signal.sawtooth(phase) * .7 + signal.sawtooth(phase * 1.013 + .7) * .3
    # Inharmonic growl plus formants; there is no recorded human voice.
    rasp = throat * (.7 + .3 * np.sin(2 * np.pi * 31.7 * t))
    x = lp(rasp, 310) * .8 + bp(rasp, 350, 630) * .8 + bp(rasp, 920, 1450) * .5
    x += noise(duration, 100, 3500) * (.16 + .1 * np.sin(2 * np.pi * 12 * t))
    env = (1 - np.exp(-t * 26)) * np.sin(np.pi * t / duration) ** .55
    x *= env * (.86 + .14 * np.sin(2 * np.pi * 4.4 * t))
    return room(fade(np.tanh(x * 1.4), .025, .11), .22, 1.7)


def make_sfx(event, variant):
    i = variant % 5
    concrete = lambda ratio=1: source("impact", f"footstep_concrete_{i:03d}", ratio)
    metal = lambda weight="medium", ratio=1: source("impact", f"impactMetal_{weight}_{i:03d}", ratio)
    plate = lambda weight="light", ratio=1: source("impact", f"impactPlate_{weight}_{i:03d}", ratio)
    punch = lambda weight="heavy", ratio=1: source("impact", f"impactPunch_{weight}_{i:03d}", ratio)
    soft = lambda ratio=1: source("impact", f"impactSoft_heavy_{i:03d}", ratio)
    cloth = lambda ratio=1: source("rpg", f"cloth{variant % 4 + 1}", ratio)
    mine = lambda ratio=1: source("impact", f"impactMining_{i:03d}", ratio)
    if event in ("knight_swing", "knight_heavy", "boss_swing"):
        heavy = {"knight_swing": 1, "knight_heavy": 1.35, "boss_swing": 1.9}[event]
        duration = (.29 + variant * .018) * heavy
        knife = source("rpg", "knifeSlice" + ("2" if i % 2 else ""), 1.27 / heavy)
        x = mix((whoosh(duration, heavy), 0, 1), (knife, .015, .28),
                (cloth(1.12 / math.sqrt(heavy)), 0, .16),
                (source("rpg", f"drawKnife{i % 3 + 1}", 1 / heavy), .005, .10))
        if event == "boss_swing":
            x = mix((x, 0, 1), (whoosh(duration * .65, 2.8), duration * .14, .38))
        return room(x, .08, .8)
    if event == "step":
        return room(mix((concrete(1 + variant * .008), 0, 1),
                        (source("rpg", "beltHandle1" if i % 2 else "beltHandle2", 1.1), .012, .13),
                        (thud(.17, 143), .003, .28)), .07, .65)
    if event == "boss_step":
        return room(mix((concrete(.68 + variant * .018), 0, .7),
                        (punch("heavy", .74), 0, .38), (thud(.34, 75 + variant * 3), 0, .75),
                        (plate("heavy", .76), .018, .13)), .18, 1.4)
    if event == "armor_takeoff":
        return mix((cloth(1.12), 0, .5), (source("rpg", "clothBelt" + ("2" if i % 2 else "")), 0, .45),
                   (source("rpg", "handleCoins" + ("2" if i % 2 else ""), 1.12), .012, .19),
                   (plate("light", 1.17), .01, .18))
    if event == "body_contact":
        return room(mix((soft(1.11), 0, .68), (cloth(.95), .006, .32),
                        (source("rpg", "dropLeather", 1.0), 0, .22), (thud(.22, 112), 0, .26)), .06)
    if event == "boot_land":
        return room(mix((concrete(.88), 0, 1), (soft(.94), 0, .35),
                        (plate("medium", .9), .015, .2), (thud(.25, 98), .003, .42)), .13)
    if event == "hit":
        return room(mix((punch("medium", .96 + i * .013), 0, 1),
                        (soft(1.05), .008, .30), (cloth(1.3), 0, .12),
                        (thud(.22, 103), .001, .25)), .065)
    if event == "impact_knight":
        return room(mix((metal("heavy", .93 + i * .02), 0, 1),
                        (plate("medium", 1.04), .005, .36), (punch("heavy", .91), .001, .28),
                        (thud(.26, 109), 0, .35)), .19)
    if event == "impact_beast":
        return room(mix((punch("heavy", .76 + i * .018), 0, 1),
                        (source("rpg", "chop", .91 + i * .01), .004, .38),
                        (soft(.86), .007, .25), (thud(.29, 84), .001, .4)), .15)
    if event == "guard":
        return room(mix((metal("medium", .97 + i * .018), 0, .85),
                        (mine(.83), 0, .48), (plate("heavy", .89), .008, .29),
                        (thud(.19, 132), 0, .25)), .22)
    if event == "parry":
        return room(mix((metal("light", 1.12 + i * .025), 0, .8),
                        (mine(1.13 + i * .01), .002, .85),
                        (ring(.67, 1320 + i * 83), .006, .12),
                        (thud(.18, 158), 0, .18)), .21)
    if event == "slam":
        layers = [(concrete(.62), 0, .8), (punch("heavy", .62), 0, .6),
                  (source("impact", f"impactWood_heavy_{i:03d}", .68), .003, .3),
                  (thud(.62, 65 + i * 4), 0, 1.3), (plate("heavy", .7), .012, .15)]
        for k in range(7):
            debris = source("impact", f"footstep_concrete_{(i + k) % 5:03d}", .9 + .045 * k)
            layers.append((debris, .05 + k * .073, .15 * math.exp(-k * .23)))
        grit = noise(.63, 160, 5200) * np.exp(-np.arange(int(.63 * SR)) / SR * 6)
        layers.append((fade(grit, .004, .08), .015, .2))
        return room(mix(*layers), .26, 1.8)
    if event == "flask":
        return room(mix((source("rpg", "handleSmallLeather" + ("2" if i % 2 else ""), 1.08), 0, .28),
                        (source("impact", f"impactGlass_light_{i:03d}", 1.14), .04, .22),
                        (water(.74), .10, 1), (ring(.45, 860 + i * 97), .55, .035)), .06)
    if event == "roar":
        return creature(1.62 + variant * .21, variant)
    if event == "death":
        return room(mix((source("impact", "impactPlate_heavy_003", .65), 0, .7),
                        (source("impact", "impactSoft_heavy_002", .7), .04, .9),
                        (source("rpg", "dropLeather", .7), .19, .43),
                        (source("impact", "impactMetal_medium_001", .79), .26, .46),
                        (source("rpg", "cloth3", .72), .07, .4),
                        (thud(.8, 69), 0, .8), (ring(1.6, 293.665), .03, .05)), .27, 2)
    if event == "win":
        layers = [(thud(.9, 73.416), 0, .15)]
        for at, hz, gain in [(0, 293.665, .5), (.24, 440, .33), (.48, 587.33, .33), (.73, 698.456, .22)]:
            layers.append((ring(2.0, hz), at, gain))
        return room(mix(*layers), .33, 2.1)
    if event == "menu":
        return fade(mix((source("rpg", "metalClick", 1.3 + .06 * i), 0, .6),
                        (source("rpg", "beltHandle1", 1.4), 0, .1),
                        (ring(.105, 960 + i * 140), .001, .035)), .001, .025)
    if event == "projectile":
        return room(mix((whoosh(.42 + i * .04, 1.3), 0, 1),
                        (source("rpg", "knifeSlice2", .89 + i * .03), 0, .16),
                        (ring(.46, 560 + i * 65), .008, .045)), .19, 1.3)
    if event == "blade_drag":
        # Recorded blade friction carries this sound; discard the mining strike's
        # initial hit so that dragging does not become a sequence of hammer blows.
        draw = source("rpg", f"drawKnife{i % 3 + 1}", .45 + i * .025)
        tail = mine(.66 + i * .02)[int(.09 * SR):]
        layers = [(draw, 0, .8), (tail, .04, .13)]
        for k in range(5):
            grit = hp(concrete(.85 + .03 * k), 500)
            layers.append((grit, .08 + k * .16, .065 * (1 - .11 * k)))
        n = noise(1.03 + i * .1, 480, 6500)
        t = np.arange(len(n)) / SR
        irregular = lp(RNG.normal(size=len(n)), 19)
        irregular /= max(np.max(np.abs(irregular)), 1e-10)
        rasp = n * (.45 + .35 * irregular) * np.sin(np.pi * t / (1.03 + i * .1)) ** .55
        layers += [(fade(rasp, .025, .17), 0, .19), (whoosh(.4, 2), .07, .08)]
        return room(mix(*layers), .15, 1.4)
    raise KeyError(event)


COUNTS = {
    "knight_swing": 4, "knight_heavy": 3, "boss_swing": 4, "boss_step": 4,
    "step": 5, "armor_takeoff": 3, "body_contact": 3, "boot_land": 3,
    "hit": 4, "impact_knight": 4, "impact_beast": 4, "guard": 3, "parry": 3,
    "slam": 3, "flask": 2, "roar": 2, "death": 1, "win": 1, "menu": 3,
    "projectile": 3, "blade_drag": 2,
}

SFX_RMS_FLOORS = {
    "step": -24.5, "boss_step": -22.5, "armor_takeoff": -24.5,
    "body_contact": -24, "boot_land": -23.5, "hit": -23.5,
    "impact_knight": -24, "impact_beast": -23.5, "guard": -24,
    "parry": -24, "menu": -26, "knight_swing": -25,
    "knight_heavy": -24.5, "boss_swing": -23.5,
}


def cyclic_add(target, x, at, gain=1, pan=0):
    """Constant-power stereo placement, including tails crossing a loop edge."""
    start = int(round(at * SR)) % len(target)
    weights = np.array([math.sqrt((1 - pan) / 2), math.sqrt((1 + pan) / 2)])
    x = x[:, None] * (weights * gain)
    first = min(len(x), len(target) - start)
    target[start:start + first] += x[:first]
    if first < len(x):
        target[:len(x) - first] += x[first:]


def periodic_noise(n, low, high):
    SOURCES.add(SYNTH)
    f = np.fft.rfftfreq(n, 1 / SR)
    spectrum = RNG.normal(size=len(f)) + 1j * RNG.normal(size=len(f))
    weight = (1 - np.exp(-(f / low) ** 4)) * np.exp(-(f / high) ** 4)
    x = np.fft.irfft(spectrum * weight, n=n)
    return x / max(np.sqrt(np.mean(x * x)), 1e-10)


def make_music(phase):
    duration, beat = 36.0, .75
    n = int(duration * SR)
    t = np.arange(n) / SR
    x = np.zeros((n, 2))
    # Both 80 BPM / 4-4 / 12-bar loops share the same D-minor pedal and harmony.
    for hz, level, detune in [(73.4162, .095, 0), (146.8324, .055, 1), (110, .037, 2)]:
        k = round(hz * duration)
        for channel in range(2):
            p = 2 * np.pi * (k + (channel * 2 - 1) * detune) * t / duration
            x[:, channel] += np.sin(p + .2 * channel) * level * (1 + .15 * np.sin(2 * np.pi * t / 9))
            x[:, channel] += np.sin(p * 2 + .3) * level * .3
    harmony = [(50, 53, 57), (46, 53, 58), (48, 55, 60), (50, 53, 57)] * 3
    for bar, chord in enumerate(harmony):
        for voice, midi in enumerate(chord):
            d = 4.25
            tt = np.arange(int(d * SR)) / SR
            f = 440 * 2 ** ((midi - 69) / 12)
            p = 2 * np.pi * f * tt
            pad = (np.sin(p) + .22 * np.sin(2 * p + .4) + .10 * np.sin(3 * p + .8))
            pad += .18 * np.sin(p * 1.0021 + .7) + .14 * np.sin(p * .9978 + 1.8)
            pad *= np.sin(np.pi * tt / d) ** 1.35
            cyclic_add(x, pad, bar * 3 - .6, .04 if phase == 1 else .044, (voice - 1) * .65)
    for bar in range(12):
        drum = mix((thud(.71, 63 + bar % 3 * 2), 0, .65),
                   (source("impact", f"impactPunch_heavy_{bar % 5:03d}", .59), 0, .2),
                   (source("impact", f"impactWood_heavy_{bar % 5:03d}", .66), .006, .09))
        drum = room(lp(drum, 1900), .32, 2.2)
        drum /= max(np.max(np.abs(drum)), 1e-9)
        hits = [(0, .39), (2.0, .23)] if phase == 1 else [(0, .43), (1.5, .24), (2, .33), (3.5, .19)]
        for b, gain in hits:
            cyclic_add(x, drum, (bar * 4 + b) * beat, gain, .10 * (-1 if bar % 2 else 1))
        if phase == 2 or bar % 2:
            strike = source("impact", f"impactMetal_light_{bar % 5:03d}", .73)
            strike = room(lp(strike, 3900), .3, 1.8)
            for b in ([1, 3] if phase == 2 else [3]):
                cyclic_add(x, strike, (bar * 4 + b) * beat, .045 if phase == 2 else .03, (-1 if bar % 2 else 1) * .5)
        if phase == 2:
            for eighth in [0, 2, 3, 4, 6, 7]:
                midi = [38, 38, 45, 38, 41, 45, 38, 45][eighth]
                f = 440 * 2 ** ((midi - 69) / 12)
                tt = np.arange(int(.34 * SR)) / SR
                p = 2 * np.pi * f * tt
                pulse = (np.sin(p) + .3 * np.sin(2 * p) + .18 * np.sin(3 * p))
                pulse *= (1 - np.exp(-tt * 170)) * np.exp(-tt * 14)
                cyclic_add(x, pulse, (bar * 4 + eighth * .5) * beat, .065, .17 * (-1 if eighth % 2 else 1))
        if bar % 3 == 2:
            cyclic_add(x, room(ring(2.3, 587.33), .36, 2.3), bar * 3 + 1.5, .018, .4)
    air = periodic_noise(n, 250, 2100)
    x[:, 0] += air * (.008 + .004 * np.sin(2 * np.pi * t / 12))
    x[:, 1] += np.roll(air, int(.019 * SR)) * (.008 + .004 * np.sin(2 * np.pi * t / 12 + .7))
    # Circular diffuse stone reflections: no truncated reverb tails at bar twelve.
    x += .11 * np.roll(x, int(.137 * SR), axis=0)[:, ::-1]
    x += .055 * np.roll(x, int(.251 * SR), axis=0)
    return fade(hp(lp(x, 8800), 31), .004, .004)


def make_ambient():
    duration = 18.0
    n = int(duration * SR)
    t = np.arange(n) / SR
    x = np.zeros((n, 2))
    wind = periodic_noise(n, 70, 1650)
    low = periodic_noise(n, 32, 210)
    shimmer = periodic_noise(n, 900, 3600)
    for channel in range(2):
        breath = .15 + .055 * np.sin(2 * np.pi * t / 9 + channel * .5)
        breath += .022 * np.sin(2 * np.pi * t / 6 + .6)
        x[:, channel] = np.roll(wind, channel * int(.026 * SR)) * breath
        x[:, channel] += np.roll(low, channel * 503) * .048
        x[:, channel] += np.roll(shimmer, channel * 701) * .009
        x[:, channel] += np.sin(2 * np.pi * round(55 * duration) * t / duration + channel * .2) * .014
    for at, hz, pan in [(2.4, 283, -.55), (9.2, 397, .6), (14.1, 211, -.2)]:
        cyclic_add(x, room(ring(2.5, hz), .6, 2.5), at, .025, pan)
    return fade(hp(x, 28), .006, .006)


def master(x, peak_db=-4, rms_floor=None):
    x = np.nan_to_num(x)
    x -= np.mean(x, axis=0)
    if rms_floor is not None:
        # Gentle bus saturation only when a stray transient makes the bed too quiet.
        for drive in [1, 1.2, 1.5, 1.9, 2.4, 3.0]:
            candidate = np.tanh(x / max(np.max(np.abs(x)), 1e-10) * drive)
            candidate *= 10 ** (peak_db / 20) / max(np.max(np.abs(candidate)), 1e-10)
            if metrics(candidate)["rms_dbfs"] >= rms_floor:
                return candidate
        return candidate
    x *= 10 ** (peak_db / 20) / max(np.max(np.abs(x)), 1e-10)
    return x


def write_wav(path, x):
    pcm = np.round(np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1 if x.ndim == 1 else x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return pcm.astype(float) / 32768


def write_mp3(path, x, bitrate):
    run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-f", "f32le", "-ar", str(SR),
         "-ac", "2", "-i", "pipe:0", "-map_metadata", "-1", "-c:a", "libmp3lame", "-b:a", bitrate,
         "-ar", str(SR), "-write_xing", "1", "-id3v2_version", "3", str(path)], x.astype("<f4").tobytes())
    return decode(path, 2)


def file_metadata(path, x, sources, loop=False):
    result = {"file": path.name, "loop": loop, "duration_s": round(len(x) / SR, 6),
              "sample_rate": SR, "channels": 1 if x.ndim == 1 else x.shape[1],
              "encoding": "mp3" if path.suffix == ".mp3" else "pcm_s16le",
              "bytes": path.stat().st_size, **metrics(x),
              "true_peak_4x_dbfs": round(true_peak(x), 3), "sources": sorted(sources)}
    if loop:
        result.update(loop_start_s=0, loop_end_s=round(len(x) / SR, 6))
    return result


def seam_metrics(x):
    jump = float(np.max(np.abs(x[0] - x[-1])))
    ordinary = float(np.sqrt(np.mean(np.diff(x, axis=0) ** 2)))
    edge = int(.012 * SR)
    a, b = x[:edge], x[-edge:]
    return {"endpoint_jump_dbfs": round(db(jump), 3),
            "jump_to_typical_sample_delta": round(jump / max(ordinary, 1e-10), 3),
            "head_12ms_rms_dbfs": round(db(np.sqrt(np.mean(a * a))), 3),
            "tail_12ms_rms_dbfs": round(db(np.sqrt(np.mean(b * b))), 3)}


def write_licenses(bank):
    parts = ["BLACKBLADE MOBILE — BATTLE AUDIO SOURCES\n",
             "All packaged battle audio is CC0-1.0. No extracted game audio.\n",
             "Kenney source archives were retrieved from the author's own website.\n",
             "Recorded foley was trimmed, filtered, pitched, layered and mastered.\n",
             "Air movement, creature growls, resonators, ambience, and the 80 BPM\n",
             "D-minor music arrangement were synthesized originally for this project.\n",
             "These original contributions are dedicated to the public domain under\n",
             "CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/\n\n"]
    for key, spec in PACKS.items():
        parts += [spec["title"] + "\n", "Page: " + spec["page"] + "\n",
                  "Archive: " + spec["url"] + "\n", "SHA-256: " + spec["sha256"] + "\n",
                  "License: CC0 1.0 Universal\nOriginal bundled License.txt follows verbatim:\n",
                  "----- BEGIN ORIGINAL LICENSE -----\n"]
        original = (WORK / "raw" / key / "License.txt").read_bytes().decode("utf-8-sig")
        parts += [original, "\n----- END ORIGINAL LICENSE -----\n\n"]
    parts.append("PROVENANCE BY FINAL FILE (full paths are relative to assets/audio/battle):\n")
    for clip in bank["files"].values():
        parts += [clip["file"] + "\n", *["  " + src + "\n" for src in clip["sources"]]]
    (ROOT / "LICENSES/Battle-Audio-Sources.txt").write_bytes("".join(parts).encode("utf-8"))


def build():
    global RNG
    ensure_sources()
    bank = {"version": 1, "files": {}, "events": {}, "loops": {}}
    audio = {}
    serial = 0
    for event, count in COUNTS.items():
        ids = []
        for v in range(count):
            SOURCES.clear()
            RNG = np.random.default_rng(SEED + serial)
            x = make_sfx(event, v)
            x = master(fade(hp(lp(x, 11800), 31), .001, .025), -4, SFX_RMS_FLOORS.get(event))
            reconstructed_peak = true_peak(x)
            if reconstructed_peak > -3.05:
                x *= 10 ** ((-3.05 - reconstructed_peak) / 20)
            key = f"{event}_{v + 1:02d}"
            path = OUT / (key + ".wav")
            x = write_wav(path, x)
            bank["files"][key] = file_metadata(path, x, SOURCES.copy())
            audio[key] = x
            ids.append(key)
            serial += 1
        gain = {"step": -2, "menu": -4, "body_contact": -2, "blade_drag": -2}.get(event, 0)
        bank["events"][event] = {"clips": ids, "gain_db": gain,
                                "pitch": [0.97, 1.03] if event not in ("win", "death") else [1, 1]}
        print(event, count, "clips", flush=True)
    loop_checks = {}
    for name in ["ambient", "music_1", "music_2"]:
        SOURCES.clear()
        RNG = np.random.default_rng(SEED + 1000 + (0 if name == "ambient" else int(name[-1])))
        x = make_ambient() if name == "ambient" else make_music(int(name[-1]))
        original_length = len(x)
        target = -10.5 if name == "ambient" else -7
        x = master(x, target - .3, -27 if name == "ambient" else -19.5)
        x = fade(x, .003, .003)
        pre = seam_metrics(x)
        path = OUT / (name + ".mp3")
        decoded = write_mp3(path, x, "96k" if name == "ambient" else "128k")
        correction = target - metrics(decoded)["peak_dbfs"]
        if abs(correction) > .08:
            x *= 10 ** (correction / 20)
            decoded = write_mp3(path, x, "96k" if name == "ambient" else "128k")
        if len(decoded) != original_length:
            raise RuntimeError(name + " MP3 gapless sample count mismatch")
        bank["files"][name] = file_metadata(path, decoded, SOURCES.copy(), True)
        if name.startswith("music"):
            bank["files"][name].update(bpm=80, beats_per_bar=4, bars=12, key="D minor")
        bank["loops"][name] = name
        loop_checks[name] = {"pre_encode": pre, "decoded": seam_metrics(decoded),
                             "decoded_samples_per_channel": len(decoded),
                             "gapless_sample_count_matches": True}
        audio[name] = decoded
        print(name, metrics(decoded), flush=True)
    (OUT / "bank.json").write_text(json.dumps(bank, indent=2) + "\n")
    write_licenses(bank)
    total = sum(v["bytes"] for v in bank["files"].values())
    sfx = [v for v in bank["files"].values() if not v["loop"]]
    report = {"version": 1, "seed": SEED, "source_archives": PACKS,
              "bank": str(OUT / "bank.json"), "audio_file_count": len(bank["files"]),
              "sfx_count": len(sfx), "event_count": len(bank["events"]),
              "encoded_audio_bytes": total, "encoded_audio_mib": round(total / 1048576, 3),
              "total_sfx_duration_s": round(sum(v["duration_s"] for v in sfx), 3),
              "sfx_peak_range_dbfs": [min(v["peak_dbfs"] for v in sfx), max(v["peak_dbfs"] for v in sfx)],
              "sfx_rms_range_dbfs": [min(v["rms_dbfs"] for v in sfx), max(v["rms_dbfs"] for v in sfx)],
              "max_true_peak_4x_dbfs": max(v["true_peak_4x_dbfs"] for v in bank["files"].values()),
              "clipped_samples": int(sum(np.sum(np.abs(x) >= 1) for x in audio.values())),
              "loop_checks": loop_checks, "files": bank["files"]}
    if total > 12 * 1048576:
        raise RuntimeError("Encoded audio exceeds 12 MiB")
    if report["clipped_samples"]:
        raise RuntimeError("Clipping detected")
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("files", "source_archives")}, indent=2))


def check():
    bank = json.loads((OUT / "bank.json").read_text())
    problems = []
    for name, f in bank["files"].items():
        path = OUT / f["file"]
        x = decode(path, f["channels"])
        m = metrics(x)
        if len(x) != round(f["duration_s"] * SR):
            problems.append(name + ": decoded duration changed")
        if m["peak_dbfs"] > -2.99:
            problems.append(name + ": peak too high")
        if true_peak(x) > -3:
            problems.append(name + ": reconstructed true peak too high")
        if not np.isfinite(x).all():
            problems.append(name + ": non-finite PCM")
        if path.suffix == ".wav":
            with wave.open(str(path)) as w:
                if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, SR):
                    problems.append(name + ": incorrect PCM format")
        if f["loop"]:
            print(name, m, seam_metrics(x))
    if set(bank["events"]) != set(COUNTS):
        problems.append("Missing logical events")
    for e in bank["events"].values():
        if not all(k in bank["files"] for k in e["clips"]):
            problems.append("Event references missing clip")
    if problems:
        raise RuntimeError("; ".join(problems))
    print("PASS:", len(bank["files"]), "files;", len(bank["events"]), "events; float decode and PCM format verified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Decode and verify the completed bank")
    args = parser.parse_args()
    check() if args.check else build()
