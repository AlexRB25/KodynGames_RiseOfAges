extends Node
## Autoload "Economy": monedas, gemas, Game Pass Premium (pase de temporada), colección y
## tienda. Todo lo decide Supabase (supabase/temporadas.sql); aquí solo se muestra el
## estado (roa_status) y se piden acciones. Las gemas se compran con Stripe por el
## servidor del juego (server/pagos.js).
##
## Desarrollo: --demo-tienda llena el estado con datos de ejemplo (sin internet) para ver
## las pantallas; las acciones se simulan en memoria.

signal changed
signal message(text: String)

const ICONS := {"coins": "ui/iconos/moneda.png", "gems": "ui/iconos/gema.png", "premium": "ui/iconos/premium.png"}
const RARITY_COLORS := {"comun": Color(0.75, 0.72, 0.66), "raro": Color(0.35, 0.65, 1.0),
	"epico": Color(0.72, 0.45, 1.0), "legendario": Color(1.0, 0.75, 0.25)}

var status: Dictionary = {}
var loading := false
var demo := false
var last_error := ""
var _pending_payment := false


func _ready() -> void:
	demo = "--demo-tienda" in OS.get_cmdline_user_args()
	if demo:
		status = _demo_status()
	# Web: volvió de pagar con Stripe (?pago=ok): las gemas llegan en unos segundos.
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("location.search")
		if q is String and q.contains("pago="):
			_pending_payment = q.contains("pago=ok")
			JavaScriptBridge.eval("history.replaceState(null, '', location.pathname)")


func ready_to_use() -> bool:
	return demo or not status.is_empty()


func coins() -> int:
	return int(status.get("coins", 0))


func gems() -> int:
	return int(status.get("gems", 0))


func premium() -> bool:
	return bool(status.get("premium", false))


func season() -> Dictionary:
	var s = status.get("season")
	return s if s is Dictionary else {}


func xp() -> int:
	return int(status.get("xp", 0))


func tier_xp() -> int:
	return maxi(1, int(season().get("tier_xp", 500)))


func tiers() -> int:
	return int(season().get("tiers", 50))


## Nivel del pase alcanzado (0 = ninguno).
func tier() -> int:
	return mini(tiers(), xp() / tier_xp())


## Xp dentro del nivel actual (para la barra).
func tier_progress() -> float:
	if tier() >= tiers():
		return 1.0
	return float(xp() % tier_xp()) / float(tier_xp())


func days_left() -> int:
	var s := season()
	if s.is_empty():
		return 0
	var end := Time.get_unix_time_from_datetime_string(String(s.get("ends_at", "")).left(19))
	var now := Time.get_unix_time_from_datetime_string(String(s.get("now", "")).left(19))
	if now <= 0:
		now = int(Time.get_unix_time_from_system())
	return maxi(0, ceili((end - now) / 86400.0))


func item(id: String) -> Dictionary:
	var items: Dictionary = status.get("items", {})
	return items.get(id, {})


func item_name(id: String) -> String:
	return Lang.t(String(item(id).get("name", id)))


func owns(id: String) -> bool:
	if bool(item(id).get("free", false)):
		return true
	return status.get("owned", []).has(id)


## Lo que tiene de un tipo ('imagen', 'estandarte', 'titulo'), gratis incluido.
func owned_of(kind: String) -> Array:
	var out: Array = []
	var items: Dictionary = status.get("items", {})
	for id in items:
		if items[id].get("kind") == kind and owns(id):
			out.append(id)
	out.sort()
	return out


func equipped(kind: String) -> String:
	match kind:
		"imagen":
			var i := String(status.get("image", ""))
			return i if i != "" else "img_maya_1"
		"estandarte":
			var b := String(status.get("banner", ""))
			return b if b != "" else "est_barro"
		"titulo":
			return String(status.get("title", ""))
	return ""


## Civilizaciones de temporada o de la tienda: bloqueadas hasta tenerlas.
func civ_locked(civ: String) -> bool:
	var items: Dictionary = status.get("items", {})
	for id in items:
		var it: Dictionary = items[id]
		if it.get("kind") == "civ" and String(it.get("detail", {}).get("civ", "")) == civ:
			return not owns(id)
	return false


func reward(tier_n: int, track: String) -> Dictionary:
	for r in status.get("rewards", []):
		if int(r["tier"]) == tier_n and r["track"] == track:
			return r
	return {}


func claimed(tier_n: int, track: String) -> bool:
	return status.get("claimed", []).has("%s:%d" % [track, tier_n])


func can_claim(tier_n: int, track: String) -> bool:
	if reward(tier_n, track).is_empty() or claimed(tier_n, track) or tier_n > tier():
		return false
	return track == "free" or premium()


