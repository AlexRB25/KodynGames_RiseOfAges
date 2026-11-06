class_name Building
extends Entity
## Edificio de un jugador. Empieza como cimiento con andamio; los aldeanos lo
## levantan. Completo: recibe recursos, entrena unidades, investiga la era y las
## mejoras, dispara (torre/centro/castillo) o cura (monasterio). Cambia de aspecto
## por era; torre, muralla y puerta además por nivel (mejoras).

var def: Dictionary
var complete := false
var progress := 0.0          # 0..1 de construcción
var queue: Array = []        # tipos de unidad o "era"
var train_t := 0.0
var waiting_pop := false
var rally := Vector2.INF
var rally_ent: Entity = null
var atk_timer := 0.0
var heal_timer := 0.0
var food := 0.0              # granjas
var worker: Unit = null      # granjas: quién la trabaja
var sow := 0.0               # granjas: avance de la siembra (0..1); en 1 se cosecha
var visual: Node3D
var scaffold: Node3D
var built_age := 1
var built_level := 0
var garrison: Array = []     # arqueros dentro (torres)
var relics: Array = []       # reliquias guardadas (maravilla)
var thorn_t := 0.0
var waiting_santo := false
var _flag: Node3D
var _crops: Node3D


func is_building() -> bool:
	return true


func is_static() -> bool:
	return true


func display_name() -> String:
	return Lang.t(stat("name", def["name"]))


## Dato del edificio según el nivel del dueño (torre, muralla, puerta) o el de siempre.
func stat(key: String, default_v = null):
	return Defs.bstat(kind, game.players[owner_id].techs, key, default_v)


func level() -> int:
	return Defs.level_of(kind, game.players[owner_id].techs)


## Lugares libres para arqueros dentro (torres de guardia).
func garrison_space() -> int:
	if not complete:
		return 0
	return int(stat("garrison", 0)) - garrison.size()


func blocks() -> bool:
	return not def.get("walkable", false)


func init(g: Game, k: String, owner: int, tile: Vector2i, done: bool) -> void:
	game = g
	kind = k
	owner_id = owner
	def = Defs.BUILDINGS[k]
	var sz: int = def["size"]
	rect = Rect2i(tile, Vector2i(sz, sz))
	pos = center()
	position = Vector3(pos.x, MapData.active.tile_h(tile) if MapData.active else 0.0, pos.y)
	radius = sz * 0.5
	sight = int(stat("sight", def["sight"]))
	max_hp = _hp_for_age()
	food = def.get("food", 0.0)
	if done:
		complete = true
		progress = 1.0
		hp = max_hp
	else:
		hp = max_hp * 0.1
	built_age = game.players[owner].age
	built_level = level()
	_build_visual()


func _hp_for_age() -> float:
	var p: PlayerState = game.players[owner_id]
	var base: float = float(stat("hp", def["hp"])) * p.civ_value("bld_hp", 1.0) * (1.0 + Defs.tech_sum(p.techs, "bld_hp"))
	return base * (1.0 + Defs.AGE_HP * (p.age - 1))


## Llamado por los aldeanos cada paso mientras construyen.
func add_progress(dt: float) -> void:
	if complete:
		return
	var t: float = def["time"]
	var before := progress
	progress = minf(1.0, progress + dt * game.players[owner_id].civ_value("build_speed", 1.0) / t)
	hp = minf(max_hp, hp + (progress - before) * max_hp * 0.9)
	_refresh_construction()
	if progress >= 1.0:
		complete = true
		_refresh_construction()
		game.on_building_complete(self)


func on_age_up() -> void:
	var old := max_hp
	max_hp = _hp_for_age()
	hp += max_hp - old
	if complete and game.players[owner_id].age != built_age:
		built_age = game.players[owner_id].age
		_rebuild_visual()


## Se investigó una mejora: vida y aspecto según el nuevo nivel.
func on_tech() -> void:
	var old := max_hp
	max_hp = _hp_for_age()
	hp += max_hp - old
	sight = int(stat("sight", def["sight"]))
	if level() != built_level:
		built_level = level()
		if visual:
			_rebuild_visual()


func can_train(k: String) -> bool:
	return complete and def.get("trains", []).has(k)


func enqueue(k: String) -> void:
	queue.append(k)
	if queue.size() == 1:
		train_t = 0.0


func train_time(k: String) -> float:
	if k == "era":
		return Defs.AGES[game.players[owner_id].age]["time"]
	if k.begins_with("tech:"):
		return Defs.TECHS[k.trim_prefix("tech:")]["time"]
	if k == "reliquia":
		return Defs.RELIC_TIME
	var t: float = Defs.UNITS[k]["time"]
	if k != "aldeano":
		t *= game.players[owner_id].civ_value("mil_train", 1.0)
	return t


