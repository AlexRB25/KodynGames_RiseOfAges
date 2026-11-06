class_name Game
extends Node3D
## Partida: crea el mapa, los jugadores y las entidades, avanza la simulación en
## pasos fijos y ofrece las consultas y órdenes que usan el jugador y los bots.

signal game_over(winner_team: int)

var map := MapData.new()
var map_type := ""   # tipo de mapa que tocó (Defs.MAP_TYPES)
var fog := Fog.new()
var players: Array[PlayerState] = []
var units: Array[Unit] = []
var buildings: Array[Building] = []
var animals: Array[Animal] = []
var resources: Array[ResourceNode] = []
var relics: Array[Relic] = []
var projectiles: Array = []
var sim_rng := RandomNumberGenerator.new()   # azar de la simulación (igual en todos los equipos en línea)
var bots: Array = []
var local_id := 0
var time := 0.0
var time_scale := 1.0
var paused := false
var over := false
var headless := false

var camera: RtsCamera
var controller: Controller
var hud: Hud

var _acc := 0.0
var _next_id := 1
var _fog_t := 0.0
var _vic_t := 0.0
var _notify_seen := {}
var _attack_note_t := -100.0
var _world: Node3D

# Órdenes: todo lo que hace un jugador pasa por issue() -> apply_cmd() en un paso fijo.
# En línea (lockstep): el servidor junta las órdenes de todos por turno y las reparte.
const TURN_TICKS := 2                # 1 turno de red = 2 pasos de 50 ms
var ents := {}                       # id -> Entity
var online := false
var tick := 0
var turn_cmds := {}                  # turno -> Array de [jugador, orden]
var last_turn := -1
var _local_cmds: Array = []
var stop_at_tick := -1                # pruebas: no pasar de este paso


signal loading(p: float, text: String)   # avance para la pantalla de carga
signal loaded


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	Sfx.game = self
	Sfx.music("partida")
	start_match()


## Avisa el avance a la pantalla de carga y la deja dibujarse (solo si hay pantalla de carga).
func _phase(p: float, text: String) -> void:
	if not Setup.loading:
		return
	loading.emit(p, text)
	await get_tree().process_frame
	await get_tree().process_frame


func start_match() -> void:
	var cfg: Array = Setup.players
	local_id = Setup.local_player
	online = Setup.online
	var size: int = Defs.MAP_SIZES.get(Setup.map_size, 160)
	var seed_v: int = Setup.seed_value if Setup.seed_value != 0 else randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_v = int(arg.get_slice("=", 1))
		elif arg.begins_with("--tipo="):
			Setup.map_type = arg.get_slice("=", 1)
		elif arg == "--tutorial":
			Setup.tutorial = true
			Setup.map_size = "pequeno"
			Setup.map_type = "valle"
			seed_v = 4242
		elif arg.begins_with("--civ=") and not Setup.players.is_empty():
			Setup.players[Setup.local_player]["civ"] = arg.get_slice("=", 1)
	await _phase(0.05, Lang.t("Creando el mapa…"))
	map.setup(size)
	var teams: Array = []
	for i in cfg.size():
		var c: Dictionary = cfg[i]
		var p := PlayerState.new()
		p.id = i
		p.name = c.get("name", Lang.t("Jugador %d") % (i + 1))
		p.civ = c.get("civ", "mexica")
		if not Defs.CIVS.has(p.civ):
			p.civ = Defs.CIV_ORDER[0]
		p.team = c.get("team", i + 1)
		p.color_idx = c.get("color", i)
		p.color = Defs.PLAYER_COLORS[p.color_idx % Defs.PLAYER_COLORS.size()]
		p.is_bot = c.get("bot", false)
		p.difficulty = c.get("difficulty", "normal")
		p.res = Defs.START_RES.duplicate()
		p.give(Defs.civ_mod(p.civ, "start", {}))
		for r in p.res:
			p.res[r] = float(p.res[r])
		players.append(p)
		teams.append(p.team)
	var plan := MapGen.new().generate(map, cfg.size(), teams, seed_v, Setup.map_type)
	map_type = String(plan.get("type", ""))
	await _phase(0.45, Lang.t("Dibujando el terreno…"))
	fog.setup(map)
	Mat.setup(fog.texture, Vector2(size, size))

	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_setup_env()
	var tv := TerrainView.new()
	tv.build(map, fog.texture)
	_world.add_child(tv)
	await _phase(0.7, Lang.t("Poniendo árboles y animales…"))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	sim_rng.seed = seed_v * 31 + 7
	for n in plan["nodes"]:
		spawn_resource(n["kind"], n["tile"], rng.randi())
	for a in plan["animals"]:
		spawn_animal(a["kind"], a["pos"], rng.randi())
	for i in players.size():
		var st: Vector2i = plan["starts"][i]
		players[i].start_tile = st
		var c := spawn_building("centro", i, st, true)
		for k in Defs.START_VILLAGERS:
			var t := map.nearest_free(st + Vector2i(4 + k % 2, k - 1))
			spawn_unit("aldeano", i, MapData.center(t))
		recount_pop(i)
	for p in players:
		if p.is_bot:
			bots.append(Bot.new(self, p.id))
	await _phase(0.92, Lang.t("Preparando tu pueblo…"))

	if not headless:
		camera = RtsCamera.new()
		add_child(camera)
		camera.setup(self)
		var c0 := players[local_id].start_tile
		camera.focus(Vector2(c0) + Vector2(2, 2))
		hud = Hud.new()
		add_child(hud)
		controller = Controller.new()
		add_child(controller)
		controller.setup(self)
		hud.setup(self)
		if Setup.tutorial:
			var tut := Tutorial.new()
			add_child(tut)
			tut.setup(self)
		elif Defs.MAP_TYPES.has(map_type):
			hud.notify(Lang.t("Mapa: %s. %s") % [Lang.t(Defs.MAP_TYPES[map_type]["name"]), Lang.t(Defs.MAP_TYPES[map_type]["desc"])], Vector2.INF)
	_update_fog()
	if online:
		Net.attach(self)
	_started = true
	loaded.emit()
	_dev_args()


