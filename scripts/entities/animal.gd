class_name Animal
extends Entity
## Animal salvaje. Vivo: pasea y huye cuando lo atacan. Muerto: queda tirado
## y se convierte en comida que se va acabando (y achicando) al recolectarla.

var def: Dictionary
var food := 0.0
var max_food := 1.0
var home := Vector2.ZERO
var prev_pos := Vector2.ZERO
var goal := Vector2.ZERO
var moving := false
var wait_t := 0.0
var flee_t := 0.0
var flee_from := Vector2.ZERO
var speed := 1.0
var visual: Node3D
var body: Node3D
var legs: Array[Node3D] = []
var _death_t := 0.0
var _anim := 0.0
var _rng := RandomNumberGenerator.new()
var tame := false                     # se puede pastorear (cabra, guajolote)
var path := PackedVector2Array()      # camino cuando su dueño lo manda a algún lado
var graze_tick := -10                 # último paso en que pastó en un corral
var held_tick := -10                  # último paso en que un aldeano lo estaba pastoreando
var herd_claims := {}                 # jugador -> último paso en que lo pastoreó
var _collar: Node3D
## Arte en 3D (assets/modelos/recursos/<animal>/): viva.glb y, ya muerto, etapa75/50/25
## según la carne que le queda. Si no hay, la figura por código.
const ART_W := {"cabra": 0.62}
const ART_YAW := {"cabra": PI * 0.5}   # giro para que la cabeza del modelo mire hacia +X
const DEAD_SINK := {75: 0.2, 50: 0.2, 25: 0.3}   # su base de pasto queda bajo el suelo
var art := false
var _stage := -1


func is_mobile() -> bool:
	return not dead


func has_resource() -> bool:
	return dead and food > 0.0 and not removed


func res_type() -> String:
	return "comida"


func res_group() -> String:
	return "caza"


func remaining() -> float:
	return food if dead else max_food


func display_name() -> String:
	return Lang.t(def["name"]) + (Lang.t(" (cazado)") if dead else "")


func grazing() -> bool:
	return not dead and game != null and game.tick - graze_tick <= 2


## Cambia de dueño (-1 = salvaje). Lleva un listón del color de su dueño.
func set_herd_owner(pid: int) -> void:
	owner_id = pid
	path.clear()
	home = pos
	if _collar:
		_collar.queue_free()
		_collar = null
	if pid >= 0 and body:
		var h := 0.42 if kind == "guajolote" else 0.46
		var x := 0.18 if kind == "guajolote" else 0.24
		_collar = Mat.box(body, Vector3(0.08, 0.07, 0.26), Vector3(x, h, 0), game.players[pid].color)
	if pid >= 0:
		# Si su nuevo dueño tiene un corral cerca, se va solo para allá.
		var best: Building = null
		var bd := 40.0
		for b in game.buildings:
			if b.owner_id == pid and b.kind == "corral" and b.complete and not b.dead:
				var d := b.center().distance_to(pos)
				if d < bd:
					bd = d
					best = b
		if best:
			cmd_move(best.center())
		game.notify(pid, Lang.t("Nuevo animal en tu pueblo: %s.%s") % [Lang.t(def["name"]).to_lower(),
			Lang.t(" Va hacia tu corral.") if best else Lang.t(" Construye un Corral para que paste.")], pos)


## Orden del dueño: ir a un punto (o al corral, para quedarse pastando ahí).
func cmd_move(p: Vector2) -> void:
	if dead:
		return
	home = p
	path = game.map.path_to_tile(pos, MapData.to_tile(p), p)
	wait_t = _rng.randf_range(3.0, 6.0)
	if path.is_empty():
		moving = false
		return
	goal = path[0]
	path.remove_at(0)
	moving = true


func cmd_stop() -> void:
	path.clear()
	moving = false
	home = pos


## Un aldeano lo está pastoreando en este paso: se queda quieto.
## Devuelve false si otro jugador también lo pastorea (disputado: nadie avanza).
func hold_for(pid: int) -> bool:
	held_tick = game.tick
	moving = false
	path.clear()
	herd_claims[pid] = game.tick
	for other in herd_claims:
		if other != pid and game.tick - int(herd_claims[other]) <= 1:
			return false
	return true


func being_herded() -> bool:
	return game.tick - held_tick <= 1


