class_name Unit
extends Entity
## Unidad de un jugador (aldeano o militar) con su máquina de estados.
## Aldeano: va al recurso -> recolecta hasta CARRY -> lo lleva al edificio más
## cercano que lo acepte -> regresa. Si se acaba, busca otro igual cerca; si no
## hay, se queda quieto y avisa.

enum S { IDLE, MOVE, GATHER, RETURN, BUILD, ATTACK, DEAD }

var def: Dictionary
var state := S.IDLE
var prev_pos := Vector2.ZERO
var speed := 2.0
var path := PackedVector2Array()
var path_i := 0
var target: Entity = null
var dropoff: Building = null
var attack_move := false
var move_goal := Vector2.ZERO

# trabajo de aldeano
var carry_type := ""
var carry := 0.0
var work_group := ""
var work_pos := Vector2.ZERO
var finish_after_drop := false
var build_queue: Array = []
var idle_notice := ""         # texto del aviso "ya terminé"

var atk_timer := 0.0
var scan_timer := 0.0
var repath_t := 0.0
var fail_count := 0
var _goal_for: Entity = null
var _stuck_t := 0.0

# visual
var visual: Node3D
var body: Node3D
var arm: Node3D
var legs: Array[Node3D] = []
var carry_box: MeshInstance3D
var idle_label: Label3D
var working := false
var _anim := 0.0
var _swing := 0.0
var _death_t := 0.0
var _face := 0.0


func is_unit() -> bool:
	return true


func is_mobile() -> bool:
	return not dead


func is_villager() -> bool:
	return def.get("villager", false)


func is_military() -> bool:
	return not is_villager()


func display_name() -> String:
	return def["name"]


func init(g: Game, k: String, owner: int, p: Vector2) -> void:
	game = g
	kind = k
	owner_id = owner
	def = Defs.UNITS[k]
	var ps: PlayerState = g.players[owner]
	max_hp = def["hp"] * (ps.civ_value("mil_hp", 1.0) if not def.get("villager", false) else 1.0)
	hp = max_hp
	speed = def["speed"] * (ps.civ_value("villager_speed", 1.0) if def.get("villager", false) else 1.0)
	sight = def["sight"]
	radius = 0.28 if k != "jinete" else 0.38
	pos = p
	prev_pos = p
	position = Vector3(p.x, MapData.ground_y(p), p.y)
	_build_visual()


func attack_range() -> float:
	var r: float = def["range"]
	if kind == "arquero":
		r += game.players[owner_id].civ_value("archer_range", 0.0)
	return r


func attack_damage(t: Entity) -> float:
	var a: float = def["atk"]
	if is_military():
		a += game.players[owner_id].civ_value("mil_atk", 0.0)
	var bonus: Dictionary = def.get("bonus_vs", {})
	if bonus.has(t.kind):
		a += bonus[t.kind]
	var armor := 0.0
	if t is Unit:
		armor = t.def["armor"]
	if t is Building:
		a *= 0.6 if kind != "aldeano" else 0.3
	return maxf(1.0, a - armor)


# ---------------- órdenes ----------------

func _reset_task() -> void:
	path.clear()
	path_i = 0
	_goal_for = null
	target = null
	attack_move = false
	finish_after_drop = false
	fail_count = 0
	working = false
	_set_idle_notice("")
	if dropoff and state != S.RETURN:
		dropoff = null
	_leave_farm()


func cmd_stop() -> void:
	_reset_task()
	build_queue.clear()
	state = S.IDLE


func cmd_move(p: Vector2, amove := false) -> void:
	_reset_task()
	build_queue.clear()
	attack_move = amove and is_military()
	move_goal = p
	path = game.map.path_to_tile(pos, MapData.to_tile(p), p)
	path_i = 0
	state = S.MOVE


func cmd_gather(e: Entity) -> void:
	if not is_villager():
		if e is Animal and not e.dead:
			cmd_attack(e)
		else:
			cmd_move(e.center())
		return
	_reset_task()
	build_queue.clear()
	target = e
	work_group = e.res_group()
	work_pos = e.center()
	if e is Building:
		work_group = "granja"
	state = S.GATHER


func cmd_build(b: Building, queue := false) -> void:
	if not is_villager():
		return
	if queue and state == S.BUILD and Entity.live(target):
		build_queue.append(b)
		return
	_reset_task()
	build_queue.clear()
	target = b
	state = S.BUILD


