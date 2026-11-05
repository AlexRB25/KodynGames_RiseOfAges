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
var projectiles: Array = []
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


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	start_match()


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
		elif arg.begins_with("--civ=") and not Setup.players.is_empty():
			Setup.players[Setup.local_player]["civ"] = arg.get_slice("=", 1)
	map.setup(size)
	var teams: Array = []
	for i in cfg.size():
		var c: Dictionary = cfg[i]
		var p := PlayerState.new()
		p.id = i
		p.name = c.get("name", "Jugador %d" % (i + 1))
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
	fog.setup(map)
	Mat.setup(fog.texture, Vector2(size, size))

	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_setup_env()
	var tv := TerrainView.new()
	tv.build(map, fog.texture)
	_world.add_child(tv)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
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
		if Defs.MAP_TYPES.has(map_type):
			hud.notify("Mapa: %s. %s" % [Defs.MAP_TYPES[map_type]["name"], Defs.MAP_TYPES[map_type]["desc"]], Vector2.INF)
	_update_fog()
	if online:
		Net.attach(self)
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
		elif a.begins_with("--at=") and camera:
			# --at=x,y,distancia  (desarrollo: mirar un punto del mapa)
			var v := a.get_slice("=", 1).split(",")
			camera.focus(Vector2(float(v[0]), float(v[1])))
			if v.size() > 2:
				camera.dist = float(v[2])
				camera.target_dist = float(v[2])
		elif a.begins_with("--edificio="):
			# Desarrollo: --edificio=templo:1  pone ese edificio terminado junto al centro del jugador 1.
			var parts := a.get_slice("=", 1).split(":")
			var who := int(parts[1]) if parts.size() > 1 else local_id
			var ec := main_center(who).center()
			var eb: Building = null
			for r in range(7, 18):
				for k in 16:
					var t := MapData.to_tile(ec + Vector2.from_angle(TAU * k / 16.0) * r)
					if eb == null and can_place(who, parts[0], t):
						eb = spawn_building(parts[0], who, t, true)
			if eb:
				camera.focus(eb.center())
				camera.dist = 16.0
				camera.target_dist = 16.0
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
		elif a.begins_with("--tab=") and hud:
			hud.set_tab(a.get_slice("=", 1))
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
				if map.solid[i] == 0 and not map.ground_blocks(i):
					map.astar.set_point_solid(t, false)
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
	buildings.erase(b)
	if b.worker:
		b.worker = null
	if controller:
		controller.forget(b)
	recount_pop(b.owner_id)
	if by_attack:
		notify(b.owner_id, "Perdiste: %s." % b.display_name(), b.pos)
		if b.kind == "centro" and not players[b.owner_id].defeated:
			var nc := main_center(b.owner_id)
			if nc:
				notify(b.owner_id, "Destruyeron tu centro. El otro centro es ahora el principal.", nc.pos)
			else:
				notify(b.owner_id, "¡Destruyeron tu último centro!", b.pos)
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
	if b.kind != "muralla" and b.kind != "granja":
		notify(b.owner_id, "%s terminado." % b.display_name(), b.pos)
	if hud:
		hud.refresh_selection()


func on_attacked(e: Entity, from: Entity) -> void:
	if from == null:
		return
	if e.owner_id == local_id and time - _attack_note_t > 12.0:
		_attack_note_t = time
		notify(local_id, "¡Te están atacando!", e.pos)
	for b in bots:
		if b.pid == e.owner_id:
			b.on_attacked(e, from)


# ---------------- simulación ----------------

func _process(delta: float) -> void:
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
		if team_of(u.owner_id) != lt:
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


## Regla: pierde quien se queda sin ningún Centro terminado. El centro más
## antiguo que siga en pie es el "principal".
func _check_victory() -> void:
	if over:
		return
	for p in players:
		if p.defeated:
			continue
		if main_center(p.id) == null:
			_defeat(p.id)
	var teams_alive := {}
	for p in players:
		if not p.defeated:
			teams_alive[p.team] = true
	if teams_alive.size() <= 1:
		over = true
		var winner: int = teams_alive.keys()[0] if teams_alive.size() == 1 else -1
		game_over.emit(winner)
		if hud:
			hud.show_result(winner == team_of(local_id))