func cancel_last() -> void:
	if queue.is_empty():
		return
	var k: String = queue.pop_back()
	game.refund(owner_id, k, self)
	if queue.is_empty():
		train_t = 0.0


func queue_progress() -> float:
	if queue.is_empty():
		return 0.0
	return clampf(train_t / train_time(queue[0]), 0.0, 1.0)


func sim(dt: float) -> void:
	if dead or not complete:
		return
	if kind == "corral":
		_graze(dt)
	# entrenamiento / investigación
	if not queue.is_empty():
		var k: String = queue[0]
		var is_unit := Defs.UNITS.has(k)
		if is_unit and not game.has_pop_room(owner_id):
			if not waiting_pop:
				waiting_pop = true
				game.notify(owner_id, Lang.t("Necesitas más casas para entrenar."), pos)
		elif k == "reliquia" and game.santo_near(self) == null:
			# La reliquia la hace un santo: sin santo junto al monasterio, no avanza.
			if not waiting_santo:
				waiting_santo = true
				game.notify(owner_id, Lang.t("Para crear la reliquia necesitas un santo junto al monasterio."), pos)
		else:
			waiting_pop = false
			waiting_santo = false
			train_t += dt * game.players[owner_id].speed_mult()
			if train_t >= train_time(k):
				train_t = 0.0
				queue.pop_front()
				if k == "era":
					game.advance_age(owner_id)
				elif k.begins_with("tech:"):
					game.finish_tech(owner_id, k.trim_prefix("tech:"))
				elif k == "reliquia":
					game.spawn_relic(owner_id, self)
				else:
					game.spawn_trained(self, k)
	# disparar (y los arqueros de adentro, una flecha más cada uno)
	var atk: float = float(stat("atk", 0.0))
	if atk > 0.0 or not garrison.is_empty():
		atk_timer -= dt
		if atk_timer <= 0.0:
			var rng: float = float(stat("range", 7.0))
			var en := game.find_enemy_near(self, rng)
			if en:
				atk_timer = float(stat("cd", 2.0))
				var p: PlayerState = game.players[owner_id]
				var ranged := Defs.tech_sum(p.techs, "ranged")
				if atk > 0.0:
					var dmg := atk
					if kind == "torre":
						dmg += p.civ_value("tower_atk", 0.0) + ranged
					game.spawn_projectile(self, en, dmg, float(stat("splash", 0.0)))
				for u in garrison:
					var en2 := game.find_enemy_near(self, rng + 1.0)
					if en2:
						game.spawn_projectile(self, en2, float(u.def["atk"]) + ranged, 0.0)
			else:
				atk_timer = 0.5
	# muro de púas: lastima a los enemigos pegados
	var thorns: float = float(stat("thorns", 0.0))
	if thorns > 0.0:
		thorn_t -= dt
		if thorn_t <= 0.0:
			thorn_t = 1.0
			for u in game.units_near(center(), 1.4):
				if game.is_enemy(owner_id, u.owner_id) and not u.is_naval():
					u.take_damage(thorns, self)
	# curar
	if def.has("heal"):
		heal_timer -= dt
		if heal_timer <= 0.0:
			heal_timer = 1.0
			for u in game.units_near(pos, 7.0):
				if u.owner_id == owner_id and u.hp < u.max_hp:
					u.hp = minf(u.max_hp, u.hp + def["heal"])
					u.refresh_bar()


## Granjas y trampas para peces: la comida se va acabando.
func has_resource() -> bool:
	return (kind == "granja" or kind == "trampa") and complete and food > 0.0 and not removed


func res_type() -> String:
	return "comida" if kind == "granja" or kind == "trampa" else ""


func res_group() -> String:
	return kind if kind == "granja" or kind == "trampa" else ""


func remaining() -> float:
	return food


func sowing() -> bool:
	return kind == "granja" and sow < 1.0


## Granja: primero se siembra (no da alimento), después se cosecha.
func take_resource(a: float) -> float:
	if not has_resource():
		return 0.0
	if kind == "trampa":
		var tt := minf(a, food)
		food -= tt
		if food <= 0.0:
			game.notify(owner_id, Lang.t("Una trampa para peces se vació. Pon otra desde el muelle."), pos)
			game.destroy_building(self, false)
		return tt
	if sow < 1.0:
		sow = minf(1.0, sow + a / Defs.FARM_RATE / Defs.SOW_TIME)
		_refresh_crops()
		return 0.0
	var t := minf(a, food)
	food -= t
	_refresh_crops()
	if food <= 0.0:
		var p: PlayerState = game.players[owner_id]
		if p.seeds > 0:
			p.seeds -= 1
			food = def["food"]
			sow = 0.0
			_refresh_crops()
			game.notify(owner_id, Lang.t("Granja resembrada (quedan %d siembras).") % p.seeds, pos)
		else:
			game.notify(owner_id, Lang.t("Una granja se agotó. Compra siembra en el Centro."), pos)
			game.destroy_building(self, false)
	return t