func cmd_attack(e: Entity) -> void:
	_reset_task()
	build_queue.clear()
	target = e
	state = S.ATTACK


## Llevar lo que carga a un edificio concreto.
func cmd_drop(b: Building) -> void:
	if carry <= 0.0:
		cmd_move(b.center())
		return
	var keep := target
	var group := work_group
	_reset_task()
	dropoff = b
	target = keep if Entity.valid(keep) and keep.has_resource() else null
	work_group = group
	finish_after_drop = target == null
	state = S.RETURN


# ---------------- simulación ----------------

func sim(dt: float) -> void:
	prev_pos = pos
	if dead:
		return
	atk_timer -= dt
	working = false
	match state:
		S.IDLE:
			_do_idle(dt)
		S.MOVE:
			if attack_move:
				scan_timer -= dt
				if scan_timer <= 0.0:
					scan_timer = 0.5
					var en := game.find_enemy_near(self, float(sight))
					if en:
						var am := move_goal
						cmd_attack(en)
						attack_move = true
						move_goal = am
						return
			if _follow(dt):
				state = S.IDLE
				if attack_move:
					attack_move = false
		S.GATHER:
			_do_gather(dt)
		S.RETURN:
			_do_return(dt)
		S.BUILD:
			_do_build(dt)
		S.ATTACK:
			_do_attack(dt)


func _do_idle(dt: float) -> void:
	if is_military():
		scan_timer -= dt
		if scan_timer <= 0.0:
			scan_timer = 0.6 + (id % 7) * 0.05
			var en := game.find_enemy_near(self, float(sight))
			if en:
				cmd_attack(en)


func _follow(dt: float) -> bool:
	var step := speed * dt
	while step > 0.0 and path_i < path.size():
		var t: Vector2 = path[path_i]
		var d := t - pos
		var l := d.length()
		if l <= step:
			pos = t
			step -= l
			path_i += 1
		else:
			pos += d / l * step
			step = 0.0
	return path_i >= path.size()


func _move_direct(t: Vector2, dt: float) -> bool:
	var d := t - pos
	var l := d.length()
	if l < 0.001:
		return true
	var np := pos + d / l * minf(l, speed * dt)
	if not game.map.is_free(MapData.to_tile(np)):
		return false
	pos = np
	return true


## 1 = llegó (a distancia "reach"), 0 = en camino, -1 = no puede llegar.
func _approach(e: Entity, reach: float, dt: float) -> int:
	if e.dist_to(pos) <= reach:
		path.clear()
		path_i = 0
		_goal_for = null
		fail_count = 0
		_stuck_t = 0.0
		return 1
	if e.is_mobile() and pos.distance_to(e.pos) < 2.5:
		if _move_direct(e.pos, dt):
			return 0
		_goal_for = null
	repath_t -= dt
	var finished := path_i >= path.size()
	var need := _goal_for != e or finished or (e.is_mobile() and repath_t <= 0.0)
	if need:
		if finished and _goal_for == e and repath_t > 0.0:
			_stuck_t += dt
			return 0
		repath_t = 0.8
		if finished and _goal_for == e:
			fail_count += 1
			if fail_count >= 4:
				fail_count = 0
				_goal_for = null
				return -1
		_goal_for = e
		if e is Building and e.def.get("walkable", false):
			path = game.map.path_to_tile(pos, MapData.to_tile(e.center()), e.center())
		elif e.is_static():
			path = game.map.path_to_rect(pos, e.rect)
		else:
			path = game.map.path_to_tile(pos, MapData.to_tile(e.pos), e.pos)
		path_i = 0
		if path.is_empty():
			fail_count += 1
			if fail_count >= 4:
				fail_count = 0
				_goal_for = null
				return -1
			return 0
	_follow(dt)
	return 0


func _face_to(p: Vector2) -> void:
	var d := p - pos
	if d.length_squared() > 0.0001:
		_face = -atan2(d.y, d.x)


