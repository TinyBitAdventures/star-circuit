"""
Render Star Circuit's soundtrack to loopable OGG files.

    audio/.venv/bin/python audio/build_music.py [track ...]

Tracks: menu, verdant, arid, crystal, ember, space, combat
"""

import os
import subprocess
import sys
import tempfile

import numpy as np

import synth as S

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "game", "assets", "audio", "music"))
os.makedirs(OUT, exist_ok=True)

SCALES = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
}


# ---------------------------------------------------------------- theory

def deg_midi(root, scale, deg, octave=0):
    sc = SCALES[scale]
    o, i = divmod(deg, len(sc))
    return root + sc[i] + 12 * (o + octave)


def chord_tones(root, scale, deg, size=4, octave=0):
    return [deg_midi(root, scale, deg + 2 * k, octave) for k in range(size)]


# ---------------------------------------------------------------- instruments

def inst_pad(notes, dur, cutoff=1400, attack=1.6, release=2.8, detune=0.09, voice="saw", gain=0.16):
    n = S.n_samples(dur + release)
    out = np.zeros((2, n))
    for j, m in enumerate(notes):
        f = S.midi_hz(m)
        for k, d in enumerate((-detune, 0.0, detune)):
            fr = f * 2 ** (d / 12)
            osc = S.saw(fr, n, S.rng().random()) if voice == "saw" else S.tri(fr, n)
            out += S.pan(osc, (k - 1) * 0.6 * (1 if j % 2 else -1))
        out += S.pan(S.sine(f / 2, n), 0) * 0.35
    env = S.adsr(n, attack, 1.0, 0.8, release, hold=dur)
    lp = S.lowpass(out, cutoff, 2)
    # slow filter shimmer
    lfo = 0.85 + 0.15 * np.sin(np.linspace(0, np.pi * 2 * dur / 7.0, n))
    return lp * env * lfo * gain / max(1, len(notes)) * 3


def inst_pluck(m, vel=1.0, decay=0.45, bright=2.2, ratio=2.0):
    n = S.n_samples(decay * 4)
    f = S.midi_hz(m)
    idx_env = S.exp_decay(n, 0.07)
    x = S.fm(f, n, ratio, bright, idx_env) * 0.7 + S.sine(f, n) * 0.3
    return x * S.exp_decay(n, decay) * vel * 0.3


def inst_bell(m, vel=1.0, decay=2.4):
    n = S.n_samples(decay * 3)
    f = S.midi_hz(m)
    x = S.fm(f, n, 3.5, 2.6, S.exp_decay(n, 0.5)) * 0.6
    x += S.sine(f * 2.01, n) * S.exp_decay(n, decay * 0.4) * 0.2
    return x * S.exp_decay(n, decay) * vel * 0.22


def inst_marimba(m, vel=1.0):
    n = S.n_samples(1.2)
    f = S.midi_hz(m)
    x = S.fm(f, n, 4.0, 1.6, S.exp_decay(n, 0.03)) * 0.5 + S.sine(f, n) * 0.5
    return x * S.exp_decay(n, 0.28) * vel * 0.32


def inst_bass(m, dur, cutoff=420, gain=0.32):
    n = S.n_samples(dur + 0.25)
    f = S.midi_hz(m)
    x = S.sine(f, n) + 0.35 * S.lowpass(S.saw(f, n), cutoff, 2)
    return x * S.adsr(n, 0.015, 0.25, 0.75, 0.2, hold=dur) * gain


def inst_drone(m, dur, gain=0.2):
    n = S.n_samples(dur)
    f = S.midi_hz(m)
    x = S.sine(f, n) * 0.7 + S.lowpass(S.saw(f * 1.003, n), 300, 2) * 0.3 + S.sine(f * 1.5, n) * 0.12
    env = S.adsr(n, dur * 0.3, 0.1, 1.0, dur * 0.35)
    return x * env * gain


def inst_lead(m, dur, vel=1.0):
    n = S.n_samples(dur + 0.3)
    f = S.midi_hz(m)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * np.arange(n) / S.SR) * np.clip(np.arange(n) / S.SR - 0.2, 0, 1)
    x = S.saw(f * vib, n) * 0.6 + S.square(f * 1.002 * vib, n, 0.35) * 0.4
    x = S.sweep_lowpass(x, 4200, 1300)
    return x * S.adsr(n, 0.01, 0.15, 0.6, 0.25, hold=dur) * vel * 0.14


