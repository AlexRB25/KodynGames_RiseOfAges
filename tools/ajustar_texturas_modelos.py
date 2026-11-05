"""Deja ligeras las texturas de los modelos 3D (assets/modelos/**).

Meshy entrega texturas de 2048 px; en un RTS de lejos no se nota la diferencia con
512 px y la versión web pesa mucho menos. Cambia los .import de las texturas que
Godot extrae de cada .glb: máximo 512 px y compresión con pérdida (WebP), sin
pasarla a formato de tarjeta de video. Después hay que reimportar:
  godot --headless --path . --import
Uso: python tools/ajustar_texturas_modelos.py [tamaño=512]
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "modelos")
SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 512
SET = {
    "compress/mode": "1",            # 1 = con pérdida (WebP)
    "compress/lossy_quality": "0.8",
    "detect_3d/compress_to": "0",    # no convertir a formato de tarjeta de video
    "process/size_limit": str(SIZE),
    "mipmaps/generate": "true",
}

changed = 0
for d, _, files in os.walk(ROOT):
    for f in files:
        if not f.endswith(".import") or ".vista." in f:
            continue
        if not re.search(r"\.(png|jpg|jpeg|webp)\.import$", f):
            continue
        p = os.path.join(d, f)
        s = open(p, encoding="utf-8").read()
        new = s
        for k, v in SET.items():
            if re.search(r"^%s=" % re.escape(k), new, flags=re.M):
                new = re.sub(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), new, flags=re.M)
            else:
                new = new.replace("[params]\n", "[params]\n\n%s=%s\n" % (k, v), 1)
        if new != s:
            open(p, "w", encoding="utf-8").write(new)
            changed += 1
print("Texturas ajustadas:", changed)
