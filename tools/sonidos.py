"""Genera la música y los efectos del juego (sin archivos de afuera): todo sale de
síntesis con numpy. Escribe assets/sonidos/*.wav (mono, 16 bits).

    python tools/sonidos.py

Los sonidos llevan semilla fija: correrlo otra vez da los mismos archivos.
La música se escribe con puntos de repetición (chunk "smpl") para que Godot la
repita sin cortes.
"""
import os
import struct
import numpy as np
from scipy import signal

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sonidos")
rng = np.random.default_rng(25)


# ---------------------------------------------------------------- utilidades

def t_of(dur):
    return np.arange(int(dur * SR)) / SR


def env(n, a=0.005, d=None, curve=4.0, sustain=0.0):
    """Ataque lineal y caída exponencial."""
    x = np.ones(n)
    na = max(1, int(a * SR))
    x[:na] = np.linspace(0, 1, na)
    rest = n - na
    if rest > 0:
        k = np.linspace(0, 1, rest)
        x[na:] = sustain + (1 - sustain) * np.exp(-curve * k)
    return x


def fade(x, fi=0.003, fo=0.01):
    x = x.copy()
    a, b = int(fi * SR), int(fo * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def osc(freq, dur, wave="sine", phase=0.0):
    """freq puede ser número o arreglo (glissando)."""
    n = int(dur * SR)
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, dtype=float)[:n]
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if wave == "sine":
        return np.sin(ph)
    if wave == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if wave == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if wave == "square":
        return np.sign(np.sin(ph))
    raise ValueError(wave)


def glide(f0, f1, dur, shape=1.0):
    k = np.linspace(0, 1, int(dur * SR)) ** shape
    return f0 + (f1 - f0) * k


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR / 2 - 100) / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, min(f, SR / 2 - 100) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def mix(*parts):
    n = max(len(p[1]) + int(p[0] * SR) for p in parts)
    out = np.zeros(n)
    for off, x, *g in parts:
        i = int(off * SR)
        out[i:i + len(x)] += x * (g[0] if g else 1.0)
    return out


def norm(x, peak=0.85):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (peak / m)


def reverb(x, secs=0.9, wet=0.25, tail=True):
    n = int(secs * SR)
    ir = rng.uniform(-1, 1, n) * np.exp(-np.linspace(0, 7, n))
    ir = lp(ir, 5000)
    ir /= np.sqrt(np.sum(ir ** 2))
    y = signal.fftconvolve(np.concatenate([x, np.zeros(n if tail else 0)]), ir)[: len(x) + (n if tail else 0)]
    dry = np.concatenate([x, np.zeros(n if tail else 0)])
    return dry * (1 - wet) + y * wet


def write(name, x, loop=False, peak=0.85):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    if loop:
        # smpl: un lazo hacia adelante de todo el archivo.
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(x) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    chunks += b"data" + struct.pack("<I", len(data)) + data
    with open(os.path.join(ROOT, name + ".wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print(f"{name}.wav  {len(x) / SR:.2f} s")


# ---------------------------------------------------------------- voces
# Voz sintética: pulsos glotales filtrados por formantes (vocales) y ruido
# filtrado para las consonantes. Suena a "personita" de juego, a propósito.

VOWELS = {
    "a": (800, 1200, 2600),
    "e": (450, 1900, 2600),
    "i": (300, 2300, 3000),
    "o": (480, 850, 2600),
    "u": (330, 750, 2400),
    "m": (260, 1000, 2300),
}


def resonator(x, f, bw):
    r = np.exp(-np.pi * bw / SR)
    th = 2 * np.pi * f / SR
    b = [1 - r]
    a = [1, -2 * r * np.cos(th), r * r]
    return signal.lfilter(b, a, x)


def voiced(vowel, dur, f0a, f0b, rough=0.0, breath=0.05):
    n = int(dur * SR)
    f0 = glide(f0a, f0b, dur, 0.8)
    f0 = f0 * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * np.arange(n) / SR))
    src = osc(f0, dur, "saw")
    if rough:
        src = src * (1 + rough * rng.uniform(-1, 1, n))
    src = src + breath * rng.uniform(-1, 1, n)
    F = VOWELS[vowel]
    y = resonator(src, F[0], 80) * 1.0 + resonator(src, F[1], 110) * 0.6 + resonator(src, F[2], 160) * 0.3
    if vowel == "m":
        y = lp(y, 900)
    return y * env(n, 0.02, curve=1.2, sustain=0.6)