## Opciones de desarrollo: --reveal (ver todo), --fast=N (simular N s al inicio), --shot=archivo.png
func _dev_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--reveal":
			fog.reveal_all = true
			_update_fog()
		elif a.begins_with("--fast="):
			run_seconds(float(a.get_slice("=", 1)))
			_update_fog()
		elif a.begins_with("--look=") and camera:
			var c := main_center(int(a.get_slice("=", 1)))
			if c:
				camera.focus(c.center())
				camera.dist = 20.0
				camera.target_dist = 20.0
		elif a == "--sinhud" and hud:
			hud.visible = false   # desarrollo: capturas limpias para la página
		elif a.begins_with("--at=") and camera:
			# --at=x,y,distancia  (desarrollo: mirar un punto del mapa)
			var v := a.get_slice("=", 1).split(",")
			camera.focus(Vector2(float(v[0]), float(v[1])))
			if v.size() > 2:
				camera.dist = float(v[2])
				camera.target_dist = float(v[2])
		elif a.begins_with("--edificio="):
			# Desarrollo: --edificio=monasterio:1  pone ese edificio terminado junto al centro del jugador 1.
			var parts := a.get_slice("=", 1).split(":")
			var who := int(parts[1]) if parts.size() > 1 else local_id
			var ec := main_center(who).center()
			var eb: Building = null
			var far := 70 if Defs.BUILDINGS[parts[0]].get("dock", false) or Defs.BUILDINGS[parts[0]].get("water", false) else 18
			for r in range(7, far):
				for k in 32:
					var t := MapData.to_tile(ec + Vector2.from_angle(TAU * k / 32.0) * r)
					if eb == null and can_place(who, parts[0], t):
						eb = spawn_building(parts[0], who, t, true)
			if eb:
				print("edificio en ", eb.rect)
				camera.focus(eb.center())
				camera.dist = maxf(16.0, eb.def["size"] * 4.0)
				camera.target_dist = camera.dist
				controller.set_selection([eb])
		elif a == "--corral":
			# Desarrollo: un corral junto a tu centro con las cabras cercanas pastando.
			var cc := main_center(local_id).center()
			var co: Building = null
			for r in range(7, 16):
				for k in 16:
					var t := MapData.to_tile(cc + Vector2.from_angle(TAU * k / 16.0) * r)
					if co == null and can_place(local_id, "corral", t):
						co = spawn_building("corral", local_id, t, true)
			if co:
				for an in animals:
					if an.tame and an.pos.distance_to(cc) < 14.0:
						an.set_herd_owner(local_id)
						an.cmd_move(co.center())
				camera.focus(co.center())
				camera.dist = 14.0
				camera.target_dist = 14.0
				controller.set_selection([co])
		elif a == "--desfile":
			# Desarrollo: aldeanos y guerreros de las 5 eras en fila junto a tu centro.
			var dc := main_center(local_id).center() + Vector2(5, -3)
			var real_age := players[local_id].age
			for era in range(1, 6):
				players[local_id].age = era
				spawn_unit("aldeano", local_id, dc + Vector2(era * 1.1, 0))
				spawn_unit("guerrero", local_id, dc + Vector2(era * 1.1, -1.4))
			players[local_id].age = real_age
			camera.focus(dc + Vector2(3.3, -0.7))
			camera.dist = 7.0
			camera.target_dist = 7.0
		elif a.begins_with("--paso=") and hud:
			for ch in get_children():
				if ch is Tutorial:
					ch._go(int(a.get_slice("=", 1)) - 1)
		elif a.begins_with("--tab=") and hud:
			hud.set_tab(a.get_slice("=", 1))
		elif a.begins_with("--arrastre") and controller:
			# Desarrollo: simula dejar el dedo en un aldeano y arrastrarlo hasta un árbol.
			await get_tree().process_frame
			var vill: Unit = null
			for u in units:
				if u.owner_id == local_id and u.is_villager():
					vill = u
					break
			var tree := find_resource_near("arbol", vill.pos, 30.0, local_id)
			camera.focus(vill.pos.lerp(tree.center(), 0.5))
			camera.dist = 22.0
			camera.target_dist = 22.0
			for k in 20:
				await get_tree().process_frame
			var p0 := controller._screen_of(vill.pos, 0.6)
			var p1 := controller._screen_of(tree.center(), 0.3)
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			down.position = p0
			controller._unhandled_input(down)
			var mv := InputEventMouseMotion.new()
			mv.position = p1
			controller._unhandled_input(mv)
			if a == "--arrastre=soltar":
				var up := InputEventMouseButton.new()
				up.button_index = MOUSE_BUTTON_LEFT
				up.pressed = false
				up.position = p1
				controller._unhandled_input(up)
				await get_tree().create_timer(1.0).timeout
				print("arrastre: aldeano ", vill.status_text(), " objetivo=", (vill.target.kind if vill.target else "nada"))
		elif a.begins_with("--mantener=") and hud:
			# Desarrollo: simula dejar el dedo sobre un botón.
			var want2 := a.get_slice("=", 1)
			for spec in hud._btn_specs:
				if spec[0].text == want2:
					spec[0].button_down.emit()
		elif a.begins_with("--ver=") and hud:
			# Desarrollo: abrir la información de un botón como si se tocara en el celular.
			var want := a.get_slice("=", 1)
			for spec in hud._btn_specs:
				if spec[0].text == want:
					spec[0].pressed.emit()
		elif a.begins_with("--sel=") and controller:
			var sc := main_center(int(a.get_slice("=", 1)))
			if sc:
				controller.set_selection([sc])
		elif a == "--mapa" and hud:
			# Desarrollo: abrir el mapa grande y tocarlo (debe seguir abierto).
			hud.full_map.visible = true
			await get_tree().process_frame
			var vp := get_viewport().get_visible_rect().size
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = vp * Vector2(0.6, 0.6)
				ev.global_position = ev.position
				Input.parse_input_event(ev)
		elif a == "--pedir-rendirse" and hud:
			# Desarrollo: tocar "Rendirse" en el menú (debe preguntar).
			hud.toggle_menu()
			for b in hud.menu_panel.find_children("*", "Button", true, false):
				if b.text == Lang.t("Rendirse"):
					b.pressed.emit()
		elif a.begins_with("--techs="):
			# Desarrollo: --techs=torre_guardia,muro_piedra  da esas mejoras al jugador local.
			for t in a.get_slice("=", 1).split(","):
				if Defs.TECHS.has(t):
					finish_tech(local_id, t)
		elif a.begins_with("--era="):
			# Desarrollo: --era=5  sube al jugador local a esa era.
			while players[local_id].age < int(a.get_slice("=", 1)):
				advance_age(local_id)
		elif a.begins_with("--unidad="):
			# Desarrollo: --unidad=catapulta  pone una junto al centro (barcos: en el agua más cercana).
			var uk := a.get_slice("=", 1)
			var uc := main_center(local_id).center() + Vector2(5, 3)
			var nv := MapData.WATER_NAV if Defs.UNITS[uk].get("naval", false) else 0
			var ut := map.nearest_free(MapData.to_tile(uc), 60, nv)
			var nu := spawn_unit(uk, local_id, MapData.center(ut))
			recount_pop(local_id)
			camera.focus(nu.pos)
			camera.dist = 12.0
			camera.target_dist = 12.0
			controller.set_selection([nu])
		elif a == "--obra":
			# Desarrollo: una casa en construcción con un aldeano y 3 aldeanos en cola en el centro.
			var oc := main_center(local_id)
			players[local_id].res["comida"] += 300
			players[local_id].res["madera"] += 100
			for r in range(6, 14):
				var ot := MapData.to_tile(oc.center() + Vector2(r, 0))
				if can_place(local_id, "casa", ot):
					var ob := place_building(local_id, "casa", ot)
					var ov := nearest_villager(local_id, ob.center())
					ov.cmd_build(ob)
					ob.add_progress(8.0)
					camera.focus(ob.center())
					camera.dist = 14.0
					camera.target_dist = 14.0
					break
			for i in 3:
				train(local_id, oc, "aldeano")
		elif a == "--palanca" and hud and hud.joystick:
			# Desarrollo: empujar la palanca a la derecha 1 segundo (celular).
			var c0 := camera.ground_pos()
			hud.joystick.vec = Vector2(1, 0)
			await get_tree().create_timer(1.0).timeout
			hud.joystick.vec = Vector2.ZERO
			print("palanca: la cámara se movió %.1f casillas" % camera.ground_pos().distance_to(c0))
		elif a == "--reliquia":
			# Desarrollo: una reliquia junto a tu centro.
			var rl := Relic.new()
			rl.init(self, MapData.center(map.nearest_free(MapData.to_tile(main_center(local_id).center() + Vector2(5, -2)))))
			relics.append(rl)
			_register(rl)
			camera.focus(rl.pos)
			camera.dist = 9.0
			camera.target_dist = 9.0
			controller.set_selection([rl])
		elif a == "--campana":
			# Desarrollo: tocar la campana y ver a los aldeanos refugiados en el centro.
			var cc := main_center(local_id)
			apply_cmd(local_id, {"k": "bell"})
			run_seconds(15.0)
			camera.focus(cc.center())
			camera.dist = 16.0
			camera.target_dist = 16.0
			controller.set_selection([cc])
		elif a == "--rendirse":
			# Ver la pantalla final (y el premio de la partida).
			_defeat(local_id, true)
			_check_victory()
		elif a.begins_with("--shot="):
			var path := a.get_slice("=", 1)
			await get_tree().create_timer(2.5).timeout
			get_viewport().get_texture().get_image().save_png(path)
			print("captura: ", path)
			get_tree().quit()


func _setup_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	_world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.80, 0.70)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)


# ---------------- crear entidades ----------------

func _register(e: Entity) -> void:
	e.id = _next_id
	ents[e.id] = e
	_next_id += 1
	_world.add_child(e)


