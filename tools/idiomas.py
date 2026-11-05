"""Junta todas las frases del juego (en español) y revisa los archivos de idioma.

Uso:  python tools/idiomas.py            -> lista lo que falta traducir en cada idioma
      python tools/idiomas.py --faltan   -> escribe tools/faltan_<idioma>.json para llenarlos

Frases que se juntan:
  - Lang.t("...") en scripts/
  - textos de las constantes con texto visible (Defs, pestañas, consejos…)
  - nombre y descripción de cada civilización (data/civs/*.json)
Los archivos de idioma son data/idiomas/<código>.json: {"frase en español": "traducción"}.
"""
import json, os, re, sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["en", "pt"]
LIT = r'"((?:[^"\\]|\\.)*)"'

# Constantes cuyo texto se ve en pantalla: (archivo, nombre de la constante, claves a tomar o None = todos los textos)
CONSTS = [
    ("scripts/core/defs.gd", "RES_NAMES", None),
    ("scripts/core/defs.gd", "COLOR_NAMES", None),
    ("scripts/core/defs.gd", "NODES", ["name"]),
    ("scripts/core/defs.gd", "ANIMALS", ["name"]),
    ("scripts/core/defs.gd", "UNITS", ["name", "desc"]),
    ("scripts/core/defs.gd", "BUILDINGS", ["name", "desc"]),
    ("scripts/core/defs.gd", "AGES", "ages"),
    ("scripts/core/defs.gd", "DIFFICULTY", ["name"]),
    ("scripts/core/defs.gd", "MAP_TYPES", ["name", "desc"]),
    ("scripts/ui/hud.gd", "TAB_NAMES", None),
    ("scripts/ui/menu.gd", "TYPES", None),
    ("scripts/ui/carga.gd", "TIPS", None),
    ("scripts/ui/solo_screen.gd", "PRESETS", None),
]


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def const_block(src, name):
    m = re.search(r'^(?:static\s+)?const\s+%s\b[^=]*=\s*' % name, src, re.M)
    if not m:
        raise SystemExit("No encontré la constante " + name)
    i = m.end()
    depth, j = 0, i
    in_str = False
    while j < len(src):
        c = src[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "[{(":
            depth += 1
        elif c in "]})":
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
        j += 1
    return src[i:]


def phrases():
    out = []
    seen = set()

    def add(s):
        if s and s not in seen:
            seen.add(s)
            out.append(s)

    for base, _, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if f.endswith(".gd"):
                src = open(os.path.join(base, f), encoding="utf-8").read()
                src = "\n".join(l for l in src.split("\n") if not l.lstrip().startswith("#"))
                for m in re.finditer(r'(?:Lang\.t|tr)\(' + LIT + r'\)', src):
                    add(unescape(m.group(1)))
    for path, name, keys in CONSTS:
        block = const_block(open(os.path.join(ROOT, path), encoding="utf-8").read(), name)
        if keys is None:
            for m in re.finditer(LIT, block):
                if not re.match(r'\s*:', block[m.end():]) and not re.fullmatch(r'[a-z0-9_]+', m.group(1)):
                    add(unescape(m.group(1)))   # (las claves e ids no se ven)
        elif keys == "ages":
            for m in re.finditer(r'"name":\s*' + LIT, block):
                add(unescape(m.group(1)))
            for m in re.finditer(r'\d+,\s*' + LIT + r'\]', block):
                add(unescape(m.group(1)))
        else:
            for k in keys:
                for m in re.finditer(r'"%s":\s*' % k + LIT, block):
                    add(unescape(m.group(1)))
    # Mensajes del servidor que el juego muestra (se traducen en el cliente).
    js = open(os.path.join(ROOT, "server", "server.js"), encoding="utf-8").read()
    for m in re.finditer(r"msg: '([^']+)'|return '([A-ZÁÉÍÓÚ¡¿][^']+)'", js):
        add(m.group(1) or m.group(2))
    civ_dir = os.path.join(ROOT, "data", "civs")
    for f in sorted(os.listdir(civ_dir)):
        if f.endswith(".json"):
            d = json.load(open(os.path.join(civ_dir, f), encoding="utf-8"))
            add(d.get("name", ""))
            add(d.get("desc", ""))
    return out


def main():
    ph = phrases()
    print("Frases del juego:", len(ph))
    bad = 0
    for lang in LANGS:
        path = os.path.join(ROOT, "data", "idiomas", lang + ".json")
        have = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        missing = [p for p in ph if not have.get(p)]
        extra = [k for k in have if k not in ph]
        # Los %d/%s deben ser los mismos que en español (si no, el juego falla al formatear).
        fmt = [k for k in have if have[k] and re.findall(r'%[-+0-9.]*[dfsx%]', k) != re.findall(r'%[-+0-9.]*[dfsx%]', have[k])]
        print(f"{lang}: faltan {len(missing)}, sobran {len(extra)}, formato distinto {len(fmt)}")
        for k in fmt:
            print("   formato:", repr(k), "->", repr(have[k]))
        bad += len(missing) + len(fmt)
        if "--faltan" in sys.argv:
            json.dump({p: "" for p in missing}, open(os.path.join(ROOT, "tools", "faltan_%s.json" % lang), "w", encoding="utf-8"),
                      ensure_ascii=False, indent=1)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
