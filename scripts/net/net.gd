extends Node
## Autoload "Net": conexión al servidor (WebSocket) para jugar en línea.
## Modelo lockstep: cada jugador manda solo sus órdenes; el servidor las junta
## por turnos de 100 ms y se las reparte a todos. Cada cliente simula lo mismo.

signal room_changed
signal started
signal failed(msg: String)
signal closed

const PROTOCOL := 1
const DEFAULT_SERVER := "wss://conquista.onrender.com/ws"

var ws := WebSocketPeer.new()
var is_open := false
var player_name := "Jugador"
var room: Dictionary = {}      # {code, you, host, players, bots, map}
var game: Game = null
var _buffer: Array = []        # turnos que llegan antes de que cargue la partida
var _want_open := false
var _on_open: Dictionary = {}


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


func close() -> void:
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


func set_config(map_size: String, bots: Array) -> void:
	send({"t": "config", "map": map_size, "bots": bots})


func start_game() -> void:
	send({"t": "start"})


func is_host() -> bool:
	return room.get("you", -1) == room.get("host", -2)


func attach(g: Game) -> void:
	game = g
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
			failed.emit(String(m.get("msg", "Error")))
		"start":
			Setup.players = m["players"]
			for p in Setup.players:
				p["team"] = int(p["team"])
				p["color"] = int(p["color"])
			Setup.local_player = int(m["you"])
			Setup.map_size = String(m["map"])
			Setup.seed_value = int(m["seed"])
			Setup.online = true
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