## En línea con rango: el servidor da la partida por terminada (el rival abandonó).
func end_by_forfeit(winner_team: int, forfeit: bool) -> void:
	if over or not forfeit:
		return
	over = true
	if hud:
		hud.show_result(winner_team == team_of(local_id))


func main_center(pid: int) -> Building:
	for b in buildings:
		if b.owner_id == pid and b.kind == "centro" and b.complete and not b.dead:
			return b
	return null


func _defeat(pid: int, resigned := false) -> void:
	var p := players[pid]
	p.defeated = true
	if resigned:
		notify(local_id, "%s se rindió." % p.name if pid != local_id else "Te rendiste.", Vector2.INF)
	else:
		notify(local_id, "%s se quedó sin centros y fue derrotado." % p.name if pid != local_id else "Te quedaste sin centros.", Vector2.INF)
	for u in units.duplicate():
		if u.owner_id == pid:
			u.take_damage(99999.0, null)
	for b in buildings.duplicate():
		if b.owner_id == pid:
			destroy_building(b, false)


# ---------------- proyectiles ----------------

func spawn_projectile(src: Entity, target: Entity, dmg: float) -> void:
	var from := src.center()
	var h := 1.0 if src is Unit else 2.0
	var pr := {"p": from, "h": h, "target": target, "dmg": dmg, "src": src, "t": 0.0, "node": null,
		"start": from, "dur": maxf(0.15, from.distance_to(target.center()) / 14.0)}
	if not headless and (fog.is_visible(from) or fog.is_visible(target.center())):
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.5, 0.04, 0.04)
		mi.mesh = m
		mi.material_override = Mat.flat(Color(0.25, 0.18, 0.1))
		_world.add_child(mi)
		pr["node"] = mi
	projectiles.append(pr)


func _sim_projectiles(dt: float) -> void:
	for pr in projectiles.duplicate():
		pr["t"] += dt
		if pr["t"] >= pr["dur"]:
			var t: Entity = pr["target"]
			if Entity.live(t):
				t.take_damage(pr["dmg"], pr["src"] if is_instance_valid(pr["src"]) else null)
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
func find_enemy_near(e: Entity, r: float) -> Entity:
	var best: Entity = null
	var best_d := INF
	var c := e.center()
	for u in units:
		if u.dead or not is_enemy(e.owner_id, u.owner_id):
			continue
		var d := e.dist_to(u.pos) if e is Building else u.pos.distance_to(c)
		if d <= r and d < best_d:
			best_d = d
			best = u
	if best or e is Building:
		return best
	for b in buildings:
		if b.dead or not is_enemy(e.owner_id, b.owner_id) or b.kind == "muralla":
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
		"granja":
			for b in buildings:
				if b.kind != "granja" or b.owner_id != owner or b == exclude or not b.has_resource():
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