func take_damage(amount: float, from: Entity) -> void:
	if dead:
		return
	hp -= amount
	flash_bar()
	game.on_attacked(self, from)
	if hp <= 0.0:
		game.destroy_building(self, true)


func bar_height() -> float:
	return 1.2 + def["size"] * 0.5


# ---------------- dibujo ----------------

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	_rebuild_visual()
	scaffold = Node3D.new()
	add_child(scaffold)
	var s: float = def["size"]
	var wood := Color(0.55, 0.40, 0.22)
	var hh := 0.6 + s * 0.35
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			Mat.box(scaffold, Vector3(0.07, hh, 0.07), Vector3(cx * s * 0.47, hh * 0.5, cz * s * 0.47), wood)
	for z in [-1, 1]:
		Mat.box(scaffold, Vector3(s * 0.95, 0.05, 0.05), Vector3(0, hh * 0.6, z * s * 0.47), wood)
		Mat.box(scaffold, Vector3(0.05, 0.05, s * 0.95), Vector3(z * s * 0.47, hh * 0.85, 0), wood)
	Mat.box(scaffold, Vector3(s * 0.9, 0.04, s * 0.9), Vector3(0, 0.03, 0), Color(0.5, 0.42, 0.3))
	# Barrita de construcción: verde lo hecho, verde oscuro lo que falta. Siempre mira a la cámara.
	_build_bar = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9 + s * 0.35, 0.16)
	_build_bar.mesh = q
	_build_mat = ShaderMaterial.new()
	_build_mat.shader = _bar_shader()
	_build_bar.material_override = _build_mat
	_build_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_bar.position = Vector3(0, bar_height() + 0.35, 0)
	add_child(_build_bar)
	_refresh_construction()


var _build_bar: MeshInstance3D
var _build_mat: ShaderMaterial
static var _bar_sh: Shader


static func _bar_shader() -> Shader:
	if _bar_sh == null:
		_bar_sh = Shader.new()
		_bar_sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