func claimable_count() -> int:
	var n := 0
	for r in status.get("rewards", []):
		if can_claim(int(r["tier"]), String(r["track"])):
			n += 1
	return n


# --- Pedidos a Supabase ------------------------------------------------------------

func refresh() -> String:
	if demo:
		changed.emit()
		return ""
	if not Account.accounts_ready():
		return Lang.t("Las cuentas en línea aún no están listas.")
	if not Account.signed_in():
		var e: String = await Account.sign_in()
		if e != "":
			last_error = e
			return e
	loading = true
	var res: Dictionary = await Account.rpc_call("roa_status", {})
	loading = false
	if res["code"] == 404:
		# Supabase todavía sin supabase/temporadas.sql.
		last_error = Lang.t("La tienda y el Game Pass se están preparando. ¡Vuelve pronto!")
		changed.emit()
		return last_error
	if res["code"] != 200 or not res["data"] is Dictionary:
		last_error = Lang.t(Account.error_text(res))
		changed.emit()
		return last_error
	_take(res["data"])
	if _pending_payment:
		_pending_payment = false
		_wait_gems(gems())
	return ""


## Después de pagar: revisar unas veces hasta que lleguen las gemas.
func _wait_gems(before: int) -> void:
	message.emit(Lang.t("¡Gracias por tu compra! Tus gemas llegan en unos segundos."))
	for i in 8:
		await get_tree().create_timer(4.0).timeout
		await refresh()
		if gems() > before:
			message.emit(Lang.t("¡Listo! Llegaron tus gemas."))
			return


func _take(d: Dictionary) -> void:
	status = d
	last_error = ""
	for k in ["coins", "gems", "title", "image", "banner"]:
		if d.has(k):
			Account.profile[k] = d[k]
	changed.emit()


## Llama una función que devuelve el estado nuevo. "" = bien; si no, el motivo.
func _act(fn: String, args: Dictionary) -> String:
	if not Account.signed_in():
		var e: String = await Account.sign_in()
		if e != "":
			return e
	var res: Dictionary = await Account.rpc_call(fn, args)
	if res["code"] != 200 or not res["data"] is Dictionary:
		return Lang.t(Account.error_text(res))
	_take(res["data"])
	return ""


func claim(tier_n: int, track: String) -> String:
	if demo:
		return _demo_claim(tier_n, track)
	return await _act("roa_claim", {"p_tier": tier_n, "p_track": track})


func claim_all() -> String:
	if demo:
		for r in status.get("rewards", []):
			if can_claim(int(r["tier"]), r["track"]):
				_demo_claim(int(r["tier"]), r["track"])
		return ""
	return await _act("roa_claim_all", {})


func buy_premium() -> String:
	if demo:
		var cost := int(season().get("premium_gems", 500))
		if gems() < cost:
			return Lang.t("No te alcanzan las gemas")
		status["gems"] = gems() - cost
		status["premium"] = true
		changed.emit()
		return ""
	return await _act("roa_buy_premium", {})


func buy_item(id: String) -> String:
	if demo:
		for s in status.get("shop", []):
			if s["item"] == id:
				var cur := "coins" if s.get("coins") != null else "gems"
				if int(status.get(cur, 0)) < int(s[cur]):
					return Lang.t("No te alcanzan las monedas") if cur == "coins" else Lang.t("No te alcanzan las gemas")
				status[cur] = int(status[cur]) - int(s[cur])
				status["owned"].append(id)
				changed.emit()
		return ""
	return await _act("roa_buy_item", {"p_item": id})


func equip(kind: String, id: String) -> String:
	if demo:
		status[{"imagen": "image", "estandarte": "banner", "titulo": "title"}[kind]] = id
		changed.emit()
		return ""
	return await _act("roa_equip", {"p_kind": kind, "p_item": id})


## Premio de una partida contra bots. Devuelve {ok, xp, coins, why…} o {} si no hay cuenta.
func bot_result(won: bool, seconds: int) -> Dictionary:
	if demo:
		return {"ok": true, "xp": 100 if won else 40, "coins": 25 if won else 10, "tier": tier()}
	if not Account.accounts_ready():
		return {}
	if not Account.signed_in():
		if await Account.sign_in() != "":
			return {}
	var res: Dictionary = await Account.rpc_call("roa_bot_result", {"p_won": won, "p_seconds": seconds})
	if res["code"] == 404:
		return {"ok": false, "why": "off"}
	if res["code"] != 200 or not res["data"] is Dictionary:
		return {}
	var d: Dictionary = res["data"]
	if d.get("ok", false):
		refresh()
	return d


