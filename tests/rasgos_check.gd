extends Node
## Prueba sin pantalla de lo nuevo: puertas, torres con arqueros, mejoras, barcos y
## trampas, asedio, reliquias y victoria por maravilla.
## godot --headless --path . res://tests/rasgos_check.tscn

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


func _ready() -> void:
	await _gate_test()
	await _tower_tech_test()
	await _naval_test()
	await _siege_test()
	await _wonder_test()
	await _bell_test()
	await _bots_long_test()
	print("RESULTADO: %s (%d fallos)" % ["BIEN" if fails == 0 else "MAL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _new_game(seed_v: int, map_type := "valle") -> Game:
	Setup.players = [
		{"name": "A", "civ": "mexica", "team": 1, "color": 0, "bot": false},
		{"name": "B", "civ": "maya", "team": 2, "color": 1, "bot": false},
	]
	Setup.local_player = 0
	Setup.map_size = "mediano"
	Setup.map_type = map_type
	Setup.seed_value = seed_v
	var g: Game = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	g.paused = true
	await get_tree().process_frame
	while not g._started:
		await get_tree().process_frame
	return g


func _rich(g: Game, pid: int) -> void:
	for r in Defs.RES:
		g.players[pid].res[r] = 50000.0


## Lugar abierto de n×n cerca de un punto.
func _open_spot(g: Game, near: Vector2, n: int, rmin := 6) -> Vector2i:
	var c := MapData.to_tile(near)
	for r in range(rmin, 40):
		for k in 32:
			var t := MapData.to_tile(Vector2(c) + Vector2.from_angle(TAU * k / 32.0) * r)
			if g.map.rect_open(Rect2i(t - Vector2i.ONE, Vector2i(n + 2, n + 2))):
				return t
	return Vector2i(-1, -1)


func _gate_test() -> void:
	var g := await _new_game(777)
	var spot := _open_spot(g, g.main_center(0).center(), 11, 8)
	check(spot.x >= 0, "hay un lugar abierto para el corral de muros")
	# Cuadro de 9x9 con muro, y una puerta de A a la mitad del lado izquierdo.
	var o := spot + Vector2i(1, 1)
	var gate := o + Vector2i(0, 4)
	for i in 9:
		for t in [o + Vector2i(i, 0), o + Vector2i(i, 8), o + Vector2i(0, i), o + Vector2i(8, i)]:
			if t == gate:
				continue
			if g.map.entity_at(t) == null:
				g.spawn_building("muralla", 0, t, true)
	var gb := g.spawn_building("puerta", 0, gate, true)
	check(gb.display_name() == Lang.t("Portón de madera"), "la puerta empieza como portón de madera")
	check(g.map.is_free(gate, 1) and not g.map.is_free(gate, 2) and not g.map.is_free(gate, 0), "la puerta deja pasar solo al equipo dueño")
	var inside := MapData.center(o + Vector2i(4, 4))
	var outside := MapData.center(o + Vector2i(-4, 4))
	var ua := g.spawn_unit("aldeano", 0, inside)
	var ub := g.spawn_unit("aldeano", 1, inside + Vector2(0.5, 0.5))
	ua.cmd_move(outside)
	ub.cmd_move(outside)
	g.run_seconds(20.0)
	print("     guerrero en ", ua.pos, " meta ", outside, " vida ", ua.hp, " ", ua.status_text(), " libre meta ", g.map.is_free(MapData.to_tile(outside), 1))
	check(ua.pos.distance_to(outside) < 1.5, "tu aldeano sale por tu puerta (%.1f)" % ua.pos.distance_to(outside))
	check(Rect2(Vector2(o), Vector2(9, 9)).has_point(ub.pos), "el aldeano enemigo no puede salir por esa puerta")
	# Mejora: muro de piedra cambia muros y puertas que ya existen.
	var w0: Building = g.map.entity_at(o)
	var hp0 := w0.max_hp
	g.finish_tech(0, "muro_piedra")
	check(gb.display_name() == Lang.t("Puerta de piedra") and w0.display_name() == Lang.t("Muro de piedra"), "con la mejora: muro de piedra y puerta de piedra")
	check(w0.max_hp > hp0 * 2.0, "el muro de piedra tiene mucha más vida (%d -> %d)" % [hp0, w0.max_hp])
	check(g.build_cost(0, "muralla").has("piedra"), "los muros nuevos cuestan piedra")
	g.queue_free()
	await get_tree().process_frame


func _tower_tech_test() -> void:
	var g := await _new_game(778)
	_rich(g, 0)
	var c := g.main_center(0).center()
	var tw := g.spawn_building("torre", 0, _open_spot(g, c, 2), true)
	check(tw.display_name() == Lang.t("Puesto de avanzada") and tw.garrison_space() == 0, "la torre empieza como puesto de avanzada, sin arqueros")
	g.advance_age(0)
	var cen := g.main_center(0)
	check(g.tech_block_reason(0, cen, "torre_guardia") == "", "en el nivel 2 el centro investiga la torre de guardia")
	g.research_tech(0, cen, "torre_guardia")
	g.run_seconds(41.0)
	check(g.players[0].techs.has("torre_guardia"), "la mejora se termina de investigar")
	check(tw.display_name() == Lang.t("Torre de guardia") and tw.garrison_space() == 3, "el puesto pasó a torre de guardia con lugar para 3 arqueros")
	var archers: Array = []
	for i in 4:
		archers.append(g.spawn_unit("arquero", 0, c + Vector2(6 + i * 0.6, 6)))
	g.command_units(archers, tw, tw.center(), false)
	g.run_seconds(12.0)
	check(tw.garrison.size() == 3, "entran 3 arqueros (%d)" % tw.garrison.size())
	check(archers[0].garrison_in == tw and not archers[0].visible, "el arquero de adentro no se ve")
	# Un enemigo cerca: la torre dispara más flechas.
	var en := g.spawn_unit("guerrero", 1, tw.center() + Vector2(4, 0))
	en.cmd_stop()
	g.run_seconds(6.0)
	check(en.dead or en.hp < en.max_hp * 0.4, "la torre con arqueros lo destroza (vida %d)" % en.hp)
	g.apply_cmd(0, {"k": "eject", "e": tw.id})
	check(tw.garrison.is_empty() and archers[0].garrison_in == null and archers[0].visible, "los arqueros salen de la torre")
	# Herrería
	var hr := g.spawn_building("herreria", 0, _open_spot(g, c, 3, 10), true)
	var war := g.spawn_unit("guerrero", 0, c + Vector2(8, 8))
	var dummy := g.spawn_unit("aldeano", 1, c + Vector2(9, 8))
	var d0 := war.attack_damage(dummy)
	check(g.research_tech(0, hr, "forja"), "la herrería investiga la forja")
	check(g.tech_block_reason(0, hr, "forja2") != "", "la segunda forja pide el nivel 3 y la primera")
	g.run_seconds(41.0)
	check(war.attack_damage(dummy) == d0 + 1.0, "la forja da +1 de ataque (%d -> %d)" % [d0, war.attack_damage(dummy)])
	g.queue_free()
	await get_tree().process_frame


func _naval_test() -> void:
	var g := await _new_game(4242, "costa")
	_rich(g, 0)
	var c := g.main_center(0).center()
	# El muelle más cercano posible en la orilla.
	var dock_t := Vector2i(-1, -1)
	var bd := INF
	for y in g.map.h:
		for x in g.map.w:
			var t := Vector2i(x, y)
			var d := MapData.center(t).distance_to(c)
			if d < bd and d < 70.0 and g.can_place(0, "muelle", t):
				bd = d
				dock_t = t
	check(dock_t.x >= 0, "hay orilla para un muelle (a %.0f casillas)" % bd)
	if dock_t.x < 0:
		g.queue_free()
		return
	check(not g.can_place(0, "muelle", g.main_center(0).rect.position + Vector2i(6, 6)) or g.map.ring_around(Rect2i(g.main_center(0).rect.position + Vector2i(6, 6), Vector2i(3, 3)), MapData.WATER_NAV).size() >= 3, "el muelle solo va en la orilla")
	var dock := g.spawn_building("muelle", 0, dock_t, true)
	g.spawn_building("casa", 0, _open_spot(g, c, 2, 6), true)
	check(g.train(0, dock, "barco_pesca"), "el muelle entrena un barco pesquero")
	g.run_seconds(21.0)
	var boat: Unit = null
	for u in g.units:
		if u.kind == "barco_pesca":
			boat = u
	if boat:
		print("     barco en ", boat.pos, " suelo ", g.map.ground[g.map.idx(MapData.to_tile(boat.pos))], " estado ", boat.status_text())
	check(boat != null and g.map.is_water(MapData.to_tile(boat.pos)), "el barco aparece en el agua")
	if boat == null:
		g.queue_free()
		return
	# Trampa en el agua cerca del muelle.
	var trap_t := Vector2i(-1, -1)
	for r in range(2, 14):
		for k in 24:
			var t := MapData.to_tile(dock.center() + Vector2.from_angle(TAU * k / 24.0) * r)
			if trap_t.x < 0 and g.can_place(0, "trampa", t):
				trap_t = t
	check(trap_t.x >= 0, "hay agua libre para una trampa")
	check(not g.can_place(0, "trampa", MapData.to_tile(c)), "la trampa no va en tierra")
	var food0: float = g.players[0].res["comida"]
	g.apply_cmd(0, {"k": "place", "b": "trampa", "tiles": [[trap_t.x, trap_t.y]], "u": [boat.id], "q": false})
	var trap: Building = g.map.entity_at(trap_t)
	check(trap != null and trap.kind == "trampa", "se puso la trampa")
	g.run_seconds(80.0)
	check(trap.complete, "el barco construyó la trampa")
	check(trap.food < 450.0, "el barco pesca en la trampa (queda %d)" % trap.food)
	check(g.players[0].res["comida"] > food0 + 5.0, "el pescado llega al muelle (+%d)" % (g.players[0].res["comida"] - food0))
	# Barco de guerra contra un aldeano enemigo en la orilla: no se pueden pegar cuerpo a cuerpo.
	var vill := g.spawn_unit("guerrero", 1, MapData.center(g.map.nearest_free(MapData.to_tile(dock.center()), 10)))
	check(not vill.can_hit(boat), "un guerrero no puede pegarle a un barco")
	g.queue_free()
	await get_tree().process_frame


func _siege_test() -> void:
	var g := await _new_game(779)
	g.advance_age(0)
	g.advance_age(0)
	g.advance_age(0)
	var bc := g.main_center(1)
	var house := g.spawn_building("casa", 1, _open_spot(g, bc.center(), 2, 7), true)
	var ram := g.spawn_unit("ariete", 0, house.center() + Vector2(4, 0))
	var enemy := g.spawn_unit("guerrero", 1, house.center() + Vector2(4, 1))
	enemy.cmd_stop()
	check(not ram.can_hit(enemy) and ram.can_hit(house), "el ariete solo ataca edificios")
	var hp0 := house.hp
	g.command_units([ram], house, house.center(), false)
	g.run_seconds(8.0)
	check(house.hp < hp0 - 40.0 or house.dead, "el ariete le pega fuerte a la casa (%d -> %d)" % [hp0, house.hp])
	var cat := g.spawn_unit("catapulta", 0, bc.center() + Vector2(-12, 0))
	var group: Array = []
	for i in 3:
		var e2 := g.spawn_unit("aldeano", 1, bc.center() + Vector2(-5, -0.6 + i * 0.6))
		e2.cmd_stop()
		group.append(e2)
	g.command_units([cat], group[1], group[1].pos, false)
	g.run_seconds(7.0)
	var hurt := 0
	for e2 in group:
		if e2.dead or e2.hp < e2.max_hp:
			hurt += 1
	check(hurt >= 2, "la piedra de la catapulta daña en área (%d heridos)" % hurt)
	g.queue_free()
	await get_tree().process_frame


func _wonder_test() -> void:
	var g := await _new_game(780)
	_rich(g, 0)
	for i in 4:
		g.advance_age(0)
	var c := g.main_center(0).center()
	var mon := g.spawn_building("monasterio", 0, _open_spot(g, c, 3, 8), true)
	var won := g.spawn_building("maravilla", 0, _open_spot(g, c, 6, 12), true)
	check(g.build_block_reason(0, "maravilla") != "", "solo una maravilla por jugador")
	check(g.relic_block_reason(0, mon) != "", "sin santo no se crea la reliquia")
	var santo := g.spawn_unit("santo", 0, mon.center() + Vector2(2.5, 0))
	check(g.make_relic(0, mon), "con un santo junto al monasterio se empieza la reliquia")
	g.run_seconds(Defs.RELIC_TIME + 1.0)
	check(g.relics.size() == 1, "apareció una reliquia en el mapa")
	var rl: Relic = g.relics[0]
	g.command_units([santo], rl, rl.pos, false)
	var stored := false
	for i in 40:
		g.run_seconds(10.0)
		if won.relics.size() == 1:
			stored = true
			break
	check(santo.relic == null and stored, "el santo la recogió y la llevó a la maravilla")
	# Matar al santo con una reliquia: cae al suelo.
	var rl2 := g.spawn_relic(0, mon)
	santo.relic = rl2
	rl2.carrier = santo
	santo.take_damage(9999.0, null)
	g.run_seconds(0.1)
	check(rl2.on_ground(), "si muere el santo, la reliquia cae al suelo")
	g.store_relic(won, rl2)
	g.store_relic(won, g.spawn_relic(0, mon))
	g.run_seconds(1.0)
	check(g.players[0].wonder_t > 0.0, "con 3 reliquias empieza la cuenta atrás (%.0f s)" % g.players[0].wonder_t)
	g.run_seconds(Defs.WONDER_TIME + 3.0)
	check(g.players[1].defeated and g.over, "al terminar la cuenta atrás, A gana")
	g.queue_free()
	await get_tree().process_frame


## Campana: los aldeanos se refugian en el centro y luego vuelven a lo que hacían.
func _bell_test() -> void:
	var g := await _new_game(781)
	var c := g.main_center(0)
	var vills: Array = []
	for u in g.units:
		if u.owner_id == 0 and u.is_villager():
			vills.append(u)
	var tree := g.find_resource_near("arbol", c.center(), 40.0, 0)
	for u in vills:
		u.cmd_gather(tree)
	g.run_seconds(8.0)
	g.apply_cmd(0, {"k": "bell"})
	check(g.players[0].bell, "la campana queda sonando")
	g.run_seconds(25.0)
	check(g.refugees(0) == vills.size(), "todos los aldeanos se refugiaron (%d / %d)" % [g.refugees(0), vills.size()])
	var hidden := true
	for u in vills:
		if u.garrison_in != c:
			hidden = false
	check(hidden, "están adentro del centro")
	g.apply_cmd(0, {"k": "bell"})
	g.run_seconds(0.5)
	check(g.refugees(0) == 0 and not g.players[0].bell, "al tocarla otra vez salen")
	var back := 0
	for u in vills:
		if u.state == Unit.S.GATHER or u.state == Unit.S.RETURN:
			back += 1
	check(back == vills.size(), "vuelven a cortar madera (%d / %d)" % [back, vills.size()])
	g.queue_free()
	await get_tree().process_frame


## Dos bots difíciles hasta 35 minutos: suben de era, construyen lo nuevo e investigan mejoras.
func _bots_long_test() -> void:
	Setup.players = [
		{"name": "X", "civ": "zapoteca", "team": 1, "color": 0, "bot": true, "difficulty": "dificil"},
		{"name": "Y", "civ": "tolteca", "team": 2, "color": 1, "bot": true, "difficulty": "dificil"},
	]
	Setup.local_player = 0
	Setup.map_size = "mediano"
	Setup.map_type = "valle"
	Setup.seed_value = 2026
	var g: Game = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	g.paused = true
	await get_tree().process_frame
	while not g._started:
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var mins := 0
	for m in 35:
		g.run_seconds(60.0)
		mins = m + 1
		if g.over:
			break
	var best_age := 0
	var techs := 0
	var kinds := {}
	for p in g.players:
		best_age = maxi(best_age, p.age)
		techs += p.techs.size()
	for b in g.buildings:
		kinds[b.kind] = true
	print("     %d min, era máx %d, mejoras %d, edificios: %s (%d ms)" % [mins, best_age, techs, ", ".join(kinds.keys()), Time.get_ticks_msec() - t0])
	check(best_age >= 3 or g.over, "los bots llegan al nivel 3 (%d)" % best_age)
	check(techs >= 1, "los bots investigan mejoras (%d)" % techs)
	check(kinds.has("herreria") or g.over, "los bots construyen la herrería")
	g.queue_free()
	await get_tree().process_frame
