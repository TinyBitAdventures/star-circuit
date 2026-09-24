"""
Render Star Circuit's sound effects to WAV files (mono, 44.1 kHz).

    audio/.venv/bin/python audio/build_sfx.py [name ...]

Loops (suffix _loop) are crossfaded so they repeat seamlessly.
"""

import os
import sys

import numpy as np
from scipy import signal

import synth as S

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "game", "assets", "audio", "sfx"))
os.makedirs(OUT, exist_ok=True)

N = S.n_samples
SR = S.SR


def t_axis(n):
    return np.arange(n) / SR


def small_room(x, sec=0.6, wet=0.25, damp=6000):
    ir = S.reverb_ir(sec, damp, seed_=3)[0]
    ir /= np.max(np.abs(ir)) * 8
    y = signal.fftconvolve(x, ir)
    out = np.zeros(len(y))
    out[:len(x)] = x
    return out + y * wet


def fade_out(x, sec=0.02):
    f = min(len(x), N(sec))
    x = x.copy()
    x[-f:] *= np.linspace(1, 0, f)
    return x


def chirp(f0, f1, n, curve=1.0):
    return f0 * (f1 / f0) ** (np.linspace(0, 1, n) ** curve)


def seq(parts):
    """parts: [(start_sec, signal)] -> one signal."""
    end = max(int(s * SR) + len(p) for s, p in parts)
    out = np.zeros(end)
    for s, p in parts:
        i = int(s * SR)
        out[i:i + len(p)] += p
    return out


def bell(m, decay=0.5, ratio=3.5, idx=2.0):
    n = N(decay * 3)
    f = S.midi_hz(m)
    return S.fm(f, n, ratio, idx, S.exp_decay(n, decay * 0.3)) * S.exp_decay(n, decay)


def metal(f, decay=0.15):
    n = N(decay * 4)
    return (S.fm(f, n, 1.41, 3.0, S.exp_decay(n, 0.03)) * 0.6 + S.fm(f * 2.76, n, 1.0, 1.0) * 0.3) * S.exp_decay(n, decay)


# ---------------------------------------------------------------- UI

def ui_click():
    n = N(0.06)
    return S.sine(chirp(1500, 900, n), n) * S.exp_decay(n, 0.012) * 0.6 + S.highpass(S.noise(n), 4000) * S.exp_decay(n, 0.003) * 0.3


def ui_open():
    return small_room(seq([(0, bell(88, 0.12, 2.0, 1.0) * 0.5), (0.06, bell(95, 0.16, 2.0, 1.0) * 0.5)]), 0.4, 0.2)


def ui_close():
    return small_room(seq([(0, bell(95, 0.1, 2.0, 1.0) * 0.45), (0.05, bell(88, 0.14, 2.0, 1.0) * 0.45)]), 0.4, 0.2)


def ui_error():
    n = N(0.28)
    x = S.lowpass(S.square(150, n), 1800) * 0.5
    gate = ((t_axis(n) % 0.14) < 0.1).astype(float)
    return fade_out(x * gate * S.exp_decay(n, 0.3))


def notify():
    return small_room(bell(93, 0.25, 2.0, 0.8) * 0.4, 0.5, 0.25)


def pickup():
    return small_room(seq([(0, bell(84, 0.18) * 0.4), (0.05, bell(88, 0.18) * 0.4), (0.1, bell(91, 0.3) * 0.45)]), 0.6, 0.3)


def craft():
    clank = seq([(0, metal(320, 0.12) * 0.5), (0, S.lowpass(S.noise(N(0.1)), 3000) * S.exp_decay(N(0.1), 0.02) * 0.4)])
    chime = seq([(0, bell(79, 0.3) * 0.4), (0.09, bell(86, 0.45) * 0.45)])
    return small_room(seq([(0, clank), (0.14, chime)]), 0.7, 0.3)


def level_up():
    notes = [72, 76, 79, 84, 88]
    parts = [(i * 0.09, bell(m, 0.6, 2.0, 1.6) * 0.35) for i, m in enumerate(notes)]
    n = N(1.6)
    pad = sum(S.saw(S.midi_hz(m) * d, n) for m in (60, 64, 67, 72) for d in (0.997, 1.003))
    pad = S.lowpass(pad, 2200) * S.adsr(n, 0.25, 0.3, 0.6, 0.8) * 0.06
    parts.append((0.2, pad))
    return small_room(seq(parts), 1.2, 0.35)


def quest_accept():
    def horn(m, d):
        n = N(d)
        f = S.midi_hz(m)
        x = S.saw(f, n) * 0.6 + S.saw(f * 1.004, n) * 0.4
        return S.sweep_lowpass(x, 600, 2400, curve=0.5) * S.adsr(n, 0.04, 0.1, 0.8, 0.15) * 0.3
    return small_room(seq([(0, horn(67, 0.2)), (0.18, horn(72, 0.45))]), 0.9, 0.3)