## Comprar un paquete de gemas: abre el pago de Stripe. "" = se abrió.
func buy_gems(pack_id: String) -> String:
	if demo:
		return Lang.t("En la demostración no se cobra.")
	if not Account.signed_in():
		var e: String = await Account.sign_in()
		if e != "":
			return e
	var token: String = await Account.server_token()
	var base := Net.server_url().replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/ws")
	var back := ""
	if OS.has_feature("web"):
		var loc = JavaScriptBridge.eval("location.origin + location.pathname")
		back = loc if loc is String else ""
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var body := {"pack": pack_id, "currency": Money.pick(_pack_prices(pack_id)), "back": back}
	var err := req.request(base + "/api/checkout",
		PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + token]),
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return Lang.t("No se pudo conectar con la tienda.")
	var r: Array = await req.request_completed
	req.queue_free()
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	if r[1] != 200 or not d is Dictionary or not d.has("url"):
		return Lang.t(String(d.get("error", "No se pudo iniciar el pago."))) if d is Dictionary else Lang.t("No se pudo iniciar el pago.")
	if OS.has_feature("web"):
		# En la misma pestaña: al pagar, Stripe regresa al juego (?pago=ok).
		JavaScriptBridge.eval("location.href = %s" % JSON.stringify(d["url"]))
	else:
		_pending_payment = true
		OS.shell_open(d["url"])
		_watch_after_shell()
	return ""


## En PC: el pago se abre en el navegador; al volver al juego se revisan las gemas.
func _watch_after_shell() -> void:
	var before := gems()
	for i in 45:
		await get_tree().create_timer(8.0).timeout
		await refresh()
		if gems() > before:
			_pending_payment = false
			message.emit(Lang.t("¡Listo! Llegaron tus gemas."))
			return


func _pack_prices(pack_id: String) -> Dictionary:
	for p in status.get("packs", []):
		if p["id"] == pack_id:
			return p.get("prices", {})
	return {}


# --- Demostración (sin internet) ---------------------------------------------------

func _demo_claim(tier_n: int, track: String) -> String:
	if not can_claim(tier_n, track):
		return Lang.t("Aún no llegas a ese nivel del pase")
	var r := reward(tier_n, track)
	status["claimed"].append("%s:%d" % [track, tier_n])
	match String(r["kind"]):
		"coins":
			status["coins"] = coins() + int(r["amount"])
		"gems":
			status["gems"] = gems() + int(r["amount"])
		_:
			status["owned"].append(r["item"])
	changed.emit()
	return ""