func _do_gather(dt: float) -> void:
	if not Entity.valid(target) or (target.dead and not target.has_resource()):
		_find_next()
		return
	if target is Animal and not target.dead:
		# Cazar: perseguir y golpear hasta matarlo.
		var r := _approach(target, 0.7, dt)
		if r == 1:
			working = true
			_face_to(target.pos)
			if atk_timer <= 0.0:
				atk_timer = def["cd"]
				_swing = 1.0
				target.take_damage(def["atk"], self)
		elif r == -1:
			_find_next(target)
		return
	if not target.has_resource():
		_find_next()
		return
	if target is Building:
		if target.worker != null and target.worker != self and Entity.live(target.worker):
			_find_next(target)
			return
	var rt := target.res_type()
	if carry_type != rt:
		carry = 0.0
		carry_type = rt
	if carry >= Defs.CARRY - 0.001:
		_start_return()
		return
	var res := _approach(target, 0.75, dt)
	if res == 1:
		if target is Building:
			target.worker = self
		working = true
		_face_to(target.center())
		work_pos = target.center()
		var rate := game.gather_rate(self, target)
		carry += target.take_resource(rate * dt)
		if carry >= Defs.CARRY - 0.001:
			_start_return()
	elif res == -1:
		_find_next(target)


func _start_return() -> void:
	_leave_farm()
	dropoff = null
	state = S.RETURN
	path.clear()
	_goal_for = null


func _leave_farm() -> void:
	if Entity.valid(target) and target is Building and target.worker == self:
		target.worker = null


func _do_return(dt: float) -> void:
	if carry <= 0.0:
		_after_drop()
		return
	if dropoff == null or not Entity.live(dropoff) or not dropoff.complete:
		dropoff = game.nearest_dropoff(owner_id, carry_type, pos)
		_goal_for = null
		if dropoff == null:
			_go_idle("No hay dónde dejar %s. Construye un edificio que lo reciba." % Defs.RES_NAMES[carry_type].to_lower())
			return
	var r := _approach(dropoff, 0.75, dt)
	if r == 1:
		var amt := carry
		if dropoff.kind != "centro":
			amt *= Defs.CAMP_YIELD
		game.deposit(owner_id, carry_type, amt)
		carry = 0.0
		dropoff = null
		_after_drop()
	elif r == -1:
		dropoff = null


func _after_drop() -> void:
	if finish_after_drop:
		finish_after_drop = false
		_go_idle(_finished_text())
		return
	if Entity.valid(target) and (target.has_resource() or (target is Animal and not target.dead)):
		state = S.GATHER
	else:
		_find_next()


func _finished_text() -> String:
	var names := {"arbol": "árboles", "piedra": "piedra", "oro": "oro", "arbusto": "bayas",
		"caza": "animales", "pesca": "peces", "granja": "granjas libres"}
	return "Aldeano sin trabajo: ya no hay %s cerca. Asígnale otra tarea." % names.get(work_group, "recursos")


## El recurso se acabó: buscar otro del mismo tipo dentro del radio.
func _find_next(exclude: Entity = null) -> void:
	_leave_farm()
	var e := game.find_resource_near(work_group, work_pos, Defs.SEARCH_RADIUS, owner_id, exclude, self)
	if e:
		target = e
		_goal_for = null
		state = S.GATHER
		return
	target = null
	if carry > 0.0:
		finish_after_drop = true
		_start_return()
	else:
		_go_idle(_finished_text())


func _go_idle(msg: String) -> void:
	path.clear()
	target = null
	state = S.IDLE
	_set_idle_notice(msg)
	if msg != "":
		game.notify(owner_id, msg, pos)


func _set_idle_notice(msg: String) -> void:
	idle_notice = msg
	if idle_label:
		idle_label.visible = msg != "" and owner_id == game.local_id


func _do_build(dt: float) -> void:
	if not Entity.live(target) or (target is Building and target.complete):
		var done: Building = target as Building if Entity.valid(target) else null
		if not build_queue.is_empty():
			target = build_queue.pop_front()
			_goal_for = null
			return
		_after_build(done)
		return
	var r := _approach(target, 0.75, dt)
	if r == 1:
		working = true
		_face_to(target.center())
		target.add_progress(dt)
	elif r == -1:
		_go_idle("Un aldeano no puede llegar a la construcción.")


## Al terminar un campamento, el aldeano se pone a trabajar lo que le corresponde.
func _after_build(b: Building) -> void:
	target = null
	if b == null or not Entity.live(b):
		state = S.IDLE
		return
	var group := ""
	match b.kind:
		"maderero":
			group = "arbol"
		"minero":
			var g := game.find_resource_near("oro", b.center(), Defs.CAMP_RADIUS, owner_id)
			group = "oro" if g else "piedra"
		"molino":
			group = "arbusto"
		"granja":
			cmd_gather(b)
			return
	if group != "":
		var e := game.find_resource_near(group, b.center(), Defs.CAMP_RADIUS + 3.0, owner_id, null, self)
		if e:
			cmd_gather(e)
			return
	state = S.IDLE