def quest_complete():
    parts = [(0, bell(72, 0.4) * 0.35), (0.12, bell(79, 0.4) * 0.35), (0.24, bell(84, 0.5) * 0.35), (0.42, bell(88, 0.9) * 0.4), (0.42, bell(76, 0.9) * 0.3)]
    return small_room(seq(parts), 1.0, 0.35)


def skill_up():
    parts = [(i * 0.07, bell(m, 0.35, 3.0, 1.2) * 0.3) for i, m in enumerate([79, 81, 84, 88])]
    return small_room(seq(parts), 0.8, 0.3)


def low_energy():
    return seq([(0, bell(81, 0.08, 1.0, 0.5) * 0.4), (0.16, bell(81, 0.08, 1.0, 0.5) * 0.4)])


# ---------------------------------------------------------------- movement

def footstep(seed_):
    S.seed(seed_)
    n = N(0.18)
    thump = S.sine(chirp(95, 55, n), n) * S.exp_decay(n, 0.035) * 0.7
    grit = S.lowpass(S.noise(n), 900 + seed_ * 150) * S.exp_decay(n, 0.02) * 0.5
    clink = metal(900 + seed_ * 170, 0.03) * 0.08
    return fade_out(seq([(0, thump + grit), (0, clink)]))


def jump():
    n = N(0.25)
    whoosh = S.bandpass(S.noise(n), 400, 2500) * np.sin(np.linspace(0, np.pi, n)) * 0.5
    servo = S.sine(chirp(300, 700, n), n) * S.exp_decay(n, 0.08) * 0.15
    return fade_out(whoosh + servo)


def land():
    n = N(0.3)
    return fade_out(S.sine(chirp(80, 40, n), n) * S.exp_decay(n, 0.06) * 0.8 + S.lowpass(S.noise(n), 700) * S.exp_decay(n, 0.04) * 0.6)


def jet_loop():
    S.seed(5)
    n = N(2.3)
    x = S.bandpass(S.noise(n), 250, 3200) * 0.5
    flutter = 1 + 0.15 * np.sin(2 * np.pi * 13 * t_axis(n))
    x = x * flutter + S.lowpass(S.noise(n), 180) * 1.2 + S.sine(62, n) * 0.08
    return S.crossfade_loop(x * 0.6, 0.3)


def thruster_loop():
    S.seed(6)
    n = N(3.3)
    x = sum(S.saw(55 * d, n) for d in (0.995, 1.0, 1.006)) / 3
    x = S.lowpass(x, 260) * 0.6 + S.bandpass(S.noise(n), 150, 1200) * 0.35
    x *= 1 + 0.1 * np.sin(2 * np.pi * 0.6 * t_axis(n))
    return S.crossfade_loop(x * 0.7, 0.4)


def boost():
    n = N(0.7)
    x = S.bandpass(S.noise(n), 300, 4000)
    x = S.sweep_lowpass(x, 800, 6000, curve=0.5) * S.adsr(n, 0.05, 0.2, 0.6, 0.35) * 0.6
    return fade_out(x + S.sine(chirp(80, 160, n), n) * S.exp_decay(n, 0.3) * 0.3)


# ---------------------------------------------------------------- gathering

def drill_loop():
    S.seed(7)
    n = N(1.6)
    t = t_axis(n)
    motor = S.saw(110 + 6 * np.sin(2 * np.pi * 3 * t), n) * (0.6 + 0.4 * np.sin(2 * np.pi * 31 * t))
    grind = S.bandpass(S.noise(n), 700, 4500) * (0.5 + 0.5 * (S.rng().random(n) > 0.9))
    x = S.lowpass(motor, 1800) * 0.4 + grind * 0.35
    return S.crossfade_loop(x, 0.2)


def harvest_loop():
    S.seed(8)
    n = N(1.6)
    x = S.bandpass(S.noise(n), 1800, 7500)
    grains = np.zeros(n)
    r = S.rng()
    for _ in range(60):
        i = int(r.integers(0, n - 2000))
        g = N(r.uniform(0.02, 0.07))
        grains[i:i + g] += np.hanning(g) * r.uniform(0.3, 1.0)
    return S.crossfade_loop(x * grains * 0.45 + S.lowpass(S.noise(n), 500) * 0.05, 0.2)


def siphon_loop():
    S.seed(9)
    n = N(2.0)
    t = t_axis(n)
    trem = 0.7 + 0.3 * np.sin(2 * np.pi * 6 * t)
    x = (S.sine(220, n) * 0.4 + S.sine(330.5, n) * 0.25 + S.sine(441, n) * 0.2) * trem
    crackle = S.highpass(S.noise(n), 3000) * (S.rng().random(n) > 0.985) * 0.6
    return S.crossfade_loop(x * 0.45 + crackle, 0.25)