func spawn_resource(k: String, tile: Vector2i, seed_v: int) -> ResourceNode:
	var r := ResourceNode.new()
	r.init(self, k, tile, seed_v)
	map.occupy(r.rect, r, true)
	resources.append(r)
	_register(r)
	return r


func spawn_animal(k: String, p: Vector2, seed_v: int) -> Animal:
	var a := Animal.new()
	a.init(self, k, p, seed_v)
	animals.append(a)
	_register(a)
	return a


func spawn_unit(k: String, owner: int, p: Vector2) -> Unit:
	var u := Unit.new()
	u.init(self, k, owner, p)
	units.append(u)
	_register(u)
	return u


func spawn_building(k: String, owner: int, tile: Vector2i, done: bool) -> Building:
	var b := Building.new()
	b.init(self, k, owner, tile, done)
	map.occupy(b.rect, b, b.blocks())
	if b.def.get("gate", false):
		map.set_gate(tile, team_of(owner))
	if b.blocks():
		_push_units_out(b.rect)
	buildings.append(b)
	_register(b)
	if done:
		recount_pop(owner)
	return b


func _push_units_out(r: Rect2i) -> void:
	for u in units:
		if not u.dead and r.has_point(MapData.to_tile(u.pos)):
			var t := map.nearest_free(MapData.to_tile(u.pos))
			u.pos = MapData.center(t)
			u.prev_pos = u.pos
			u.path.clear()
			u._goal_for = null
	for a in animals:
		if not a.dead and r.has_point(MapData.to_tile(a.pos)):
			a.pos = MapData.center(map.nearest_free(MapData.to_tile(a.pos)))
			a.prev_pos = a.pos
			a.moving = false


## Un árbol talado deja de bloquear el paso, pero sigue siendo recurso.
func release_static(e: Entity, clear_owner: bool) -> void:
	for y in range(e.rect.position.y, e.rect.end.y):
		for x in range(e.rect.position.x, e.rect.end.x):
			var t := Vector2i(x, y)
			var i := map.idx(t)
			if map.solid[i] > 0:
				map.solid[i] -= 1
				map.refresh_tile(t)
			if clear_owner and map.ent[i] == e:
				map.ent[i] = null


func remove_entity(e: Entity) -> void:
	if e.removed:
		return
	e.removed = true
	if e is ResourceNode:
		var blocks: bool = not e.felled
		map.release(e.rect, e, blocks)
		resources.erase(e)
	elif e is Animal:
		animals.erase(e)
	if controller:
		controller.forget(e)
	e.queue_free()


func destroy_building(b: Building, by_attack: bool) -> void:
	if b.dead:
		return
	b.dead = true
	b.removed = true
	map.release(b.rect, b, b.blocks())
	if b.def.get("gate", false):
		map.set_gate(b.rect.position, 0)
	buildings.erase(b)
	if by_attack:
		Sfx.at("derribo", b.center())
	# Los arqueros de adentro salen; las reliquias de la maravilla caen alrededor.
	for u in b.garrison.duplicate():
		u._leave_garrison()
	b.garrison.clear()
	for i in b.relics.size():
		var rl: Relic = b.relics[i]
		rl.drop_at(b.center() + Vector2.from_angle(TAU * i / maxf(1, b.relics.size())) * (b.def["size"] * 0.5 + 1.5))
	b.relics.clear()
	if b.def.get("wonder", false):
		players[b.owner_id].wonder_t = -1.0
	if b.worker:
		b.worker = null
	if controller:
		controller.forget(b)
	recount_pop(b.owner_id)
	if by_attack:
		notify(b.owner_id, Lang.t("Perdiste: %s.") % b.display_name(), b.pos)
		if b.kind == "centro" and not players[b.owner_id].defeated:
			var nc := main_center(b.owner_id)
			if nc:
				notify(b.owner_id, Lang.t("Destruyeron tu centro. El otro centro es ahora el principal."), nc.pos)
			else:
				notify(b.owner_id, Lang.t("¡Destruyeron tu último centro!"), b.pos)
	var tw := b.create_tween()
	tw.tween_property(b, "position:y", -3.0, 1.5)
	tw.tween_callback(b.queue_free)
	_vic_t = 0.0


func on_unit_died(u: Unit) -> void:
	units.erase(u)
	players[u.owner_id].stats["muertes"] += 1
	recount_pop(u.owner_id)
	if controller:
		controller.forget(u)
	_vic_t = 0.0


func on_animal_killed(_a: Animal) -> void:
	pass


func on_building_complete(b: Building) -> void:
	recount_pop(b.owner_id)
	players[b.owner_id].stats["edificios"] += 1
	if b.def.get("wonder", false):
		for q in players:
			if q.id != b.owner_id:
				notify(q.id, Lang.t("%s terminó una maravilla. Si lleva 3 reliquias, empezará la cuenta atrás.") % players[b.owner_id].name, b.pos)
	if not b.kind in ["muralla", "puerta", "granja"]:
		notify(b.owner_id, Lang.t("%s terminado.") % b.display_name(), b.pos)
	if b.owner_id == local_id:
		Sfx.play("terminado")
	if hud:
		hud.refresh_selection()


func on_attacked(e: Entity, from: Entity) -> void:
	if from == null:
		return
	if e.owner_id == local_id and time - _attack_note_t > 12.0:
		_attack_note_t = time
		notify(local_id, Lang.t("¡Te están atacando!"), e.pos)
		Sfx.play("alerta", -2.0)
	for b in bots:
		if b.pid == e.owner_id:
			b.on_attacked(e, from)


# ---------------- simulación ----------------

var _started := false   # ya terminó de crear la partida


func _process(delta: float) -> void:
	if not _started:
		return
	if online:
		_process_online(delta)
	elif not paused and not over:
		_acc += delta * time_scale
		var steps := 0
		while _acc >= Defs.TICK and steps < 8:
			_acc -= Defs.TICK
			for c in _local_cmds:
				apply_cmd(c[0], c[1])
			_local_cmds.clear()
			step()
			steps += 1
		if steps >= 8:
			_acc = 0.0
	var alpha := clampf(_acc / Defs.TICK, 0.0, 1.0)
	for u in units:
		u.render(alpha, delta)
	for a in animals:
		a.render(alpha, delta)
	for r in relics:
		r.render(delta)
	for b in buildings:
		b.tick_bar(delta)
	_render_projectiles(delta)


## En línea: solo avanza hasta el último turno recibido del servidor.
func _process_online(delta: float) -> void:
	if over:
		return
	var allowed := (last_turn + 1) * TURN_TICKS
	if stop_at_tick >= 0:
		allowed = mini(allowed, stop_at_tick)
	var behind := allowed - tick
	_acc += delta * (2.0 if behind > 8 else 1.0)
	var steps := 0
	while _acc >= Defs.TICK and tick < allowed and steps < 12:
		_acc -= Defs.TICK
		if tick % TURN_TICKS == 0:
			var n := tick / TURN_TICKS
			for c in turn_cmds.get(n, []):
				apply_cmd(int(c[0]), c[1])
			turn_cmds.erase(n)
			if n % 50 == 0 and n > 0:
				Net.send_hash(n, state_hash())
		step()
		steps += 1
	if tick >= allowed:
		_acc = minf(_acc, Defs.TICK)


func receive_turn(n: int, cmds: Array) -> void:
	turn_cmds[n] = cmds
	last_turn = maxi(last_turn, n)


## Suma de control del estado (para detectar desincronización en línea).
func state_hash() -> int:
	var h := 17
	for u in units:
		h = (h * 31 + u.id * 7 + int(u.pos.x * 100.0) * 13 + int(u.pos.y * 100.0) + int(u.hp)) % 1000000007
	for p in players:
		for r in Defs.RES:
			h = (h * 31 + int(p.res[r])) % 1000000007
	h = (h * 31 + buildings.size()) % 1000000007
	return h


