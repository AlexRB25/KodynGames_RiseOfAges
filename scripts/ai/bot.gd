class_name Bot
extends RefCounted
## Jugador controlado por la computadora. Usa las mismas órdenes que el jugador
## (no hace trampa con recursos; la dificultad cambia ritmo, metas y tiempos).

var g: Game
var pid := 0
var p: PlayerState
var diff: Dictionary
var think_t := 0.0
var next_attack := 0.0
var wave := 0
var threat: Entity = null
var threat_t := -100.0
var rng := RandomNumberGenerator.new()

const RATIOS_EARLY := {"comida": 0.50, "madera": 0.35, "oro": 0.10, "piedra": 0.05}
const RATIOS_LATE := {"comida": 0.38, "madera": 0.30, "oro": 0.20, "piedra": 0.12}


func _init(game: Game, id: int) -> void:
	g = game
	pid = id
	p = g.players[id]
	diff = Defs.DIFFICULTY[p.difficulty]
	next_attack = diff["attack_at"]
	rng.seed = id * 7919 + 13
	think_t = rng.randf() * 1.0


func tick(dt: float) -> void:
	if p.defeated or g.over:
		return
	think_t -= dt
	if think_t > 0.0:
		return
	think_t = diff["think"]
	_think()


func on_attacked(_e: Entity, from: Entity) -> void:
	if Entity.live(from) and g.is_enemy(pid, from.owner_id):
		threat = from
		threat_t = g.time


