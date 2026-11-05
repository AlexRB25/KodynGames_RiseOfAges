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
	return def["name"] + (" (cazado)" if dead else "")


func init(g: Game, k: String, p: Vector2, seed_v: int) -> void:
	game = g
	kind = k
	def = Defs.ANIMALS[k]
	max_hp = def["hp"]
	hp = max_hp
	food = def["food"]
	max_food = food
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
	if from:
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
	if flee_t > 0.0:
		flee_t -= dt
	if not moving:
		wait_t -= dt
		if wait_t <= 0.0:
			wait_t = _rng.randf_range(2.0, 6.0)
			for k in 5:
				var g := home + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
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
		body.position.y = absf(sin(_anim)) * 0.03
	else:
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