def inst_texture(dur, lo=300, hi=2400, gain=0.08):
    n = S.n_samples(dur)
    x = S.bandpass(S.noise(n), lo, hi, 2)
    swell = np.sin(np.linspace(0, np.pi, n)) ** 2
    return S.pan(x * swell * gain, 0.3) + S.pan(S.bandpass(S.noise(n), lo * 1.3, hi * 1.2, 2) * swell * gain, -0.3)


def drum_kick(vel=1.0):
    n = S.n_samples(0.45)
    f = 45 + 110 * S.exp_decay(n, 0.035)
    return (S.sine(f, n) * S.exp_decay(n, 0.16) + S.lowpass(S.noise(n), 1500) * S.exp_decay(n, 0.01) * 0.3) * vel * 0.9


def drum_snare(vel=1.0):
    n = S.n_samples(0.3)
    body = S.sine(190, n) * S.exp_decay(n, 0.05) * 0.5
    nz = S.bandpass(S.noise(n), 1200, 7000, 2) * S.exp_decay(n, 0.09)
    return (body + nz) * vel * 0.55


def drum_hat(vel=1.0, open_=False):
    n = S.n_samples(0.35 if open_ else 0.08)
    return S.lowpass(S.highpass(S.noise(n), 6500, 2), 11000, 2) * S.exp_decay(n, 0.12 if open_ else 0.022) * vel * 0.18


def drum_tom(m, vel=1.0):
    n = S.n_samples(0.5)
    f = S.midi_hz(m) * (1 + 0.6 * S.exp_decay(n, 0.04))
    return S.sine(f, n) * S.exp_decay(n, 0.18) * vel * 0.6


# ---------------------------------------------------------------- arrangement helpers

class Track:
    def __init__(self, bpm, bars, verb_sec=3.5, verb_damp=5000, delay_beats=0.75):
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.bars = bars
        self.length = S.n_samples(bars * 4 * self.spb)
        tail = S.n_samples(10)
        self.dry = np.zeros((2, self.length + tail))
        self.verb = np.zeros_like(self.dry)
        self.dly = np.zeros_like(self.dry)
        self.verb_sec = verb_sec
        self.verb_damp = verb_damp
        self.delay_beats = delay_beats

    def at(self, beat):
        return S.n_samples(beat * self.spb)

    def add(self, sig, beat, pan=0.0, verb=0.3, dly=0.0, gain=1.0):
        st = sig if sig.ndim == 2 else S.pan(sig, pan)
        st = st * gain
        i = self.at(beat)
        S.mix_into(self.dry, st, i)
        if verb:
            S.mix_into(self.verb, st * verb, i)
        if dly:
            S.mix_into(self.dly, st * dly, i)

    def render(self, rms_target=0.11):
        ir = S.reverb_ir(self.verb_sec, self.verb_damp)
        wet = S.reverb(self.verb, ir, wet=1.0)[:, :self.dry.shape[1]]
        d = S.delay(self.dly, self.delay_beats * self.spb, 0.45, 6, True, 1.0)[:, :self.dry.shape[1]]
        mix = self.dry + wet * 0.9 + d * 0.6
        mix = S.highpass(mix, 28, 2)
        mix = S.fold_loop(mix, self.length)
        rms = np.sqrt(np.mean(mix ** 2))
        mix *= rms_target / max(rms, 1e-6)
        return S.soft_clip(mix, 1.2) * 0.92