func init(g: Game, k: String, p: Vector2, seed_v: int) -> void:
	game = g
	kind = k
	def = Defs.ANIMALS[k]
	max_hp = def["hp"]
	hp = max_hp
	food = def["food"]
	max_food = food
	tame = def.get("tame", false)
	speed = def["speed"]
	pos = p
	prev_pos = p
	home = p
	radius = 0.25
	_rng.seed = seed_v
	wait_t = _rng.randf_range(0.5, 4.0)
	position = Vector3(p.x, MapData.ground_y(p), p.y)
	_build_visual()


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	body = Node3D.new()
	visual.add_child(body)
	var c: Color = def["color"]
	var live := Art.stage_model_file(kind, "viva") if ART_W.has(kind) else null
	if live:
		art = true
		var n := Art.fitted(live, ART_W[kind])
		n.rotation.y = ART_YAW[kind]
		body.add_child(n)
		return
	match kind:
		"guajolote":
			Mat.ball(body, 0.17, Vector3(0, 0.25, 0), c, 6)
			Mat.ball(body, 0.07, Vector3(0.18, 0.42, 0), Color(0.75, 0.3, 0.3), 5)
			Mat.box(body, Vector3(0.04, 0.22, 0.26), Vector3(-0.15, 0.32, 0), c.darkened(0.2))
			for z in [-0.06, 0.06]:
				legs.append(Mat.box(body, Vector3(0.03, 0.14, 0.03), Vector3(0, 0.07, z), Color(0.8, 0.6, 0.3)))
		_:
			var h := 0.32 if kind == "cabra" else 0.42
			Mat.box(body, Vector3(0.5, 0.22, 0.22), Vector3(0, h, 0), c)
			Mat.box(body, Vector3(0.16, 0.16, 0.14), Vector3(0.3, h + 0.14, 0), c.lightened(0.05))
			if kind == "cabra":
				Mat.box(body, Vector3(0.03, 0.12, 0.03), Vector3(0.3, h + 0.27, 0.05), Color(0.4, 0.35, 0.3), Vector3(0, 0, -0.5))
				Mat.box(body, Vector3(0.03, 0.12, 0.03), Vector3(0.3, h + 0.27, -0.05), Color(0.4, 0.35, 0.3), Vector3(0, 0, -0.5))
			else:
				Mat.box(body, Vector3(0.03, 0.2, 0.03), Vector3(0.28, h + 0.3, 0.06), Color(0.45, 0.35, 0.25), Vector3(0.3, 0, -0.3))
				Mat.box(body, Vector3(0.03, 0.2, 0.03), Vector3(0.28, h + 0.3, -0.06), Color(0.45, 0.35, 0.25), Vector3(-0.3, 0, -0.3))
			for lx in [-0.18, 0.18]:
				for lz in [-0.08, 0.08]:
					var leg := Mat.box(body, Vector3(0.05, h, 0.05), Vector3(lx, h * 0.5, lz), c.darkened(0.25))
					legs.append(leg)


func take_damage(amount: float, from: Entity) -> void:
	if dead:
		return
	hp -= amount
	flash_bar()
	if from and owner_id < 0:   # los animales de un pueblo no huyen
		flee_t = def["flee"]
		flee_from = from.pos
		_pick_flee_goal()
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	hp = 0
	moving = false
	_death_t = 0.001
	_update_bar_visibility()
	game.on_animal_killed(self)


func _pick_flee_goal() -> void:
	var dir := (pos - flee_from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	for k in 6:
		var g := pos + dir.rotated(_rng.randf_range(-0.8, 0.8)) * 2.5
		if game.map.is_free(MapData.to_tile(g)):
			goal = g
			moving = true
			return
	moving = false


func sim(dt: float) -> void:
	prev_pos = pos
	if dead:
		return
	if being_herded():
		return
	if flee_t > 0.0:
		flee_t -= dt
	if not moving:
		wait_t -= dt
		if wait_t <= 0.0:
			wait_t = _rng.randf_range(2.0, 6.0)
			var roam := 4.0 if owner_id < 0 else 1.6   # los de un pueblo no se alejan
			for k in 5:
				var g := home + Vector2(_rng.randf_range(-roam, roam), _rng.randf_range(-roam, roam))
				if game.map.is_free(MapData.to_tile(g)):
					goal = g
					moving = true
					break
		return
	var sp := speed * (1.8 if flee_t > 0.0 else 1.0)
	var d := goal - pos
	var step := sp * dt
	if d.length() <= step:
		pos = goal
		if not path.is_empty():
			goal = path[0]
			path.remove_at(0)
			return
		moving = false
		if flee_t > 0.0:
			_pick_flee_goal()
		return
	var np := pos + d.normalized() * step
	if not game.map.is_free(MapData.to_tile(np)):
		moving = false
		return
	pos = np


func render(alpha: float, dt: float) -> void:
	var p := prev_pos.lerp(pos, alpha)
	position = Vector3(p.x, MapData.ground_y(p), p.y)
	tick_bar(dt)
	if dead and art:
		var st := 75 if food > max_food * 0.66 else (50 if food > max_food * 0.33 else 25)
		if st != _stage:
			var ps := Art.stage_model(kind, st)
			if ps:
				_stage = st
				body.visible = false
				for ch in visual.get_children():
					if ch != body:
						ch.queue_free()
				var n := Art.fitted(ps, ART_W[kind] * 1.25, false, DEAD_SINK[st])
				n.rotation.y = ART_YAW[kind]
				visual.add_child(n)
		return
	if dead:
		if _death_t < 1.0:
			_death_t = minf(1.0, _death_t + dt * 2.5)
			body.rotation.x = PI * 0.5 * ease(_death_t, 0.4)
			body.position.y = -0.1 * _death_t
		var f := clampf(food / max_food, 0.0, 1.0)
		visual.scale = Vector3.ONE * (0.35 + 0.65 * f)
		return
	var v := pos - prev_pos
	if v.length_squared() > 0.000001:
		visual.rotation.y = -atan2(v.y, v.x)
		_anim += dt * 12.0
		for i in legs.size():
			legs[i].rotation.z = sin(_anim + i * PI * 0.5) * 0.5
		body.position.y = absf(sin(_anim)) * (0.06 if art else 0.03)
		if art:
			body.rotation.x = sin(_anim) * 0.06
	else:
		body.position.y = 0.0
		body.rotation.x = 0.0
		for l in legs:
			l.rotation.z = 0


func take_resource(a: float) -> float:
	if not dead or food <= 0.0:
		return 0.0
	var t := minf(a, food)
	food -= t
	if food <= 0.0:
		game.remove_entity(self)
	return t


func bar_height() -> float:
	return 0.9
