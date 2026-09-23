"""Objective checks on rendered audio: levels, clipping, loop seam, brightness + spectrogram PNGs."""
import os, subprocess, sys, tempfile
import numpy as np
from scipy.io import wavfile
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def load(path):
    tmp = os.path.join(tempfile.gettempdir(), "sc_an.wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, tmp], check=True)
    sr, x = wavfile.read(tmp)
    x = x.astype(np.float64) / 32768.0
    return sr, (x.mean(axis=1) if x.ndim == 2 else x)

out_png = sys.argv[1]
files = sys.argv[2:]
fig, axes = plt.subplots(len(files), 1, figsize=(12, 2.1 * len(files)))
axes = np.atleast_1d(axes)
for ax, f in zip(axes, files):
    sr, x = load(f)
    peak = np.max(np.abs(x)); rms = np.sqrt(np.mean(x ** 2))
    clip = np.mean(np.abs(x) > 0.99) * 100
    seam = abs(x[0] - x[-1]); step = np.median(np.abs(np.diff(x)))
    spec = np.abs(np.fft.rfft(x)); freqs = np.fft.rfftfreq(len(x), 1 / sr)
    centroid = np.sum(freqs * spec) / np.sum(spec)
    # loudness over time (1s windows) to spot silent gaps / spikes
    w = sr; lv = [np.sqrt(np.mean(x[i:i + w] ** 2)) for i in range(0, len(x) - w, w)]
    print(f"{os.path.basename(f):22s} dur={len(x)/sr:6.1f}s peak={peak:.2f} rms={20*np.log10(rms):6.1f}dB clip={clip:.3f}% "
          f"seam={seam:.4f} (typ step {step:.4f}) centroid={centroid:6.0f}Hz loud[min/max]={20*np.log10(min(lv)+1e-9):.0f}/{20*np.log10(max(lv)):.0f}dB")
    ax.specgram(x, NFFT=2048, Fs=sr, noverlap=1024, cmap="magma", vmin=-120)
    ax.set_ylim(0, 8000); ax.set_title(os.path.basename(f), fontsize=9); ax.set_yticks([])
plt.tight_layout(); plt.savefig(out_png, dpi=70)
