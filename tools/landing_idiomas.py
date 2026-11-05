"""Traduce la página principal (server/public/index.html) a inglés y portugués.

Las traducciones viven en tools/landing_idiomas/<en|pt>.json como {"texto en español": "traducción"}
(el texto con sus etiquetas HTML, tal como está en la página, con los espacios juntados).
Este script marca cada texto de la página con data-t="N" (y las imágenes con data-ta="N")
y mete al final un <script> con las traducciones y el cambio de idioma.

Uso:
  python tools/landing_idiomas.py              aplica y avisa qué textos faltan
  python tools/landing_idiomas.py --faltan     además escribe tools/landing_idiomas/faltan.json

Idioma de la página: el que eligió (localStorage "roa_idioma", el mismo que usa el juego)
o el del navegador; si no es es/pt, inglés.
"""
import json
import os
import re
import sys
from html.parser import HTMLParser

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PAGE = os.path.join(ROOT, "server", "public", "index.html")
DIR = os.path.join(ROOT, "tools", "landing_idiomas")
LANGS = ["en", "pt"]
TEXT_TAGS = {"title", "h2", "h3", "p", "li", "td", "figcaption", "small", "footer", "a", "span", "b", "button"}
MARK_START = "<!-- idiomas:inicio -->"
MARK_END = "<!-- idiomas:fin -->"


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def has_words(s: str) -> bool:
    return re.search(r"[A-Za-zÁÉÍÓÚáéíóúÑñ]{2,}", re.sub(r"<[^>]+>", "", s)) is not None


class Finder(HTMLParser):
    """Encuentra los elementos con texto (sin contar los que ya están dentro de otro elegido)."""

    def __init__(self, src):
        super().__init__(convert_charrefs=False)
        self.src = src
        self.lines = [0]
        for m in re.finditer("\n", src):
            self.lines.append(m.end())
        self.stack = []      # [tag, start_offset, end_of_start_tag, chosen, attrs]
        self.found = []      # (tag_start, tag_end_of_start, inner_start, inner_end)
        self.alts = []       # (tag_start, alt)
        self.meta = []

    def off(self):
        ln, col = self.getpos()
        return self.lines[ln - 1] + col

    def handle_starttag(self, tag, attrs):
        start = self.off()
        text = self.get_starttag_text()
        end = start + len(text)
        a = dict(attrs)
        if tag == "img" and a.get("alt") and has_words(a["alt"]):
            self.alts.append((start, a["alt"]))
        if tag == "meta" and a.get("name") == "description":
            self.meta.append((start, a["content"]))
        if tag in ("img", "meta", "link", "br", "input", "source"):
            return
        inside = any(s[3] for s in self.stack)
        chosen = (tag in TEXT_TAGS and not inside and "sr" not in a.get("class", "").split()
                  and a.get("translate") != "no")
        self.stack.append([tag, start, end, chosen])

    def handle_endtag(self, tag):
        start = self.off()
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                t, s0, s1, chosen = self.stack[i]
                del self.stack[i:]
                if chosen:
                    inner = self.src[s1:start]
                    if has_words(inner):
                        self.found.append((s0, s1, inner))
                return


def main():
    src = open(PAGE, encoding="utf-8").read()
    # Quitar lo que puso una corrida anterior.
    src = re.sub(r"\n?" + re.escape(MARK_START) + r".*?" + re.escape(MARK_END), "", src, flags=re.S)
    src = re.sub(r' data-t[a]?="\d+"', "", src)
    f = Finder(src)
    f.feed(src)
    tr = {}
    for l in LANGS:
        p = os.path.join(DIR, l + ".json")
        tr[l] = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    keys = []          # texto en español por número
    inserts = []       # (posición, texto a insertar)

    def key_id(k):
        if k not in keys:
            keys.append(k)
        return keys.index(k)

    for s0, s1, inner in f.found:
        tagname_end = s0 + 1 + len(re.match(r"<(\w+)", src[s0:]).group(1))
        inserts.append((tagname_end, ' data-t="%d"' % key_id(norm(inner))))
    for s0, alt in f.alts:
        inserts.append((s0 + 4, ' data-ta="%d"' % key_id(norm(alt))))
    meta_id = key_id(norm(f.meta[0][1])) if f.meta else -1
    for pos, txt in sorted(inserts, reverse=True):
        src = src[:pos] + txt + src[pos:]

    faltan = {l: [k for k in keys if not tr[l].get(k)] for l in LANGS}
    data = {l: [tr[l].get(k, "") for k in keys] for l in LANGS}
    js = """%s
<script>
(function(){
  var D=%s, ES=%s, META=%d;
  function pick(){var l='';try{l=localStorage.getItem('roa_idioma')||'';}catch(e){}
    if(!l)l=(navigator.language||'en').slice(0,2).toLowerCase();return(l==='es'||l==='pt')?l:'en';}
  function apply(l){
    var T=D[l];document.documentElement.lang=l;
    document.querySelectorAll('[data-t]').forEach(function(e){var i=+e.getAttribute('data-t');e.innerHTML=(T&&T[i])||ES[i];});
    document.querySelectorAll('[data-ta]').forEach(function(e){var i=+e.getAttribute('data-ta');e.alt=(T&&T[i])||ES[i];});
    if(META>=0){var m=document.querySelector('meta[name=description]');if(m)m.content=(T&&T[META])||ES[META];}
    document.querySelectorAll('.lang button').forEach(function(b){b.setAttribute('aria-pressed',b.getAttribute('data-l')===l?'true':'false');});
  }
  window.roaLang=function(l){try{localStorage.setItem('roa_idioma',l);}catch(e){}apply(l);};
  apply(pick());
})();
</script>
%s""" % (MARK_START, json.dumps(data, ensure_ascii=False), json.dumps(keys, ensure_ascii=False), meta_id, MARK_END)
    src = src.replace("</body>", js + "\n</body>", 1)
    open(PAGE, "w", encoding="utf-8", newline="").write(src)
    print("textos: %d" % len(keys))
    for l in LANGS:
        print("faltan en %s: %d" % (l, len(faltan[l])))
    if "--faltan" in sys.argv:
        os.makedirs(DIR, exist_ok=True)
        json.dump(faltan, open(os.path.join(DIR, "faltan.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