func _do_attack(dt: float) -> void:
	if not Entity.live(target):
		target = null
		if attack_move:
			var g := move_goal
			cmd_move(g, true)
		else:
			state = S.IDLE
			scan_timer = 0.0
		return
	var rng := attack_range()
	var reach := rng if rng > 0.0 else 0.6
	var r := _approach(target, reach, dt)
	if r == 1:
		working = true
		_face_to(target.center())
		if atk_timer <= 0.0:
			atk_timer = def["cd"]
			_swing = 1.0
			var dmg := attack_damage(target)
			if rng > 0.0:
				game.spawn_projectile(self, target, dmg)
			else:
				target.take_damage(dmg, self)
	elif r == -1:
		state = S.IDLE
		target = null


func take_damage(amount: float, from: Entity) -> void:
	if dead:
		return
	hp -= amount
	flash_bar()
	if hp <= 0.0:
		_die()
		return
	if from and Entity.live(from) and is_military() and (state == S.IDLE or (state == S.MOVE and attack_move)):
		if game.is_enemy(owner_id, from.owner_id):
			cmd_attack(from)
	game.on_attacked(self, from)


func _die() -> void:
	dead = true
	hp = 0
	state = S.DEAD
	_leave_farm()
	_set_idle_notice("")
	if selected:
		set_selected(false)
	_update_bar_visibility()
	_death_t = 0.001
	game.on_unit_died(self)


func is_idle() -> bool:
	return state == S.IDLE and not dead


func status_text() -> String:
	match state:
		S.IDLE:
			return "Sin tarea"
		S.MOVE:
			return "Moviéndose"
		S.GATHER:
			if not Entity.valid(target):
				return "Buscando recurso"
			if target is Animal and not target.dead:
				return "Cazando"
			if target is Building and target.sowing():
				return "Sembrando"
			if target is Building:
				return "Cosechando"
			return "Recolectando %s" % Defs.RES_NAMES.get(target.res_type(), "")
		S.RETURN:
			return "Llevando %s" % Defs.RES_NAMES.get(carry_type, "")
		S.BUILD:
			return "Construyendo"
		S.ATTACK:
			return "Atacando"
	return ""


# ---------------- dibujo ----------------

var built_age := 1


func refresh_age() -> void:
	if dead or game.players[owner_id].age == built_age:
		return
	visual.queue_free()
	idle_label.queue_free()
	legs.clear()
	_build_visual()