func nearest_dropoff(owner: int, rt: String, p: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.owner_id != owner or not b.complete or b.dead:
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

## Devuelve "" si se puede, o el motivo por el que no.
func build_block_reason(owner: int, k: String) -> String:
	var d: Dictionary = Defs.BUILDINGS[k]
	var p := players[owner]
	if d.get("age", 1) > p.age:
		return "Requiere el nivel %d (%s)." % [d["age"], Defs.AGES[d["age"] - 1]["name"]]
	if d.get("seed", false) and p.seeds <= 0:
		return "No tienes siembras. Cómpralas en el Centro."
	if d.has("needs") and count_buildings(owner, [d["needs"]]) == 0:
		return "Requiere %s." % Defs.BUILDINGS[d["needs"]]["name"]
	if not p.can_afford(Defs.cost_of(k, p.civ)):
		return "Faltan recursos."
	return ""


func can_place(owner: int, k: String, tile: Vector2i) -> bool:
	var sz: int = Defs.BUILDINGS[k]["size"]
	var r := Rect2i(tile, Vector2i(sz, sz))
	if not map.rect_open(r):
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
	players[owner].pay(Defs.cost_of(k, players[owner].civ))
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
		return "Este edificio no lo entrena."
	if Defs.UNITS[k].get("age", 1) > p.age:
		return "Requiere el nivel %d (%s)." % [Defs.UNITS[k]["age"], Defs.AGES[Defs.UNITS[k]["age"] - 1]["name"]]
	if b.queue.size() >= 10:
		return "La cola está llena."
	if not p.can_afford(Defs.cost_of(k, p.civ)):
		return "Faltan recursos."
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
	else:
		players[owner].give(Defs.cost_of(k, players[owner].civ))


func spawn_trained(b: Building, k: String) -> void:
	var toward := b.rally if b.rally != Vector2.INF else b.center() + Vector2(b.def["size"], b.def["size"])
	var cands := map.ring_around(b.rect)
	if cands.is_empty():
		cands = [map.nearest_free(MapData.to_tile(b.center()), 30)]
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
		out.append({"text": r[2], "have": have, "need": r[1], "ok": have >= r[1]})
	return out


func age_block_reason(owner: int, b: Building) -> String:
	var p := players[owner]
	if b.kind != "centro" or not b.complete:
		return "Se investiga en el Centro."
	if p.age >= Defs.AGES.size():
		return "Ya estás en la última era."
	for bb in buildings:
		if bb.owner_id == owner and bb.queue.has("era"):
			return "Ya se está investigando."
	var missing: Array[String] = []
	for r in age_requirements(owner):
		if not r["ok"]:
			missing.append("%s (%d/%d)" % [r["text"], r["have"], r["need"]])
	if not missing.is_empty():
		return "Falta: " + ", ".join(missing)
	if not p.can_afford(Defs.AGES[p.age]["cost"]):
		return "Faltan recursos."
	return ""


func research_age(owner: int, b: Building) -> bool:
	if b.owner_id != owner or age_block_reason(owner, b) != "":
		return false
	players[owner].pay(Defs.AGES[players[owner].age]["cost"])
	b.enqueue("era")
	return true


func advance_age(owner: int) -> void:
	var p := players[owner]
	p.age = mini(p.age + 1, Defs.AGES.size())
	for b in buildings:
		if b.owner_id == owner:
			b.on_age_up()
	for u in units:
		if u.owner_id == owner:
			u.refresh_age()
	notify(owner, "¡Avanzaste a la era %s!" % p.age_name(), Vector2.INF)
	if owner != local_id and team_of(owner) != team_of(local_id):
		notify(local_id, "%s avanzó a la era %s." % [p.name, p.age_name()], Vector2.INF)
	if hud:
		hud.refresh_selection()


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
		if Entity.live(target) or (Entity.valid(target) and target.has_resource()):
			# Aldeano + cabra o guajolote vivo que no es tuyo = pastorearlo (también para robarlo).
			if u.is_villager() and target is Animal and not target.dead and target.tame and target.owner_id != u.owner_id:
				u.cmd_herd(target)
				continue
			if is_enemy(u.owner_id, target.owner_id):
				u.cmd_attack(target)
				continue
			if target is Building and target.owner_id == u.owner_id:
				if u.is_villager():
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
			if target.has_resource() or target is Animal:
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
		if not map.is_free(MapData.to_tile(dest)):
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
			var vills: Array[Unit] = []
			for u in _own_units(pid, c.get("u", [])):
				if u.is_villager():
					vills.append(u)
			if vills.is_empty():
				var near := nearest_villager(pid, placed[0].center())
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


## Aldeano más cercano de un jugador (prefiere los que no tienen tarea).
func nearest_villager(pid: int, p: Vector2) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in units:
		if u.owner_id != pid or not u.is_villager() or u.dead:
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