def melody_phrase(root, scale, prog, bars_per_chord, octave, seed_, density=0.6):
    """A 4-chord phrase as [(beat, midi, dur, vel)] relative to phrase start."""
    r = np.random.default_rng(seed_)
    rhythms = [[1, 1, 2], [0.5, 0.5, 1, 2], [2, 1, 1], [1.5, 0.5, 2], [3, 1], [1, 0.5, 0.5, 2], [4]]
    notes = []
    deg = prog[0] + 7 * octave + 2
    beat = 0.0
    for ci, cdeg in enumerate(prog):
        for b in range(bars_per_chord):
            rh = rhythms[r.integers(len(rhythms))]
            for k, dur in enumerate(rh):
                if r.random() < density or k == 0:
                    if k == 0:
                        # land on a chord tone
                        tones = [cdeg + 7 * octave + t for t in (0, 2, 4)]
                        deg = min(tones, key=lambda t: abs(t - deg) + r.random() * 0.5)
                    else:
                        deg += int(r.choice([-2, -1, -1, 1, 1, 2, 3, -3]))
                    lo, hi = cdeg + 7 * octave - 2, cdeg + 7 * octave + 9
                    deg = int(np.clip(deg, lo, hi))
                    notes.append((beat, deg_midi(root, scale, deg), dur * 0.95, 0.75 + 0.25 * r.random()))
                beat += dur
    return notes