func _think() -> void:
	var centro := g.main_center(pid)
	if centro == null:
		return
	var vills: Array[Unit] = []
	var army: Array[Unit] = []
	for u in g.units:
		if u.owner_id != pid or u.dead:
			continue
		if u.is_villager():
			vills.append(u)
		else:
			army.append(u)
	var home := centro.center()
	# ¿Ahorrar para la siguiente era? (requisitos de edificios ya cumplidos)
	var saving := false
	if p.age < Defs.AGES.size() and vills.size() >= mini(diff["villagers"], 10 + p.age * 5):
		var reqs_ok := true
		for r in g.age_requirements(pid):
			if not r["ok"]:
				reqs_ok = false
		var researching := false
		for b in g.buildings:
			if b.owner_id == pid and b.queue.has("era"):
				researching = true
		saving = reqs_ok and not researching
	var under_threat := Entity.live(threat) and g.time - threat_t < 15.0

	# 1. Aldeanos
	if vills.size() < diff["villagers"] and centro.queue.size() < 2 and not centro.queue.has("era") 			and not (saving and p.res["comida"] < Defs.AGES[p.age]["cost"].get("comida", 0) + 50):
		g.train(pid, centro, "aldeano")

	# 2. Casas antes de quedarse sin población
	var margin := 3 if vills.size() < 15 else 6
	if p.pop_cap < Defs.POP_MAX and p.pop_cap - p.pop <= margin and _pending("casa") == 0:
		_build("casa", home, vills, 6, 14)

	# 3. Economía
	if vills.size() >= 6 and g.count_buildings(pid, ["maderero"], false) == 0:
		var t := g.find_resource_near("arbol", home, 40.0, pid)
		if t:
			_build("maderero", t.center(), vills, 2, 6)
	if vills.size() >= 9 and g.count_buildings(pid, ["molino"], false) == 0:
		var b := g.find_resource_near("arbusto", home, 25.0, pid)
		_build("molino", b.center() if b else home, vills, 2, 8)
	if vills.size() >= 11 and g.count_buildings(pid, ["minero"], false) == 0:
		var o := g.find_resource_near("oro", home, 40.0, pid)
		if o:
			_build("minero", o.center(), vills, 2, 6)
	if p.age >= 2 and vills.size() >= 16 and g.count_buildings(pid, ["minero"], false) < 2:
		var s := g.find_resource_near("piedra", home, 40.0, pid)
		if s:
			_build("minero", s.center(), vills, 2, 6)
	# Granjas: una por cada aldeano que debería estar en alimento y no tiene bayas/caza.
	if g.count_buildings(pid, ["molino"]) > 0:
		var ratios: Dictionary = RATIOS_EARLY if p.age == 1 else RATIOS_LATE
		var food_goal := int(ratios["comida"] * vills.size())
		var natural := 0
		for u in vills:
			if Entity.valid(u.target) and (u.target is Animal or u.target is ResourceNode) and u.target.res_type() == "comida":
				natural += 1
		var want := clampi(food_goal - natural, 0, 24)
		if p.age >= 2:
			want = maxi(want, 4)
		if g.count_buildings(pid, ["granja"], false) < want and _pending("granja") < 3:
			if p.seeds == 0:
				g.buy_seed(pid)
			var mol := _nearest_own("molino", home)
			_build("granja", mol.center() if mol else home, vills, 2, 9)
	# Guardar un par de siembras para que las granjas se resiembren solas.
	if g.count_buildings(pid, ["granja"]) > 0 and p.seeds < 2 and p.res["madera"] > 250:
		g.buy_seed(pid)
	_rebalance(vills)
	_herding(vills, home)
	_use_market()

	# 4. Militares y defensas
	if vills.size() >= 10 and g.count_buildings(pid, ["cuartel"], false) == 0:
		_build("cuartel", home, vills, 7, 16)
	if p.age >= 2 and vills.size() >= 15 and g.count_buildings(pid, ["arqueria"], false) == 0:
		_build("arqueria", home, vills, 7, 16)
	if p.age >= 2 and g.count_buildings(pid, ["torre"], false) == 0:
		_build("torre", home, vills, 5, 9)
	if p.age >= 3 and g.count_buildings(pid, ["establo"], false) == 0:
		_build("establo", home, vills, 7, 16)
	if p.age >= 3 and g.count_buildings(pid, ["templo"], false) == 0:
		_build("templo", home, vills, 6, 14)
	if p.age >= 2 and vills.size() >= 20 and g.count_buildings(pid, ["centro"], false) < 2:
		_build("centro", home, vills, 14, 24)

	# 5. Eras
	if g.age_block_reason(pid, centro) == "":
		g.research_age(pid, centro)

	# 6. Ejército
	var army_goal: int = diff["army"] + wave * 3
	if (army.size() < army_goal or p.res["comida"] > 600) and (not saving or under_threat):
		for b in g.buildings:
			if b.owner_id != pid or not b.complete or b.queue.size() >= 2:
				continue
			for k in b.def.get("trains", []):
				if k == "aldeano":
					continue
				g.train(pid, b, k)

	# 7. Repartir aldeanos sin tarea
	_assign_idle(vills, home)

	# 8. Defender o atacar
	if Entity.live(threat) and g.time - threat_t < 15.0 and threat.pos.distance_to(home) < 30.0:
		for u in army:
			if u.state == Unit.S.IDLE or u.state == Unit.S.MOVE:
				u.cmd_attack(threat)
		return
	if g.time >= next_attack and army.size() >= diff["army"]:
		var target := _enemy_target(home)
		if target:
			wave += 1
			next_attack = g.time + 150.0 - minf(60.0, wave * 10.0)
			for u in army:
				u.cmd_move(target.center(), true)
	else:
		# Reagrupar a los que regresan sin enemigo.
		for u in army:
			if u.is_idle() and u.pos.distance_to(home) > 40.0 and g.time > next_attack + 60.0:
				u.cmd_move(home + Vector2(4, 4), true)


