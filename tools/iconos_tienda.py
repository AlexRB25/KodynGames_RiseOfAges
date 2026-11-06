"""Dibuja los iconos de la tienda: moneda, gema (diamante) y corona del Premium.

  python tools/iconos_tienda.py    -> assets/ui/iconos/moneda.png, gema.png, premium.png (128x128)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "iconos")
S = 512          # se dibuja grande y se reduce (bordes suaves)
FINAL = 128


def save(img, name):
    img = img.resize((FINAL, FINAL), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("listo", name)


def shadowed(draw_fn):
    """Dibuja con una sombra suave debajo (como los otros iconos)."""
    shape = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_fn(shape)
    alpha = shape.split()[3]
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.putalpha(alpha.point(lambda a: int(a * 0.55)))
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(sh, (0, 14))
    out.alpha_composite(shape)
    return out


def coin(img):
    d = ImageDraw.Draw(img)
    c = S / 2
    r = S * 0.42
    # canto oscuro, cara dorada, aro interior y brillo
    d.ellipse([c - r, c - r + 18, c + r, c + r + 18], fill=(150, 92, 18, 255))
    d.ellipse([c - r, c - r, c + r, c + r], fill=(246, 190, 52, 255), outline=(120, 70, 10, 255), width=14)
    r2 = r * 0.74
    d.ellipse([c - r2, c - r2, c + r2, c + r2], fill=(255, 210, 80, 255), outline=(196, 128, 24, 255), width=12)
    # sol de cuatro puntas (motivo del juego)
    pts = []
    for i in range(16):
        a = i * math.pi / 8 - math.pi / 2
        rr = r2 * (0.78 if i % 2 == 0 else 0.30)
        if i % 4 == 2:
            rr = r2 * 0.48
        pts.append((c + rr * math.cos(a), c + rr * math.sin(a)))
    d.polygon(pts, fill=(214, 140, 26, 255))
    d.ellipse([c - r2 * 0.2, c - r2 * 0.2, c + r2 * 0.2, c + r2 * 0.2], fill=(255, 228, 120, 255))
    # brillo
    d.arc([c - r * 0.86, c - r * 0.86, c + r * 0.86, c + r * 0.86], 200, 260, fill=(255, 246, 200, 255), width=16)


def gem(img):
    d = ImageDraw.Draw(img)
    c = S / 2
    top, mid, bot = S * 0.16, S * 0.38, S * 0.88
    w = S * 0.40
    tw = S * 0.22
    # silueta del diamante
    outline = [(c - tw, top), (c + tw, top), (c + w, mid), (c, bot), (c - w, mid)]
    d.polygon(outline, fill=(40, 120, 230, 255))
    # facetas
    facets = [
        ([(c - tw, top), (c - tw * 0.2, top), (c - w * 0.45, mid), (c - w, mid)], (110, 190, 255, 255)),
        ([(c - tw * 0.2, top), (c + tw * 0.2, top), (c + w * 0.45, mid), (c - w * 0.45, mid)], (150, 215, 255, 255)),
        ([(c + tw * 0.2, top), (c + tw, top), (c + w, mid), (c + w * 0.45, mid)], (70, 160, 245, 255)),
        ([(c - w, mid), (c - w * 0.45, mid), (c, bot)], (50, 130, 235, 255)),
        ([(c - w * 0.45, mid), (c + w * 0.45, mid), (c, bot)], (90, 175, 250, 255)),
        ([(c + w * 0.45, mid), (c + w, mid), (c, bot)], (25, 95, 200, 255)),
    ]
    for poly, col in facets:
        d.polygon(poly, fill=col)
    d.line(outline + [outline[0]], fill=(12, 50, 120, 255), width=14, joint="curve")
    d.line([(c - w, mid), (c + w, mid)], fill=(12, 50, 120, 200), width=8)
    # destello
    sx, sy = c - w * 0.42, top + (mid - top) * 0.45
    d.polygon([(sx, sy - 34), (sx + 9, sy - 9), (sx + 34, sy), (sx + 9, sy + 9), (sx, sy + 34),
               (sx - 9, sy + 9), (sx - 34, sy), (sx - 9, sy - 9)], fill=(255, 255, 255, 255))


def crown(img):
    d = ImageDraw.Draw(img)
    base_y, top_y = S * 0.74, S * 0.22
    l, r = S * 0.12, S * 0.88
    pts = [(l, base_y), (l, S * 0.36), (S * 0.31, S * 0.52), (S * 0.5, top_y), (S * 0.69, S * 0.52),
           (r, S * 0.36), (r, base_y)]
    d.polygon(pts, fill=(250, 196, 50, 255))
    d.line(pts + [pts[0]], fill=(120, 66, 8, 255), width=14, joint="curve")
    d.rectangle([l, base_y - 6, r, S * 0.86], fill=(214, 140, 26, 255), outline=(120, 66, 8, 255), width=12)
    # joyas
    for x, y, col in [(S * 0.5, S * 0.62, (220, 40, 60, 255)), (S * 0.3, S * 0.64, (40, 150, 240, 255)),
                      (S * 0.7, S * 0.64, (40, 190, 100, 255))]:
        d.ellipse([x - 26, y - 26, x + 26, y + 26], fill=col, outline=(90, 40, 6, 255), width=8)
    for x, y in [(l, S * 0.36), (S * 0.5, top_y), (r, S * 0.36)]:
        d.ellipse([x - 22, y - 22, x + 22, y + 22], fill=(255, 236, 150, 255), outline=(120, 66, 8, 255), width=8)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save(shadowed(coin), "moneda.png")
    save(shadowed(gem), "gema.png")
    save(shadowed(crown), "premium.png")
