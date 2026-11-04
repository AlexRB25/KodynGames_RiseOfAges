extends Node
## Prueba de red: un servidor local y dos clientes.
## godot --headless --path . res://tests/net_check.tscn -- --server=ws://127.0.0.1:8080/ws --role=host --dir=CARPETA
## godot --headless --path . res://tests/net_check.tscn -- --server=... --role=guest --dir=CARPETA

var role := "host"
var dir := ""
var g: Game
var t0 := 0.0
var ordered := false
var done := false


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.get_slice("=", 1)
	return d


func _ready() -> void:
	role = _arg("role", "host")
	dir = _arg("dir", "")
	Net.failed.connect(func(m: String) -> void:
		print("[%s] error: %s" % [role, m])
		get_tree().quit(2))
	Net.room_changed.connect(_on_room)
	Net.started.connect(_on_started)
	if role == "host":
		Net.create_room("Anfitrión")
	else:
		var code := ""
		for i in 100:
			code = FileAccess.get_file_as_string(dir + "/code.txt")
			if code != "":
				break
			await get_tree().create_timer(0.1).timeout
		Net.join_room("Invitado", code)


func _on_room() -> void:
	var r := Net.room
	if role == "host":
		var f := FileAccess.open(dir + "/code.txt", FileAccess.WRITE)
		f.store_string(r["code"])
		f.close()
		if r["players"].size() == 2 and r["bots"].is_empty():
			# 1 bot en el equipo del invitado; el invitado se pone en el equipo 2.
			Net.set_config("pequeno", [{"civ": "zapoteca", "team": 1, "difficulty": "normal"}])
		elif r["players"].size() == 2 and int(r["players"][1]["team"]) == 2 and not r["bots"].is_empty():
			Net.start_game()
	else:
		var me: Dictionary = {}
		for p in r["players"]:
			if int(p["id"]) == int(r["you"]):
				me = p
		if not me.is_empty() and int(me["team"]) != 2:
			Net.set_me("maya", 2, 3)


func _on_started() -> void:
	print("[%s] partida iniciada, soy el jugador %d de %d" % [role, Setup.local_player, Setup.players.size()])
	g = load("res://scenes/game.tscn").instantiate()
	g.stop_at_tick = 600
	add_child(g)
	t0 = Time.get_ticks_msec() / 1000.0


func _process(_dt: float) -> void:
	if g == null or done:
		return
	var t := Time.get_ticks_msec() / 1000.0 - t0
	if not ordered and t > 2.0:
		ordered = true
		var mine: Array = []
		for u in g.units:
			if u.owner_id == g.local_id:
				mine.append(u)
		var c := g.main_center(g.local_id)
		var tree := g.find_resource_near("arbol", c.center(), 40.0, g.local_id)
		g.order_units(mine.slice(0, 3), tree, tree.center(), false)
		g.issue({"k": "train", "e": c.id, "b": "aldeano"})
		var berry := g.find_resource_near("arbusto", c.center(), 40.0, g.local_id)
		if berry:
			g.order_units(mine.slice(3, 5), berry, berry.center(), false)
	if g.tick >= 600:
		done = true
		# Comparar el estado exactamente en el paso 600.
		var h := g.state_hash()
		var res := "tick=%d hash=%d madera=%d comida=%d unidades=%d" % [g.tick, h,
			g.players[g.local_id].res["madera"], g.players[g.local_id].res["comida"], g.units.size()]
		print("[%s] %s" % [role, res])
		var f := FileAccess.open(dir + "/" + role + ".txt", FileAccess.WRITE)
		f.store_string(str(h))
		f.close()
		get_tree().quit(0)
