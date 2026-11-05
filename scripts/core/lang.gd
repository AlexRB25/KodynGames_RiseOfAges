extends Node
## Autoload "Lang": idioma del juego.
## El texto del juego está escrito en español; data/idiomas/<código>.json trae la
## traducción de cada frase ({"frase en español": "traducción"}).
## Los Label/Button traducen su texto solos si es una frase exacta del archivo;
## el texto armado en código usa Lang.t("...") (o tr()) antes de meter los valores:
##   Lang.t("Cuesta %d de comida") % n
## Al arrancar se usa el idioma guardado en Configuración o, si no hay, el del dispositivo.

signal changed

## Idiomas disponibles: código -> nombre (en su propio idioma).
const LANGS := {"es": "Español", "en": "English", "pt": "Português"}
const FALLBACK := "en"   # si el dispositivo está en otro idioma
const CFG := "user://cuenta.cfg"

var code := "es"


func _ready() -> void:
	for c in LANGS:
		if c == "es":
			continue
		var txt := FileAccess.get_file_as_string("res://data/idiomas/%s.json" % c)
		var d = JSON.parse_string(txt) if txt != "" else null
		if not d is Dictionary:
			continue
		var tr_ := Translation.new()
		tr_.locale = c
		for k in d:
			if String(d[k]) != "":
				tr_.add_message(k, d[k])
		TranslationServer.add_translation(tr_)
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	var saved: String = cfg.get_value("jugador", "idioma", "")
	# Desarrollo: --idioma=en fuerza un idioma sin guardarlo.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--idioma="):
			saved = a.get_slice("=", 1)
	_apply(saved if LANGS.has(saved) else device())


## El idioma del dispositivo (o del navegador), si lo tenemos; si no, inglés.
static func device() -> String:
	var l := OS.get_locale_language()
	return l if LANGS.has(l) else FALLBACK


## ¿El jugador ya eligió idioma en Configuración? (si no, se sigue al dispositivo)
func chosen() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	return LANGS.has(String(cfg.get_value("jugador", "idioma", "")))


func set_lang(c: String) -> void:
	if not LANGS.has(c):
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("jugador", "idioma", c)
	cfg.save(CFG)
	# Web: la página de carga (antes de que arranque el juego) lee el idioma de aquí.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('roa_idioma','%s')}catch(e){}" % c)
	_apply(c)


func _apply(c: String) -> void:
	code = c
	TranslationServer.set_locale(c)
	changed.emit()


## Traducir una frase escrita en español (sirve también desde funciones estáticas).
static func t(s: String) -> String:
	return TranslationServer.translate(s)
