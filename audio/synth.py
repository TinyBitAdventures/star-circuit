"""
Tiny numpy synthesizer used to render Star Circuit's music and sound effects.
Everything is deterministic for a given seed.
"""

import numpy as np
from scipy import signal

SR = 44100
_rng = np.random.default_rng(1)


def seed(s):
    global _rng
    _rng = np.random.default_rng(s)


def rng():
    return _rng


def n_samples(sec):
    return max(1, int(round(sec * SR)))


def midi_hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


# ---------------------------------------------------------------- oscillators

def phase_of(freq, n):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.cumsum(f) / SR


def sine(freq, n, phase0=0.0):
    return np.sin(2 * np.pi * (phase_of(freq, n) + phase0))


def saw(freq, n, phase0=0.0):
    p = (phase_of(freq, n) + phase0) % 1.0
    return 2.0 * p - 1.0


def square(freq, n, pw=0.5):
    p = phase_of(freq, n) % 1.0
    return np.where(p < pw, 1.0, -1.0)


def tri(freq, n):
    p = phase_of(freq, n) % 1.0
    return 4.0 * np.abs(p - 0.5) - 1.0


def noise(n):
    return _rng.uniform(-1.0, 1.0, n)


def fm(freq, n, ratio, index, index_env=None, fb=0.0):
    """Two-operator FM. index_env multiplies the modulation index over time."""
    mod_phase = phase_of(np.asarray(freq) * ratio, n)
    idx = index * (index_env if index_env is not None else 1.0)
    mod = np.sin(2 * np.pi * mod_phase) * idx
    car_phase = phase_of(freq, n)
    return np.sin(2 * np.pi * car_phase + mod)


# ---------------------------------------------------------------- envelopes

def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2, hold=None):
    """ADSR where the note is held for `hold` sec (default: until release)."""
    a_n, d_n, r_n = n_samples(a), n_samples(d), n_samples(r)
    hold_n = n - r_n if hold is None else n_samples(hold)
    hold_n = max(hold_n, 1)
    env = np.zeros(n)
    i = 0
    seg = min(a_n, hold_n)
    env[:seg] = np.linspace(0, 1, seg, endpoint=False)
    i = seg
    seg = min(d_n, max(0, hold_n - i))
    env[i:i + seg] = np.linspace(1, s, seg, endpoint=False)
    i += seg
    if hold_n > i:
        env[i:hold_n] = s
    i = hold_n
    level = env[i - 1] if i > 0 else 0
    rest = n - i
    if rest > 0:
        env[i:] = np.linspace(level, 0, rest)
    return env


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def ramp(n, a, b, curve=1.0):
    x = np.linspace(0, 1, n) ** curve
    return a + (b - a) * x


# ---------------------------------------------------------------- filters

def _sos(kind, cutoff, order=2, q=None):
    nyq = SR / 2
    if kind in ("lowpass", "highpass"):
        return signal.butter(order, min(cutoff / nyq, 0.99), btype=kind, output="sos")
    lo, hi = cutoff
    return signal.butter(order, [max(lo / nyq, 1e-4), min(hi / nyq, 0.99)], btype="bandpass", output="sos")


def lowpass(x, cutoff, order=2):
    return signal.sosfilt(_sos("lowpass", cutoff, order), x, axis=-1)


def highpass(x, cutoff, order=2):
    return signal.sosfilt(_sos("highpass", cutoff, order), x, axis=-1)


def bandpass(x, lo, hi, order=2):
    return signal.sosfilt(_sos("band", (lo, hi), order), x, axis=-1)


def sweep_lowpass(x, cut_from, cut_to, block=512, curve=1.0):
    """Time-varying lowpass (block-wise with carried filter state)."""
    out = np.zeros_like(x)
    n = len(x)
    blocks = max(1, n // block)
    zi = None
    for b in range(blocks + 1):
        s, e = b * block, min(n, (b + 1) * block)
        if s >= e:
            break
        t = (s / n) ** curve
        cut = cut_from + (cut_to - cut_from) * t
        sos = _sos("lowpass", max(20.0, cut), 2)
        if zi is None:
            zi = signal.sosfilt_zi(sos) * 0.0
        out[s:e], zi = signal.sosfilt(sos, x[s:e], zi=zi)
    return out


# ---------------------------------------------------------------- effects

def reverb_ir(seconds=3.0, damp=4000.0, seed_=7, predelay=0.02):
    r = np.random.default_rng(seed_)
    n = n_samples(seconds)
    t = np.arange(n) / SR
    env = np.exp(-t * (6.9 / seconds))
    irs = []
    for ch in range(2):
        nz = r.standard_normal(n) * env
        nz = lowpass(nz, damp, 1)
        pd = np.zeros(n_samples(predelay + 0.004 * ch))
        irs.append(np.concatenate([pd, nz]))
    m = min(len(irs[0]), len(irs[1]))
    ir = np.stack([irs[0][:m], irs[1][:m]])
    return ir / np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))


def reverb(stereo, ir, wet=0.3):
    """stereo: (2, n). Output is longer by len(ir)."""
    n = stereo.shape[1]
    out = np.zeros((2, n + ir.shape[1] - 1))
    for ch in range(2):
        out[ch] = signal.fftconvolve(stereo[ch], ir[ch])
    dry = np.zeros_like(out)
    dry[:, :n] = stereo
    return dry * (1 - wet * 0.5) + out * wet


def delay(stereo, time, feedback=0.4, taps=6, pingpong=True, wet=0.3):
    d = n_samples(time)
    n = stereo.shape[1]
    out = np.zeros((2, n + d * taps))
    out[:, :n] += stereo
    g = wet
    for k in range(1, taps + 1):
        src = stereo if not pingpong else (stereo[::-1] if k % 2 else stereo)
        out[:, k * d:k * d + n] += src * g
        g *= feedback
    return out


def pan(mono, p):
    """p in [-1, 1]."""
    ang = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(ang), mono * np.sin(ang)])


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (peak / m)


def mix_into(buf, sig, start):
    """Add sig (mono or stereo) into stereo buf at sample `start` (clipped)."""
    if sig.ndim == 1:
        sig = np.stack([sig, sig])
    s = max(0, start)
    e = min(buf.shape[1], start + sig.shape[1])
    if e > s:
        buf[:, s:e] += sig[:, s - start:e - start]


def fold_loop(buf, length):
    """Wrap everything after `length` back onto the start for a seamless loop."""
    out = buf[:, :length].copy()
    tail = buf[:, length:]
    k = 0
    while tail.shape[1] > 0:
        seg = tail[:, :length]
        out[:, :seg.shape[1]] += seg
        tail = tail[:, length:]
        k += 1
    return out


def crossfade_loop(mono, fade_sec=0.25):
    """Make a mono loop seamless by overlapping its end onto its start."""
    f = n_samples(fade_sec)
    body = mono[:-f].copy()
    tail = mono[-f:]
    w = np.linspace(0, 1, f)
    body[:f] = body[:f] * w + tail * (1 - w)
    return body


# ---------------------------------------------------------------- output

def write_wav(path, x):
    from scipy.io import wavfile
    x = np.clip(x, -1, 1)
    data = (x.T if x.ndim == 2 else x) * 32767
    wavfile.write(path, SR, data.astype(np.int16))