def fric(kind, dur):
    x = noise(dur)
    if kind == "s":
        x = bp(x, 4000, 9000) * 0.5
    elif kind == "j":
        x = bp(x, 1200, 3500) * 0.6
    elif kind == "h":
        x = bp(x, 600, 2500) * 0.3
    elif kind == "k":
        x = bp(x, 1500, 3500) * 1.2
        x *= env(len(x), 0.001, curve=9)
        return x
    return x * env(len(x), 0.02, curve=1.0, sustain=0.5)


def word(parts, rough=0.0, gain=1.0):
    """parts: lista de (tipo, dur, f0a, f0b) o (fricativa, dur)."""
    out = []
    for p in parts:
        if p[0] in VOWELS:
            out.append(voiced(p[0], p[1], p[2], p[3], rough))
        elif p[0] == "_":
            out.append(np.zeros(int(p[1] * SR)))
        else:
            out.append(fric(p[0], p[1]))
    # unir con pequeñas mezclas
    y = out[0]
    for z in out[1:]:
        ov = int(0.015 * SR)
        if len(y) > ov and len(z) > ov:
            y = np.concatenate([y[:-ov], y[-ov:] * np.linspace(1, 0, ov) + z[:ov] * np.linspace(0, 1, ov), z[ov:]])
        else:
            y = np.concatenate([y, z])
    y = fade(y, 0.004, 0.04)
    return reverb(y, 0.25, 0.12) * gain


def voices():
    # Aldeanos: "¡Sí!", "¡Ok!", "¡Ajá!", "¡Vamos!"... (agudos y alegres)
    write("ok_aldeano_1", word([("s", 0.07), ("i", 0.2, 210, 160)]))
    write("ok_aldeano_2", word([("o", 0.13, 190, 200), ("_", 0.03), ("k", 0.04), ("e", 0.09, 230, 210), ("i", 0.11, 215, 165)]))
    write("ok_aldeano_3", word([("a", 0.08, 170, 175), ("j", 0.06), ("a", 0.2, 230, 160)]))
    write("ok_aldeano_4", word([("u", 0.05, 160, 170), ("a", 0.1, 180, 200), ("m", 0.06, 200, 190), ("o", 0.15, 190, 150), ("s", 0.07)]))
    # Al seleccionar un aldeano: "¿Sí?" / "¿Mm?"
    write("sel_aldeano_1", word([("s", 0.06), ("i", 0.18, 160, 240)], gain=0.8))
    write("sel_aldeano_2", word([("m", 0.08, 170, 175), ("m", 0.12, 175, 230)], gain=0.8))
    # Guerreros: "¡Ja!", "¡Hah!", "¡Vamos!" más graves y ásperos
    write("ok_guerrero_1", word([("j", 0.06), ("a", 0.2, 125, 95)], rough=0.35))
    write("ok_guerrero_2", word([("h", 0.05), ("a", 0.1, 115, 120), ("_", 0.04), ("h", 0.04), ("a", 0.16, 130, 90)], rough=0.35))
    write("ok_guerrero_3", word([("u", 0.05, 105, 110), ("a", 0.1, 115, 125), ("m", 0.06, 125, 120), ("o", 0.16, 120, 90), ("s", 0.07)], rough=0.3))
    write("sel_guerrero_1", word([("m", 0.07, 110, 112), ("m", 0.12, 112, 140)], rough=0.25, gain=0.8))
    write("sel_guerrero_2", word([("h", 0.04), ("e", 0.16, 105, 130)], rough=0.3, gain=0.8))


# ---------------------------------------------------------------- instrumentos

def drum(f=70, dur=0.6, punch=2.2, vol=1.0):
    """Huéhuetl: tambor grave de piel."""
    n = int(dur * SR)
    fr = f * (1 + punch * np.exp(-np.linspace(0, 1, n) * 30))
    body = osc(fr, dur) * env(n, 0.002, curve=6)
    skin = lp(noise(dur), 1800) * env(n, 0.001, curve=40) * 0.5
    return (body + skin) * vol