func step() -> void:
	var dt := Defs.TICK
	tick += 1
	time += dt
	for u in units.duplicate():
		u.sim(dt)
	for a in animals.duplicate():
		a.sim(dt)
	for b in buildings.duplicate():
		b.sim(dt)
	for r in relics:
		r.sim(dt)
	_sim_wonders(dt)
	_sim_projectiles(dt)
	for bot in bots:
		bot.tick(dt)
	_fog_t -= dt
	if _fog_t <= 0.0:
		_fog_t = 0.25
		_update_fog()
	_vic_t -= dt
	if _vic_t <= 0.0:
		_vic_t = 2.0
		_check_victory()


## Corre la simulación sin dibujar (pruebas).
func run_seconds(s: float) -> void:
	var n := int(s / Defs.TICK)
	for i in n:
		step()
		if over:
			return


func _update_fog() -> void:
	var lt := team_of(local_id)
	var src: Array = []
	for u in units:
		if team_of(u.owner_id) == lt:
			src.append([u.pos, u.sight])
	for b in buildings:
		if team_of(b.owner_id) == lt:
			src.append([b.center(), b.sight + b.def["size"] / 2])
	for a in animals:
		if not a.dead and a.owner_id >= 0 and team_of(a.owner_id) == lt:
			src.append([a.pos, 3.0])
	fog.update(src)
	for u in units:
		if u.garrison_in:
			u.visible = false
		elif team_of(u.owner_id) != lt:
			u.visible = fog.is_visible(u.pos)
	for a in animals:
		a.visible = fog.is_visible(a.pos) or (a.dead and fog.is_explored_rect(Rect2i(MapData.to_tile(a.pos), Vector2i.ONE))) \
			or (not a.dead and a.owner_id >= 0 and team_of(a.owner_id) == lt)
	for b in buildings:
		if team_of(b.owner_id) != lt:
			if fog.is_visible_rect(b.rect):
				b.seen_once = true
			b.visible = b.seen_once
	for r in resources:
		r.visible = fog.is_explored_rect(r.rect)
	for rl in relics:
		if rl.on_ground():
			rl.visible = fog.is_visible(rl.pos) or fog.is_explored_rect(Rect2i(MapData.to_tile(rl.pos), Vector2i.ONE))


## Regla: pierde quien se queda sin ningún Centro terminado. El centro más
## antiguo que siga en pie es el "principal". También gana quien mantiene su
## maravilla con 3 reliquias hasta que termina la cuenta atrás.
func _check_victory() -> void:
	if over:
		return
	for p in players:
		if p.defeated:
			continue
		if main_center(p.id) == null:
			_defeat(p.id)
	for p in players:
		if not p.defeated and p.wonder_t == 0.0:
			for q in players:
				if not q.defeated and q.team != p.team:
					q.defeated = true
					notify(local_id, Lang.t("La maravilla de %s cumplió su cuenta atrás.") % p.name, Vector2.INF)
	var teams_alive := {}
	for p in players:
		if not p.defeated:
			teams_alive[p.team] = true
	if teams_alive.size() <= 1:
		over = true
		var winner: int = teams_alive.keys()[0] if teams_alive.size() == 1 else -1
		game_over.emit(winner)
		Sfx.music("")
		Sfx.play("victoria" if winner == team_of(local_id) else "derrota")
		if hud:
			hud.show_result(winner == team_of(local_id))


## En línea con rango: el servidor da la partida por terminada (el rival abandonó).
func end_by_forfeit(winner_team: int, forfeit: bool) -> void:
	if over or not forfeit:
		return
	over = true
	Sfx.music("")
	Sfx.play("victoria" if winner_team == team_of(local_id) else "derrota")
	if hud:
		hud.show_result(winner_team == team_of(local_id))


## Campana del centro: los aldeanos corren a refugiarse al centro más cercano con
## lugar; al tocarla otra vez salen y vuelven a lo que hacían.
func ring_bell(pid: int) -> void:
	var p: PlayerState = players[pid]
	p.bell = not p.bell
	if pid == local_id:
		Sfx.play("campana")
	if p.bell:
		var room := {}
		for b in buildings:
			if b.owner_id == pid and b.kind == "centro" and b.complete and not b.dead:
				room[b] = b.garrison_space()
		if room.is_empty():
			p.bell = false
			return
		var left := 0
		for u in units:
			if u.owner_id != pid or u.dead or not u.is_villager() or u.garrison_in != null:
				continue
			var best: Building = null
			var bd := INF
			for b in room:
				if room[b] > 0:
					var d: float = b.center().distance_squared_to(u.pos)
					if d < bd:
						bd = d
						best = b
			if best == null:
				left += 1
				continue
			room[best] -= 1
			var prev := u.task_snapshot()
			u.cmd_garrison(best)
			u.bell_prev = prev
		notify(pid, Lang.t("¡Campana! Los aldeanos corren a refugiarse al centro urbano."), main_center(pid).pos if main_center(pid) else Vector2.ZERO)
		if left > 0:
			notify(pid, Lang.t("No caben todos: %d aldeanos siguen afuera. Construye otro centro urbano.") % left, main_center(pid).pos if main_center(pid) else Vector2.ZERO)
	else:
		for b in buildings:
			if b.owner_id == pid and b.kind == "centro":
				for u in b.garrison.duplicate():
					if u.is_villager():
						u._leave_garrison()
		for u in units:
			if u.owner_id != pid or u.dead or u.bell_prev.is_empty():
				continue
			var prev: Dictionary = u.bell_prev
			u.bell_prev = {}
			if u.garrison_in == null and (u.state == Unit.S.GARRISON or u.state == Unit.S.IDLE):
				u.cmd_stop()
				u.restore_task(prev)
		notify(pid, Lang.t("Los aldeanos vuelven a sus labores."), main_center(pid).pos if main_center(pid) else Vector2.ZERO)


## Aldeanos refugiados en los centros.
func refugees(pid: int) -> int:
	var n := 0
	for b in buildings:
		if b.owner_id == pid and b.kind == "centro":
			for u in b.garrison:
				if u.is_villager():
					n += 1
	return n


func main_center(pid: int) -> Building:
	for b in buildings:
		if b.owner_id == pid and b.kind == "centro" and b.complete and not b.dead:
			return b
	return null


func _defeat(pid: int, resigned := false) -> void:
	var p := players[pid]
	p.defeated = true
	if resigned:
		notify(local_id, Lang.t("%s se rindió.") % p.name if pid != local_id else Lang.t("Te rendiste."), Vector2.INF)
	else:
		notify(local_id, Lang.t("%s se quedó sin centros y fue derrotado.") % p.name if pid != local_id else Lang.t("Te quedaste sin centros."), Vector2.INF)
	for u in units.duplicate():
		if u.owner_id == pid:
			u.take_damage(99999.0, null)
	for b in buildings.duplicate():
		if b.owner_id == pid:
			destroy_building(b, false)


# ---------------- proyectiles ----------------

func spawn_projectile(src: Entity, target: Entity, dmg: float, splash := 0.0) -> void:
	var from := src.center()
	var h := 1.0 if src is Unit else 2.0
	Sfx.at("piedra" if splash > 0.0 else "flecha", from, -4.0)
	var pr := {"p": from, "h": h, "target": target, "dmg": dmg, "src": src, "t": 0.0, "node": null,
		"start": from, "dur": maxf(0.15, from.distance_to(target.center()) / (14.0 if splash <= 0.0 else 9.0)),
		"splash": splash, "owner": src.owner_id, "end": target.center()}
	if not headless and (fog.is_visible(from) or fog.is_visible(target.center())):
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.5, 0.04, 0.04) if splash <= 0.0 else Vector3(0.22, 0.22, 0.22)
		mi.mesh = m
		mi.material_override = Mat.flat(Color(0.25, 0.18, 0.1) if splash <= 0.0 else Color(0.2, 0.2, 0.22))
		_world.add_child(mi)
		pr["node"] = mi
	projectiles.append(pr)