def rock_break():
    S.seed(10)
    parts = [(0, S.sine(chirp(90, 40, N(0.4)), N(0.4)) * S.exp_decay(N(0.4), 0.09) * 0.7)]
    r = S.rng()
    for i in range(14):
        n = N(r.uniform(0.02, 0.08))
        parts.append((r.uniform(0, 0.25), S.bandpass(S.noise(n), 400, r.uniform(2000, 6000)) * S.exp_decay(n, 0.015) * r.uniform(0.3, 0.8)))
    return small_room(fade_out(seq(parts)), 0.5, 0.2)


def plant_snap():
    n = N(0.25)
    snap = S.highpass(S.noise(n), 2500) * S.exp_decay(n, 0.012) * 0.8
    pop = S.sine(chirp(500, 200, n), n) * S.exp_decay(n, 0.04) * 0.5
    rustle = S.bandpass(S.noise(n), 2000, 7000) * S.exp_decay(n, 0.08) * 0.25
    return fade_out(snap + pop + rustle)


def siphon_done():
    n = N(0.8)
    x = S.sine(chirp(300, 1200, n, 0.6), n) * S.adsr(n, 0.05, 0.3, 0.4, 0.4) * 0.3
    return small_room(seq([(0, x), (0.35, bell(91, 0.4) * 0.35)]), 0.8, 0.35)


def scan():
    n = N(1.4)
    ping = S.sine(1480, n) * S.exp_decay(n, 0.35) * 0.4 + S.sine(chirp(2200, 700, n), n) * S.exp_decay(n, 0.12) * 0.2
    echo = np.zeros(n + N(0.9))
    for k, g in enumerate((1.0, 0.45, 0.2, 0.09)):
        i = N(0.28 * k)
        echo[i:i + n] += ping * g
    return fade_out(echo)


# ---------------------------------------------------------------- combat

def blaster():
    n = N(0.18)
    f = chirp(1900, 320, n, 0.6)
    x = S.square(f, n, 0.3) * 0.3 + S.sine(f * 0.5, n) * 0.4
    x = S.lowpass(x, 5000) * S.exp_decay(n, 0.05)
    click = S.highpass(S.noise(n), 3000) * S.exp_decay(n, 0.004) * 0.3
    return fade_out(x + click)


def turret_shot():
    n = N(0.12)
    f = chirp(2600, 700, n, 0.5)
    return fade_out(S.lowpass(S.square(f, n, 0.25), 6000) * S.exp_decay(n, 0.035) * 0.35)


def hit():
    n = N(0.2)
    return fade_out(seq([(0, metal(260, 0.05) * 0.5)])[:n] + S.bandpass(S.noise(n), 800, 5000) * S.exp_decay(n, 0.015) * 0.5)


def crit():
    return seq([(0, hit()), (0.01, bell(96, 0.15, 1.5, 1.5) * 0.35)])


def enemy_die():
    S.seed(11)
    n = N(1.4)
    boom = S.sine(chirp(70, 32, n), n) * S.exp_decay(n, 0.25) * 0.9
    blast = S.sweep_lowpass(S.noise(n), 5000, 150, curve=0.4) * S.exp_decay(n, 0.3) * 0.7
    parts = [(0, boom + blast)]
    r = S.rng()
    for _ in range(10):
        parts.append((r.uniform(0.05, 0.6), metal(r.uniform(400, 1400), 0.05) * r.uniform(0.08, 0.2)))
    return small_room(fade_out(seq(parts), 0.2), 0.8, 0.25)


def player_hurt():
    n = N(0.3)
    crunch = S.soft_clip(S.lowpass(S.noise(n), 1400) * 3, 3) * S.exp_decay(n, 0.05) * 0.5
    thud = S.sine(chirp(120, 60, n), n) * S.exp_decay(n, 0.07) * 0.6
    return fade_out(crunch + thud)


def shield_hit():
    n = N(0.35)
    return fade_out(S.fm(chirp(700, 500, n), n, 1.5, 4.0, S.exp_decay(n, 0.05)) * S.exp_decay(n, 0.1) * 0.35)


def saw_swipe():
    n = N(0.3)
    whoosh = S.bandpass(S.noise(n), 900, 5000) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.5
    buzz = S.lowpass(S.saw(180 + 40 * np.sin(np.linspace(0, 6, n)), n), 2500) * np.sin(np.linspace(0, np.pi, n)) * 0.25
    return fade_out(whoosh + buzz)


def sentinel_shot():
    n1 = N(0.28)
    charge = S.sine(chirp(300, 1100, n1, 0.7), n1) * np.linspace(0.1, 0.5, n1)
    n2 = N(0.35)
    zap = S.fm(chirp(900, 200, n2), n2, 2.1, 5.0, S.exp_decay(n2, 0.05)) * S.exp_decay(n2, 0.09) * 0.5
    return fade_out(seq([(0, charge * 0.5), (0.26, zap)]))


