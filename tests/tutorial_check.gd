extends Node
## Recorre el tutorial como un jugador y revisa que cada paso avance solo.
## Necesita pantalla (el tutorial vive en la interfaz):
## godot --path . res://tests/tutorial_check.tscn

var fails := 0


func check(c: bool, msg: String) -> void:
	print(("OK   " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _wait(g: Game, secs: float) -> void:
	for c in g._local_cmds:
		g.apply_cmd(c[0], c[1])
	g._local_cmds.clear()
	g.run_seconds(secs)
	for k in 3:
		await get_tree().process_frame


func _ready() -> void:
	Setup.default_skirmish()
	Setup.players[0]["civ"] = "maya"
	Setup.tutorial = true
	Setup.map_size = "pequeno"
	Setup.map_type = "valle"
	Setup.seed_value = 4242
	var g: Game = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	g.paused = true
	for k in 5:
		await get_tree().process_frame
	var tut: Tutorial = null
	for c in g.get_children():
		if c is Tutorial:
			tut = c
	check(tut != null, "el tutorial arranca en la partida guiada")
	check(tut.i == 0, "paso 1: bienvenida en el Centro")
	tut._on_next()
	await get_tree().process_frame
	check(tut.i == 1, "paso 2: seleccionar un aldeano")
	# Tocar dentro del círculo (como con el dedo), no por código.
	g.controller.set_selection([])
	await get_tree().process_frame
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = tut.target_pos + Vector2(0, tut.target_r * 0.7)
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(tut.i == 2, "al tocar el círculo pasa a 'Muévelo'")
	g.order_units([tut._villager], null, tut._spot, false)
	await _wait(g, 8.0)
	check(tut.i == 3, "al llegar a la marca pasa a 'Junta madera'")
	g.order_units([tut._villager], tut._tree(), tut._tree().center(), false)
	await _wait(g, 6.0)
	check(tut.i == 4, "al cortar el árbol pasa a 'Junta comida'")
	var other: Unit = null
	for u in g.units:
		if u.owner_id == g.local_id and u.is_villager() and u != tut._villager:
			other = u
			break
	var f := tut._food()
	g.order_units([other], f, f.center(), false)
	await _wait(g, 10.0)
	check(tut.i == 5, "al juntar comida pasa a 'Compra un aldeano'")
	g.issue({"k": "train", "e": g.main_center(g.local_id).id, "b": "aldeano"})
	await _wait(g, 0.5)
	check(tut.i == 6, "al comprar pasa a 'Construye una casa'")
	var c := g.main_center(g.local_id).center()
	var placed := false
	for r in range(5, 14):
		for k in 12:
			var t := MapData.to_tile(c + Vector2.from_angle(TAU * k / 12.0) * r)
			if not placed and g.can_place(g.local_id, "casa", t):
				g.issue({"k": "place", "b": "casa", "tiles": [[t.x, t.y]], "u": [], "q": false})
				placed = true
	await _wait(g, 0.5)
	check(tut.i == 7, "al poner la casa pasa a 'Tus recursos'")
	tut._on_next()
	await get_tree().process_frame
	tut._on_next()
	await get_tree().process_frame
	check(tut.i == 9 and steps_last(tut), "último paso: '¡Listo!' con Seguir jugando / Ir al menú")
	tut._skip()
	check(Account.tutorial_done(), "queda guardado que ya hizo el tutorial")
	print("RESULTADO: %s (%d fallos)" % ["BIEN" if fails == 0 else "MAL", fails])
	get_tree().quit(1 if fails else 0)


func steps_last(tut: Tutorial) -> bool:
	return tut.steps[tut.i].get("last", false)