func _sim_projectiles(dt: float) -> void:
	for pr in projectiles.duplicate():
		pr["t"] += dt
		if pr["t"] >= pr["dur"]:
			var t: Entity = pr["target"]
			var src: Entity = pr["src"] if is_instance_valid(pr["src"]) else null
			if Entity.live(t):
				pr["end"] = t.center()
				t.take_damage(pr["dmg"], src)
			# Bomba o piedra: también lastima a los enemigos de alrededor.
			if pr["splash"] > 0.0:
				for u in units_near(pr["end"], pr["splash"]):
					if u != t and is_enemy(pr["owner"], u.owner_id) and u.garrison_in == null:
						u.take_damage(pr["dmg"] * 0.5, src)
			if pr["node"]:
				pr["node"].queue_free()
			projectiles.erase(pr)


func _render_projectiles(_dt: float) -> void:
	for pr in projectiles:
		var n: MeshInstance3D = pr["node"]
		if n == null:
			continue
		var t: Entity = pr["target"]
		var end: Vector2 = t.center() if is_instance_valid(t) else pr["start"]
		var f := clampf(pr["t"] / pr["dur"], 0.0, 1.0)
		var p: Vector2 = pr["start"].lerp(end, f)
		var y: float = lerpf(pr["h"], 0.7, f) + sin(f * PI) * 1.2 + map.height_at(p)
		n.position = Vector3(p.x, y, p.y)
		var d: Vector2 = end - pr["start"]
		n.rotation.y = -atan2(d.y, d.x)


# ---------------- consultas ----------------

func team_of(pid: int) -> int:
	if pid < 0 or pid >= players.size():
		return -1
	return players[pid].team