def arp_line(t, root, scale, prog, bar0, bars, bars_per_chord, octave, pattern, step, inst, gain, pan_spread=0.5, verb=0.35, dly=0.25):
    steps_per_bar = int(4 / step)
    for b in range(bars):
        cdeg = prog[((bar0 + b) // bars_per_chord) % len(prog)]
        tones = chord_tones(root, scale, cdeg, 4, octave) + chord_tones(root, scale, cdeg, 3, octave + 1)
        for s in range(steps_per_bar):
            m = tones[pattern[s % len(pattern)] % len(tones)]
            beat = (bar0 + b) * 4 + s * step
            vel = 1.0 if s % 4 == 0 else 0.7
            p = pan_spread * np.sin(s * 0.9)
            t.add(inst(m, vel), beat, pan=p, verb=verb, dly=dly, gain=gain)


# ---------------------------------------------------------------- tracks

def ambient(name, seed_, bpm, root, scale, prog, bars, *, pad_cut, pad_voice="saw", arp_inst=inst_pluck, arp_step=0.5,
            arp_pattern=(0, 2, 1, 3, 2, 4, 3, 5), mel_inst=inst_bell, mel_oct=1, verb_sec=4.0, texture=None,
            bass=True, drone=False, bars_per_chord=2, mel_density=0.55, arp_gain=0.8, mel_gain=1.0, perc=False):
    S.seed(seed_)
    t = Track(bpm, bars, verb_sec)
    # pads + bass through the whole loop
    for b in range(0, bars, bars_per_chord):
        cdeg = prog[(b // bars_per_chord) % len(prog)]
        notes = chord_tones(root, scale, cdeg, 4, 0)
        dur = bars_per_chord * 4 * t.spb
        t.add(inst_pad(notes, dur + 0.6, pad_cut, attack=1.0, voice=pad_voice), b * 4, verb=0.45)
        if bass:
            bm = deg_midi(root, scale, cdeg, -2)
            for k in range(bars_per_chord):
                t.add(inst_bass(bm, 3.6 * t.spb), (b + k) * 4, verb=0.1)
                t.add(inst_bass(bm + (7 if k % 2 else 12), 0.9 * t.spb, gain=0.18), (b + k) * 4 + 3, verb=0.1)
        if drone:
            t.add(S.pan(inst_drone(deg_midi(root, scale, 0, -2), dur + 1.5), 0), b * 4, verb=0.3)
    if perc:
        # gentle shaker + soft kick once the arp is in
        for b in range(4, bars):
            for e in range(8):
                t.add(drum_hat(0.5 if e % 2 else 0.8), b * 4 + e * 0.5, pan=0.35, verb=0.15, gain=0.7)
            t.add(drum_kick(0.55), b * 4, verb=0.05)
            t.add(drum_kick(0.4), b * 4 + 2.5, verb=0.05)
            if b % 2 == 1:
                t.add(drum_snare(0.35), b * 4 + 3, verb=0.3)
    if texture:
        for b in range(0, bars, 4):
            t.add(inst_texture(4 * 4 * t.spb, *texture), b * 4, verb=0.5)
    # arp enters after the intro, melody in the middle section
    arp_line(t, root, scale, prog, 4, bars - 4, bars_per_chord, 1, list(arp_pattern), arp_step, arp_inst, arp_gain)
    phrase_len = len(prog) * bars_per_chord
    pa = melody_phrase(root, scale, prog, bars_per_chord, mel_oct, seed_ + 1, mel_density)
    pb = melody_phrase(root, scale, prog, bars_per_chord, mel_oct, seed_ + 2, mel_density)
    mel_start, mel_end = bars // 3, bars - 2
    bar = mel_start - (mel_start % phrase_len)
    k = 0
    while bar < mel_end:
        phrase = pa if k % 2 == 0 else pb
        for beat, m, dur, vel in phrase:
            abs_beat = bar * 4 + beat
            if mel_start * 4 <= abs_beat < mel_end * 4:
                t.add(mel_inst(m, vel), abs_beat, pan=0.15, verb=0.5, dly=0.3, gain=mel_gain)
        bar += phrase_len
        k += 1
    return t.render()


def track_space():
    S.seed(77)
    root, scale = 52, "minor"  # E minor
    prog = [0, 5, 3, 6]
    t = Track(58, 24, verb_sec=7.0, verb_damp=3500, delay_beats=1.5)
    for b in range(0, 24, 3):
        cdeg = prog[(b // 3) % len(prog)]
        notes = chord_tones(root, scale, cdeg, 4, 0) + [deg_midi(root, scale, cdeg + 8, 0)]
        dur = 3 * 4 * t.spb
        t.add(inst_pad(notes, dur + 2.0, 900, attack=2.0, release=5.0, voice="saw", gain=0.14), b * 4, verb=0.7)
        t.add(inst_pad(chord_tones(root, scale, cdeg, 3, 1), dur, 1800, attack=3.0, release=5.0, voice="tri", gain=0.06), b * 4 + 2, verb=0.8)
        t.add(S.pan(inst_drone(deg_midi(root, scale, cdeg, -2), dur + 2, 0.24), 0), b * 4, verb=0.3)
        t.add(inst_texture(dur, 400, 2500, 0.018), b * 4, verb=0.8)
    r = np.random.default_rng(78)
    for bar in range(2, 23):
        for _ in range(r.integers(0, 3)):
            cdeg = prog[(bar // 3) % len(prog)]
            m = deg_midi(root, scale, cdeg + int(r.choice([0, 2, 4, 7, 9])), 2)
            t.add(inst_bell(m, 0.5 + 0.4 * r.random(), 3.5), bar * 4 + float(r.integers(0, 8)) * 0.5, pan=float(r.uniform(-0.7, 0.7)), verb=0.8, dly=0.4)
    return t.render(0.1)


def track_combat():
    S.seed(99)
    root, scale = 45, "minor"  # A minor
    prog = [0, 5, 2, 6]
    bars = 24
    t = Track(124, bars, verb_sec=1.8, verb_damp=6000, delay_beats=0.75)
    for b in range(bars):
        cdeg = prog[(b // 2) % len(prog)]
        section = 0 if b < 4 else (1 if b < 16 else 2)
        # drums
        for beat in range(4):
            pos = b * 4 + beat
            if beat in (0, 2) or (section > 0 and beat == 3 and b % 2):
                t.add(drum_kick(), pos, verb=0.05)
            if beat in (1, 3) and section > 0:
                t.add(drum_snare(), pos, verb=0.25)
            for h in (0, 0.5):
                t.add(drum_hat(0.9 if h == 0 else 0.6, open_=(beat == 3 and h == 0.5)), pos + h, pan=0.3, verb=0.05)
        if b % 4 == 3 and section > 0:
            for k, m in enumerate((50, 47, 43)):
                t.add(drum_tom(m), b * 4 + 3 + k * 0.25, pan=0.4 - k * 0.4, verb=0.2)
        # driving bass 8ths
        bm = deg_midi(root, scale, cdeg, -1)
        for e in range(8):
            t.add(inst_bass(bm + (12 if e in (3, 6) else 0), 0.42 * t.spb, cutoff=900, gain=0.28), b * 4 + e * 0.5, verb=0.05)
        # pad stabs
        if b % 2 == 0:
            notes = chord_tones(root, scale, cdeg, 4, 1)
            t.add(inst_pad(notes, 7.5 * t.spb, 2200, attack=0.05, release=0.8, gain=0.12), b * 4, verb=0.3)
    # lead riff in the middle section
    riff = [(0, 0), (0.75, 2), (1.5, 4), (2, 3), (3, 2), (3.5, 1)]
    for b in range(8, 20):
        cdeg = prog[(b // 2) % len(prog)]
        for beat, dd in riff:
            m = deg_midi(root, scale, cdeg + dd, 2)
            t.add(inst_lead(m, 0.45 * t.spb), b * 4 + beat, pan=-0.1, verb=0.25, dly=0.25)
    arp_line(t, root, scale, prog, 16, 8, 2, 1, [0, 1, 2, 3, 4, 3, 2, 1], 0.25, lambda m, v: inst_pluck(m, v, 0.2, 3.0), 0.5)
    return t.render(0.13)


def track_ocean(dark=False):
    """The Deep Sea. Light version: sunlit shallows, slow and airy with
    swelling pads and far-off bells. Dark version: the midnight water, a
    low drone, sonar-like pings and a whale-song lead."""
    S.seed(88 if dark else 87)
    root, scale = (43, "phrygian") if dark else (50, "dorian")
    prog = [0, 6, 5, 3] if dark else [0, 3, 6, 4]
    bars = 24
    t = Track(52 if dark else 60, bars, verb_sec=8.0, verb_damp=2200 if dark else 3200, delay_beats=1.5)
    for b in range(0, bars, 3):
        cdeg = prog[(b // 3) % len(prog)]
        dur = 3 * 4 * t.spb
        t.add(inst_pad(chord_tones(root, scale, cdeg, 4, 0), dur + 2.5, 500 if dark else 1000, attack=2.5, release=5.5, voice="tri" if not dark else "saw", gain=0.15), b * 4, verb=0.8)
        t.add(S.pan(inst_drone(deg_midi(root, scale, cdeg, -2), dur + 2.0, 0.26 if dark else 0.18), 0), b * 4, verb=0.4)
        t.add(inst_texture(dur, 90, 500 if dark else 900, 0.03), b * 4, verb=0.8)
    r = np.random.default_rng(89 if dark else 90)
    # sonar-ish pings / glinting bells, far away
    for bar in range(1, bars - 1):
        if r.random() < (0.55 if dark else 0.7):
            cdeg = prog[(bar // 3) % len(prog)]
            m = deg_midi(root, scale, cdeg + int(r.choice([0, 2, 4, 7])), 1 if dark else 2)
            t.add(inst_bell(m, 0.45 + 0.3 * r.random(), 4.0), bar * 4 + float(r.integers(0, 6)) * 0.5,
                  pan=float(r.uniform(-0.8, 0.8)), verb=0.9, dly=0.5)
    # a slow singing lead, bending between notes like whale song
    for bar in range(4, bars - 2, 4):
        cdeg = prog[(bar // 3) % len(prog)]
        m0 = deg_midi(root, scale, cdeg + 4, 0 if dark else 1)
        m1 = deg_midi(root, scale, cdeg + int(r.choice([2, 5, 7])), 0 if dark else 1)
        n = S.n_samples(6 * t.spb)
        f = S.midi_hz(m0) * (S.midi_hz(m1) / S.midi_hz(m0)) ** (np.linspace(0, 1, n) ** 2.5)
        f = f * (1 + 0.01 * np.sin(2 * np.pi * 4.5 * np.arange(n) / S.SR))
        voice = S.lowpass(S.sine(f, n) * 0.6 + S.tri(f * 2.0, n) * 0.15, 1400) * S.adsr(n, 0.9, 0.5, 0.7, 1.8) * 0.22
        t.add(voice, bar * 4 + 1, pan=float(r.uniform(-0.3, 0.3)), verb=0.85, dly=0.35)
    return t.render(0.09)


def track_orbit():
    """Holding orbit: a hovering, weightless pulse over wide pads."""
    return ambient("orbit", 101, 66, 52, "lydian", [0, 4, 2, 5], 24, pad_cut=1300, pad_voice="tri",
                   arp_inst=lambda m, v: inst_bell(m, v * 0.5, 1.1), arp_step=0.5,
                   arp_pattern=(0, 4, 2, 6, 4, 2, 5, 3), mel_inst=lambda m, v: inst_bell(m, v * 0.8, 3.0), mel_oct=2,
                   verb_sec=7.0, texture=(600, 3000, 0.015), bass=False, drone=True, mel_density=0.35, arp_gain=0.55)


def track_hyperspace():
    """Pirate interdiction in hyperspace: a driving minor-key synthwave pulse."""
    S.seed(131)
    root, scale = 45, "minor"  # A minor
    prog = [0, 5, 3, 6]
    bars = 16
    t = Track(132, bars, verb_sec=2.2, verb_damp=6000, delay_beats=0.75)
    for b in range(bars):
        cdeg = prog[(b // 2) % len(prog)]
        # sixteenth-note bass pulse
        bm = deg_midi(root, scale, cdeg, -2)
        for s16 in range(16):
            t.add(inst_bass(bm + (12 if s16 % 4 == 2 else 0), 0.22 * t.spb, cutoff=700, gain=0.22), b * 4 + s16 * 0.25, verb=0.05)
        if b % 2 == 0:
            t.add(inst_pad(chord_tones(root, scale, cdeg, 4, 0), 8 * t.spb, 1600, attack=0.3, release=1.0, voice="saw", gain=0.1), b * 4, verb=0.4)
        for beat in range(4):
            t.add(drum_kick(0.9), b * 4 + beat, verb=0.05)
            t.add(drum_hat(0.6, beat % 2 == 1), b * 4 + beat + 0.5, pan=0.3, verb=0.1, gain=0.8)
            if beat % 2 == 1:
                t.add(drum_snare(0.8), b * 4 + beat, verb=0.25)
    # a soaring arpeggio after the intro
    arp_line(t, root, scale, prog, 4, bars - 4, 2, 1, [0, 2, 4, 6, 4, 2, 5, 3], 0.25,
             lambda m, v: inst_pluck(m, v, 0.25, 3.0, 2.0), 0.6)
    return t.render(0.13)


def inst_bloop(m, vel=1.0):
    """A bubble that sings: a short sine whose pitch rises into the note."""
    n = S.n_samples(0.22)
    f = S.midi_hz(m)
    sweep = f * (0.72 + 0.28 * (1 - np.exp(-np.arange(n) / (S.SR * 0.025))))
    return S.sine(sweep, n) * S.exp_decay(n, 0.09) * vel * 0.45


def track_lab():
    """The Micro Lab: a playful, bubbling groove, like something simmering."""
    return ambient("lab", 141, 94, 50, "dorian", [0, 3, 5, 3], 24, pad_cut=900, pad_voice="tri",
                   arp_inst=inst_bloop, arp_step=0.25, arp_pattern=(0, 4, 2, 5, 1, 4, 3, 6),
                   mel_inst=lambda m, v: inst_marimba(m, v), mel_oct=1, verb_sec=2.4,
                   texture=(150, 800, 0.03), mel_density=0.5, mel_gain=1.1, bars_per_chord=2, perc=True, arp_gain=0.55)


TRACKS = {
    "menu": lambda: ambient("menu", 11, 72, 50, "lydian", [0, 1, 5, 4], 24, pad_cut=1500, arp_step=0.5,
                            arp_pattern=(0, 2, 4, 3, 5, 4, 2, 1), mel_inst=inst_bell, verb_sec=5.0,
                            texture=(400, 2500, 0.02), mel_density=0.5),
    "verdant": lambda: ambient("verdant", 21, 88, 55, "major", [0, 4, 5, 3], 32, pad_cut=1800, pad_voice="tri",
                               arp_inst=inst_marimba, arp_step=0.5, arp_pattern=(0, 2, 1, 3, 4, 3, 2, 1),
                               mel_inst=lambda m, v: inst_pluck(m, v, 0.6, 1.6, 1.0), verb_sec=3.0, mel_density=0.65,
                               mel_gain=1.3),
    "arid": lambda: ambient("arid", 31, 76, 50, "dorian", [0, 3, 6, 4], 24, pad_cut=1100, pad_voice="saw",
                            arp_inst=lambda m, v: inst_pluck(m, v, 0.35, 2.8, 3.0), arp_step=0.5,
                            arp_pattern=(0, 1, 2, 1, 3, 2, 1, 0), mel_inst=lambda m, v: inst_pluck(m, v, 0.8, 2.0, 1.5),
                            verb_sec=4.0, texture=(250, 1500, 0.04), drone=True, mel_density=0.45, mel_gain=1.2),
    "crystal": lambda: ambient("crystal", 41, 66, 57, "lydian", [0, 4, 1, 5], 24, pad_cut=2400, pad_voice="tri",
                               arp_inst=lambda m, v: inst_bell(m, v * 0.7, 1.4), arp_step=0.5,
                               arp_pattern=(0, 4, 2, 5, 3, 6, 4, 2), mel_inst=inst_bell, mel_oct=2, verb_sec=6.0,
                               texture=(1200, 5000, 0.014), bass=False, drone=True, mel_density=0.4),
    "ember": lambda: ambient("ember", 51, 70, 45, "phrygian", [0, 1, 0, 6], 24, pad_cut=700, pad_voice="saw",
                             arp_inst=lambda m, v: inst_pluck(m, v, 0.3, 3.5, 1.0), arp_step=0.5,
                             arp_pattern=(0, 1, 0, 2, 0, 1, 3, 1), mel_inst=lambda m, v: inst_bell(m, v, 1.8), mel_oct=1,
                             verb_sec=4.5, texture=(120, 900, 0.09), drone=True, mel_density=0.35),
    "town": lambda: ambient("town", 61, 96, 53, "major", [0, 3, 4, 0, 5, 3, 1, 4], 32, pad_cut=1600, pad_voice="tri",
                            arp_inst=inst_marimba, arp_step=0.5, arp_pattern=(0, 2, 4, 2, 1, 3, 5, 3),
                            mel_inst=lambda m, v: inst_pluck(m, v, 0.5, 1.4, 1.0), verb_sec=2.2, mel_density=0.7,
                            mel_gain=1.3, bars_per_chord=1, perc=True),
    "underground": lambda: ambient("underground", 71, 60, 45, "phrygian", [0, 5, 1, 4], 24, pad_cut=650, pad_voice="saw",
                                   arp_inst=lambda m, v: inst_bell(m, v * 0.55, 2.2), arp_step=1.0,
                                   arp_pattern=(0, 4, 2, 6, 3, 1), mel_inst=lambda m, v: inst_bell(m, v * 0.8, 3.0), mel_oct=1,
                                   verb_sec=7.0, texture=(120, 700, 0.03), drone=True, bass=False, mel_density=0.3, arp_gain=0.6),
    "space": track_space,
    "ocean": track_ocean,
    "abyss": lambda: track_ocean(True),
    "orbit": track_orbit,
    "hyperspace": track_hyperspace,
    # the Homespace: a cozy lo-fi loop with soft drums and warm keys
    "home": lambda: ambient("home", 121, 78, 53, "mixolydian", [0, 3, 5, 4], 24, pad_cut=1200, pad_voice="tri",
                            arp_inst=inst_marimba, arp_step=0.5, arp_pattern=(0, 2, 4, 6, 4, 2, 5, 3),
                            mel_inst=lambda m, v: inst_pluck(m, v, 0.7, 1.2, 1.0), verb_sec=2.6, mel_density=0.55,
                            mel_gain=1.2, bars_per_chord=2, perc=True, arp_gain=0.6),
    "combat": track_combat,
    "lab": track_lab,
}


def encode(name, stereo):
    tmp = os.path.join(tempfile.gettempdir(), f"sc_{name}.wav")
    S.write_wav(tmp, stereo)
    out = os.path.join(OUT, f"{name}.ogg")
    subprocess.run(["oggenc", "-Q", "-q", "5", "-o", out, tmp], check=True)
    os.remove(tmp)
    print(f"[music] {name}: {stereo.shape[1] / S.SR:.1f}s -> {out} ({os.path.getsize(out) // 1024} KB)")


if __name__ == "__main__":
    names = sys.argv[1:] or list(TRACKS)
    for n in names:
        encode(n, TRACKS[n]())
