"""Imagen -> modelo 3D con la API de Meshy (https://docs.meshy.ai/en/api/image-to-3d).

Uso:
  python tools/meshy_generar.py IMAGEN.png SALIDA.glb [--polys 4000] [--personaje]

La clave se lee de la variable MESHY_API_KEY (de la sesión o, en Windows, la guardada
para el usuario). Nunca se imprime ni se guarda en el proyecto.
Modo por defecto: Smart Topology (low poly con textura, 15 créditos por modelo).
Guarda junto al .glb un .json con el id de la tarea y los créditos gastados.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.meshy.ai/openapi/v1/image-to-3d"


def api_key() -> str:
    k = os.environ.get("MESHY_API_KEY", "")
    if not k and sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as h:
                k = winreg.QueryValueEx(h, "MESHY_API_KEY")[0]
        except OSError:
            pass
    if not k:
        sys.exit("Falta la variable MESHY_API_KEY.")
    return k


def call(method: str, url: str, key: str, body=None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    for intento in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:400]
            if e.code == 429 and intento < 4:
                time.sleep(int(e.headers.get("Retry-After", "10")))
                continue
            sys.exit("Meshy respondió %d: %s" % (e.code, msg))
        except urllib.error.URLError as e:
            if intento < 4:
                time.sleep(5)
                continue
            sys.exit("Sin conexión con Meshy: %s" % e)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("imagen")
    ap.add_argument("salida")
    ap.add_argument("--polys", type=int, default=4000)
    ap.add_argument("--personaje", action="store_true", help="pide pose en A (para poder animarlo)")
    a = ap.parse_args()
    key = api_key()
    ext = os.path.splitext(a.imagen)[1].lower().lstrip(".")
    mime = {"jpg": "jpeg"}.get(ext, ext)
    with open(a.imagen, "rb") as f:
        uri = "data:image/%s;base64,%s" % (mime, base64.b64encode(f.read()).decode())
    body = {
        "image_url": uri,
        "model_type": "smart-topology",
        "ai_model": "meshy-t2",
        "target_polycount": a.polys,
        "should_texture": True,
        "texture_resolution": "2k",
        "target_formats": ["glb"],
        "alpha_thumbnail": True,
    }
    if a.personaje:
        body["pose_mode"] = "a-pose"
    task = call("POST", API, key, body)["result"]
    print("Tarea creada:", task, flush=True)
    t0 = time.time()
    while True:
        time.sleep(10)
        st = call("GET", API + "/" + task, key)
        print("  %s %d %% (%d s)" % (st["status"], st.get("progress", 0), time.time() - t0), flush=True)
        if st["status"] == "SUCCEEDED":
            break
        if st["status"] in ("FAILED", "CANCELED"):
            sys.exit("Falló: %s" % (st.get("task_error") or st["status"]))
        if time.time() - t0 > 1800:
            sys.exit("Tardó más de 30 minutos; revisa la tarea %s en Meshy." % task)
    os.makedirs(os.path.dirname(os.path.abspath(a.salida)), exist_ok=True)
    urllib.request.urlretrieve(st["model_urls"]["glb"], a.salida)
    thumb = st.get("alpha_thumbnail_url") or st.get("thumbnail_url")
    if thumb:
        urllib.request.urlretrieve(thumb, os.path.splitext(a.salida)[0] + ".vista.png")
    info = {"tarea": task, "creditos": st.get("consumed_credits"), "polys": a.polys,
            "imagen": os.path.basename(a.imagen)}
    with open(os.path.splitext(a.salida)[0] + ".meshy.json", "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    print("Listo: %s (%d KB, %s créditos)" % (a.salida, os.path.getsize(a.salida) // 1024, info["creditos"]))


if __name__ == "__main__":
    main()