func is_enemy(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and team_of(a) != team_of(b)


func units_near(p: Vector2, r: float) -> Array[Unit]:
	var out: Array[Unit] = []
	var r2 := r * r
	for u in units:
		if not u.dead and u.pos.distance_squared_to(p) <= r2:
			out.append(u)
	return out


## Enemigo más cercano a una entidad (prefiere unidades; luego edificios).
## Una unidad solo busca lo que puede atacar (los arietes, solo edificios).
func find_enemy_near(e: Entity, r: float) -> Entity:
	var best: Entity = null
	var best_d := INF
	var c := e.center()
	var me: Unit = e as Unit
	for u in units:
		if u.dead or u.garrison_in or not is_enemy(e.owner_id, u.owner_id):
			continue
		if me and not me.can_hit(u):
			continue
		var d := e.dist_to(u.pos) if e is Building else u.pos.distance_to(c)
		if d <= r and d < best_d:
			best_d = d
			best = u
	if best or e is Building:
		return best
	var siege := me != null and me.is_siege()
	for b in buildings:
		if b.dead or not is_enemy(e.owner_id, b.owner_id) or (b.def.get("wall", false) and not siege) or b.def.get("hidden", false):
			continue
		var d := b.dist_to(c)
		if d <= r and d < best_d:
			best_d = d
			best = b
	return best


## Recurso del mismo grupo más cercano a un punto (para seguir trabajando).
func find_resource_near(group: String, p: Vector2, r: float, owner: int, exclude: Entity = null, asker: Unit = null) -> Entity:
	var best: Entity = null
	var best_d := INF
	match group:
		"caza":
			# Primero animales ya cazados con comida; luego vivos.
			for a in animals:
				if a == exclude or a.removed:
					continue
				# No cazar solo: animales vivos de otro pueblo ni los tuyos que pastan.
				if not a.dead and ((a.owner_id >= 0 and (a.owner_id != owner or a.grazing())) or a.being_herded()):
					continue
				var d := a.pos.distance_to(p)
				if a.dead:
					d -= 100.0
				if d <= r or (a.dead and d + 100.0 <= r):
					if d < best_d:
						best_d = d
						best = a
		"granja", "trampa":
			for b in buildings:
				if b.kind != group or b.owner_id != owner or b == exclude or not b.has_resource():
					continue
				if b.worker != null and b.worker != asker and Entity.live(b.worker):
					continue
				var d := b.dist_to(p)
				if d <= r and d < best_d:
					best_d = d
					best = b
		"":
			return null
		_:
			var t0 := MapData.to_tile(p)
			var ri := ceili(r)
			for y in range(t0.y - ri, t0.y + ri + 1):
				for x in range(t0.x - ri, t0.x + ri + 1):
					var e = map.entity_at(Vector2i(x, y))
					if e == null or e == exclude or not (e is ResourceNode) or e.res_group() != group or not e.has_resource():
						continue
					var d := MapData.center(Vector2i(x, y)).distance_to(p)
					# Preferir árboles ya talados para no abrir el bosque de más.
					if e is ResourceNode and e.felled:
						d -= 1.5
					if d <= r and d < best_d:
						best_d = d
						best = e
	return best


## Edificio más cercano que recibe ese recurso (los barcos, solo en un muelle).
func nearest_dropoff(owner: int, rt: String, p: Vector2, naval := false) -> Building:
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.owner_id != owner or not b.complete or b.dead:
			continue
		if naval and not b.def.get("dock", false):
			continue
		if not b.def.get("drop", []).has(rt):
			continue
		var d := b.dist_to(p)
		if d < best_d:
			best_d = d
			best = b
	return best


func gather_rate(u: Unit, t: Entity) -> float:
	var rt := t.res_type()
	var base := 0.0
	if t is Animal:
		base = Defs.MEAT_RATE
	elif t is Building:
		base = Defs.FARM_RATE
	elif t is ResourceNode:
		base = t.def["rate"]
	var m := players[u.owner_id].gather_mult(rt)
	var c := t.center()
	for b in buildings:
		if b.owner_id == u.owner_id and b.complete and b.kind != "centro" and b.def.get("drop", []).has(rt) \
				and b.center().distance_to(c) <= Defs.CAMP_RADIUS:
			m *= Defs.CAMP_SPEED
			break
	return base * m


func deposit(owner: int, rt: String, amount: float) -> void:
	players[owner].res[rt] = players[owner].res.get(rt, 0.0) + amount
	players[owner].stats["recolectado"] += amount


func recount_pop(owner: int) -> void:
	var p := players[owner]
	var n := 0
	for u in units:
		if u.owner_id == owner and not u.dead:
			n += 1
	var cap := 0
	for b in buildings:
		if b.owner_id == owner and b.complete and not b.dead:
			cap += int(b.def.get("pop", 0))
	p.pop = n
	p.pop_cap = mini(cap, Defs.POP_MAX)


func has_pop_room(owner: int) -> bool:
	recount_pop(owner)
	return players[owner].pop < players[owner].pop_cap


func count_buildings(owner: int, kinds: Array, only_complete := true) -> int:
	var n := 0
	for b in buildings:
		if b.owner_id == owner and kinds.has(b.kind) and (b.complete or not only_complete):
			n += 1
	return n


func notify(owner: int, text: String, p: Vector2) -> void:
	if owner != local_id or hud == null:
		return
	var last: float = _notify_seen.get(text, -100.0)
	if time - last < 3.0:
		return
	_notify_seen[text] = time
	hud.notify(text, p)


# ---------------- construcción, entrenamiento y eras ----------------

## Nombre de un edificio para un jugador (torre, muralla y puerta cambian con su nivel).
func building_name(owner: int, k: String) -> String:
	return Lang.t(Defs.bstat(k, players[owner].techs, "name", Defs.BUILDINGS[k]["name"]))


## Costo de un edificio para un jugador (según su nivel y su civilización).
func build_cost(owner: int, k: String) -> Dictionary:
	var p := players[owner]
	var c: Dictionary = Defs.bstat(k, p.techs, "cost", Defs.BUILDINGS[k]["cost"]).duplicate()
	var mult: Dictionary = Defs.civ_mod(p.civ, "cost_mult", {})
	if mult.has(k):
		for r in c:
			c[r] = roundi(c[r] * float(mult[k]))
	return c


## Devuelve "" si se puede, o el motivo por el que no.
func build_block_reason(owner: int, k: String) -> String:
	var d: Dictionary = Defs.BUILDINGS[k]
	var p := players[owner]
	if d.get("age", 1) > p.age:
		return Lang.t("Requiere el nivel %d (%s).") % [d["age"], Lang.t(Defs.AGES[d["age"] - 1]["name"])]
	if d.get("seed", false) and p.seeds <= 0:
		return Lang.t("No tienes siembras. Cómpralas en el Centro.")
	if d.has("needs") and count_buildings(owner, [d["needs"]]) == 0:
		return Lang.t("Requiere %s.") % Lang.t(Defs.BUILDINGS[d["needs"]]["name"])
	if d.get("wonder", false) and count_buildings(owner, [k], false) > 0:
		return Lang.t("Solo puedes tener una maravilla.")
	if not p.can_afford(build_cost(owner, k)):
		return Lang.t("Faltan recursos.")
	return ""


func can_place(owner: int, k: String, tile: Vector2i) -> bool:
	var d: Dictionary = Defs.BUILDINGS[k]
	var sz: int = d["size"]
	var r := Rect2i(tile, Vector2i(sz, sz))
	if d.get("water", false):
		# En el agua (trampa para peces).
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if not map.is_open_water(Vector2i(x, y)):
					return false
		return true
	if not map.rect_open(r):
		return false
	if d.get("dock", false):
		# En la orilla: al menos 3 casillas de agua libres junto al muelle.
		if map.ring_around(r, MapData.WATER_NAV).size() < 3:
			return false
	for u in units:
		if not u.dead and u.owner_id != owner and r.has_point(MapData.to_tile(u.pos)):
			return false
	return true


## Igual que can_place, pero además pide que el jugador local ya haya explorado ahí (solo interfaz).
func can_place_ui(k: String, tile: Vector2i) -> bool:
	var sz: int = Defs.BUILDINGS[k]["size"]
	return can_place(local_id, k, tile) and (fog.reveal_all or _rect_explored(Rect2i(tile, Vector2i(sz, sz))))


func _rect_explored(r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if fog.explored[map.idx(Vector2i(x, y))] == 0:
				return false
	return true


func place_building(owner: int, k: String, tile: Vector2i) -> Building:
	if build_block_reason(owner, k) != "" or not can_place(owner, k, tile):
		return null
	players[owner].pay(build_cost(owner, k))
	if Defs.BUILDINGS[k].get("seed", false):
		players[owner].seeds -= 1
	return spawn_building(k, owner, tile, false)


func buy_seed(owner: int) -> bool:
	var p := players[owner]
	if main_center(owner) == null or not p.can_afford(Defs.SEED_COST):
		return false
	p.pay(Defs.SEED_COST)
	p.seeds += 1
	return true


func train_block_reason(owner: int, b: Building, k: String) -> String:
	var p := players[owner]
	if not b.can_train(k):
		return Lang.t("Este edificio no lo entrena.")
	if Defs.UNITS[k].get("naval", false) and map.ring_around(b.rect, MapData.WATER_NAV).is_empty():
		return Lang.t("No hay agua libre junto al muelle.")
	if Defs.UNITS[k].get("age", 1) > p.age:
		return Lang.t("Requiere el nivel %d (%s).") % [Defs.UNITS[k]["age"], Lang.t(Defs.AGES[Defs.UNITS[k]["age"] - 1]["name"])]
	if b.queue.size() >= 10:
		return Lang.t("La cola está llena.")
	if not p.can_afford(Defs.cost_of(k, p.civ)):
		return Lang.t("Faltan recursos.")
	return ""


func train(owner: int, b: Building, k: String) -> bool:
	if b.owner_id != owner or train_block_reason(owner, b, k) != "":
		return false
	players[owner].pay(Defs.cost_of(k, players[owner].civ))
	b.enqueue(k)
	return true


func refund(owner: int, k: String, _b: Building) -> void:
	if k == "era":
		players[owner].give(Defs.AGES[players[owner].age]["cost"])
	elif k.begins_with("tech:"):
		players[owner].give(Defs.TECHS[k.trim_prefix("tech:")]["cost"])
	elif k == "reliquia":
		players[owner].give(Defs.RELIC_COST)
	else:
		players[owner].give(Defs.cost_of(k, players[owner].civ))


func spawn_trained(b: Building, k: String) -> void:
	if b.owner_id == local_id:
		Sfx.play("listo", -3.0)
	var toward := b.rally if b.rally != Vector2.INF else b.center() + Vector2(b.def["size"], b.def["size"])
	var nv := MapData.WATER_NAV if Defs.UNITS[k].get("naval", false) else 0
	var cands := map.ring_around(b.rect, nv)
	if cands.is_empty():
		cands = [map.nearest_free(MapData.to_tile(b.center()), 30, nv)]
	cands.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		return MapData.center(x).distance_squared_to(toward) < MapData.center(y).distance_squared_to(toward))
	var u := spawn_unit(k, b.owner_id, MapData.center(cands[0]))
	players[b.owner_id].stats["entrenados"] += 1
	recount_pop(b.owner_id)
	if b.rally_ent and Entity.live(b.rally_ent):
		command_units([u], b.rally_ent, b.rally_ent.center(), false)
	elif b.rally != Vector2.INF:
		u.cmd_move(b.rally)


## Requisitos para la siguiente era: Array de {text, have, need, ok}
func age_requirements(owner: int) -> Array:
	var p := players[owner]
	var out: Array = []
	if p.age >= Defs.AGES.size():
		return out
	for r in Defs.AGES[p.age]["req"]:
		var have := count_buildings(owner, r[0])
		out.append({"text": Lang.t(r[2]), "have": have, "need": r[1], "ok": have >= r[1]})
	return out


func age_block_reason(owner: int, b: Building) -> String:
	var p := players[owner]
	if b.kind != "centro" or not b.complete:
		return Lang.t("Se investiga en el Centro.")
	if p.age >= Defs.AGES.size():
		return Lang.t("Ya estás en la última era.")
	for bb in buildings:
		if bb.owner_id == owner and bb.queue.has("era"):
			return Lang.t("Ya se está investigando.")
	var missing: Array[String] = []
	for r in age_requirements(owner):
		if not r["ok"]:
			missing.append("%s (%d/%d)" % [r["text"], r["have"], r["need"]])
	if not missing.is_empty():
		return Lang.t("Falta: ") + ", ".join(missing)
	if not p.can_afford(Defs.AGES[p.age]["cost"]):
		return Lang.t("Faltan recursos.")
	return ""


func research_age(owner: int, b: Building) -> bool:
	if b.owner_id != owner or age_block_reason(owner, b) != "":
		return false
	players[owner].pay(Defs.AGES[players[owner].age]["cost"])
	b.enqueue("era")
	return true


func advance_age(owner: int) -> void:
	var p := players[owner]
	if owner == local_id:
		Sfx.play("era")
	p.age = mini(p.age + 1, Defs.AGES.size())
	for b in buildings:
		if b.owner_id == owner:
			b.on_age_up()
	for u in units:
		if u.owner_id == owner:
			u.refresh_age()
	notify(owner, Lang.t("¡Avanzaste a la era %s!") % p.age_name(), Vector2.INF)
	if owner != local_id and team_of(owner) != team_of(local_id):
		notify(local_id, Lang.t("%s avanzó a la era %s.") % [p.name, p.age_name()], Vector2.INF)
	if hud:
		hud.refresh_selection()


# ---------------- mejoras, reliquias y maravilla ----------------

## "" si se puede investigar esa mejora en ese edificio, o el motivo.
func tech_block_reason(owner: int, b: Building, t: String) -> String:
	var d: Dictionary = Defs.TECHS.get(t, {})
	var p := players[owner]
	if d.is_empty() or b == null or b.kind != d["at"] or not b.complete:
		return Lang.t("Se investiga en: %s.") % Lang.t(Defs.BUILDINGS[d.get("at", "centro")]["name"])
	if p.techs.has(t):
		return Lang.t("Ya la investigaste.")
	if int(d["age"]) > p.age:
		return Lang.t("Requiere el nivel %d (%s).") % [d["age"], Lang.t(Defs.AGES[int(d["age"]) - 1]["name"])]
	if d.has("needs") and not p.techs.has(d["needs"]):
		return Lang.t("Primero investiga: %s.") % Lang.t(Defs.TECHS[d["needs"]]["name"])
	for bb in buildings:
		if bb.owner_id == owner and bb.queue.has("tech:" + t):
			return Lang.t("Ya se está investigando.")
	if b.queue.size() >= 10:
		return Lang.t("La cola está llena.")
	if not p.can_afford(d["cost"]):
		return Lang.t("Faltan recursos.")
	return ""


func research_tech(owner: int, b: Building, t: String) -> bool:
	if b == null or b.owner_id != owner or tech_block_reason(owner, b, t) != "":
		return false
	players[owner].pay(Defs.TECHS[t]["cost"])
	b.enqueue("tech:" + t)
	return true


func finish_tech(owner: int, t: String) -> void:
	var p := players[owner]
	if p.techs.has(t):
		return
	p.techs[t] = true
	if owner == local_id:
		Sfx.play("mejora")
	for b in buildings:
		if b.owner_id == owner:
			b.on_tech()
	notify(owner, Lang.t("Mejora lista: %s.") % Lang.t(Defs.TECHS[t]["name"]), Vector2.INF)
	if hud:
		Thumbs.clear()
		hud.refresh_selection()


## Santo tuyo junto al edificio (para crear reliquias).
func santo_near(b: Building) -> Unit:
	for u in units:
		if u.owner_id == b.owner_id and u.kind == "santo" and not u.dead and u.garrison_in == null and b.dist_to(u.pos) <= 3.0:
			return u
	return null


func relic_block_reason(owner: int, b: Building) -> String:
	if b == null or b.kind != "monasterio" or not b.complete or b.owner_id != owner:
		return Lang.t("Las reliquias se crean en el monasterio.")
	if b.queue.has("reliquia"):
		return Lang.t("Ya se está creando una reliquia.")
	if santo_near(b) == null:
		return Lang.t("Necesitas un santo junto al monasterio.")
	if not players[owner].can_afford(Defs.RELIC_COST):
		return Lang.t("Faltan recursos.")
	return ""


func make_relic(owner: int, b: Building) -> bool:
	if relic_block_reason(owner, b) != "":
		return false
	players[owner].pay(Defs.RELIC_COST)
	b.enqueue("reliquia")
	return true


## La reliquia aparece en un lugar al azar del mapa (en tierra, lejos de las orillas).
func spawn_relic(owner: int, b: Building) -> Relic:
	if owner == local_id:
		Sfx.play("reliquia")
	var t := Vector2i(-1, -1)
	for i in 400:
		var c := Vector2i(sim_rng.randi_range(4, map.w - 5), sim_rng.randi_range(4, map.h - 5))
		if map.is_free(c) and map.reserved[map.idx(c)] == 0:
			t = c
			break
	if t.x < 0:
		t = map.nearest_free(MapData.to_tile(b.center()))
	var rl := Relic.new()
	rl.init(self, MapData.center(t))
	relics.append(rl)
	_register(rl)
	notify(owner, Lang.t("¡Tu santo creó una reliquia! Apareció en algún lugar del mapa: búscala y llévala a tu maravilla."), rl.pos)
	for q in players:
		if q.id != owner:
			notify(q.id, Lang.t("Apareció una reliquia en el mapa. Un santo puede llevarla a una maravilla."), rl.pos)
	_update_fog()
	return rl


func own_wonder(owner: int) -> Building:
	for b in buildings:
		if b.owner_id == owner and b.def.get("wonder", false) and b.complete and not b.dead:
			return b
	return null


## El santo deja la reliquia dentro de la maravilla.
func store_relic(w: Building, rl: Relic) -> void:
	if rl == null:
		return
	rl.carrier = null
	rl.wonder = w
	if w.owner_id == local_id:
		Sfx.play("reliquia")
	rl.pos = w.center()
	w.relics.append(rl)
	if w.visual:
		w._rebuild_visual()
	notify(w.owner_id, Lang.t("Reliquia guardada en tu maravilla (%d / %d).") % [w.relics.size(), Defs.WONDER_RELICS], w.pos)


## Cuenta atrás de las maravillas con todas sus reliquias.
func _sim_wonders(dt: float) -> void:
	for p in players:
		if p.defeated:
			continue
		var w := own_wonder(p.id)
		var ready := w != null and w.relics.size() >= Defs.WONDER_RELICS
		if not ready:
			if p.wonder_t >= 0.0:
				p.wonder_t = -1.0
				notify(local_id, Lang.t("Se detuvo la cuenta atrás de la maravilla de %s.") % p.name, Vector2.INF)
			continue
		if p.wonder_t < 0.0:
			p.wonder_t = Defs.WONDER_TIME
			for q in players:
				if q.id == p.id:
					notify(q.id, Lang.t("¡Tu maravilla tiene sus 3 reliquias! Si sigue en pie %d minutos, ganas.") % int(Defs.WONDER_TIME / 60.0), w.pos)
				else:
					notify(q.id, Lang.t("¡%s empezó la cuenta atrás de su maravilla! Destrúyela antes de %d minutos.") % [p.name, int(Defs.WONDER_TIME / 60.0)], w.pos)
		p.wonder_t = maxf(0.0, p.wonder_t - dt)
		if p.wonder_t == 0.0:
			_vic_t = 0.0


## La cuenta atrás de maravilla que más pronto termina: {name, t, mine} o {}.
func wonder_countdown() -> Dictionary:
	var best := {}
	for p in players:
		if not p.defeated and p.wonder_t >= 0.0 and (best.is_empty() or p.wonder_t < best["t"]):
			best = {"name": p.name, "t": p.wonder_t, "mine": team_of(p.id) == team_of(local_id)}
	return best


# ---------------- mercado ----------------

const MARKET_LOT := 100.0


func market_price(owner: int, r: String) -> float:
	return players[owner].prices.get(r, 100.0)


func market_buy(owner: int, r: String) -> bool:
	var p := players[owner]
	var price := market_price(owner, r)
	if count_buildings(owner, ["mercado"]) == 0 or p.res["oro"] < price:
		return false
	p.res["oro"] -= price
	p.res[r] += MARKET_LOT
	p.prices[r] = minf(300.0, price + 5.0)
	return true


func market_sell(owner: int, r: String) -> bool:
	var p := players[owner]
	if count_buildings(owner, ["mercado"]) == 0 or p.res[r] < MARKET_LOT:
		return false
	var price := market_price(owner, r)
	p.res[r] -= MARKET_LOT
	p.res["oro"] += floorf(price * 0.75)
	p.prices[r] = maxf(25.0, price - 5.0)
	return true


# ---------------- órdenes ----------------

## Orden contextual (clic derecho) para un grupo de unidades.
func command_units(list: Array, target: Entity, point: Vector2, queue: bool) -> void:
	var movers: Array[Unit] = []
	for u in list:
		if not (u is Unit) or u.dead:
			continue
		if u.garrison_in:
			u._leave_garrison()
		# Santo: reliquia del suelo o llevarla a tu maravilla.
		if u.kind == "santo" and target is Relic and target.on_ground():
			u.cmd_relic(target)
			continue
		if u.kind == "santo" and u.relic and target is Building and target.owner_id == u.owner_id and target.def.get("wonder", false) and target.complete:
			u.cmd_relic(target)
			continue
		# Arquero: entrar a una torre de guardia tuya con lugar.
		if u.kind == "arquero" and target is Building and target.owner_id == u.owner_id and target.garrison_space() > 0:
			u.cmd_garrison(target)
			continue
		# Barco pesquero: pescar en bancos de peces y trampas, o construir trampas.
		if u.is_fisher() and Entity.valid(target):
			if target is Building and target.owner_id == u.owner_id and target.kind == "trampa":
				if not target.complete:
					u.cmd_build(target, queue)
				else:
					u.cmd_gather(target)
				continue
			if target is ResourceNode and target.kind == "pesca" and target.has_resource():
				u.cmd_gather(target)
				continue
			if target is Building and target.owner_id == u.owner_id and target.def.get("dock", false) and u.carry > 0.0:
				u.cmd_drop(target)
				continue
		if Entity.live(target) or (Entity.valid(target) and target.has_resource()):
			# Aldeano + cabra o guajolote vivo que no es tuyo = pastorearlo (también para robarlo).
			if u.is_villager() and target is Animal and not target.dead and target.tame and target.owner_id != u.owner_id:
				u.cmd_herd(target)
				continue
			if is_enemy(u.owner_id, target.owner_id):
				if u.can_hit(target):
					u.cmd_attack(target)
					continue
				movers.append(u)
				continue
			if target is Building and target.owner_id == u.owner_id:
				if u.is_villager() and not target.def.get("water", false):
					if not target.complete:
						u.cmd_build(target, queue)
						continue
					if target.kind == "granja":
						u.cmd_gather(target)
						continue
					if u.carry > 0.0 and target.def.get("drop", []).has(u.carry_type):
						u.cmd_drop(target)
						continue
				movers.append(u)
				continue
			if (target.has_resource() or target is Animal) and not u.is_naval():
				u.cmd_gather(target)
				continue
		movers.append(u)
	_group_move(movers, point)


func _group_move(list: Array[Unit], point: Vector2) -> void:
	if list.is_empty():
		return
	var n := list.size()
	var cols := ceili(sqrt(n))
	var spacing := 0.8
	# Ordenar por cercanía para que no se crucen.
	var center := Vector2.ZERO
	for u in list:
		center += u.pos
	center /= n
	var dir := (point - center).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x)
	list.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.pos.dot(side) < b.pos.dot(side))
	for i in n:
		var row := i / cols
		var col := i % cols
		var off := side * (col - (cols - 1) * 0.5) * spacing - dir * row * spacing
		var dest := point + off if n > 1 else point
		if not map.is_free(MapData.to_tile(dest), list[i].nav()):
			dest = point
		list[i].cmd_move(dest)