uniform float progress = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec3 c = UV.x < progress ? vec3(0.25, 0.9, 0.3) : vec3(0.04, 0.18, 0.06);
	if (UV.y < 0.14 || UV.y > 0.86 || UV.x < 0.015 || UV.x > 0.985) c = vec3(0.0);
	ALBEDO = c;
}
"""
	return _bar_sh


func _refresh_construction() -> void:
	if _build_bar:
		_build_bar.visible = not complete
		_build_mat.set_shader_parameter("progress", progress)
	if scaffold:
		scaffold.visible = not complete
	if visual:
		var f := 1.0 if complete else (0.08 + 0.92 * progress)
		visual.scale = Vector3(1, f, 1)


func _rebuild_visual() -> void:
	for c in visual.get_children():
		c.queue_free()
	var age: int = game.players[owner_id].age
	var team: Color = game.players[owner_id].color
	var s: float = def["size"]
	var pal := Look.palette(age)
	var stone_age := age >= 3
	var wall_c: Color = pal["wall"]
	var thatch := Color(0.78, 0.64, 0.34)
	var roof_c: Color = pal["roof"]
	var trim: Color = pal["trim"]
	var stone: Color = pal["stone"]
	var wood := Color(0.50, 0.35, 0.20)
	var v := visual
	# Modelo 3D del arte (assets/modelos/<civ>/<edificio>/nivelN.glb), si existe.
	var ms := Art.model(game.players[owner_id].civ, kind, age)
	if ms:
		v.add_child(Art.fitted(ms, s * 0.96))
		# Franja del color del jugador en la base, para saber de quién es.
		var hb := s * 0.49
		for z in [-hb, hb]:
			Mat.box(v, Vector3(s * 0.98, 0.06, 0.1), Vector3(0, 0.03, z), team)
		for x in [-hb, hb]:
			Mat.box(v, Vector3(0.1, 0.06, s * 0.98), Vector3(x, 0.03, 0), team)
		return
	match kind:
		"centro":
			# Pirámide escalonada con templo arriba.
			var steps := 3 + (1 if age >= 2 else 0) + (1 if age >= 4 else 0)
			for i in steps:
				var w := s * (0.95 - i * 0.15)
				Mat.box(v, Vector3(w, 0.45, w), Vector3(0, 0.225 + i * 0.45, 0), stone.lightened(0.04 * i))
			# escalinata al frente
			var top := steps * 0.45
			var run := s * 0.5
			var slope := atan2(top, run)
			var st := Mat.box(v, Vector3(sqrt(top * top + run * run), 0.12, 0.8), Vector3(s * 0.25, top * 0.5, 0), stone.darkened(0.12))
			st.rotation.z = -slope
			Mat.box(v, Vector3(1.0, 0.6, 1.0), Vector3(0, top + 0.3, 0), wall_c)
			Mat.roof(v, Vector3(1.2, 0.5, 1.2), Vector3(0, top + 0.85, 0), roof_c)
			Mat.box(v, Vector3(1.02, 0.12, 1.02), Vector3(0, top + 0.5, 0), team)
		"casa":
			match age:
				1:
					# choza redonda de bajareque con techo de paja
					Mat.cyl(v, 0.62, 0.68, 0.6, Vector3(0, 0.3, 0), wall_c, 8)
					Mat.cyl(v, 0.0, 0.95, 0.9, Vector3(0, 1.05, 0), roof_c, 8)
					Mat.box(v, Vector3(0.05, 0.4, 0.28), Vector3(0.66, 0.2, 0), wood)
				2:
					# casa de adobe con techo de paja a cuatro aguas
					Mat.box(v, Vector3(1.4, 0.7, 1.2), Vector3(0, 0.35, 0), wall_c)
					var hr := Mat.cyl(v, 0.0, 1.05, 0.8, Vector3(0, 1.1, 0), roof_c, 4)
					hr.rotation.y = PI * 0.25
					Mat.box(v, Vector3(0.05, 0.4, 0.3), Vector3(0.71, 0.2, 0), wood)
				3:
					# piedra con techo de teja
					Mat.box(v, Vector3(1.5, 0.12, 1.3), Vector3(0, 0.06, 0), stone.darkened(0.1))
					Mat.box(v, Vector3(1.4, 0.75, 1.2), Vector3(0, 0.48, 0), wall_c)
					Mat.roof(v, Vector3(1.6, 0.55, 1.4), Vector3(0, 1.13, 0), roof_c)
					Mat.box(v, Vector3(0.05, 0.45, 0.3), Vector3(0.71, 0.32, 0), wood)
				_:
					# estuco de dos niveles (era 5 con adornos dorados)
					Mat.box(v, Vector3(1.6, 0.15, 1.4), Vector3(0, 0.07, 0), stone)
					Mat.box(v, Vector3(1.5, 0.7, 1.3), Vector3(0, 0.5, 0), wall_c)
					Mat.box(v, Vector3(1.0, 0.5, 0.9), Vector3(-0.15, 1.1, 0), wall_c)
					Mat.box(v, Vector3(1.52, 0.08, 1.32), Vector3(0, 0.86, 0), trim)
					Mat.roof(v, Vector3(1.15, 0.4, 1.0), Vector3(-0.15, 1.55, 0), roof_c)
					Mat.box(v, Vector3(0.05, 0.45, 0.3), Vector3(0.76, 0.37, 0), wood)
			Mat.box(v, Vector3(0.3, 0.06, 0.04), Vector3(0.3, 0.15, 0.62), team)
		"mercado":
			Mat.box(v, Vector3(s * 0.9, 0.1, s * 0.9), Vector3(0, 0.05, 0), stone)
			for i in 3:
				var x := -0.9 + i * 0.9
				for z in [-0.35, 0.35]:
					Mat.box(v, Vector3(0.06, 0.8, 0.06), Vector3(x - 0.3, 0.4, z), wood)
					Mat.box(v, Vector3(0.06, 0.8, 0.06), Vector3(x + 0.3, 0.4, z), wood)
				Mat.roof(v, Vector3(0.8, 0.3, 0.9), Vector3(x, 0.95, 0), [team, Color(0.9, 0.85, 0.7), roof_c][i])
				Mat.box(v, Vector3(0.5, 0.2, 0.4), Vector3(x, 0.2, 0.9), [Defs.RES_COLORS["comida"], Defs.RES_COLORS["oro"], Color(0.4, 0.6, 0.25)][i])
		"maderero":
			for x in [-0.7, 0.7]:
				for z in [-0.6, 0.6]:
					Mat.box(v, Vector3(0.08, 0.9, 0.08), Vector3(x, 0.45, z), wood)
			Mat.roof(v, Vector3(1.7, 0.45, 1.5), Vector3(0, 1.1, 0), roof_c)
			for i in 3:
				var lg := Mat.cyl(v, 0.1, 0.1, 1.2, Vector3(-0.2, 0.12 + i * 0.18, -0.25 + i * 0.12), wood.lightened(0.1), 6)
				lg.rotation.x = PI * 0.5
			Mat.box(v, Vector3(0.3, 0.1, 0.3), Vector3(0.6, 1.4, 0), team)
		"minero":
			for x in [-0.7, 0.7]:
				for z in [-0.6, 0.6]:
					Mat.box(v, Vector3(0.08, 0.9, 0.08), Vector3(x, 0.45, z), wood)
			Mat.roof(v, Vector3(1.7, 0.45, 1.5), Vector3(0, 1.1, 0), roof_c)
			Mat.box(v, Vector3(0.4, 0.3, 0.4), Vector3(-0.3, 0.15, 0.2), Defs.RES_COLORS["oro"])
			Mat.box(v, Vector3(0.45, 0.35, 0.4), Vector3(0.25, 0.17, -0.2), Defs.RES_COLORS["piedra"])
			Mat.box(v, Vector3(0.3, 0.1, 0.3), Vector3(0.6, 1.4, 0), team)
		"molino":
			Mat.cyl(v, 0.7, 0.8, 1.0, Vector3(0, 0.5, 0), wall_c, 10)
			Mat.cyl(v, 0.0, 0.95, 0.8, Vector3(0, 1.4, 0), roof_c, 10)
			Mat.cyl(v, 0.82, 0.82, 0.08, Vector3(0, 0.95, 0), team, 10)
			Mat.box(v, Vector3(0.05, 0.4, 0.3), Vector3(0.79, 0.2, 0), wood)
		"corral":
			# Cerca de troncos con una entrada, paja en el suelo y un bebedero.
			Mat.box(v, Vector3(s * 0.96, 0.03, s * 0.96), Vector3(0, 0.015, 0), Color(0.72, 0.62, 0.35))
			var hs := s * 0.48
			for i in 7:
				var t := -hs + i * (hs * 2.0 / 6.0)
				for side in [Vector3(t, 0, -hs), Vector3(t, 0, hs), Vector3(-hs, 0, t), Vector3(hs, 0, t)]:
					if side.x == hs and absf(side.z) < 0.5:
						continue   # entrada
					Mat.box(v, Vector3(0.09, 0.55, 0.09), side + Vector3(0, 0.27, 0), wood)
			for z in [-hs, hs]:
				Mat.box(v, Vector3(s * 0.96, 0.06, 0.05), Vector3(0, 0.42, z), wood.lightened(0.1))
				Mat.box(v, Vector3(s * 0.96, 0.06, 0.05), Vector3(0, 0.22, z), wood.lightened(0.1))
			Mat.box(v, Vector3(0.05, 0.06, s * 0.96), Vector3(-hs, 0.42, 0), wood.lightened(0.1))
			Mat.box(v, Vector3(0.05, 0.06, s * 0.96), Vector3(-hs, 0.22, 0), wood.lightened(0.1))
			for z in [-hs * 0.6, hs * 0.6]:
				Mat.box(v, Vector3(0.05, 0.06, hs * 0.75), Vector3(hs, 0.42, z), wood.lightened(0.1))
			Mat.box(v, Vector3(0.9, 0.2, 0.3), Vector3(-0.6, 0.1, -0.8), wood.darkened(0.2))
			Mat.box(v, Vector3(0.8, 0.04, 0.2), Vector3(-0.6, 0.19, -0.8), Color(0.25, 0.5, 0.65))
			Mat.box(v, Vector3(0.3, 0.06, 0.04), Vector3(hs + 0.05, 0.6, 0.6), team)
		"granja":
			Mat.box(v, Vector3(1.94, 0.04, 1.94), Vector3(0, 0.02, 0), Color(0.45, 0.32, 0.18))
			_crops = Node3D.new()
			v.add_child(_crops)
			for i in 4:
				Mat.box(_crops, Vector3(1.7, 0.16, 0.2), Vector3(0, 0.08, -0.69 + i * 0.46), Color(0.55, 0.62, 0.22))
			for x in [-0.97, 0.97]:
				Mat.box(v, Vector3(0.05, 0.22, 1.94), Vector3(x, 0.11, 0), wood)
			_refresh_crops()
		"cuartel", "arqueria", "establo":
			Mat.box(v, Vector3(s * 0.85, 0.9, s * 0.7), Vector3(0, 0.45, -0.2), wall_c)
			Mat.roof(v, Vector3(s * 0.95, 0.6, s * 0.8), Vector3(0, 1.2, -0.2), roof_c)
			Mat.box(v, Vector3(s * 0.86, 0.1, s * 0.71), Vector3(0, 0.82, -0.2), team)
			match kind:
				"cuartel":
					for i in 3:
						Mat.box(v, Vector3(0.04, 0.8, 0.04), Vector3(-0.6 + i * 0.6, 0.4, 1.1), wood, Vector3(0.3, 0, 0))
				"arqueria":
					var tg := Mat.cyl(v, 0.35, 0.35, 0.06, Vector3(0.5, 0.45, 1.1), Color(0.9, 0.85, 0.7), 10)
					tg.rotation.x = PI * 0.5
					var bull := Mat.cyl(v, 0.15, 0.15, 0.07, Vector3(0.5, 0.45, 1.1), Color(0.8, 0.15, 0.1), 10)
					bull.rotation.x = PI * 0.5
				"establo":
					for x in [-1.3, 1.3]:
						Mat.box(v, Vector3(0.05, 0.4, 1.2), Vector3(x, 0.2, 0.8), wood)
					Mat.box(v, Vector3(2.6, 0.05, 0.05), Vector3(0, 0.35, 1.4), wood)
		"torre":
			var lv := level()
			if lv == 0:
				# puesto de avanzada: plataforma de madera sobre cuatro postes
				for cx in [-0.4, 0.4]:
					for cz in [-0.4, 0.4]:
						Mat.box(v, Vector3(0.1, 2.0, 0.1), Vector3(cx, 1.0, cz), wood)
				Mat.box(v, Vector3(1.1, 0.1, 1.1), Vector3(0, 2.0, 0), wood.lightened(0.1))
				for z in [-0.5, 0.5]:
					Mat.box(v, Vector3(1.1, 0.3, 0.05), Vector3(0, 2.2, z), wood)
				var tr0 := Mat.cyl(v, 0.0, 0.8, 0.5, Vector3(0, 2.6, 0), thatch, 4)
				tr0.rotation.y = PI * 0.25
				Mat.box(v, Vector3(0.3, 0.2, 0.03), Vector3(0.2, 2.95, 0), team)
			else:
				var c := stone if lv >= 2 else stone.lightened(0.05)
				var hgt := 2.6 + 0.4 * lv
				Mat.box(v, Vector3(1.2, hgt, 1.2), Vector3(0, hgt * 0.5, 0), c)
				Mat.box(v, Vector3(1.5, 0.3, 1.5), Vector3(0, hgt + 0.1, 0), c.lightened(0.1))
				for cx in [-0.6, 0.6]:
					for cz in [-0.6, 0.6]:
						Mat.box(v, Vector3(0.25, 0.25, 0.25), Vector3(cx, hgt + 0.35, cz), c.lightened(0.1))
				if lv == 3:
					# bombarda: cañón de bronce asomado
					var gun := Mat.cyl(v, 0.12, 0.16, 0.9, Vector3(0.6, hgt + 0.3, 0), Color(0.55, 0.42, 0.2), 8)
					gun.rotation.z = PI * 0.5
				else:
					var tr := Mat.cyl(v, 0.0, 1.0, 0.7, Vector3(0, hgt + 0.6, 0), roof_c, 4)
					tr.rotation.y = PI * 0.25
				Mat.box(v, Vector3(1.22, 0.15, 1.22), Vector3(0, hgt * 0.8, 0), team)
		"muralla", "puerta":
			var lv := level()
			var c := wood if lv == 0 else (stone if lv == 1 else stone.darkened(0.08))
			var hgt := 1.3 + 0.2 * lv
			if kind == "puerta":
				# dos pilares y un dintel; el hueco se ve abierto
				for x in [-0.38, 0.38]:
					Mat.box(v, Vector3(0.24, hgt, 1.0), Vector3(x, hgt * 0.5, 0), c)
				Mat.box(v, Vector3(1.0, 0.3, 1.0), Vector3(0, hgt - 0.15, 0), c.lightened(0.08))
				Mat.box(v, Vector3(0.52, hgt - 0.3, 0.08), Vector3(0, (hgt - 0.3) * 0.5, 0), wood.darkened(0.15) if lv == 0 else Color(0.35, 0.3, 0.25))
				Mat.box(v, Vector3(0.5, 0.08, 0.1), Vector3(0, hgt - 0.5, 0.05), team)
			elif lv == 0:
				# empalizada: troncos con punta
				for x in [-0.33, 0.0, 0.33]:
					for z in [-0.33, 0.0, 0.33]:
						if absf(x) + absf(z) > 0.5:
							continue
						Mat.cyl(v, 0.13, 0.15, hgt, Vector3(x, hgt * 0.5, z), c.lightened(randf_range(-0.04, 0.04)), 6)
						Mat.cyl(v, 0.0, 0.13, 0.25, Vector3(x, hgt + 0.12, z), c.lightened(0.1), 6)
			else:
				Mat.box(v, Vector3(1.0, hgt, 1.0), Vector3(0, hgt * 0.5, 0), c)
				Mat.box(v, Vector3(0.3, 0.25, 0.3), Vector3(0.3, hgt + 0.12, 0.3), c.lightened(0.08))
				Mat.box(v, Vector3(0.3, 0.25, 0.3), Vector3(-0.3, hgt + 0.12, -0.3), c.lightened(0.08))
				if lv == 3:
					for a in 6:
						var sp := Mat.cyl(v, 0.0, 0.05, 0.4, Vector3(0.5 * cos(a), 0.6, 0.5 * sin(a)), Color(0.3, 0.3, 0.32), 4)
						sp.rotation = Vector3(0, -a, PI * 0.5)
		"muelle":
			# plataforma de madera sobre el agua con postes y una caseta
			Mat.box(v, Vector3(s * 0.96, 0.15, s * 0.96), Vector3(0, 0.08, 0), wood.lightened(0.1))
			for cx in [-1, 1]:
				for cz in [-1, 1]:
					Mat.cyl(v, 0.1, 0.1, 0.9, Vector3(cx * s * 0.45, -0.25, cz * s * 0.45), wood.darkened(0.2), 6)
			Mat.box(v, Vector3(1.4, 0.9, 1.2), Vector3(-0.5, 0.6, -0.5), wall_c)
			Mat.roof(v, Vector3(1.6, 0.5, 1.4), Vector3(-0.5, 1.3, -0.5), roof_c)
			Mat.box(v, Vector3(0.6, 0.3, 0.4), Vector3(0.7, 0.3, 0.7), Color(0.35, 0.55, 0.7))
			Mat.box(v, Vector3(1.42, 0.1, 1.22), Vector3(-0.5, 1.0, -0.5), team)
		"trampa":
			# cerco de varas en el agua
			var hs2 := s * 0.45
			for i in 8:
				var t2 := -hs2 + i * (hs2 * 2.0 / 7.0)
				for side in [Vector3(t2, 0, -hs2), Vector3(t2, 0, hs2), Vector3(-hs2, 0, t2), Vector3(hs2, 0, t2)]:
					Mat.box(v, Vector3(0.06, 0.6, 0.06), side + Vector3(0, 0.1, 0), wood)
			for z in [-hs2, hs2]:
				Mat.box(v, Vector3(s * 0.9, 0.04, 0.04), Vector3(0, 0.3, z), wood.lightened(0.1))
			Mat.box(v, Vector3(s * 0.85, 0.02, s * 0.85), Vector3(0, 0.0, 0), Color(0.28, 0.42, 0.45))
			Mat.box(v, Vector3(0.25, 0.05, 0.04), Vector3(hs2, 0.45, 0), team)
		"herreria":
			Mat.box(v, Vector3(s * 0.85, 0.9, s * 0.75), Vector3(0, 0.45, -0.1), wall_c)
			Mat.roof(v, Vector3(s * 0.95, 0.55, s * 0.85), Vector3(0, 1.15, -0.1), roof_c)
			Mat.box(v, Vector3(0.5, 1.6, 0.5), Vector3(0.8, 1.0, -0.6), stone.darkened(0.15))   # chimenea
			Mat.box(v, Vector3(0.5, 0.3, 0.3), Vector3(0.2, 0.15, 1.1), Color(0.25, 0.25, 0.28))  # yunque
			Mat.box(v, Vector3(0.3, 0.2, 0.3), Vector3(-0.6, 0.1, 1.1), Color(0.9, 0.4, 0.1))    # brasas
			Mat.box(v, Vector3(s * 0.86, 0.1, s * 0.76), Vector3(0, 0.82, -0.1), team)
		"universidad":
			Mat.box(v, Vector3(s * 0.9, 0.2, s * 0.9), Vector3(0, 0.1, 0), stone)
			Mat.box(v, Vector3(s * 0.75, 1.1, s * 0.6), Vector3(0, 0.75, -0.2), wall_c)
			for x in [-0.9, -0.3, 0.3, 0.9]:
				Mat.cyl(v, 0.12, 0.12, 1.1, Vector3(x, 0.75, 0.55), stone.lightened(0.1), 8)
			Mat.box(v, Vector3(s * 0.85, 0.2, s * 0.8), Vector3(0, 1.4, 0), stone.lightened(0.05))
			Mat.cyl(v, 0.0, 0.7, 0.6, Vector3(0, 1.8, -0.2), roof_c, 8)
			Mat.box(v, Vector3(s * 0.86, 0.08, s * 0.81), Vector3(0, 1.3, 0), team)
		"taller":
			Mat.box(v, Vector3(s * 0.8, 0.8, s * 0.6), Vector3(-0.2, 0.4, -0.3), wall_c)
			Mat.roof(v, Vector3(s * 0.9, 0.5, s * 0.7), Vector3(-0.2, 1.05, -0.3), roof_c)
			Mat.box(v, Vector3(s * 0.81, 0.1, s * 0.61), Vector3(-0.2, 0.75, -0.3), team)
			# rueda grande y viga de catapulta
			var wh := Mat.cyl(v, 0.45, 0.45, 0.1, Vector3(0.9, 0.45, 0.9), wood.darkened(0.2), 10)
			wh.rotation.x = PI * 0.5
			Mat.box(v, Vector3(1.4, 0.1, 0.1), Vector3(0.3, 0.6, 1.0), wood, Vector3(0, 0, 0.4))
		"maravilla":
			# gran pirámide escalonada con templo dorado
			for i in 6:
				var w2 := s * (0.98 - i * 0.14)
				Mat.box(v, Vector3(w2, 0.6, w2), Vector3(0, 0.3 + i * 0.6, 0), stone.lightened(0.03 * i))
			var top2 := 6 * 0.6
			var st2 := Mat.box(v, Vector3(4.2, 0.15, 1.2), Vector3(s * 0.25, top2 * 0.5, 0), stone.darkened(0.15))
			st2.rotation.z = -atan2(top2, s * 0.5)
			Mat.box(v, Vector3(1.4, 1.0, 1.4), Vector3(0, top2 + 0.5, 0), Look.GOLD)
			Mat.roof(v, Vector3(1.7, 0.7, 1.7), Vector3(0, top2 + 1.35, 0), roof_c)
			Mat.box(v, Vector3(s * 0.99, 0.2, s * 0.99), Vector3(0, 0.6, 0), team)
			for r in relics.size():
				Mat.box(v, Vector3(0.3, 0.3, 0.3), Vector3(-0.6 + r * 0.6, top2 + 0.15, 0.9), Look.GOLD.lightened(0.2))
		"monasterio":
			for i in 4:
				var w := s * (0.95 - i * 0.2)
				Mat.box(v, Vector3(w, 0.4, w), Vector3(0, 0.2 + i * 0.4, 0), stone.lightened(0.05 * i))
			Mat.box(v, Vector3(0.9, 0.7, 0.9), Vector3(0, 1.95, 0), Color(0.85, 0.82, 0.75))
			Mat.box(v, Vector3(1.0, 0.25, 1.0), Vector3(0, 2.4, 0), Color(0.75, 0.25, 0.2))
			Mat.box(v, Vector3(0.92, 0.12, 0.92), Vector3(0, 1.7, 0), team)
		"castillo":
			Mat.box(v, Vector3(s * 0.8, 1.8, s * 0.8), Vector3(0, 0.9, 0), stone)
			for cx in [-1, 1]:
				for cz in [-1, 1]:
					Mat.cyl(v, 0.45, 0.5, 2.6, Vector3(cx * s * 0.4, 1.3, cz * s * 0.4), stone.darkened(0.05), 8)
					Mat.cyl(v, 0.0, 0.55, 0.7, Vector3(cx * s * 0.4, 2.95, cz * s * 0.4), roof_c, 8)
			Mat.box(v, Vector3(1.4, 2.6, 1.4), Vector3(0, 1.3, 0), stone.lightened(0.05))
			Mat.box(v, Vector3(s * 0.82, 0.18, s * 0.82), Vector3(0, 1.6, 0), team)
		_:
			Mat.box(v, Vector3(s * 0.9, 1.0, s * 0.9), Vector3(0, 0.5, 0), wall_c)
	# Bandera del jugador
	if kind in ["centro", "cuartel", "arqueria", "establo", "castillo", "monasterio", "mercado", "herreria", "universidad", "taller", "maravilla"]:
		var h := 1.0 + s * 0.3
		if kind == "centro":
			h = 0.6
		if kind == "castillo":
			h = 3.6
		if kind == "maravilla":
			h = 5.5
		var base_y := 0.0
		var fx := -s * 0.4
		if kind == "centro":
			base_y = (3 + (1 if age >= 2 else 0) + (1 if age >= 4 else 0)) * 0.45 + 1.0
			fx = 0.0
		Mat.box(v, Vector3(0.04, h, 0.04), Vector3(fx, base_y + h * 0.5, -s * 0.4 if kind != "centro" else 0.0), Color(0.3, 0.22, 0.12))
		Mat.box(v, Vector3(0.35, 0.22, 0.03), Vector3(fx + 0.18, base_y + h - 0.15, -s * 0.4 if kind != "centro" else 0.0), team)


func _refresh_crops() -> void:
	if _crops == null:
		return
	if sow < 1.0:
		_crops.scale = Vector3(1, 0.05 + 0.5 * sow, 1)
		return
	var f := clampf(food / maxf(1.0, def.get("food", 1.0)), 0.0, 1.0)
	_crops.scale = Vector3(1, 0.3 + 0.7 * f, 1)


## Corral: los animales del dueño que están cerca pastan, dan alimento y engordan.
var grazers := 0


func _graze(dt: float) -> void:
	grazers = 0
	var c := center()
	for a in game.animals:
		if grazers >= Defs.CORRAL_CAP:
			break
		if a.dead or not a.tame or a.owner_id != owner_id or a.graze_tick == game.tick:
			continue
		if MapData.dist_to_rect(a.pos, rect) > Defs.CORRAL_RADIUS - 2.0 and a.pos.distance_to(c) > Defs.CORRAL_RADIUS:
			continue
		a.graze_tick = game.tick
		a.food = minf(a.food + Defs.FATTEN_RATE * dt, a.def["food"] * Defs.FATTEN_MAX)
		a.max_food = maxf(a.max_food, a.food)
		grazers += 1
	if grazers > 0:
		var mult: float = game.players[owner_id].gather_mult("comida")
		game.deposit(owner_id, "comida", Defs.GRAZE_RATE * grazers * dt * mult)