def log_drum(f=320, dur=0.35, vol=1.0):
    """Teponaztli: tambor de tronco, sonido de madera afinada."""
    n = int(dur * SR)
    x = osc(f, dur) + 0.45 * osc(f * 2.76, dur) + 0.2 * osc(f * 5.4, dur)
    x *= env(n, 0.001, curve=9)
    click = bp(noise(dur), 1500, 4000) * env(n, 0.0005, curve=80) * 0.4
    return (x + click) * vol


def rattle(dur=0.12, vol=1.0):
    """Sonaja / ayoyote."""
    n = int(dur * SR)
    x = hp(noise(dur), 3500) * env(n, 0.004, curve=7)
    return x * vol


def flute(f, dur, vol=1.0, vib=0.012):
    """Flauta de barro: casi senoidal, con soplo y vibrato que entra tarde."""
    n = int(dur * SR)
    tt = np.arange(n) / SR
    v = vib * np.clip((tt - 0.12) / 0.3, 0, 1)
    fr = f * (1 + v * np.sin(2 * np.pi * 5.2 * tt))
    x = osc(fr, dur) + 0.12 * osc(fr * 2, dur) + 0.04 * osc(fr * 3, dur)
    breath = bp(noise(dur), f * 0.8, f * 3.5) * 0.18
    a = min(0.06, dur * 0.3)
    e = np.ones(n)
    na = int(a * SR)
    e[:na] = np.linspace(0, 1, na) ** 0.7
    nr = int(min(0.12, dur * 0.4) * SR)
    e[-nr:] *= np.linspace(1, 0, nr)
    return (x + breath) * e * vol


def conch(f, dur, vol=1.0):
    """Caracol (atecocolli): bocina grave."""
    n = int(dur * SR)
    tt = np.arange(n) / SR
    fr = f * (1 + 0.015 * np.sin(2 * np.pi * 4 * tt)) * (1 - 0.03 * np.exp(-tt * 8))
    x = lp(osc(fr, dur, "saw"), f * 4.5)
    x += 0.3 * osc(fr, dur)
    e = np.minimum(1, tt / 0.12) * np.minimum(1, (dur - tt) / 0.25)
    return x * e * vol


def bell(f, dur=1.6, vol=1.0):
    n = int(dur * SR)
    parts = [(1.0, 1.0), (2.0, 0.6), (2.4, 0.5), (3.0, 0.35), (4.2, 0.25), (5.4, 0.15)]
    x = np.zeros(n)
    for k, (m, a) in enumerate(parts):
        x += a * osc(f * m, dur) * env(n, 0.001, curve=3 + k * 1.6)
    x += bp(noise(dur), 2000, 6000) * env(n, 0.0005, curve=90) * 0.3
    return x * vol


def chime(f, dur=0.8, vol=1.0):
    n = int(dur * SR)
    x = osc(f, dur) + 0.35 * osc(f * 3.01, dur) * env(n, 0.001, curve=9)
    return x * env(n, 0.002, curve=5) * vol


def pluck(f, dur=0.4, vol=1.0):
    n = int(dur * SR)
    x = osc(f, dur, "tri") + 0.3 * osc(f * 2, dur)
    return lp(x, 3000) * env(n, 0.002, curve=8) * vol


# ---------------------------------------------------------------- efectos

def note(name):
    # La menor pentatónica (A C D E G) y alrededores.
    tbl = {"A3": 220.0, "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.0, "A4": 440.0,
           "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.0, "C6": 1046.5,
           "E3": 164.81, "G3": 196.0, "D3": 146.83, "A2": 110.0, "E2": 82.41}
    return tbl[name]


