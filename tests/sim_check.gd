extends Node
## Prueba sin pantalla: godot --headless --path . res://tests/sim_check.tscn

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	for c in Defs.CIV_ORDER:
		var sc := Defs.civ_score(c)
		check(absf(sc) <= 1.0, "civilización %s balanceada (puntos %.2f)" % [c, sc])
	await _economy_test()
	await _herd_test()
	await _bot_match_test()
	print("RESULTADO: %s (%d fallos)" % ["BIEN" if fails == 0 else "MAL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _new_game(players: Array, seed_v: int) -> Game:
	Setup.players = players
	Setup.local_player = 0
	Setup.map_size = "mediano"
	Setup.seed_value = seed_v
	var g: Game = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	g.paused = true
	await get_tree().process_frame
	return g


func _economy_test() -> void:
	var g := await _new_game([
		{"name": "A", "civ": "mexica", "team": 1, "color": 0, "bot": false},
		{"name": "B", "civ": "maya", "team": 2, "color": 1, "bot": false},
	], 1234)
	var p := g.players[0]
	var vills: Array[Unit] = []
	for u in g.units:
		if u.owner_id == 0:
			vills.append(u)
	check(vills.size() == 5, "empieza con 5 aldeanos")
	check(p.pop_cap == 5, "población máxima inicial 5 (centro)")
	var centro := g.main_center(0)
	# Caza: la cabra más cercana
	var goat: Animal = null
	var bd := INF
	for a in g.animals:
		if a.kind == "cabra" and a.pos.distance_to(centro.center()) < bd:
			bd = a.pos.distance_to(centro.center())
			goat = a
	check(goat != null, "hay cabras cerca del centro (%.1f)" % bd)
	var food0: float = p.res["comida"]
	vills[0].cmd_gather(goat)
	# Madera
	var tree := g.find_resource_near("arbol", centro.center(), 30.0, 0)
	check(tree != null, "hay árboles cerca")
	var wood0: float = p.res["madera"]
	vills[1].cmd_gather(tree)
	# Casa
	var spot := Vector2i(-1, -1)
	for r in range(5, 12):
		for dx in range(-r, r + 1):
			var t := centro.rect.position + Vector2i(dx, -r)
			if g.can_place(0, "casa", t):
				spot = t
				break
		if spot.x >= 0:
			break
	var house := g.place_building(0, "casa", spot)
	check(house != null, "se coloca una casa (cuesta madera)")
	vills[2].cmd_build(house)
	# Bayas
	var berry := g.find_resource_near("arbusto", centro.center(), 30.0, 0)
	vills[3].cmd_gather(berry)
	# Granja: comprar 2 siembras en el centro, colocar una y trabajarla
	p.res["madera"] += 200
	check(g.build_block_reason(0, "granja") != "", "sin siembra no se puede poner granja")
	check(g.buy_seed(0) and g.buy_seed(0), "comprar 2 siembras en el centro")
	var fspot := Vector2i(-1, -1)
	for r in range(6, 14):
		for dx in range(-r, r + 1):
			var t := centro.rect.position + Vector2i(dx, r)
			if g.can_place(0, "granja", t):
				fspot = t
				break
		if fspot.x >= 0:
			break
	var farm := g.place_building(0, "granja", fspot)
	check(farm != null and farm.rect.size == Vector2i(2, 2), "granja de 4 cuadros colocada")
	check(p.seeds == 1, "queda 1 siembra guardada")
	vills[4].cmd_build(farm)
	g.run_seconds(90.0)
	check(goat.dead, "la cabra murió al cazarla")
	check(house.complete, "la casa se terminó")
	check(p.pop_cap == 10, "con 1 casa la población máxima es 10 (es %d)" % p.pop_cap)
	check(p.res["comida"] > food0 + 40, "llegó alimento al centro (%.0f -> %.0f)" % [food0, p.res["comida"]])
	check(p.res["madera"] > wood0 - 30 + 15, "llegó madera (%.0f)" % p.res["madera"])
	check(farm.complete and not farm.sowing(), "la granja se construyó y se sembró")
	check(farm.food < 250.0, "el granjero ya cosecha (queda %d)" % farm.food)
	g.run_seconds(700.0)
	check(p.seeds == 0 and Entity.valid(farm), "al agotarse se resembró sola con la siembra guardada")
	# Entrenar aldeano
	check(g.train(0, centro, "aldeano"), "se puede entrenar un aldeano")
	g.run_seconds(15.0)
	var n := 0
	for u in g.units:
		if u.owner_id == 0:
			n += 1
	check(n == 6, "ahora hay 6 aldeanos (%d)" % n)
	# Agotar la caza: dejar que siga cazando un buen rato
	g.run_seconds(400.0)
	var hunter := vills[0]
	print("     cazador: estado=%s aviso='%s'" % [hunter.status_text(), hunter.idle_notice])
	var eaten := 0
	for a in g.animals:
		if a.kind == "cabra" and a.home.distance_to(centro.center()) < 12.0:
			eaten += 1
	check(eaten < 5, "el cazador pasó a las siguientes cabras (quedan %d cerca)" % eaten)
	# Era: requisitos
	var reason := g.age_block_reason(0, centro)
	check(reason.begins_with("Falta"), "subir de era pide edificios: " + reason)
	# Victoria: destruir el centro de B
	var cb := g.main_center(1)
	cb.take_damage(99999.0, null)
	g.run_seconds(3.0)
	check(g.players[1].defeated, "B sin centro queda derrotado")
	check(g.over, "la partida termina")
	g.queue_free()
	await get_tree().process_frame


func _bot_match_test() -> void:
	var g := await _new_game([
		{"name": "Obs", "civ": "mexica", "team": 1, "color": 0, "bot": true, "difficulty": "dificil"},
		{"name": "Bot", "civ": "maya", "team": 2, "color": 1, "bot": true, "difficulty": "dificil"},
	], 99)
	var t0 := Time.get_ticks_msec()
	var corral_seen := false
	var herded_max := 0
	for m in 14:
		g.run_seconds(60.0)
		var line := "     min %2d:" % (m + 1)
		for p in g.players:
			var v := 0
			var a := 0
			for u in g.units:
				if u.owner_id == p.id:
					if u.is_villager():
						v += 1
					else:
						a += 1
			line += "  %s ald=%d ejer=%d edif=%d era=%d com=%d mad=%d oro=%d pie=%d |" % [p.name, v, a,
				g.count_buildings(p.id, Defs.BUILDINGS.keys()), p.age, p.res["comida"], p.res["madera"], p.res["oro"], p.res["piedra"]]
		print(line)
		for b in g.buildings:
			if b.kind == "corral" and b.complete:
				corral_seen = true
		var owned := 0
		for an in g.animals:
			if not an.dead and an.owner_id >= 0:
				owned += 1
		herded_max = maxi(herded_max, owned)
		if g.over:
			break
	print("     tiempo real: %d ms" % (Time.get_ticks_msec() - t0))
	var best_v := 0
	var best_age := 0
	for p in g.players:
		var v := 0
		for u in g.units:
			if u.owner_id == p.id and u.is_villager():
				v += 1
		best_v = maxi(best_v, v)
		best_age = maxi(best_age, p.age)
	check(best_v >= 15 or g.over, "un bot creció a 15+ aldeanos (%d)" % best_v)
	check(best_age >= 2 or g.over, "un bot avanzó de era (era %d)" % best_age)
	check(corral_seen, "los bots construyeron un corral")
	check(herded_max >= 2, "los bots pastorearon animales (%d a la vez)" % herded_max)
	g.queue_free()
	await get_tree().process_frame


## Pastoreo: solo un aldeano, 10 segundos seguidos; acercarse no basta. En el corral
## da alimento sin morir y engorda. El rival la roba pastoreándola igual; si se
## interrumpe, vuelve a empezar.
func _herd_test() -> void:
	var g := await _new_game([
		{"name": "A", "civ": "mexica", "team": 1, "color": 0, "bot": false},
		{"name": "B", "civ": "maya", "team": 2, "color": 1, "bot": false},
	], 4321)
	var c := g.main_center(0).center()
	var goat: Animal = null
	var bd := INF
	for a in g.animals:
		if a.kind == "cabra" and a.pos.distance_to(c) < bd:
			bd = a.pos.distance_to(c)
			goat = a
	check(goat != null and goat.owner_id == -1, "hay una cabra salvaje cerca")
	var mine: Unit = null
	var enemy: Unit = null
	for u in g.units:
		if u.owner_id == 0 and mine == null:
			mine = u
		if u.owner_id == 1 and enemy == null:
			enemy = u
	# Solo acercarse no basta.
	mine.pos = goat.pos + Vector2(1.0, 0)
	mine.prev_pos = mine.pos
	g.run_seconds(4.0)
	check(goat.owner_id == -1, "acercarse no la vuelve tuya")
	# Pastorearla: a los 5 s aún no, a los 10 s seguidos sí.
	g.apply_cmd(0, {"k": "order", "u": [mine.id], "t": goat.id, "x": goat.pos.x, "y": goat.pos.y})
	check(mine.state == Unit.S.HERD, "clic derecho con un aldeano en la cabra = pastorear")
	g.run_seconds(5.0)
	check(goat.owner_id == -1, "a los 5 segundos todavía no es tuya (%s)" % mine.status_text())
	g.run_seconds(6.5)
	check(goat.owner_id == 0, "tras 10 segundos seguidos de pastoreo es tuya")
	check(mine.state == Unit.S.IDLE, "el aldeano termina de pastorear")
	# Corral terminado cerca del centro.
	var corral: Building = null
	for r in range(6, 16):
		for k in 16:
			var t := MapData.to_tile(c + Vector2.from_angle(TAU * k / 16.0) * r)
			if corral == null and g.can_place(0, "corral", t):
				corral = g.spawn_building("corral", 0, t, true)
	check(corral != null, "se puso un corral")
	g.apply_cmd(0, {"k": "order", "u": [goat.id], "t": corral.id, "x": corral.center().x, "y": corral.center().y})
	mine.cmd_move(c)
	var food0: float = g.players[0].res["comida"]
	var meat0 := goat.food
	g.run_seconds(60.0)
	var gained: float = g.players[0].res["comida"] - food0
	check(goat.grazing(), "la cabra está pastando en el corral")
	check(gained > 6.0, "el corral dio alimento sin matar a la cabra (+%d)" % int(gained))
	check(goat.food > meat0 + 3.0 and not goat.dead, "la cabra engordó (%d -> %d de carne)" % [int(meat0), int(goat.food)])
	# El rival la pastorea lejos de tu centro (que dispara a los enemigos); si lo interrumpen, vuelve a empezar.
	var far := g.main_center(1).center().lerp(c, 0.5)
	far = MapData.center(g.map.nearest_free(MapData.to_tile(far)))
	goat.pos = far
	goat.prev_pos = far
	goat.home = far
	enemy.pos = goat.pos + Vector2(0, 1.0)
	enemy.prev_pos = enemy.pos
	g.apply_cmd(1, {"k": "order", "u": [enemy.id], "t": goat.id, "x": goat.pos.x, "y": goat.pos.y})
	g.run_seconds(6.0)
	g.apply_cmd(1, {"k": "stop", "u": [enemy.id]})
	g.run_seconds(0.5)
	g.apply_cmd(1, {"k": "order", "u": [enemy.id], "t": goat.id, "x": goat.pos.x, "y": goat.pos.y})
	g.run_seconds(6.0)
	check(goat.owner_id == 0, "interrumpido, el rival vuelve a empezar (6 + 6 s no bastan)")
	g.run_seconds(6.0)
	check(goat.owner_id == 1, "el rival la robó pastoreándola 10 segundos seguidos (%s)" % enemy.status_text())
	g.queue_free()
	await get_tree().process_frame