# ---------------- capa de órdenes (local y en línea) ----------------

func entity(id) -> Entity:
	var e = ents.get(int(id))
	return e if Entity.valid(e) else null


func issue(c: Dictionary) -> void:
	if online:
		Net.send_cmd(c)
	else:
		_local_cmds.append([local_id, c])


func _ids(list: Array) -> Array:
	var out: Array = []
	for e in list:
		if Entity.valid(e):
			out.append(e.id)
	return out


func _own_animals(pid: int, ids: Array) -> Array[Animal]:
	var out: Array[Animal] = []
	for i in ids:
		var e := entity(i)
		if e is Animal and e.owner_id == pid and not e.dead:
			out.append(e)
	return out


## Tus animales: a un corral tuyo (se quedan pastando) o a un punto, un poco separados.
func _order_animals(pid: int, ids: Array, target: Entity, point: Vector2) -> void:
	var list := _own_animals(pid, ids)
	if list.is_empty():
		return
	var dest := point
	if target is Building and target.owner_id == pid and target.kind == "corral":
		dest = target.center()
	var cols := ceili(sqrt(list.size()))
	for i in list.size():
		var off := Vector2((i % cols) - (cols - 1) * 0.5, (i / cols) - (cols - 1) * 0.5) * 0.7
		var p := dest + off
		if not map.is_free(MapData.to_tile(p)):
			p = dest
		list[i].cmd_move(p)


