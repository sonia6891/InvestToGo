#!/usr/bin/env python3
"""Writes the four skins' confirm sounds (spec 7.1 音效) as CAF files, synthesised here: no recorded or third-party audio.

    python3 Scripts/make_sounds.py            # writes App/Resources/Sounds/{thud,chip,snip,scribble}.caf

Standard library only. The CAF container is written directly (Apple Core Audio Format: 'caff' header, 'desc' chunk
with 16-bit little-endian linear PCM, 'data' chunk), so no macOS tool is needed. The noise is seeded, so running it
again gives byte-identical files.

- thud (黑金): a low 「咚」, a falling sine from 140 Hz to 55 Hz with a soft click on top.
- chip (像素): an 8-bit 「叮」, two square-wave notes a fifth apart.
- snip (縫線): scissors 「喀嚓」, two short bright noise clicks with a metallic ring.
- scribble (手繪): a pencil 「沙沙」, band-limited noise in three quick strokes.
"""
import math
import os
import random
import struct

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Sounds")


def envelope(t, attack, decay):
    return min(t / attack, 1.0) * math.exp(-t * decay) if attack > 0 else math.exp(-t * decay)


def thud():
    n = int(RATE * 0.32)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        freq = 55 + 85 * math.exp(-t * 18)
        phase += 2 * math.pi * freq / RATE
        body = math.sin(phase) * envelope(t, 0.004, 11)
        click = math.sin(2 * math.pi * 900 * t) * envelope(t, 0.0005, 160) * 0.25
        out.append(0.9 * body + click)
    return out


def chip():
    n = int(RATE * 0.22)
    notes = [(1046.5, 0.0, 0.07), (1568.0, 0.06, 0.16)]
    out = []
    for i in range(n):
        t = i / RATE
        value = 0.0
        for freq, start, length in notes:
            local = t - start
            if 0 <= local < length:
                square = 1.0 if (local * freq) % 1 < 0.5 else -1.0
                value += 0.32 * square * (1 - local / length) ** 0.5
        out.append(value)
    return out


def snip(rng):
    n = int(RATE * 0.2)
    out, last = [], 0.0
    for i in range(n):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        bright = noise - last  # first difference of white noise: a thin, bright click
        last = noise
        value = 0.0
        for start in (0.0, 0.085):
            local = t - start
            if local >= 0:
                value += 0.7 * bright * envelope(local, 0.0003, 120)
                value += 0.25 * math.sin(2 * math.pi * 3150 * local) * envelope(local, 0.0005, 60)
        out.append(value)
    return out


def scribble(rng):
    n = int(RATE * 0.36)
    strokes = [(0.0, 0.1), (0.12, 0.1), (0.24, 0.11)]
    out, low, band = [], 0.0, 0.0
    for i in range(n):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += 0.35 * (noise - low)       # gentle low-pass
        band = low - band * 0.6           # take some of the rumble out
        gain = 0.0
        for start, length in strokes:
            local = t - start
            if 0 <= local < length:
                gain += math.sin(math.pi * local / length) ** 2 * (0.8 + 0.2 * math.sin(2 * math.pi * 38 * local))
        out.append(0.55 * band * gain)
    return out


def normalise(samples, peak=0.8):
    top = max(abs(s) for s in samples) or 1.0
    fade = int(RATE * 0.004)
    result = []
    for i, s in enumerate(samples):
        tail = min(1.0, (len(samples) - 1 - i) / fade)
        result.append(s / top * peak * tail)
    return result


def write_caf(path, samples):
    pcm = b"".join(struct.pack("<h", max(-32767, min(32767, int(round(s * 32767))))) for s in samples)
    # CAF 'desc': sample rate, 'lpcm', flags kCAFLinearPCMFormatFlagIsLittleEndian (2; integer samples are signed),
    # 2 bytes per packet, 1 frame per packet, 1 channel, 16 bits per channel.
    desc = struct.pack(">d4sIIIII", float(RATE), b"lpcm", 2, 2, 1, 1, 16)
    assert len(desc) == 32
    with open(path, "wb") as f:
        f.write(b"caff" + struct.pack(">HH", 1, 0))
        f.write(b"desc" + struct.pack(">q", len(desc)) + desc)
        data = struct.pack(">I", 0) + pcm  # edit count, then the samples
        f.write(b"data" + struct.pack(">q", len(data)) + data)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(12)
    sounds = {"thud": thud(), "chip": chip(), "snip": snip(rng), "scribble": scribble(rng)}
    for name, samples in sounds.items():
        path = os.path.join(OUT, name + ".caf")
        write_caf(path, normalise(samples))
        print(f"{os.path.relpath(path)}  {len(samples) / RATE:.2f} s")


if __name__ == "__main__":
    main()
