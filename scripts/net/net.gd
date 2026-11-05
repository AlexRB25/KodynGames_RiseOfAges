extends Node
## Autoload "Net": conexión al servidor (WebSocket) para jugar en línea.
## Modelo lockstep: cada jugador manda solo sus órdenes; el servidor las junta
## por turnos de 100 ms y se las reparte a todos. Cada cliente simula lo mismo.

signal room_changed
signal started
signal failed(msg: String)
signal closed
signal queue_changed      # cambió queue_info (buscando partida con rango)
signal rated(msg: Dictionary)   # el servidor repartió los puntos de la partida con rango

const PROTOCOL := 2
const DEFAULT_SERVER := "wss://conquista-srzq.onrender.com/ws"

var ws := WebSocketPeer.new()
var is_open := false
var player_name := "Jugador"
var room: Dictionary = {}      # {code, you, host, players, bots, map}
var game: Game = null
var _buffer: Array = []        # turnos que llegan antes de que cargue la partida
var _want_open := false
var _on_open: Dictionary = {}
var ranked := false            # la partida actual es con rango
var queue_info: Dictionary = {}   # {mode, waiting, need} mientras buscas partida
var last_rated: Dictionary = {}


func server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			return a.get_slice("=", 1)
	if OS.has_feature("web"):
		var loc = JavaScriptBridge.eval("location.protocol + '//' + location.host")
		if loc is String and loc.begins_with("http"):
			return loc.replace("https://", "wss://").replace("http://", "ws://") + "/ws"
	var cfg := FileAccess.get_file_as_string("res://data/online.json")
	var d = JSON.parse_string(cfg) if cfg != "" else null
	if d is Dictionary and d.has("server"):
		return d["server"]
	return DEFAULT_SERVER


## Conecta y, al abrir, manda la primera orden (crear o unirse a sala).
func open_and(first: Dictionary) -> void:
	close()
	ws = WebSocketPeer.new()
	_on_open = first
	_want_open = true
	var err := ws.connect_to_url(server_url())
	if err != OK:
		_want_open = false
		failed.emit("No se pudo conectar al servidor.")


func create_room(name: String) -> void:
	player_name = name
	open_and({"t": "create", "name": name, "v": PROTOCOL})


func join_room(name: String, code: String) -> void:
	player_name = name
	open_and({"t": "join", "name": name, "code": code.strip_edges().to_upper(), "v": PROTOCOL})


## Buscar partida con rango (1v1, 2v2 o 4v4): el servidor empareja por puntos.
func queue(mode: String, civ: String) -> void:
	player_name = Account.player_name if Account.player_name != "" else player_name
	if Account.accounts_ready() and not Account.signed_in():
		var err: String = await Account.sign_in()
		if err != "":
			failed.emit(err)
			return
	var token: String = await Account.server_token()
	open_and({"t": "queue", "v": PROTOCOL, "mode": mode, "civ": civ, "name": player_name, "token": token})
	queue_info = {"mode": mode, "waiting": 0, "need": 0}
	queue_changed.emit()


func unqueue() -> void:
	send({"t": "unqueue"})
	close()


func close() -> void:
	queue_info = {}
	ranked = false
	last_rated = {}
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN or ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		ws.close()
	is_open = false
	_want_open = false
	room = {}
	game = null
	_buffer.clear()


func send(d: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


func send_cmd(c: Dictionary) -> void:
	send({"t": "cmd", "c": c})


func send_hash(n: int, h: int) -> void:
	send({"t": "hash", "n": n, "h": h})


func set_me(civ: String, team: int, color: int) -> void:
	send({"t": "set", "civ": civ, "team": team, "color": color})


func set_config(map_size: String, bots: Array, map_type := "") -> void:
	if map_type == "":
		map_type = String(room.get("type", "azar"))
	send({"t": "config", "map": map_size, "bots": bots, "type": map_type})


func start_game() -> void:
	send({"t": "start"})


func is_host() -> bool:
	return room.get("you", -1) == room.get("host", -2)


func attach(g: Game) -> void:
	game = g
	if ranked:
		game.game_over.connect(func(winner: int) -> void: send({"t": "over", "winner": winner}))
	for t in _buffer:
		game.receive_turn(t[0], t[1])
	_buffer.clear()


func _process(_dt: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not is_open:
			is_open = true
			if not _on_open.is_empty():
				send(_on_open)
				_on_open = {}
		while ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var m = JSON.parse_string(txt)
			if m is Dictionary:
				_handle(m)
	elif st == WebSocketPeer.STATE_CLOSED:
		if is_open or _want_open:
			var was_open := is_open
			is_open = false
			_want_open = false
			if not queue_info.is_empty():
				queue_info = {}
				queue_changed.emit()
			if was_open:
				closed.emit()
				if game and game.hud:
					game.hud.notify("Se perdió la conexión con el servidor.", Vector2.INF)
			else:
				failed.emit("No se pudo conectar al servidor (%s)." % server_url())


func _handle(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"room":
			room = m
			room_changed.emit()
		"error":
			if not queue_info.is_empty():
				queue_info = {}
				queue_changed.emit()
			failed.emit(String(m.get("msg", "Error")))
		"queued", "queue":
			queue_info = {"mode": m.get("mode", ""), "waiting": int(m.get("waiting", 0)), "need": int(m.get("need", 0))}
			if m.has("points"):
				Account.take_server_profile(m)
			queue_changed.emit()
		"unqueued":
			queue_info = {}
			queue_changed.emit()
			if m.has("msg"):
				failed.emit(String(m["msg"]))
		"rated":
			last_rated = m
			if m.get("you") is Dictionary:
				Account.take_server_profile(m["you"])
			if game:
				game.end_by_forfeit(int(m["winner"]) if m.get("winner") != null else -1, bool(m.get("forfeit", false)))
				if game.hud:
					game.hud.show_rating(m)
			rated.emit(m)
		"start":
			Setup.players = m["players"]
			for p in Setup.players:
				p["team"] = int(p["team"])
				p["color"] = int(p["color"])
			Setup.local_player = int(m["you"])
			Setup.map_size = String(m["map"])
			Setup.map_type = String(m.get("type", "azar"))
			Setup.seed_value = int(m["seed"])
			Setup.online = true
			ranked = bool(m.get("ranked", false))
			queue_info = {}
			_buffer.clear()
			started.emit()
		"turn":
			var n := int(m["n"])
			var cmds: Array = m.get("cmds", [])
			if game:
				game.receive_turn(n, cmds)
			else:
				_buffer.append([n, cmds])
		"left":
			if game and game.hud:
				game.hud.notify("%s se desconectó." % m.get("name", "Un jugador"), Vector2.INF)
		"desync":
			if game and game.hud:
				game.hud.notify("Aviso: la partida se desincronizó (turno %d)." % int(m.get("n", 0)), Vector2.INF)