def telegraph():
    n = N(0.95)
    f = chirp(180, 620, n, 1.2)
    gate = 0.6 + 0.4 * (np.sin(2 * np.pi * np.cumsum(chirp(6, 22, n)) / SR) > 0)
    return fade_out(S.lowpass(S.square(f, n, 0.4), 2500) * gate * np.linspace(0.2, 0.5, n) * 0.6)


def slam():
    S.seed(12)
    n = N(1.5)
    boom = S.sine(chirp(60, 28, n), n) * S.exp_decay(n, 0.35)
    rumble = S.lowpass(S.noise(n), 400) * S.exp_decay(n, 0.4) * 1.2
    crack = S.bandpass(S.noise(n), 600, 5000) * S.exp_decay(n, 0.04) * 0.6
    return small_room(fade_out(boom + rumble + crack, 0.2), 1.0, 0.3)


def dash():
    n = N(0.4)
    x = S.bandpass(S.noise(n), 500, 6000)
    x = S.sweep_lowpass(x, 1000, 7000, curve=0.4) * np.sin(np.linspace(0, np.pi, n)) ** 1.5 * 0.7
    return fade_out(x + S.sine(chirp(400, 1600, n), n) * S.exp_decay(n, 0.15) * 0.15)


def turret_deploy():
    parts = [(0, metal(180, 0.08) * 0.5), (0.12, metal(260, 0.06) * 0.4), (0.22, metal(210, 0.1) * 0.45)]
    n = N(0.5)
    parts.append((0.25, S.sine(chirp(400, 1400, n), n) * S.adsr(n, 0.05, 0.1, 0.5, 0.2) * 0.15))
    return small_room(seq(parts), 0.5, 0.2)


def nova():
    n = N(1.3)
    swell = S.sweep_lowpass(S.noise(n), 600, 9000, curve=0.3) * S.exp_decay(n, 0.35) * 0.5
    cluster = seq([(i * 0.03, bell(m, 0.6, 3.0, 1.5) * 0.18) for i, m in enumerate((79, 83, 86, 91))])
    return small_room(fade_out(seq([(0, swell), (0, cluster)])), 1.2, 0.35)


def death():
    S.seed(13)
    n = N(1.8)
    f = chirp(420, 35, n, 0.7)
    x = S.lowpass(S.saw(f, n) * 0.5 + S.square(f * 0.5, n) * 0.3, 1800) * S.adsr(n, 0.01, 0.3, 0.8, 0.8)
    crack = S.highpass(S.noise(n), 2500) * (S.rng().random(n) > 0.97) * np.linspace(0.6, 0, n)
    return small_room(fade_out(x * 0.5 + crack * 0.4 + enemy_die()[:n] * 0.4), 0.8, 0.3)


def respawn():
    n = N(1.0)
    x = S.lowpass(S.saw(chirp(60, 440, n, 0.7), n), 2500) * S.adsr(n, 0.05, 0.3, 0.7, 0.3) * 0.25
    return small_room(seq([(0, x), (0.7, bell(84, 0.4) * 0.3), (0.8, bell(91, 0.6) * 0.3)]), 0.9, 0.3)


# ---------------------------------------------------------------- travel

def takeoff():
    S.seed(14)
    n = N(2.4)
    rumble = S.sweep_lowpass(S.noise(n), 200, 3500, curve=1.5) * S.adsr(n, 0.3, 0.5, 0.9, 0.6) * 0.8
    tone = S.sine(chirp(50, 220, n, 1.3), n) * S.adsr(n, 0.5, 0.5, 0.8, 0.6) * 0.3
    return fade_out(rumble + tone, 0.3)


def atmo_entry():
    S.seed(15)
    n = N(2.2)
    x = S.sweep_lowpass(S.noise(n), 5000, 250, curve=0.6) * S.adsr(n, 0.4, 0.4, 0.8, 0.8) * 0.8
    return fade_out(x, 0.3)


def warp():
    S.seed(16)
    n = N(3.0)
    f = chirp(80, 2400, n, 2.2)
    sweep = sum(S.saw(f * d, n) for d in (0.99, 1.0, 1.01)) / 3
    sweep = S.lowpass(sweep, 4000) * S.adsr(n, 0.6, 0.4, 0.9, 0.2, hold=2.3) * 0.3
    swell = S.sweep_lowpass(S.noise(n), 300, 8000, curve=2.0) * np.linspace(0, 0.5, n) ** 2
    n2 = N(1.8)
    boom = S.sine(chirp(90, 30, n2), n2) * S.exp_decay(n2, 0.35) * 0.9
    return small_room(fade_out(seq([(0, sweep + swell), (2.35, boom)]), 0.3), 1.5, 0.4)


# ---------------------------------------------------------------- ambience / creatures

def wind_loop():
    S.seed(17)
    n = N(10.0)
    t = t_axis(n)
    gust = 0.45 + 0.35 * np.sin(2 * np.pi * 0.11 * t) + 0.2 * np.sin(2 * np.pi * 0.27 * t + 1.3)
    x = S.lowpass(S.noise(n), 500) * gust * 1.4 + S.bandpass(S.noise(n), 700, 1800) * gust ** 3 * 0.25
    return S.crossfade_loop(x * 0.5, 1.5)


