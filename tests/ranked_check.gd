extends Node
## Prueba de partida con rango (servidor en modo prueba, sin Supabase):
## dos clientes entran a la cola 1v1, el servidor los empareja, "a" se rinde y
## los dos deben recibir sus puntos (a pierde, b gana).
## godot --headless --path . res://tests/ranked_check.tscn -- --server=ws://127.0.0.1:8080/ws --role=a --name=Ana

var role := "a"
var g: Game
var resigned := false


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.get_slice("=", 1)
	return d


func _ready() -> void:
	role = _arg("role", "a")
	Net.failed.connect(func(m: String) -> void:
		print("[%s] error: %s" % [role, m])
		get_tree().quit(2))
	Net.queue_changed.connect(func() -> void: print("[%s] cola: %s" % [role, Net.queue_info]))
	Net.started.connect(_on_started)
	Net.rated.connect(_on_rated)
	Account.set_player_name(_arg("name", role))
	Net.queue("1v1", "maya" if role == "a" else "mexica")
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[%s] FALLO: tiempo agotado" % role)
		get_tree().quit(3))


func _on_started() -> void:
	print("[%s] emparejado: soy %d de %d, rango=%s, mapa=%s" % [role, Setup.local_player, Setup.players.size(), Net.ranked, Setup.map_size])
	g = load("res://scenes/game.tscn").instantiate()
	add_child(g)


func _process(_dt: float) -> void:
	if g and role == "a" and not resigned and g.tick > 60:
		resigned = true
		print("[a] me rindo")
		g.issue({"k": "resign"})


func _on_rated(m: Dictionary) -> void:
	var you: Dictionary = m.get("you", {})
	var won: bool = bool(you.get("won", false))
	var ok := (won and role == "b") or (not won and role == "a")
	print("[%s] %s puntos: %+d -> %d (nivel %d), ganador equipo %s, mi equipo %d" % [role, "OK" if ok else "FALLO",
		int(you.get("delta", 0)), int(you.get("points", 0)), int(you.get("level", 1)), str(m.get("winner")), g.team_of(g.local_id)])
	get_tree().quit(0 if ok else 1)