def effects():
    # Clic de botón: madera suave.
    write("clic", log_drum(900, 0.08, 1.0) * 0.6, peak=0.5)
    # Seleccionar un edificio: toc de teponaztli.
    write("seleccion", log_drum(420, 0.25), peak=0.6)
    # Colocar una obra: golpe sordo de tierra.
    n = int(0.35 * SR)
    thud = osc(glide(140, 55, 0.35), 0.35) * env(n, 0.002, curve=8) + lp(noise(0.35), 600) * env(n, 0.002, curve=10) * 0.8
    write("colocar", thud, peak=0.8)
    # Edificio terminado: "suut" (soplo que sube) + dos campanitas.
    sw = bp(noise(0.45), 500, 4000)
    sw = signal.lfilter(*signal.butter(2, 0.05, "low"), sw) * 0 + sw
    k = np.linspace(0, 1, len(sw))
    sweep = np.zeros_like(sw)
    for i, (lo, hi) in enumerate([(400, 900), (900, 1800), (1800, 3500), (3500, 7000)]):
        part = bp(noise(0.45), lo, hi)
        w = np.exp(-((k - i / 3) ** 2) / 0.04)
        sweep += part * w
    sweep *= np.sin(np.pi * k) * 0.8
    done = mix((0, sweep), (0.3, chime(note("E5"), 0.9)), (0.42, chime(note("A5"), 1.1)))
    write("terminado", reverb(done, 0.8, 0.25), peak=0.75)
    # Subir de era: "tu-nuun" de tambores + caracol + acorde de flauta.
    era = mix(
        (0.0, drum(75, 0.7, vol=1.0)),
        (0.28, drum(58, 1.3, punch=1.6, vol=1.1)),
        (0.28, conch(note("A2") * 2, 1.6, 0.35)),
        (0.3, flute(note("A4"), 1.5, 0.25)),
        (0.45, flute(note("E5"), 1.35, 0.2)),
        (0.6, flute(note("A5"), 1.2, 0.15)),
        (0.28, rattle(0.6, 0.15)),
    )
    write("era", reverb(era, 1.4, 0.3), peak=0.9)
    # Unidad lista: dos notas de madera hacia arriba.
    write("listo", mix((0, pluck(note("E4"), 0.3)), (0.09, pluck(note("A4"), 0.45))), peak=0.55)
    # Mejora investigada: tres campanitas.
    write("mejora", reverb(mix((0, chime(note("A4"), 0.7)), (0.11, chime(note("C5"), 0.7)), (0.22, chime(note("E5"), 1.0))), 0.8, 0.3), peak=0.65)
    # Campana del centro: dos golpes de campana.
    write("campana", reverb(mix((0, bell(520, 1.6)), (0.45, bell(520, 1.8, 0.9))), 1.0, 0.25), peak=0.8)
    # Alerta de ataque: caracol que sube dos veces.
    alarm = mix((0, conch(110, 0.55, 1.0)), (0.6, conch(147, 0.75, 1.0)))
    write("alerta", reverb(alarm, 0.9, 0.2), peak=0.8)
    # Flecha: silbido corto.
    n = int(0.22 * SR)
    arrow = bp(noise(0.22), 2500, 7000) * np.sin(np.pi * np.linspace(0, 1, n)) ** 2
    write("flecha", arrow, peak=0.4)
    # Piedra de catapulta / honda: silbido grave + golpe.
    n = int(0.5 * SR)
    stone = mix((0, bp(noise(0.3), 400, 1500) * np.sin(np.pi * np.linspace(0, 1, int(0.3 * SR)))), (0.25, drum(60, 0.3, 3.0, 0.8)))
    write("piedra", stone, peak=0.6)
    # Golpes cuerpo a cuerpo: macana de obsidiana.
    for i in range(1, 4):
        d = 0.16
        n = int(d * SR)
        f = [1600, 2100, 1300][i - 1]
        hit = bp(noise(d), f * 0.6, f * 1.8) * env(n, 0.0008, curve=22) + osc(glide(220, 90, d), d) * env(n, 0.001, curve=14) * 0.7
        write("golpe_%d" % i, hit, peak=0.55)
    # Edificio derribado: se desmorona.
    d = 1.4
    n = int(d * SR)
    crumble = lp(noise(d), 900) * env(n, 0.01, curve=3)
    for j in range(9):
        crumble = mix((0, crumble), (rng.uniform(0, 0.9), drum(rng.uniform(50, 110), 0.35, 2.0, rng.uniform(0.3, 0.7))))
    write("derribo", reverb(crumble, 0.7, 0.2), peak=0.75)
    # Error / no alcanza: dos toques graves.
    n = int(0.12 * SR)
    b1 = lp(osc(180, 0.12, "square"), 1200) * env(n, 0.002, curve=3)
    write("error", mix((0, b1), (0.14, b1)), peak=0.4)
    # Reliquia: brillo.
    sh = mix(*[(0.06 * i, chime(f, 0.9, 0.6)) for i, f in enumerate([note("E5"), note("G5"), note("A5"), note("C6")])])
    write("reliquia", reverb(sh, 1.0, 0.35), peak=0.6)
    # Trabajo (se oyen cerca de la cámara): hacha, pico, cosecha, martillo.
    for i in range(1, 3):
        f = [520, 450][i - 1]
        write("hacha_%d" % i, log_drum(f, 0.18) + lp(noise(0.18), 2500) * env(int(0.18 * SR), 0.001, curve=25) * 0.6, peak=0.45)
    for i in range(1, 3):
        f = [2600, 3100][i - 1]
        d = 0.25
        n = int(d * SR)
        ping = (osc(f, d) + 0.5 * osc(f * 1.5, d)) * env(n, 0.0005, curve=12) + bp(noise(d), 2000, 6000) * env(n, 0.0005, curve=40) * 0.5
        write("pico_%d" % i, ping, peak=0.35)
    write("cosecha", bp(noise(0.25), 1500, 6000) * np.sin(np.pi * np.linspace(0, 1, int(0.25 * SR))), peak=0.3)
    write("martillo", log_drum(260, 0.15) + bp(noise(0.15), 800, 3000) * env(int(0.15 * SR), 0.0005, curve=30) * 0.5, peak=0.4)
    # Victoria y derrota.
    mel = [("A4", 0.0, 0.3), ("C5", 0.3, 0.3), ("D5", 0.6, 0.3), ("E5", 0.9, 0.6), ("G5", 1.5, 0.3), ("A5", 1.8, 1.4)]
    v = mix(*[(o, flute(note(nn), d + 0.05, 0.5)) for nn, o, d in mel],
            *[(o, drum(70, 0.5, vol=0.8)) for o in (0, 0.6, 0.9, 1.5, 1.8)],
            (1.8, conch(110, 1.6, 0.25)), (1.8, bell(880, 1.6, 0.25)))
    write("victoria", reverb(v, 1.6, 0.3), peak=0.85)
    mel = [("E5", 0.0, 0.5), ("D5", 0.5, 0.5), ("C5", 1.0, 0.5), ("A4", 1.5, 1.6)]
    v = mix(*[(o, flute(note(nn), d + 0.05, 0.5, vib=0.02)) for nn, o, d in mel],
            (0.0, drum(55, 1.2, vol=0.7)), (1.5, drum(48, 1.8, punch=1.2, vol=0.9)), (1.5, conch(82.4, 1.8, 0.3)))
    write("derrota", reverb(v, 1.6, 0.3), peak=0.8)