def chirp_call(seed_):
    S.seed(seed_)
    r = S.rng()
    parts = []
    tt = 0.0
    for _ in range(int(r.integers(2, 4))):
        n = N(r.uniform(0.06, 0.14))
        f0, f1 = r.uniform(1400, 2600), r.uniform(1800, 3600)
        vib = 1 + 0.03 * np.sin(2 * np.pi * 38 * t_axis(n))
        parts.append((tt, S.sine(chirp(f0, f1, n) * vib, n) * np.sin(np.linspace(0, np.pi, n)) * 0.35))
        tt += len(parts[-1][1]) / SR + r.uniform(0.02, 0.08)
    return small_room(seq(parts), 0.4, 0.2)


def coin():
    parts = [(0, bell(100, 0.12, 1.5, 2.0) * 0.4), (0.05, bell(107, 0.25, 1.5, 2.0) * 0.4),
             (0.0, S.highpass(S.noise(N(0.05)), 5000) * S.exp_decay(N(0.05), 0.008) * 0.3)]
    return small_room(seq(parts), 0.4, 0.2)


def laser_loop():
    S.seed(31)
    n = N(1.6)
    t = t_axis(n)
    hum = S.saw(180 * (1 + 0.01 * np.sin(2 * np.pi * 7 * t)), n) * 0.35 + S.square(362, n, 0.3) * 0.12
    hum = S.lowpass(hum, 2600)
    sizzle = S.bandpass(S.noise(n), 2500, 9000) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t)) * 0.25
    return S.crossfade_loop(hum + sizzle, 0.2)


def klaxon():
    parts = []
    for k in range(3):
        n = N(0.32)
        f = chirp(520, 760, n, 0.6)
        tone = S.lowpass(S.square(f, n, 0.45) * 0.5 + S.saw(f * 0.5, n) * 0.3, 2400) * S.adsr(n, 0.01, 0.05, 0.8, 0.06)
        parts.append((k * 0.42, tone * 0.5))
    return small_room(seq(parts), 0.6, 0.25)


# ---------------------------------------------------------------- ocean + orbit

def sonar_ping():
    # a clean ping with the long echo of open water
    n = N(0.5)
    ping = S.sine(1250, n) * S.exp_decay(n, 0.09) * 0.6 + S.sine(2500, n) * S.exp_decay(n, 0.03) * 0.15
    parts = [(0, ping)]
    for k, g in enumerate((0.35, 0.2, 0.11, 0.06)):
        parts.append((0.32 * (k + 1), S.lowpass(ping, 2200 - k * 350) * g))
    return small_room(fade_out(seq(parts), 0.1), 2.0, 0.45, damp=2500)


def splash():
    S.seed(41)
    n = N(0.9)
    body = S.sweep_lowpass(S.noise(n), 5000, 700, curve=0.5) * S.adsr(n, 0.005, 0.15, 0.35, 0.5) * 0.8
    thump = S.sine(chirp(140, 60, n), n) * S.exp_decay(n, 0.08) * 0.5
    return fade_out(seq([(0, body + thump), (0.05, bubble_pop() * 0.4)])[:n], 0.15)


def bubble_pop():
    S.seed(42)
    r = S.rng()
    parts = []
    for k in range(7):
        n = N(r.uniform(0.04, 0.09))
        f0 = r.uniform(500, 1400)
        parts.append((r.uniform(0, 0.45), S.sine(chirp(f0, f0 * 2.2, n, 0.6), n) * S.exp_decay(n, 0.02) * r.uniform(0.2, 0.45)))
    return fade_out(seq(parts), 0.05)


def ocean_loop():
    # the hush of deep water: low swell, far-off rumble, the odd bubble
    S.seed(43)
    n = N(12.0)
    t = t_axis(n)
    swell = 0.55 + 0.3 * np.sin(2 * np.pi * 0.07 * t) + 0.15 * np.sin(2 * np.pi * 0.19 * t + 2.0)
    x = S.lowpass(S.noise(n), 260) * swell * 1.6 + S.bandpass(S.noise(n), 300, 900) * swell ** 2 * 0.12
    r = S.rng()
    for k in range(10):
        b = bubble_pop() * 0.15
        i = int(r.uniform(0.5, 11.0) * SR)
        x[i:i + len(b)] += b[:len(x) - i]
    return S.crossfade_loop(x * 0.55, 2.0)