## Mover aldeanos si un recurso sobra mientras otro falta, o si nadie junta uno que se acaba.
func _rebalance(vills: Array[Unit]) -> void:
	var counts := {"comida": 0, "madera": 0, "oro": 0, "piedra": 0}
	for u in vills:
		if counts.has(u.carry_type) and (u.state == Unit.S.GATHER or u.state == Unit.S.RETURN):
			counts[u.carry_type] += 1
	var low := ""
	var high := ""
	for r in Defs.RES:
		if low == "" or p.res[r] < p.res[low]:
			low = r
		if high == "" or counts[r] > counts[high]:
			high = r
	var starving: bool = p.res[low] < 100 and counts[low] == 0 and (low == "comida" or low == "madera")
	if not starving and (p.res[high] < 700 or p.res[low] > 250):
		return
	var moved := 0
	var home := g.main_center(pid).center()
	for u in vills:
		if moved >= 2:
			break
		if u.carry_type == high and high != low and (u.state == Unit.S.GATHER or u.state == Unit.S.RETURN):
			var t := _resource_for(low, home, u)
			if t == null and low == "comida" and p.seeds == 0:
				g.buy_seed(pid)
			if t:
				u.cmd_gather(t)
				moved += 1


func _use_market() -> void:
	if g.count_buildings(pid, ["mercado"]) == 0:
		if p.age >= 2 and g.count_buildings(pid, ["mercado"], false) == 0 and p.res["madera"] > 400:
			var vills: Array[Unit] = []
			for u in g.units:
				if u.owner_id == pid and u.is_villager():
					vills.append(u)
			_build("mercado", g.main_center(pid).center(), vills, 8, 16)
		return
	for r in ["comida", "madera", "piedra"]:
		if p.res[r] > 900:
			g.market_sell(pid, r)
	if p.res["comida"] < 150 and p.res["oro"] > 400:
		g.market_buy(pid, "comida")