func _demo_status() -> Dictionary:
	var items := {}
	var rar := ["comun", "raro", "raro", "epico", "legendario"]
	for c in ["maya", "humano", "orco"]:
		for n in range(1, 6):
			items["img_%s_%d" % [c, n]] = {"kind": "imagen", "name": "Aldeano %s %d" % [c, n], "rarity": rar[n - 1],
				"free": c == "maya" and n == 1, "detail": {"file": "civs/%s/unidades/aldeano/nivel%d.png" % [c, n]}}
	var banners := {
		"est_barro": ["Barro", "#4a2f1c", "#c9a36a", "#c9a36a", "comun"], "est_selva": ["Selva", "#1f4d2b", "#9fdc6a", "#e8d27a", "comun"],
		"est_tierra": ["Tierra roja", "#7a2e16", "#f0a050", "#ffd08a", "raro"], "est_oro": ["Oro del sol", "#8a5a10", "#ffe08a", "#fff2c0", "epico"],
		"est_obsidiana": ["Obsidiana", "#15141c", "#9a7cff", "#c9b8ff", "epico"], "est_quetzal": ["Quetzal", "#0d5a5a", "#5fffd0", "#ffe066", "legendario"],
		"est_rojo": ["Rojo guerrero", "#8a1414", "#ffcf5a", "#ffcf5a", "comun"], "est_azul": ["Azul maya", "#14467a", "#7fd0ff", "#e8f6ff", "comun"],
		"est_noche": ["Noche estrellada", "#101a3c", "#ffd75a", "#fff3b0", "raro"], "est_jaguar": ["Jaguar", "#b0700f", "#2a1606", "#2a1606", "epico"],
		"est_jade": ["Jade real", "#1d6b45", "#ffd75a", "#c8ffe0", "legendario"]}
	for id in banners:
		var b: Array = banners[id]
		items[id] = {"kind": "estandarte", "name": b[0], "rarity": b[4], "free": id == "est_barro",
			"detail": {"bg": b[1], "edge": b[2], "mark": b[3]}}
	var titles := {"tit_recolector": ["Recolector", "comun"], "tit_constructor": ["Constructor", "comun"],
		"tit_cacique": ["Cacique", "raro"], "tit_senor_guerra": ["Señor de la guerra", "epico"],
		"tit_leyenda_t1": ["Leyenda de la temporada 1", "legendario"], "tit_veterano_t1": ["Veterano de la temporada 1", "raro"],
		"tit_comerciante": ["Comerciante", "comun"], "tit_rey_maiz": ["Rey del maíz", "raro"], "tit_hijo_sol": ["Hijo del sol", "epico"]}
	for id in titles:
		items[id] = {"kind": "titulo", "name": titles[id][0], "rarity": titles[id][1], "free": false, "detail": {}}
	var rewards: Array = []
	var free_items := {6: "tit_recolector", 12: "img_maya_2", 16: "est_selva", 26: "tit_constructor", 36: "img_maya_3",
		46: "est_tierra", 50: "tit_veterano_t1"}
	for g in range(2, 51, 2):
		if free_items.has(g):
			rewards.append({"tier": g, "track": "free", "kind": "item", "item": free_items[g], "amount": 0})
		elif g % 10 == 0:
			rewards.append({"tier": g, "track": "free", "kind": "gems", "item": null, "amount": 25})
		else:
			rewards.append({"tier": g, "track": "free", "kind": "coins", "item": null, "amount": 100})
	var prem_items := {1: "est_oro", 3: "img_humano_1", 8: "img_orco_1", 10: "tit_cacique", 13: "img_humano_2",
		18: "img_orco_2", 22: "est_obsidiana", 23: "img_humano_3", 28: "img_orco_3", 30: "tit_senor_guerra",
		33: "img_humano_4", 38: "img_orco_4", 42: "est_quetzal", 43: "img_humano_5", 48: "img_orco_5",
		49: "tit_leyenda_t1", 50: "img_maya_5"}
	for g in range(1, 51):
		if prem_items.has(g):
			rewards.append({"tier": g, "track": "premium", "kind": "item", "item": prem_items[g], "amount": 0})
		elif g in [15, 25, 35, 45]:
			rewards.append({"tier": g, "track": "premium", "kind": "gems", "item": null, "amount": 100})
		else:
			rewards.append({"tier": g, "track": "premium", "kind": "coins", "item": null, "amount": 300 if g % 5 == 0 else 150})
	var now := Time.get_datetime_string_from_system(true)
	var end := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 41 * 86400)
	return {
		"coins": 1250, "gems": 620, "title": "tit_recolector", "image": "img_maya_2", "banner": "est_selva",
		"season": {"id": "t1", "name": "Temporada 1: El despertar del sol", "tiers": 50, "tier_xp": 500,
			"premium_gems": 500, "premium_bonus": 0.2, "ends_at": end, "now": now},
		"xp": 6230, "premium": false, "rewards": rewards, "claimed": ["free:2", "free:4", "free:6"],
		"items": items, "owned": ["tit_recolector", "img_maya_2", "est_selva"],
		"shop": [{"item": "est_rojo", "coins": 800, "gems": null}, {"item": "est_azul", "coins": 800, "gems": null},
			{"item": "tit_comerciante", "coins": 500, "gems": null}, {"item": "tit_rey_maiz", "coins": 1500, "gems": null},
			{"item": "est_noche", "coins": null, "gems": 150}, {"item": "est_jaguar", "coins": null, "gems": 300},
			{"item": "tit_hijo_sol", "coins": null, "gems": 200}, {"item": "est_jade", "coins": null, "gems": 600},
			{"item": "img_maya_4", "coins": null, "gems": 250}],
		"packs": [{"id": "gemas_100", "gems": 100, "bonus": 0, "prices": {"USD": 0.99, "MXN": 19, "EUR": 0.99, "BRL": 4.9}},
			{"id": "gemas_500", "gems": 500, "bonus": 50, "prices": {"USD": 4.99, "MXN": 99, "EUR": 4.99, "BRL": 24.9}},
			{"id": "gemas_1000", "gems": 1000, "bonus": 200, "prices": {"USD": 9.99, "MXN": 199, "EUR": 9.99, "BRL": 49.9}},
			{"id": "gemas_2000", "gems": 2000, "bonus": 600, "prices": {"USD": 19.99, "MXN": 399, "EUR": 19.99, "BRL": 99.9}}],
		"bot_games_today": 2, "bot_daily": 8,
		"prizes": {"ranked_win": {"xp": 200, "coins": 60}, "ranked_loss": {"xp": 80, "coins": 20},
			"bots_win": {"xp": 100, "coins": 25}, "bots_loss": {"xp": 40, "coins": 10}},
	}