def whale_call():
    # the leviathan: a slow moan that bends up then sighs down
    S.seed(44)
    n = N(3.2)
    f = 95 * (1 + 0.35 * np.sin(np.linspace(0, np.pi, n)) ** 1.5) * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * t_axis(n)))
    voice = S.saw(f, n) * 0.5 + S.sine(f * 2.01, n) * 0.3 + S.sine(f * 3.0, n) * 0.12
    voice = S.bandpass(voice, 120, 900) * S.adsr(n, 0.7, 0.4, 0.8, 1.2) * 0.8
    return small_room(fade_out(voice, 0.4), 2.5, 0.55, damp=1800)


def jelly_sting():
    n = N(0.35)
    crackle = S.highpass(S.noise(n), 3000) * (S.rng().random(n) > 0.9) * S.exp_decay(n, 0.1)
    zap = S.fm(chirp(1800, 900, n), n, 3.1, 4.0, S.exp_decay(n, 0.05)) * S.exp_decay(n, 0.08) * 0.35
    return fade_out(crackle * 0.5 + zap)


def probe_launch():
    S.seed(45)
    clunk = metal(160, 0.07) * 0.6
    n = N(0.9)
    hiss = S.sweep_lowpass(S.noise(n), 6000, 900, curve=0.5) * S.exp_decay(n, 0.25) * 0.5
    whine = S.sine(chirp(300, 1100, n, 0.6), n) * S.adsr(n, 0.05, 0.3, 0.4, 0.3) * 0.2
    return small_room(fade_out(seq([(0, clunk), (0.05, hiss), (0.08, whine)]), 0.15), 0.7, 0.25)


def probe_reel_loop():
    # a winch: geared whirr with a ratchet click
    S.seed(46)
    n = N(1.2)
    t = t_axis(n)
    whirr = S.lowpass(S.saw(140 + 6 * np.sin(2 * np.pi * 3 * t), n), 1400) * 0.35 + S.square(420, n, 0.2) * 0.04
    clicks = np.zeros(n)
    for k in range(12):
        c = metal(2200, 0.012) * 0.25
        i = int(k * n / 12)
        clicks[i:i + len(c)] += c[:n - i]
    return S.crossfade_loop(whirr + clicks, 0.1)


def gem_lock():
    # a bright crystalline chord with shimmer: you got something rare
    parts = [(i * 0.06, bell(m, 0.9, 3.0, 1.2) * 0.3) for i, m in enumerate((84, 88, 91, 96))]
    n = N(1.2)
    shimmer = S.bandpass(S.noise(n), 6000, 12000) * S.exp_decay(n, 0.3) * 0.15 * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * t_axis(n)))
    parts.append((0.0, shimmer))
    return small_room(fade_out(seq(parts), 0.2), 1.6, 0.4)


def probe_lost():
    S.seed(47)
    n = N(1.0)
    crunch = S.bandpass(S.noise(n), 300, 3000) * S.exp_decay(n, 0.06) * 0.8
    fizz = S.highpass(S.noise(n), 4000) * S.exp_decay(n, 0.4) * 0.25
    drop = S.sine(chirp(600, 90, n, 0.5), n) * S.exp_decay(n, 0.25) * 0.3
    return fade_out(crunch + fizz + drop, 0.2)


def orbit_hum_loop():
    # the ship holding station: a steady, gently beating engine hum
    n = N(6.0)
    t = t_axis(n)
    hum = S.sine(55, n) * 0.4 + S.sine(55.4, n) * 0.3 + S.sine(110.2, n) * 0.12
    air = S.lowpass(S.noise(n), 900) * (0.5 + 0.2 * np.sin(2 * np.pi * 0.2 * t)) * 0.2
    return S.crossfade_loop(hum + air, 1.0)


# ---------------------------------------------------------------- homespace

def home_enter():
    # dropping into your own head: a rising digital shimmer that lands on a warm chord
    n = N(0.7)
    sweep = S.sweep_lowpass(S.noise(n), 800, 9000, curve=0.4) * np.linspace(0, 1, n) ** 2 * 0.25
    blips = seq([(i * 0.05, S.square(S.midi_hz(72 + i * 4), N(0.04), 0.3) * S.exp_decay(N(0.04), 0.015) * 0.2) for i in range(6)])
    chord = seq([(0.3 + i * 0.03, bell(m, 0.8, 2.0, 1.0) * 0.25) for i, m in enumerate((72, 76, 79, 83))])
    return small_room(fade_out(seq([(0, sweep), (0.05, blips), (0, chord)]), 0.2), 1.2, 0.35)


def home_exit():
    n = N(0.6)
    sweep = S.sweep_lowpass(S.noise(n), 9000, 600, curve=0.6) * S.exp_decay(n, 0.2) * 0.3
    blips = seq([(i * 0.05, S.square(S.midi_hz(88 - i * 4), N(0.04), 0.3) * S.exp_decay(N(0.04), 0.015) * 0.2) for i in range(6)])
    return small_room(fade_out(seq([(0, sweep), (0.02, blips)]), 0.15), 0.8, 0.3)