func _enemy_target(home: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for q in g.players:
		if q.defeated or not g.is_enemy(pid, q.id):
			continue
		var c := g.main_center(q.id)
		if c and c.center().distance_to(home) < bd:
			bd = c.center().distance_to(home)
			best = c
	return best


func _nearest_own(k: String, near: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for b in g.buildings:
		if b.owner_id == pid and b.kind == k and b.complete:
			var d := b.center().distance_to(near)
			if d < bd:
				bd = d
				best = b
	return best


func _pending(k: String) -> int:
	var n := 0
	for b in g.buildings:
		if b.owner_id == pid and b.kind == k and not b.complete:
			n += 1
	return n


## Construir cerca de un punto con un aldeano (prefiere uno sin tarea).
func _build(k: String, near: Vector2, vills: Array[Unit], rmin: int, rmax: int) -> void:
	if g.build_block_reason(pid, k) != "" or vills.is_empty():
		return
	var tile := _find_spot(k, near, rmin, rmax)
	if tile.x < 0:
		return
	var b := g.place_building(pid, k, tile)
	if b == null:
		return
	var builders := 2 if k in ["centro", "cuartel", "arqueria", "establo", "templo", "torre"] else 1
	var sorted := vills.duplicate()
	sorted.sort_custom(func(a: Unit, c: Unit) -> bool:
		return _builder_score(a, b) < _builder_score(c, b))
	for i in mini(builders, sorted.size()):
		sorted[i].cmd_build(b)


func _builder_score(u: Unit, b: Building) -> float:
	var s := u.pos.distance_to(b.center())
	if u.state == Unit.S.BUILD:
		s += 1000.0
	if u.is_idle():
		s -= 30.0
	return s


func _find_spot(k: String, near: Vector2, rmin: int, rmax: int) -> Vector2i:
	var sz: int = Defs.BUILDINGS[k]["size"]
	var c := MapData.to_tile(near)
	for r in range(rmin, rmax + 1):
		var cands: Array[Vector2i] = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				cands.append(c + Vector2i(dx, dy) - Vector2i(sz / 2, sz / 2))
		for i in range(cands.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := cands[i]
			cands[i] = cands[j]
			cands[j] = tmp
		for t in cands:
			# Dejar un pasillo de 1 casilla alrededor (salvo murallas).
			var grown := Rect2i(t - Vector2i.ONE, Vector2i(sz + 2, sz + 2))
			if g.map.rect_open(grown) and g.can_place(pid, k, t):
				return t
	return Vector2i(-1, -1)


func _assign_idle(vills: Array[Unit], home: Vector2) -> void:
	var counts := {"comida": 0, "madera": 0, "oro": 0, "piedra": 0}
	var idle: Array[Unit] = []
	for u in vills:
		if u.is_idle():
			idle.append(u)
		elif u.state == Unit.S.GATHER or u.state == Unit.S.RETURN:
			var rt := u.carry_type
			if rt == "" and Entity.valid(u.target):
				rt = u.target.res_type()
			if counts.has(rt):
				counts[rt] += 1
	var ratios: Dictionary = RATIOS_EARLY if p.age == 1 else RATIOS_LATE
	var total := maxi(1, vills.size())
	for u in idle:
		var best := "comida"
		var gap := -INF
		for r in ratios:
			var gp: float = ratios[r] * total - counts[r]
			if gp > gap:
				gap = gp
				best = r
		var t := _resource_for(best, home, u)
		if t == null:
			for r in ["madera", "comida", "oro", "piedra"]:
				t = _resource_for(r, home, u)
				if t:
					best = r
					break
		if t:
			u.cmd_gather(t)
			counts[best] += 1


func _resource_for(r: String, home: Vector2, u: Unit) -> Entity:
	match r:
		"comida":
			for grp in ["granja", "arbusto", "caza", "pesca"]:
				var e := g.find_resource_near(grp, home, 22.0 if grp != "granja" else 30.0, pid, null, u)
				if e:
					return e
			return null
		"madera":
			var camp := _nearest_own("maderero", home)
			return g.find_resource_near("arbol", camp.center() if camp else home, 45.0, pid)
		"oro", "piedra":
			var camp: Building = null
			var bd := INF
			for b in g.buildings:
				if b.owner_id == pid and b.kind == "minero" and b.complete:
					if g.find_resource_near(r, b.center(), Defs.CAMP_RADIUS, pid):
						var d := b.center().distance_to(home)
						if d < bd:
							bd = d
							camp = b
			return g.find_resource_near(r, camp.center() if camp else home, 45.0, pid)
	return null


## Pastoreo: corral cerca del centro, un aldeano pastorea cabras y guajolotes salvajes
## cercanos (uno a la vez) y los animales del bot se van a pastar al corral.
func _herding(vills: Array[Unit], home: Vector2) -> void:
	var wild: Array[Animal] = []
	var mine: Array[Animal] = []
	for a in g.animals:
		if a.dead or not a.tame:
			continue
		if a.owner_id == pid:
			mine.append(a)
		elif a.owner_id < 0 and a.pos.distance_to(home) < 28.0:
			wild.append(a)
	var corral := _nearest_own("corral", home)
	if corral == null:
		if _pending("corral") == 0 and vills.size() >= 7 and wild.size() + mine.size() >= 2 and p.res["madera"] >= 130:
			_build("corral", home, vills, 5, 11)
		return
	var grazing := 0
	for a in mine:
		if a.grazing():
			grazing += 1
		elif not a.moving and a.pos.distance_to(corral.center()) > 3.0:
			a.cmd_move(corral.center())
	var herding := false
	for u in vills:
		if u.state == Unit.S.HERD:
			herding = true
	if herding or wild.is_empty() or mine.size() >= Defs.CORRAL_CAP:
		return
	# El animal salvaje más cercano al centro y el aldeano más cercano a él (que no construya).
	wild.sort_custom(func(a: Animal, b: Animal) -> bool: return a.pos.distance_to(home) < b.pos.distance_to(home))
	var target := wild[0]
	var best: Unit = null
	var bd := INF
	for u in vills:
		if u.state == Unit.S.BUILD or u.carry > 0.0:
			continue
		var d := u.pos.distance_to(target.pos) - (30.0 if u.is_idle() else 0.0)
		if d < bd:
			bd = d
			best = u
	if best:
		best.cmd_herd(target)