func _build_visual() -> void:
	built_age = game.players[owner_id].age
	var age := built_age
	visual = Node3D.new()
	add_child(visual)
	body = Node3D.new()
	visual.add_child(body)
	var team: Color = game.players[owner_id].color
	var wood := Color(0.45, 0.32, 0.2)
	var y0 := 0.0
	if kind == "jinete":
		var horse := Color(0.45, 0.30, 0.18)
		Mat.box(body, Vector3(0.8, 0.32, 0.28), Vector3(0, 0.62, 0), horse)
		Mat.box(body, Vector3(0.18, 0.38, 0.16), Vector3(0.42, 0.85, 0), horse, Vector3(0, 0, -0.5))
		Mat.box(body, Vector3(0.24, 0.12, 0.13), Vector3(0.55, 1.0, 0), horse.darkened(0.1))
		Mat.box(body, Vector3(0.82, 0.06, 0.3), Vector3(0, 0.8, 0), team if age < 5 else Look.GOLD)
		for lx in [-0.3, 0.3]:
			for lz in [-0.1, 0.1]:
				legs.append(Mat.box(body, Vector3(0.07, 0.5, 0.07), Vector3(lx, 0.25, lz), horse.darkened(0.2)))
		y0 = 0.55
	var sk: Array = Defs.CIVS.get(game.players[owner_id].civ, {}).get("look", {}).get("skin", [0.62, 0.42, 0.28])
	var parts := Look.person(body, kind, age, team, y0, Color(sk[0], sk[1], sk[2]))
	arm = parts["arm"]
	for l in parts["legs"]:
		legs.append(l)
	var blade := Color(0.12, 0.12, 0.14) if age < 4 else Color(0.2, 0.2, 0.25)
	match kind:
		"aldeano":
			Mat.box(arm, Vector3(0.04, 0.45, 0.04), Vector3(0.08, -0.25, 0), wood, Vector3(0, 0, 1.2))
			Mat.box(arm, Vector3(0.1, 0.06, 0.06), Vector3(0.28, -0.32, 0), Color(0.35, 0.35, 0.38))
		"guerrero":
			# macuahuitl (en era 1, un garrote)
			Mat.box(arm, Vector3(0.05, 0.5, 0.04), Vector3(0.1, -0.3, 0), wood, Vector3(0, 0, 0.9))
			if age >= 2:
				Mat.box(arm, Vector3(0.02, 0.4, 0.06), Vector3(0.12, -0.3, 0), blade, Vector3(0, 0, 0.9))
			if age >= 2:
				var sh := Mat.cyl(body, 0.17, 0.17, 0.04, Vector3(0.02, y0 + 0.52, -0.2), team.lightened(0.2) if age < 5 else Look.GOLD, 10)
				sh.rotation.x = PI * 0.5
		"lancero":
			Mat.box(arm, Vector3(0.03, 1.3, 0.03), Vector3(0.0, -0.1, 0), wood, Vector3(0, 0, 1.4))
			Mat.box(arm, Vector3(0.12, 0.05, 0.05), Vector3(0.66, 0.0, 0), blade, Vector3(0, 0, 1.4))
		"arquero":
			Mat.box(arm, Vector3(0.03, 0.6, 0.03), Vector3(0.12, -0.15, 0), Color(0.40, 0.25, 0.12))
			Mat.box(body, Vector3(0.08, 0.32, 0.08), Vector3(-0.14, y0 + 0.6, 0.05), Color(0.5, 0.35, 0.2), Vector3(0.3, 0, 0))
		"jinete":
			Mat.box(arm, Vector3(0.03, 1.1, 0.03), Vector3(0.1, -0.1, 0), wood, Vector3(0, 0, 1.3))
	carry_box = Mat.box(body, Vector3(0.14, 0.14, 0.14), Vector3(-0.17, y0 + 0.58, 0), Color.WHITE)
	carry_box.visible = false
	idle_label = Label3D.new()
	idle_label.text = "!"
	idle_label.font_size = 64
	idle_label.outline_size = 12
	idle_label.modulate = Color(1, 0.85, 0.2)
	idle_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	idle_label.no_depth_test = true
	idle_label.position = Vector3(0, y0 + 1.35, 0)
	idle_label.pixel_size = 0.006
	idle_label.visible = idle_notice != "" and owner_id == game.local_id
	add_child(idle_label)


func render(alpha: float, dt: float) -> void:
	if dead:
		_death_t += dt
		if _death_t < 1.0:
			body.rotation.x = PI * 0.5 * ease(minf(_death_t * 2.0, 1.0), 0.4)
		elif _death_t > 5.0:
			body.position.y = -(_death_t - 5.0) * 0.3
			if _death_t > 7.0:
				queue_free()
		return
	var p := prev_pos.lerp(pos, alpha)
	position = Vector3(p.x, MapData.ground_y(p), p.y)
	tick_bar(dt)
	var v := pos - prev_pos
	var walking := v.length_squared() > 0.000001
	if walking:
		_face = -atan2(v.y, v.x)
	visual.rotation.y = lerp_angle(visual.rotation.y, _face, minf(1.0, dt * 14.0))
	if walking:
		_anim += dt * 11.0
		for i in legs.size():
			legs[i].rotation.z = sin(_anim + i * PI) * 0.6
		body.position.y = absf(sin(_anim)) * 0.03
	else:
		for l in legs:
			l.rotation.z = lerpf(l.rotation.z, 0.0, dt * 8.0)
		body.position.y = 0
	# brazo: golpe al trabajar/atacar
	if working:
		if is_villager() and state != S.ATTACK and not (Entity.valid(target) and target is Animal and not target.dead):
			_swing = maxf(_swing, 0.0)
			arm.rotation.z = -absf(sin(Time.get_ticks_msec() * 0.008 + id)) * 1.6
		else:
			_swing = maxf(0.0, _swing - dt * 3.0)
			arm.rotation.z = -sin(_swing * PI) * 1.8
	else:
		arm.rotation.z = lerpf(arm.rotation.z, 0.0, dt * 8.0)
	carry_box.visible = carry > 0.5
	if carry_box.visible:
		carry_box.material_override = Mat.of(Defs.RES_COLORS.get(carry_type, Color.WHITE))
		var s := 0.5 + 0.5 * clampf(carry / Defs.CARRY, 0, 1)
		carry_box.scale = Vector3.ONE * s


func bar_height() -> float:
	return 1.25 if kind != "jinete" else 1.8