def hyper_loop():
    # the roar of hyperspace: a deep rushing wind with a shimmering whine
    S.seed(61)
    n = N(8.0)
    t = t_axis(n)
    rush = S.bandpass(S.noise(n), 120, 1400) * (0.6 + 0.25 * np.sin(2 * np.pi * 0.25 * t)) * 1.2
    whine = S.sine(880 + 30 * np.sin(2 * np.pi * 0.5 * t), n) * 0.04 + S.sine(1320 + 20 * np.sin(2 * np.pi * 0.37 * t), n) * 0.025
    sub = S.sine(48, n) * 0.35
    return S.crossfade_loop(rush * 0.5 + whine + sub, 1.0)


def volcano_rumble_loop():
    # the mountain groaning around you: sub rumble, grinding rock, far-off pops
    S.seed(71)
    n = N(9.0)
    t = t_axis(n)
    sub = S.lowpass(S.noise(n), 90) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.13 * t)) * 3.0
    grind = S.bandpass(S.noise(n), 150, 600) * (0.4 + 0.3 * np.sin(2 * np.pi * 0.31 * t + 1.0)) * 0.6
    r = S.rng()
    for k in range(7):
        i = int(r.uniform(0.3, 8.5) * SR)
        m = N(0.2)
        pop = S.lowpass(S.noise(m), 800) * S.exp_decay(m, 0.03) * 0.6
        sub[i:i + m] += pop[:n - i]
    return S.crossfade_loop(sub + grind, 1.2)


# ---------------------------------------------------------------- Micro Lab (the soup)

def _bloop(f0, f1, dur, vel=1.0, tau=0.08):
    # a bubble: a sine whose pitch rises as it closes
    n = N(dur)
    return S.sine(chirp(f0, f1, n, 0.5), n) * S.exp_decay(n, tau) * vel


def lab_zap():
    # a thin probe ray: a fast falling buzz with a fizz on top
    n = N(0.13)
    buzz = S.square(chirp(2400, 700, n, 0.6), n, 0.3) * S.exp_decay(n, 0.05) * 0.35
    fizz = S.bandpass(S.noise(n), 3000, 9000) * S.exp_decay(n, 0.03) * 0.25
    return fade_out(buzz + fizz, 0.02)


def lab_tag():
    parts = [(0.0, S.sine(S.midi_hz(84), N(0.08)) * S.exp_decay(N(0.08), 0.03) * 0.4),
             (0.05, S.sine(S.midi_hz(91), N(0.1)) * S.exp_decay(N(0.1), 0.04) * 0.35)]
    return small_room(fade_out(seq(parts), 0.02), 0.4, 0.2)


def lab_fuse():
    # two cells squelch into one: a low gloop, a bubble and a warm chime
    gloop = _bloop(90, 260, 0.35, 0.9, 0.12)
    wet = S.lowpass(S.noise(N(0.3)), 900) * S.exp_decay(N(0.3), 0.06) * 0.3
    chime = seq([(0.12, bell(m, 0.5, 2.0, 0.8) * 0.18) for m in (76, 83)])
    return small_room(fade_out(seq([(0, gloop), (0, wet), (0.1, _bloop(500, 1300, 0.08, 0.35, 0.02)), (0, chime)]), 0.1), 0.8, 0.3)


def lab_divide():
    # a cell pinching in two: a stretchy rise and a soft pop
    stretch = _bloop(180, 420, 0.25, 0.6, 0.1)
    pop = _bloop(700, 1600, 0.06, 0.5, 0.015)
    return small_room(fade_out(seq([(0, stretch), (0.2, pop)]), 0.05), 0.5, 0.25)


def lab_pop():
    # a phage zapped: a wet crunchy splat
    n = N(0.22)
    crunch = S.bandpass(S.noise(n), 600, 4000) * S.exp_decay(n, 0.04) * 0.6
    thud = S.sine(chirp(220, 80, n), n) * S.exp_decay(n, 0.05) * 0.5
    return fade_out(seq([(0, crunch + thud), (0.02, _bloop(900, 2000, 0.05, 0.3, 0.012))]), 0.03)


def lab_armor():
    return fade_out(seq([(0, metal(1900, 0.08) * 0.5), (0, metal(2600, 0.05) * 0.3)]), 0.02)


def lab_infect():
    # a cell lost to a phage: a sinking, gurgling wobble
    n = N(0.6)
    t = t_axis(n)
    f = chirp(420, 110, n, 0.7) * (1 + 0.08 * np.sin(2 * np.pi * 18 * t))
    return small_room(fade_out(S.sine(f, n) * S.exp_decay(n, 0.25) * 0.6 + S.lowpass(S.noise(n), 700) * S.exp_decay(n, 0.1) * 0.2, 0.1), 0.6, 0.3)


def lab_phage():
    # a phage drifting in: a small sour two-note sting
    parts = [(0.0, S.saw(S.midi_hz(62), N(0.12)) * S.exp_decay(N(0.12), 0.05) * 0.2),
             (0.08, S.saw(S.midi_hz(63), N(0.16)) * S.exp_decay(N(0.16), 0.06) * 0.2)]
    return small_room(fade_out(S.lowpass(seq(parts), 2200), 0.03), 0.5, 0.25)