func _own_units(pid: int, ids: Array) -> Array[Unit]:
	var out: Array[Unit] = []
	for i in ids:
		var e := entity(i)
		if e is Unit and e.owner_id == pid and not e.dead:
			out.append(e)
	return out


func _own_building(pid: int, id) -> Building:
	var e := entity(id)
	if e is Building and e.owner_id == pid and not e.dead:
		return e
	return null


# Atajos para la interfaz
func order_units(list: Array, target: Entity, point: Vector2, queue: bool) -> void:
	issue({"k": "order", "u": _ids(list), "t": target.id if target else 0, "x": point.x, "y": point.y, "q": queue})


func apply_cmd(pid: int, c: Dictionary) -> void:
	if pid < 0 or pid >= players.size() or players[pid].defeated:
		return
	match String(c.get("k", "")):
		"order":
			command_units(_own_units(pid, c.get("u", [])), entity(c.get("t", 0)), Vector2(c["x"], c["y"]), bool(c.get("q", false)))
			_order_animals(pid, c.get("u", []), entity(c.get("t", 0)), Vector2(c["x"], c["y"]))
		"stop":
			for u in _own_units(pid, c.get("u", [])):
				u.cmd_stop()
			for a in _own_animals(pid, c.get("u", [])):
				a.cmd_stop()
		"kill":
			for u in _own_units(pid, c.get("u", [])):
				u.take_damage(99999.0, null)
		"place":
			var k := String(c.get("b", ""))
			if not Defs.BUILDINGS.has(k):
				return
			var placed: Array = []
			for t in c.get("tiles", []):
				var b := place_building(pid, k, Vector2i(int(t[0]), int(t[1])))
				if b:
					placed.append(b)
			if placed.is_empty():
				return
			var fisher := String(Defs.BUILDINGS[k].get("builder", "aldeano")) == "barco_pesca"
			var vills: Array[Unit] = []
			for u in _own_units(pid, c.get("u", [])):
				if (u.is_fisher() if fisher else u.is_villager()):
					vills.append(u)
			if vills.is_empty():
				var near := nearest_villager(pid, placed[0].center(), fisher)
				if near:
					vills.append(near)
			for i in placed.size():
				for u in vills:
					u.cmd_build(placed[i], bool(c.get("q", false)) or i > 0)
		"train":
			var b := _own_building(pid, c.get("e", 0))
			if b == null and String(c.get("b", "")) == "aldeano":
				b = main_center(pid)
			if b and Defs.UNITS.has(String(c.get("b", ""))):
				train(pid, b, String(c["b"]))
		"cancel":
			var b := _own_building(pid, c.get("e", 0))
			if b:
				b.cancel_last()
		"age":
			var b := _own_building(pid, c.get("e", 0))
			if b == null:
				b = main_center(pid)
			if b:
				research_age(pid, b)
		"research":
			var b := _own_building(pid, c.get("e", 0))
			if b:
				research_tech(pid, b, String(c.get("t", "")))
		"relic":
			var b := _own_building(pid, c.get("e", 0))
			if b:
				make_relic(pid, b)
		"bell":
			ring_bell(pid)
		"eject":
			var b := _own_building(pid, c.get("e", 0))
			if b:
				for u in b.garrison.duplicate():
					u._leave_garrison()
		"seed":
			buy_seed(pid)
		"buy":
			if String(c.get("r", "")) in ["comida", "madera", "piedra"]:
				market_buy(pid, String(c["r"]))
		"sell":
			if String(c.get("r", "")) in ["comida", "madera", "piedra"]:
				market_sell(pid, String(c["r"]))
		"rally":
			var b := _own_building(pid, c.get("e", 0))
			if b:
				b.rally = Vector2(c["x"], c["y"])
				var t := entity(c.get("t", 0))
				b.rally_ent = t if t and (t.has_resource() or t is Animal) else null
		"destroy":
			var b := _own_building(pid, c.get("e", 0))
			if b:
				destroy_building(b, false)
		"resign":
			_defeat(pid, true)
			_check_victory()


## Aldeano (o barco pesquero) más cercano de un jugador (prefiere los que no tienen tarea).
func nearest_villager(pid: int, p: Vector2, fisher := false) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in units:
		if u.owner_id != pid or u.dead or not (u.is_fisher() if fisher else u.is_villager()):
			continue
		var d := u.pos.distance_to(p)
		if not u.is_idle():
			d += 25.0
		if u.state == Unit.S.BUILD:
			d += 50.0
		if d < bd:
			bd = d
			best = u
	return best