# ---------------------------------------------------------------- música

def place_loop(buf, x, at):
    """Pone x en buf empezando en la muestra `at`; lo que se pasa del final da la vuelta."""
    n = len(buf)
    i = at % n
    end = i + len(x)
    if end <= n:
        buf[i:end] += x
    else:
        k = n - i
        buf[i:] += x[:k]
        rest = x[k:]
        while len(rest):
            m = min(n, len(rest))
            buf[:m] += rest[:m]
            rest = rest[m:]


def loop_reverb(buf, secs=1.6, wet=0.3):
    n = int(secs * SR)
    ir = rng.uniform(-1, 1, n) * np.exp(-np.linspace(0, 6, n))
    ir = lp(ir, 4000)
    ir /= np.sqrt(np.sum(ir ** 2))
    # convolución circular: la cola del final suena al principio (lazo sin corte)
    L = len(buf)
    y = np.real(np.fft.ifft(np.fft.fft(buf) * np.fft.fft(np.concatenate([ir, np.zeros(L - n)]))))
    return buf * (1 - wet) + y * wet


def song(bpm, bars, melody_density, seed, drums_level, name, flute_oct=1.0):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    L = int(bars * 4 * beat * SR)
    buf = np.zeros(L)
    S = lambda b: int(b * beat * SR)
    scale = [note(n) for n in ("A3", "C4", "D4", "E4", "G4", "A4", "C5", "D5", "E5", "G5", "A5")]
    # Bordón grave (A y E) que respira muy lento.
    tt = np.arange(L) / SR
    period = L / SR
    drone = (np.sin(2 * np.pi * round(110 * period) / period * tt) * 0.5 +
             np.sin(2 * np.pi * round(164.81 * period) / period * tt) * 0.25)
    drone *= 0.55 + 0.45 * np.sin(2 * np.pi * 2 / period * tt) ** 2
    buf += lp(drone, 600) * 0.06
    # Percusión
    for bar in range(bars):
        b0 = bar * 4
        for beat_i, v in ((0, 1.0), (2, 0.7)):
            place_loop(buf, drum(68, 0.6, vol=v * drums_level), S(b0 + beat_i))
        if bar % 2 == 1:
            place_loop(buf, drum(80, 0.4, vol=0.45 * drums_level), S(b0 + 3.5))
        # teponaztli: patrón de dos tonos que cambia cada 4 compases
        pat = [(0.5, 330), (1.5, 440), (2.5, 330), (3.0, 440), (3.25, 330)] if (bar // 4) % 2 == 0 else \
              [(0.75, 440), (1.5, 330), (2.0, 330), (3.5, 440)]
        for o, f in pat:
            place_loop(buf, log_drum(f, 0.3, 0.35 * drums_level), S(b0 + o))
        # sonaja en corcheas, suave, con acento
        for e in range(8):
            place_loop(buf, rattle(0.09, (0.12 if e % 2 else 0.2) * drums_level), S(b0 + e * 0.5))
    # Melodía de flauta: frases de 2 compases con descanso, nota a nota por pasos.
    idx = 5
    bar = 2
    while bar < bars:
        if r.random() < melody_density:
            pos = 0.0
            while pos < 7.0:
                d = r.choice([0.5, 1.0, 1.0, 1.5, 2.0])
                step = r.choice([-2, -1, -1, 0, 1, 1, 2])
                idx = int(np.clip(idx + step, 2, len(scale) - 1))
                if pos + d > 8:
                    d = 8 - pos
                if r.random() < 0.85:
                    place_loop(buf, flute(scale[idx] * flute_oct, d * beat * 0.95 + 0.05, 0.22), S(bar * 4 + pos))
                pos += d
            # termina la frase en A o E
            idx = r.choice([5, 8])
        bar += 2
    buf = loop_reverb(buf, 1.8, 0.28)
    write(name, buf, loop=True, peak=0.7)


def music():
    song(92, 24, 0.75, 7, 1.0, "musica_partida")
    song(72, 12, 0.95, 3, 0.55, "musica_menu")


def extra():
    """Sonidos agregados después (van al final para no cambiar los demás)."""
    # Subir de nivel / rango: redoble de tambor, arpegio de flauta que sube, campana y caracol.
    roll = mix(*[(i * 0.06, drum(90 + i * 3, 0.25, 2.0, 0.25 + i * 0.05)) for i in range(10)])
    arp = mix(*[(0.62 + i * 0.11, flute(note(n), 0.5 if i < 4 else 1.5, 0.45)) for i, n in enumerate(["A4", "C5", "E5", "G5", "A5"])])
    up = mix((0, roll), (0.6, drum(62, 1.2, 1.8, 1.1)), (0, arp), (1.05, bell(880, 2.0, 0.5)),
             (1.05, conch(110, 1.5, 0.3)), (1.05, chime(note("E5") * 2, 1.4, 0.35)), (0.6, rattle(0.9, 0.25)))
    write("subir_nivel", reverb(up, 1.6, 0.3), peak=0.9)


if __name__ == "__main__":
    import sys
    os.makedirs(ROOT, exist_ok=True)
    if "--extra" not in sys.argv:
        voices()
        effects()
        music()
    extra()