def lab_stir():
    # a ladle through the broth: a slow sloshing swell with bubbles
    S.seed(77)
    r = S.rng()
    n = N(1.6)
    t = t_axis(n)
    slosh = S.bandpass(S.noise(n), 200, 1200) * np.sin(np.pi * t / 1.6) ** 2 * (0.7 + 0.3 * np.sin(2 * np.pi * 2.2 * t)) * 0.5
    bubbles = seq([(r.uniform(0.2, 1.3), _bloop(r.uniform(300, 700), r.uniform(900, 1600), 0.07, 0.25, 0.02)) for _ in range(6)])
    return fade_out(seq([(0, slosh), (0, bubbles)]), 0.2)


def lab_success():
    # critical mass: a bubbling rise into a bright chord
    rise = seq([(i * 0.07, _bloop(S.midi_hz(60 + i * 3), S.midi_hz(64 + i * 3), 0.12, 0.35, 0.05)) for i in range(8)])
    chord = seq([(0.55 + i * 0.03, bell(m, 1.2, 2.0, 1.0) * 0.22) for i, m in enumerate((72, 76, 79, 84))])
    return small_room(fade_out(seq([(0, rise), (0, chord)]), 0.3), 1.4, 0.35)


def lab_fail():
    n = N(1.0)
    sink = S.sine(chirp(300, 70, n, 0.6), n) * S.exp_decay(n, 0.45) * 0.5
    gurgle = seq([(0.1 + i * 0.12, _bloop(260 - i * 30, 180 - i * 20, 0.1, 0.3, 0.04)) for i in range(5)])
    return small_room(fade_out(seq([(0, sink), (0, gurgle)]), 0.2), 1.0, 0.3)


SFX = {
    "lab_zap": lab_zap, "lab_tag": lab_tag, "lab_fuse": lab_fuse, "lab_divide": lab_divide, "lab_pop": lab_pop,
    "lab_armor": lab_armor, "lab_infect": lab_infect, "lab_phage": lab_phage, "lab_stir": lab_stir,
    "lab_success": lab_success, "lab_fail": lab_fail,
    "klaxon": klaxon,
    "hyper_loop": hyper_loop, "volcano_rumble_loop": volcano_rumble_loop,
    "home_enter": home_enter, "home_exit": home_exit,
    "sonar_ping": sonar_ping, "splash": splash, "bubble_pop": bubble_pop, "ocean_loop": ocean_loop,
    "whale_call": whale_call, "jelly_sting": jelly_sting, "probe_launch": probe_launch,
    "probe_reel_loop": probe_reel_loop, "gem_lock": gem_lock, "probe_lost": probe_lost, "orbit_hum_loop": orbit_hum_loop,
    "laser_loop": laser_loop,
    "coin": coin,
    "ui_click": ui_click, "ui_open": ui_open, "ui_close": ui_close, "ui_error": ui_error, "notify": notify,
    "pickup": pickup, "craft": craft, "level_up": level_up, "quest_accept": quest_accept,
    "quest_complete": quest_complete, "skill_up": skill_up, "low_energy": low_energy,
    "step_1": lambda: footstep(1), "step_2": lambda: footstep(2), "step_3": lambda: footstep(3),
    "jump": jump, "land": land, "jet_loop": jet_loop, "thruster_loop": thruster_loop, "boost": boost,
    "drill_loop": drill_loop, "harvest_loop": harvest_loop, "siphon_loop": siphon_loop,
    "rock_break": rock_break, "plant_snap": plant_snap, "siphon_done": siphon_done, "scan": scan,
    "blaster": blaster, "turret_shot": turret_shot, "hit": hit, "crit": crit, "enemy_die": enemy_die,
    "player_hurt": player_hurt, "shield_hit": shield_hit, "saw_swipe": saw_swipe,
    "sentinel_shot": sentinel_shot, "telegraph": telegraph, "slam": slam, "dash": dash,
    "turret_deploy": turret_deploy, "nova": nova, "death": death, "respawn": respawn,
    "takeoff": takeoff, "atmo_entry": atmo_entry, "warp": warp, "wind_loop": wind_loop,
    "chirp_1": lambda: chirp_call(21), "chirp_2": lambda: chirp_call(22), "chirp_3": lambda: chirp_call(23),
}


if __name__ == "__main__":
    names = sys.argv[1:] or list(SFX)
    for name in names:
        x = SFX[name]()
        x = S.highpass(x, 30, 2) if not name.endswith("_loop") else x
        x = S.normalize(x, 0.9 if not name.endswith("_loop") else 0.7)
        S.write_wav(os.path.join(OUT, f"{name}.wav"), x)
    print(f"[sfx] wrote {len(names)} files to {OUT}")
