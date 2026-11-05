extends Node
## Autoload "Account": cuenta del ecosistema Kodyn Games (el mismo Supabase y el mismo
## login que Zombie War) y el perfil de Rise of Ages (puntos y nivel, separados de los
## de Zombie War). Sin Supabase configurado (data/online.json) el juego sigue
## funcionando: el servidor guarda los puntos en memoria por nombre (modo prueba).

signal changed

const CONFIG_PATH := "res://data/online.json"
const SESSION_PATH := "user://cuenta.cfg"

var supabase_url := ""
var anon_key := ""
var access_token := ""
var refresh_token := ""
var expires_at := 0.0
var email := ""
var is_anonymous := true
var player_name := ""
var profile := {}     # name, points, level, wins, losses, games, zombie_war


func _ready() -> void:
	var txt := FileAccess.get_file_as_string(CONFIG_PATH)
	var d = JSON.parse_string(txt) if txt != "" else null
	if d is Dictionary:
		supabase_url = String(d.get("supabase_url", "")).trim_suffix("/")
		anon_key = String(d.get("supabase_anon_key", ""))
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) == OK:
		player_name = cfg.get_value("jugador", "nombre", "")
		refresh_token = cfg.get_value("sesion", "refresh_token", "")
		email = cfg.get_value("sesion", "correo", "")


## ¿Hay cuentas de verdad (Supabase)? Si no, se juega en modo prueba.
func accounts_ready() -> bool:
	return supabase_url != "" and anon_key != ""


func signed_in() -> bool:
	return access_token != ""


func level() -> int:
	return int(profile.get("level", 1))


func points() -> int:
	return int(profile.get("points", 0))


## Civilización favorita (se guarda en este equipo).
func fav_civ() -> String:
	var cfg := ConfigFile.new()
	cfg.load(SESSION_PATH)
	var c: String = cfg.get_value("jugador", "civ", "")
	return c if Defs.CIVS.has(c) else String(Defs.CIV_ORDER[0])


func set_fav_civ(c: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SESSION_PATH)
	cfg.set_value("jugador", "civ", c)
	cfg.save(SESSION_PATH)


func set_player_name(n: String) -> void:
	player_name = n.strip_edges().left(16)
	var cfg := ConfigFile.new()
	cfg.load(SESSION_PATH)
	cfg.set_value("jugador", "nombre", player_name)
	cfg.save(SESSION_PATH)


## Recibido del servidor (modo prueba o después de una partida con rango).
func take_server_profile(d: Dictionary) -> void:
	for k in ["points", "level", "name"]:
		if d.has(k):
			profile[k] = d[k]
	changed.emit()


# --- HTTP ---------------------------------------------------------------------------

func _request(method: int, url: String, headers: PackedStringArray, body: Variant = null) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var err := req.request(url, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		req.queue_free()
		return {"code": 0, "data": null}
	var res: Array = await req.request_completed
	req.queue_free()
	var text: String = res[3].get_string_from_utf8()
	return {"code": res[1], "data": JSON.parse_string(text) if text != "" else null}


func _headers(token: String) -> PackedStringArray:
	return PackedStringArray(["apikey: " + anon_key, "Authorization: Bearer " + token, "Content-Type: application/json"])


static func error_text(res: Dictionary) -> String:
	var d = res.get("data")
	if res.get("code", 0) == 0:
		return "Sin conexión con el servidor de cuentas"
	if d is Dictionary:
		for k in ["msg", "message", "error_description", "error"]:
			if d.has(k):
				return str(d[k])
	return "Error %d" % res.get("code", 0)


# --- Sesión -------------------------------------------------------------------------

## Entra con la sesión guardada o crea una cuenta de invitado. "" = todo bien.
func sign_in() -> String:
	if not accounts_ready():
		return ""
	if signed_in():
		await _fresh_token()
		return await refresh_profile()
	var ok := false
	if refresh_token != "":
		ok = await _refresh()
	if not ok:
		var res := await _request(HTTPClient.METHOD_POST, supabase_url + "/auth/v1/signup", _headers(anon_key), {"data": {}})
		if res["code"] != 200 or not res["data"] is Dictionary:
			return "No se pudo crear tu cuenta de invitado: " + error_text(res)
		_take_session(res["data"])
	return await refresh_profile()


func refresh_profile() -> String:
	var res := await rpc_call("roa_ensure_profile", {"p_name": player_name})
	if res["code"] != 200 or not res["data"] is Dictionary:
		return "No se pudo cargar tu perfil: " + error_text(res)
	profile = res["data"]
	if player_name == "":
		set_player_name(String(profile.get("name", "")))
	changed.emit()
	return ""


func rpc_call(fn: String, args: Dictionary) -> Dictionary:
	await _fresh_token()
	return await _request(HTTPClient.METHOD_POST, "%s/rest/v1/rpc/%s" % [supabase_url, fn], _headers(access_token), args)


## Guardar el progreso del invitado con correo y contraseña (Supabase manda un correo).
func link_email(new_email: String, password: String) -> String:
	if not signed_in():
		var e := await sign_in()
		if e != "":
			return e
	await _fresh_token()
	var res := await _request(HTTPClient.METHOD_PUT, supabase_url + "/auth/v1/user", _headers(access_token),
		{"email": new_email, "password": password})
	return "" if res["code"] == 200 else error_text(res)


## Entrar con una cuenta Kodyn que ya tiene correo (la misma de Zombie War).
func login(login_email: String, password: String) -> String:
	var res := await _request(HTTPClient.METHOD_POST, supabase_url + "/auth/v1/token?grant_type=password",
		_headers(anon_key), {"email": login_email, "password": password})
	if res["code"] != 200 or not res["data"] is Dictionary:
		return error_text(res)
	_take_session(res["data"])
	player_name = ""
	return await refresh_profile()


func logout() -> void:
	access_token = ""
	refresh_token = ""
	email = ""
	is_anonymous = true
	profile = {}
	var cfg := ConfigFile.new()
	cfg.load(SESSION_PATH)
	cfg.set_value("sesion", "refresh_token", "")
	cfg.set_value("sesion", "correo", "")
	cfg.save(SESSION_PATH)
	changed.emit()


## Token para que el servidor verifique quién eres al entrar a la cola.
func server_token() -> String:
	if not accounts_ready():
		return ""
	await _fresh_token()
	return access_token


func _fresh_token() -> void:
	if refresh_token != "" and Time.get_unix_time_from_system() > expires_at - 60.0:
		await _refresh()


func _refresh() -> bool:
	var res := await _request(HTTPClient.METHOD_POST, supabase_url + "/auth/v1/token?grant_type=refresh_token",
		_headers(anon_key), {"refresh_token": refresh_token})
	if res["code"] != 200 or not res["data"] is Dictionary:
		return false
	_take_session(res["data"])
	return true


func _take_session(d: Dictionary) -> void:
	access_token = d.get("access_token", "")
	refresh_token = d.get("refresh_token", "")
	expires_at = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600))
	var user: Dictionary = d.get("user", {})
	email = String(user.get("email", "")) if user.get("email") != null else ""
	is_anonymous = bool(user.get("is_anonymous", email == ""))
	var cfg := ConfigFile.new()
	cfg.load(SESSION_PATH)
	cfg.set_value("sesion", "refresh_token", refresh_token)
	cfg.set_value("sesion", "correo", "" if is_anonymous else email)
	cfg.save(SESSION_PATH)
