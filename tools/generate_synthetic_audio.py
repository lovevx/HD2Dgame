"""Generate replaceable prototype audio for the game using only Python's standard library."""

from array import array
import math
from pathlib import Path
import random
import struct
import wave


SAMPLE_RATE = 22050
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "audio" / "synth"


def write_wave(path: Path, samples: array, channels: int) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite existing audio: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = array("h")
    for value in samples:
        pcm.append(max(-32767, min(32767, round(value * 32767))))
    if struct.pack("=h", 1) != struct.pack("<h", 1):
        pcm.byteswap()
    with wave.open(str(path), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def envelope(time: float, duration: float, attack: float, release: float, decay: float = 0.0) -> float:
    if time < 0.0 or time >= duration:
        return 0.0
    rise = min(1.0, time / max(0.001, attack))
    tail = min(1.0, (duration - time) / max(0.001, release))
    return rise * tail * math.exp(-decay * time)


def effect_sample(name: str, time: float, duration: float, noise: float) -> float:
    if name == "ui_hover":
        env = envelope(time, duration, 0.004, 0.035, 8.0)
        return math.sin(2.0 * math.pi * 920.0 * time) * env * 0.3
    if name == "ui_confirm":
        value = 0.0
        for start, frequency in ((0.0, 587.33), (0.075, 880.0)):
            local = time - start
            value += math.sin(2.0 * math.pi * frequency * local) * envelope(local, 0.16, 0.004, 0.11, 9.0) * 0.26
        return value
    if name == "ui_back":
        env = envelope(time, duration, 0.004, 0.075, 7.0)
        frequency = 680.0 - 260.0 * min(1.0, time / duration)
        return math.sin(2.0 * math.pi * frequency * time) * env * 0.3
    if name == "sword_swing":
        progress = min(1.0, time / duration)
        env = envelope(time, duration, 0.008, 0.11, 4.0)
        frequency = 920.0 - 640.0 * progress
        return (noise * 0.3 + math.sin(2.0 * math.pi * frequency * time) * 0.55) * env * 0.6
    if name == "kick":
        env = envelope(time, duration, 0.003, 0.13, 5.0)
        frequency = 118.0 - 48.0 * min(1.0, time / duration)
        click = noise * envelope(time, 0.035, 0.001, 0.025, 25.0) * 0.25
        return (math.sin(2.0 * math.pi * frequency * time) * 0.8 + click) * env * 0.65
    if name == "magic_cast":
        value = 0.0
        for start, frequency in ((0.0, 392.0), (0.12, 587.33), (0.25, 783.99), (0.39, 988.0)):
            local = time - start
            env = envelope(local, 0.32, 0.012, 0.24, 4.0)
            value += (math.sin(2.0 * math.pi * frequency * local) + 0.3 * math.sin(4.0 * math.pi * frequency * local)) * env * 0.15
        return value
    if name == "healing":
        value = 0.0
        for start, frequency in ((0.0, 523.25), (0.14, 659.25), (0.28, 783.99), (0.44, 1046.5)):
            local = time - start
            env = envelope(local, 0.4, 0.012, 0.32, 3.0)
            value += (math.sin(2.0 * math.pi * frequency * local) + 0.22 * math.sin(4.0 * math.pi * frequency * local)) * env * 0.13
        return value
    if name == "gunshot":
        env = envelope(time, duration, 0.001, 0.16, 10.0)
        low = math.sin(2.0 * math.pi * (82.0 - 34.0 * time / duration) * time) * 0.8
        crack = noise * envelope(time, 0.06, 0.001, 0.05, 15.0) * 0.75
        return (low + crack) * env * 0.75
    if name == "bomb":
        progress = min(1.0, time / duration)
        env = envelope(time, duration, 0.02, 0.25, 2.0)
        tone = math.sin(2.0 * math.pi * (260.0 + progress * 480.0) * time) * 0.45
        return (tone + noise * 0.18) * env * 0.55
    if name == "explosion":
        env = envelope(time, duration, 0.002, 0.42, 3.2)
        frequency = 74.0 - 36.0 * min(1.0, time / duration)
        rumble = math.sin(2.0 * math.pi * frequency * time) * 0.95
        crack = noise * envelope(time, 0.24, 0.001, 0.19, 8.0) * 0.75
        return (rumble + crack) * env * 0.82
    if name == "enemy_attack":
        env = envelope(time, duration, 0.006, 0.08, 4.0)
        frequency = 230.0 + 110.0 * min(1.0, time / duration)
        return (math.sin(2.0 * math.pi * frequency * time) * 0.8 + noise * 0.08) * env * 0.48
    if name == "enemy_hit":
        env = envelope(time, duration, 0.002, 0.1, 8.0)
        frequency = 165.0 - 62.0 * min(1.0, time / duration)
        return (math.sin(2.0 * math.pi * frequency * time) * 0.78 + noise * 0.22) * env * 0.66
    if name == "enemy_death":
        env = envelope(time, duration, 0.004, 0.19, 4.0)
        frequency = 370.0 - 225.0 * min(1.0, time / duration)
        return (math.sin(2.0 * math.pi * frequency * time) + noise * 0.08) * env * 0.42
    if name == "player_hurt":
        env = envelope(time, duration, 0.002, 0.16, 4.0)
        frequency = 390.0 - 175.0 * min(1.0, time / duration)
        return (math.sin(2.0 * math.pi * frequency * time) * 0.7 + noise * 0.25) * env * 0.62
    if name == "coin":
        value = 0.0
        for start, frequency in ((0.0, 1318.5), (0.08, 1760.0)):
            local = time - start
            env = envelope(local, 0.27, 0.002, 0.23, 4.0)
            value += (math.sin(2.0 * math.pi * frequency * local) + 0.25 * math.sin(4.0 * math.pi * frequency * local)) * env * 0.18
        return value
    if name == "pickup":
        value = 0.0
        for start, frequency in ((0.0, 659.25), (0.11, 783.99), (0.22, 987.77)):
            local = time - start
            env = envelope(local, 0.28, 0.006, 0.22, 4.0)
            value += math.sin(2.0 * math.pi * frequency * local) * env * 0.17
        return value
    if name == "chest":
        value = 0.0
        for start, frequency in ((0.0, 392.0), (0.16, 523.25), (0.34, 783.99)):
            local = time - start
            env = envelope(local, 0.48, 0.012, 0.38, 3.0)
            value += (math.sin(2.0 * math.pi * frequency * local) + 0.2 * math.sin(4.0 * math.pi * frequency * local)) * env * 0.16
        return value
    if name == "quest_complete":
        value = 0.0
        for start, frequency in ((0.0, 523.25), (0.17, 659.25), (0.34, 783.99), (0.55, 1046.5)):
            local = time - start
            env = envelope(local, 0.55, 0.008, 0.47, 2.7)
            value += (math.sin(2.0 * math.pi * frequency * local) + 0.2 * math.sin(4.0 * math.pi * frequency * local)) * env * 0.16
        return value
    if name == "boss_roar":
        env = envelope(time, duration, 0.06, 0.28, 0.7)
        wobble = math.sin(2.0 * math.pi * 4.0 * time) * 17.0
        fundamental = math.sin(2.0 * math.pi * (94.0 + wobble) * time)
        overtone = math.sin(2.0 * math.pi * (188.0 + wobble * 1.5) * time) * 0.38
        return (fundamental + overtone + noise * 0.16) * env * 0.58
    if name == "footstep":
        env = envelope(time, duration, 0.001, 0.08, 12.0)
        frequency = 92.0 - 26.0 * min(1.0, time / duration)
        return (math.sin(2.0 * math.pi * frequency * time) * 0.7 + noise * 0.3) * env * 0.58
    return 0.0


EFFECTS = {
    "ui_hover": 0.075, "ui_confirm": 0.25, "ui_back": 0.16,
    "sword_swing": 0.26, "kick": 0.26, "magic_cast": 0.72, "healing": 0.82,
    "gunshot": 0.28, "bomb": 0.5, "explosion": 0.78,
    "enemy_attack": 0.24, "enemy_hit": 0.2, "enemy_death": 0.4, "player_hurt": 0.35,
    "coin": 0.4, "pickup": 0.58, "chest": 0.85, "quest_complete": 1.15,
    "boss_roar": 1.25, "footstep": 0.12,
}


def generate_effect(name: str, duration: float) -> None:
    rng = random.Random(217 + sum(ord(char) for char in name))
    samples = array("f")
    peak = 0.0
    count = round(duration * SAMPLE_RATE)
    for index in range(count):
        value = effect_sample(name, index / SAMPLE_RATE, duration, rng.uniform(-1.0, 1.0))
        samples.append(value)
        peak = max(peak, abs(value))
    if peak > 0.0:
        gain = 0.66 / peak
        for index in range(count):
            samples[index] *= gain
    write_wave(OUTPUT / "sfx" / f"{name}.wav", samples, 1)


def midi_hz(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def add_music_note(left: array, right: array, start: float, duration: float, frequency: float,
                   amplitude: float, pan: float, instrument: str) -> None:
    start_index = max(0, round(start * SAMPLE_RATE))
    end_index = min(len(left), round((start + duration) * SAMPLE_RATE))
    if end_index <= start_index:
        return
    pan = max(-0.95, min(0.95, pan))
    left_gain = math.sqrt((1.0 - pan) * 0.5)
    right_gain = math.sqrt((1.0 + pan) * 0.5)
    attack = 0.36 if instrument == "pad" else (0.018 if instrument == "bass" else 0.008)
    release = 0.42 if instrument == "pad" else (0.12 if instrument == "bass" else min(0.2, duration * 0.36))
    decay = 0.05 if instrument == "pad" else (1.1 if instrument == "bass" else 3.6)
    for index in range(start_index, end_index):
        local = index / SAMPLE_RATE - start
        env = envelope(local, duration, attack, release, decay)
        if env <= 0.0:
            continue
        vibrato = 1.0 + 0.002 * math.sin(2.0 * math.pi * 4.2 * local) if instrument == "pad" else 1.0
        phase = 2.0 * math.pi * frequency * vibrato * local
        tone = math.sin(phase)
        if instrument == "pad":
            tone = tone * 0.72 + math.sin(phase * 2.0) * 0.19 + math.sin(phase * 3.0) * 0.09
        elif instrument == "bell":
            tone = tone * 0.76 + math.sin(phase * 2.0) * 0.2 + math.sin(phase * 3.01) * 0.04
        else:
            tone = tone * 0.86 + math.sin(phase * 2.0) * 0.14
        value = tone * env * amplitude
        left[index] += value * left_gain
        right[index] += value * right_gain


def add_drum(left: array, right: array, start: float, duration: float, seed: int, amplitude: float) -> None:
    rng = random.Random(seed)
    start_index = round(start * SAMPLE_RATE)
    end_index = min(len(left), round((start + duration) * SAMPLE_RATE))
    for index in range(start_index, end_index):
        local = index / SAMPLE_RATE - start
        env = envelope(local, duration, 0.001, 0.09, 14.0)
        noise = rng.uniform(-1.0, 1.0)
        tone = math.sin(2.0 * math.pi * (78.0 - 25.0 * local / duration) * local)
        value = (noise * 0.25 + tone * 0.75) * env * amplitude
        left[index] += value * 0.72
        right[index] += value * 0.72


THEMES = {
    "title": {"bpm": 72, "root": 50, "scale": (0, 2, 3, 7, 10), "progression": (0, 3, 1, 4), "density": 0.65, "battle": False},
    "harbor": {"bpm": 88, "root": 50, "scale": (0, 2, 4, 7, 9), "progression": (0, 4, 1, 3), "density": 0.85, "battle": False},
    "journey": {"bpm": 98, "root": 45, "scale": (0, 3, 5, 7, 10), "progression": (0, 3, 4, 2), "density": 0.9, "battle": False},
    "battle": {"bpm": 114, "root": 45, "scale": (0, 3, 5, 7, 10), "progression": (0, 3, 4, 0), "density": 1.0, "battle": True},
}


def generate_theme(name: str, config: dict) -> None:
    beat = 60.0 / config["bpm"]
    duration = beat * 4.0 * 8.0
    frame_count = round(duration * SAMPLE_RATE)
    left = array("f", [0.0]) * frame_count
    right = array("f", [0.0]) * frame_count
    scale = config["scale"]
    progression = config["progression"]
    density = config["density"]
    root = config["root"]
    arp_pattern = (0, 2, 1, 3, 2, 4, 1, 2)

    for bar in range(8):
        bar_start = bar * beat * 4.0
        degree = progression[bar % len(progression)]
        chord_root = root + scale[degree]
        chord_notes = (chord_root, chord_root + scale[(degree + 2) % len(scale)], chord_root + scale[(degree + 4) % len(scale)])
        pan = (-0.23, 0.0, 0.23)
        for note, side in zip(chord_notes, pan):
            add_music_note(left, right, bar_start, beat * 3.85, midi_hz(note + 12), 0.036 * density, side, "pad")
        add_music_note(left, right, bar_start, beat * 3.6, midi_hz(chord_root - 12), 0.075 * density, -0.08, "bass")
        add_music_note(left, right, bar_start + beat * 2.0, beat * 1.75,
                       midi_hz(root + scale[(degree + 2) % len(scale)] - 12), 0.045 * density, 0.1, "bass")

        step = beat * (0.5 if name in ("harbor", "journey", "battle") else 1.0)
        arp_count = 8 if step < beat else 4
        for item in range(arp_count):
            if name == "title" and item % 2 == 1:
                continue
            arp_degree = arp_pattern[(item + bar) % len(arp_pattern)]
            note = root + 12 + scale[(degree + arp_degree) % len(scale)]
            start = bar_start + item * step + (0.5 if name == "title" else 0.0)
            pan = -0.42 + 0.84 * ((item % 4) / 3.0)
            add_music_note(left, right, start, min(beat * 0.78, step * 1.55), midi_hz(note), 0.047 * density, pan, "bell" if item % 4 == 0 else "pluck")

        if bar in (1, 3, 5, 7):
            high = root + 24 + scale[(degree + bar) % len(scale)]
            add_music_note(left, right, bar_start + beat * 2.65, beat * 1.1, midi_hz(high), 0.023 * density, 0.32 if bar % 2 else -0.32, "bell")
        if config["battle"]:
            add_drum(left, right, bar_start, 0.13, 900 + bar, 0.12)
            add_drum(left, right, bar_start + beat * 2.0, 0.11, 1200 + bar, 0.075)

    # Soft echoes add space without needing effects plugins or runtime synthesis.
    delay = round(SAMPLE_RATE * 0.105)
    for index in range(delay, frame_count):
        left[index] += left[index - delay] * 0.12
        right[index] += right[index - delay] * 0.12
    fade = round(SAMPLE_RATE * 0.09)
    for index in range(frame_count):
        edge = min(1.0, index / fade, (frame_count - 1 - index) / fade)
        gain = max(0.0, edge) ** 0.7
        left[index] *= gain
        right[index] *= gain
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
    gain = 0.52 / max(peak, 0.001)
    interleaved = array("f")
    for l_value, r_value in zip(left, right):
        interleaved.append(l_value * gain)
        interleaved.append(r_value * gain)
    write_wave(OUTPUT / "music" / f"{name}.wav", interleaved, 2)


def main() -> None:
    for name, duration in EFFECTS.items():
        generate_effect(name, duration)
    for name, config in THEMES.items():
        generate_theme(name, config)
    print(f"Generated {len(EFFECTS)} effects and {len(THEMES)} seamless prototype music loops in {OUTPUT}")


if __name__ == "__main__":
    main()
