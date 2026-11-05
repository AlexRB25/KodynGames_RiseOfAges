class_name MapGen
extends RefCounted
## Genera el mapa: suelo, lagos, bosques y los recursos de cada base.
## Devuelve un plan {starts, nodes, animals} que Game convierte en entidades.

var map: MapData
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var nodes: Array = []      # {kind, tile}
var animals: Array = []    # {kind, pos: Vector2}
var starts: Array = []     # Vector2i (esquina superior izquierda del centro 4x4)
var taken := {}            # casillas ya usadas por el plan
var _a0 := 0.0
var _two_teams := false
var fords: Array[Vector2] = []


var mt: Dictionary = {}       # parámetros del tipo de mapa (Defs.MAP_TYPES)
var map_type := ""


func generate(m: MapData, player_count: int, teams: Array, seed_v: int, wanted_type := "azar") -> Dictionary:
	map = m
	rng.seed = seed_v
	noise.seed = seed_v
	noise.frequency = 0.045
	map_type = wanted_type
	if not Defs.MAP_TYPES.has(map_type) or map_type == "azar":
		map_type = Defs.MAP_TYPE_ORDER[1 + rng.randi() % (Defs.MAP_TYPE_ORDER.size() - 1)]
	mt = Defs.MAP_TYPES[map_type]
	var s := map.w
	_place_starts(player_count, teams)
	_ground_and_lakes()
	map.finish_ground()
	for i in starts.size():
		_base_resources(starts[i])
	_forests()
	_extra_mines()
	_wild_animals()
	_fish()
	if "--mapinfo" in OS.get_cmdline_user_args():
		for q in plateaus:
			print("meseta ", q["c"], " r=", q["r"])
		for i in starts.size():
			print("base ", _start_center(i))
	return {"starts": starts, "nodes": nodes, "animals": animals, "size": s, "type": map_type}


func _start_center(i: int) -> Vector2:
	return Vector2(starts[i]) + Vector2(2, 2)


func _place_starts(n: int, teams: Array) -> void:
	# Compañeros de equipo quedan juntos alrededor del círculo.
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		return teams[a] < teams[b] or (teams[a] == teams[b] and a < b))
	var c := map.w * 0.5
	var radius := map.w * (0.36 if n > 2 else 0.33)
	var a0 := rng.randf() * TAU
	_a0 = a0 - TAU / n * 0.5
	var tset := {}
	for t in teams:
		tset[t] = true
	_two_teams = tset.size() == 2 and n >= 2
	starts.resize(n)
	for k in n:
		var ang := a0 + TAU * k / n
		var p := Vector2(c, c) + Vector2(cos(ang), sin(ang)) * radius
		starts[order[k]] = Vector2i(roundi(p.x) - 2, roundi(p.y) - 2)
	for i in n:
		_reserve_area(_start_center(i), 7.0)


func _reserve_area(p: Vector2, r: float) -> void:
	for y in range(floori(p.y - r), ceili(p.y + r)):
		for x in range(floori(p.x - r), ceili(p.x + r)):
			if Vector2(x + 0.5, y + 0.5).distance_to(p) <= r:
				taken[Vector2i(x, y)] = true


func _near_start(p: Vector2, r: float) -> bool:
	for i in starts.size():
		if _start_center(i).distance_to(p) < r:
			return true
	return false


func _ground_and_lakes() -> void:
	var s := map.w
	# Biomas: selva y desierto lejos de las bases; pradera con manchas secas y de tierra.
	biome.seed = rng.randi()
	biome.frequency = 0.014
	for y in s:
		for x in s:
			var v := noise.get_noise_2d(x, y)
			var g := MapData.GRASS
			if v > 0.28:
				g = MapData.DRY
			elif v < -0.38:
				g = MapData.DIRT
			var b := _biome_at(Vector2(x + 0.5, y + 0.5))
			if b > 0.32:
				g = MapData.DESERT
			elif b < -0.32:
				g = MapData.JUNGLE
			map.ground[y * s + x] = g
	plateau.resize(s * s)
	plateau.fill(0)
	_seas()
	_plan_plateaus()
	# Lagos lejos de las bases.
	var lakes := roundi((2 + s / 60) * float(mt.get("lakes", 1.0)))
	var tries := 0
	while lakes > 0 and tries < 200:
		tries += 1
		var p := Vector2(rng.randf_range(12, s - 12), rng.randf_range(12, s - 12))
		var r := rng.randf_range(4.0, 7.5)
		if _near_start(p, 20.0 + r):
			continue
		_blob(p, r, MapData.WATER)
		lakes -= 1
	# Un estanque pequeño cerca de cada base para pescar.
	for i in starts.size():
		var c := _start_center(i)
		for t in 30:
			var ang := rng.randf() * TAU
			var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(15, 19)
			if p.x < 8 or p.y < 8 or p.x > s - 8 or p.y > s - 8 or _near_start(p, 13.0):
				continue
			_blob(p, 3.2, MapData.WATER)
			break
	if _two_teams and s >= 120 and mt.get("river", true):
		_river()
	# Arena en las orillas.
	var sand: Array[int] = []
	for y in s:
		for x in s:
			if map.ground[y * s + x] == MapData.WATER:
				continue
			for d in MapData.N8:
				if map.is_water(Vector2i(x, y) + d):
					sand.append(y * s + x)
					break
	for i in sand:
		map.ground[i] = MapData.SAND
	_cliffs()


# ---------------- mar, mesetas y barrancos ----------------

var plateau := PackedByteArray()   # casilla -> número de meseta + 1 (0 = llano)
var plateaus: Array = []           # {c: Vector2, r: float}


## Mar en las esquinas más lejanas de las bases, con playa ancha.
func _seas() -> void:
	var s := map.w
	var corners: Array = [Vector2(0, 0), Vector2(s, 0), Vector2(0, s), Vector2(s, s)]
	var far := func(cn: Vector2) -> float:
		var d := INF
		for i in starts.size():
			d = minf(d, _start_center(i).distance_to(cn))
		return d
	corners.sort_custom(func(a: Vector2, b: Vector2) -> bool: return far.call(a) > far.call(b))
	var count: int = int(mt.get("seas", -1))
	if count < 0:
		count = 1 if s < 140 else 2
	var center := Vector2(s, s) * 0.5
	if mt.get("inner_sea", false):
		_inner_sea()
	for k in mini(count, 4):
		var cn: Vector2 = corners[k]
		var radius := s * float(mt.get("sea_r", 0.27))
		for y in s:
			for x in s:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := p.distance_to(cn)
				if d > radius * 1.4:
					continue
				var wob := noise.get_noise_2d(x * 0.6, y * 0.6) * radius * 0.25
				var t := Vector2i(x, y)
				if taken.has(t):
					continue
				if d < radius + wob and not _near_start(p, 24.0):
					map.ground[map.idx(t)] = MapData.WATER
				elif d < radius + wob + 3.0 and not _near_start(p, 18.0):
					map.ground[map.idx(t)] = MapData.SAND
		# Una meseta sobre la costa: acantilados que caen al mar.
		var dir := (center - cn).normalized().rotated(rng.randf_range(-0.6, 0.6))
		var pc := cn + dir * radius * 1.02
		var r := rng.randf_range(7.5, 10.5)
		if not _near_start(pc, 22.0 + r):
			plateaus.append({"c": pc, "r": r})


## Mar en el centro del mapa, con playas y una meseta en su costa.
func _inner_sea() -> void:
	var s := map.w
	var c := Vector2(s, s) * 0.5
	var radius := s * 0.16
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			if d > radius * 1.5:
				continue
			var t := Vector2i(x, y)
			if taken.has(t):
				continue
			var wob := noise.get_noise_2d(x * 0.6, y * 0.6) * radius * 0.3
			if d < radius + wob and not _near_start(p, 22.0):
				map.ground[map.idx(t)] = MapData.WATER
			elif d < radius + wob + 2.5 and not _near_start(p, 16.0):
				map.ground[map.idx(t)] = MapData.SAND
	var pc := c + Vector2.from_angle(rng.randf() * TAU) * radius
	var r := rng.randf_range(7.0, 9.5)
	if not _near_start(pc, 22.0 + r):
		plateaus.append({"c": pc, "r": r})


func _plan_plateaus() -> void:
	var s := map.w
	var want := roundi((1 + s / 70) * float(mt.get("plateaus", 1.0)))
	var tries := 0
	while want > 0 and tries < 300:
		tries += 1
		var p := Vector2(rng.randf_range(16, s - 16), rng.randf_range(16, s - 16))
		var r := rng.randf_range(7.0, 11.5)
		if _near_start(p, 24.0 + r):
			continue
		var ok := true
		for q in plateaus:
			if q["c"].distance_to(p) < q["r"] + r + 10.0:
				ok = false
		if not ok:
			continue
		plateaus.append({"c": p, "r": r})
		want -= 1
	for k in plateaus.size():
		var c: Vector2 = plateaus[k]["c"]
		var r: float = plateaus[k]["r"]
		for y in range(floori(c.y - r - 3), ceili(c.y + r + 3)):
			for x in range(floori(c.x - r - 3), ceili(c.x + r + 3)):
				var t := Vector2i(x, y)
				if not map.inside(t) or taken.has(t) or x < 2 or y < 2 or x > s - 3 or y > s - 3:
					continue
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
				var wob := noise.get_noise_2d(x * 2.0 + 300.0, y * 2.0) * 2.2
				if d < r + wob:
					plateau[map.idx(t)] = k + 1


func _low_land(t: Vector2i) -> bool:
	return map.inside(t) and plateau[map.idx(t)] == 0 and map.ground[map.idx(t)] != MapData.WATER


## Borde de cada meseta = barranco, salvo las rampas. Mesetas sin rampa útil se aplanan.
func _cliffs() -> void:
	var s := map.w
	var border := {}
	for y in s:
		for x in s:
			var i := y * s + x
			if plateau[i] == 0 or map.ground[i] == MapData.WATER:
				continue
			var t := Vector2i(x, y)
			for d in MapData.N8:
				var n: Vector2i = t + d
				if not map.inside(n) or plateau[map.idx(n)] == 0 or map.ground[map.idx(n)] == MapData.WATER:
					border[t] = true
					break
	var ramps := {}
	var outs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Casillas del borde de cada meseta (en orden fijo: igual en todos los equipos en línea).
	var borders_of: Array = []
	for k in plateaus.size():
		borders_of.append([])
	for y in s:
		for x in s:
			var t := Vector2i(x, y)
			if border.has(t):
				borders_of[plateau[map.idx(t)] - 1].append(t)
	for k in plateaus.size():
		var c: Vector2 = plateaus[k]["c"]
		# Candidatas: casilla del borde con tierra baja (no agua) enfrente, 2 casillas de fondo.
		var cands: Array = []
		for t in borders_of[k]:
			for out in outs:
				var inner: Vector2i = t - out
				if _low_land(t + out) and _low_land(t + out * 2) and map.inside(inner) and plateau[map.idx(inner)] == k + 1 \
						and not border.has(inner):
					cands.append([t, out])
					break
		var made := 0
		var used: Array = []
		var want_ang := rng.randf() * TAU
		for j in 2:
			var best: Array = []
			var best_score := -INF
			for cd in cands:
				var t: Vector2i = cd[0]
				var score := 0.0
				if used.is_empty():
					var ang := (MapData.center(t) - c).angle()
					score = -absf(angle_difference(ang, want_ang))
				else:
					score = INF
					for u in used:
						score = minf(score, Vector2(t).distance_to(Vector2(u)))
					if score < 6.0:
						continue
				if score > best_score:
					best_score = score
					best = cd
			if best.is_empty():
				break
			var t0: Vector2i = best[0]
			var out: Vector2i = best[1]
			var side := Vector2i(out.y, out.x)
			used.append(t0)
			# Rampa de hasta 3 de ancho: los lados solo si también dan a tierra baja.
			for q in [t0, t0 + side, t0 - side]:
				if q != t0 and not (border.has(q) and plateau[map.idx(q)] == k + 1 and _low_land(q + out)):
					continue
				ramps[q] = true
				taken[q] = true
				for e in [q + out, q + out * 2, q - out]:
					if map.inside(e):
						taken[e] = true
			made += 1
		if "--mapinfo" in OS.get_cmdline_user_args():
			print("rampas meseta ", k, ": ", made)
		if made == 0:
			for i in plateau.size():
				if plateau[i] == k + 1:
					plateau[i] = 0
	for y in s:
		for x in s:
			var i := y * s + x
			if plateau[i] == 0 or map.ground[i] == MapData.WATER:
				continue
			var t := Vector2i(x, y)
			if ramps.has(t):
				map.height[i] = MapData.LEVEL_H * 0.5
				map.ground[i] = MapData.DIRT
			elif border.has(t) and plateau[i] != 0:
				var still := false
				for d in MapData.N8:
					var n: Vector2i = t + d
					if not map.inside(n) or plateau[map.idx(n)] == 0 or map.ground[map.idx(n)] == MapData.WATER:
						still = true
						break
				if still:
					map.ground[i] = MapData.CLIFF
					map.height[i] = MapData.LEVEL_H
					taken[t] = true
				else:
					map.height[i] = MapData.LEVEL_H
			else:
				map.height[i] = MapData.LEVEL_H
				if map.ground[i] == MapData.SAND:
					map.ground[i] = MapData.DRY


## Río entre los dos equipos, con vados (arena) para cruzar a pie.
func _river() -> void:
	var s := map.w
	var c := Vector2(s, s) * 0.5
	var dir := Vector2(cos(_a0), sin(_a0))
	var side := Vector2(-dir.y, dir.x)
	var half := s * 0.75
	var ford_every := 34.0
	var phase := rng.randf() * TAU
	var t := -half
	var next_ford := -half + rng.randf_range(10, 20)
	while t < half:
		var p := c + dir * t + side * sin(t * 0.06 + phase) * 5.0
		if t >= next_ford and t < next_ford + 3.5:
			fords.append(p)
		else:
			if t >= next_ford + 3.5:
				next_ford += ford_every
			_blob(p, 1.6, MapData.WATER)
		t += 0.5
	# Los vados quedan como arena caminable.
	for f in fords:
		for y in range(floori(f.y - 3), ceili(f.y + 3)):
			for x in range(floori(f.x - 3), ceili(f.x + 3)):
				var tt := Vector2i(x, y)
				if map.inside(tt) and map.ground[map.idx(tt)] == MapData.WATER and Vector2(x + 0.5, y + 0.5).distance_to(f) < 2.6:
					map.ground[map.idx(tt)] = MapData.SAND
					taken[tt] = true


var biome := FastNoiseLite.new()


## Valor de bioma (-1 selva .. +1 desierto), atenuado cerca de las bases.
func _biome_at(p: Vector2) -> float:
	var b := biome.get_noise_2d(p.x, p.y) * 1.6 + float(mt.get("bias", 0.0))
	var near := INF
	for i in starts.size():
		near = minf(near, _start_center(i).distance_to(p))
	return b * clampf((near - 16.0) / 14.0, 0.0, 1.0)


func _blob(p: Vector2, r: float, g: int) -> void:
	for y in range(floori(p.y - r - 2), ceili(p.y + r + 2)):
		for x in range(floori(p.x - r - 2), ceili(p.x + r + 2)):
			var t := Vector2i(x, y)
			if not map.inside(t) or taken.has(t):
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(p)
			var wob := noise.get_noise_2d(x * 3.0, y * 3.0) * 1.5
			if d < r + wob:
				map.ground[map.idx(t)] = g


func _free(t: Vector2i) -> bool:
	return map.inside(t) and not taken.has(t) and not map.ground_blocks(map.idx(t)) \
		and t.x > 0 and t.y > 0 and t.x < map.w - 1 and t.y < map.h - 1


func _add_node(kind: String, t: Vector2i) -> bool:
	if not _free(t):
		return false
	taken[t] = true
	nodes.append({"kind": kind, "tile": t})
	return true


## Racimo de n casillas del mismo recurso alrededor de un punto.
func _cluster(kind: String, p: Vector2, n: int) -> void:
	var t0 := MapData.to_tile(p)
	var placed := 0
	var frontier: Array[Vector2i] = [t0]
	var seen := {t0: true}
	while placed < n and not frontier.is_empty():
		var i := rng.randi_range(0, frontier.size() - 1)
		var t: Vector2i = frontier[i]
		frontier.remove_at(i)
		if _add_node(kind, t):
			placed += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nt: Vector2i = t + d
			if not seen.has(nt) and map.inside(nt):
				seen[nt] = true
				frontier.append(nt)


func _spot_around(c: Vector2, rmin: float, rmax: float, clear: float) -> Vector2:
	for k in 60:
		var ang := rng.randf() * TAU
		var p := c + Vector2(cos(ang), sin(ang)) * rng.randf_range(rmin, rmax)
		var ok := true
		for dy in range(-ceili(clear), ceili(clear) + 1):
			for dx in range(-ceili(clear), ceili(clear) + 1):
				if not _free(MapData.to_tile(p) + Vector2i(dx, dy)):
					ok = false
		if ok:
			return p
	return Vector2(-1, -1)


func _base_resources(st: Vector2i) -> void:
	var c := Vector2(st) + Vector2(2, 2)
	# Bosque propio.
	var fp := _spot_around(c, 12, 15, 2)
	if fp.x >= 0:
		_cluster("arbol", fp, 40)
	# Bayas, oro y piedra.
	var bp := _spot_around(c, 7, 9, 1)
	if bp.x >= 0:
		_cluster("arbusto", bp, 6)
	var gp := _spot_around(c, 9, 12, 1)
	if gp.x >= 0:
		_cluster("oro", gp, 6)
	var sp := _spot_around(c, 10, 13, 1)
	if sp.x >= 0:
		_cluster("piedra", sp, 5)
	# 5 cabras cerca y venados más lejos.
	for k in 5:
		var p := _spot_around(c, 6, 9, 0)
		if p.x >= 0:
			animals.append({"kind": "cabra", "pos": MapData.center(MapData.to_tile(p))})
	for k in 3:
		var p := _spot_around(c, 15, 20, 0)
		if p.x >= 0:
			animals.append({"kind": "venado", "pos": MapData.center(MapData.to_tile(p))})
	# Árboles sueltos.
	for k in 8:
		var p := _spot_around(c, 8, 16, 0)
		if p.x >= 0:
			_add_node("arbol", MapData.to_tile(p))


func _forests() -> void:
	var s := map.w
	var f2 := FastNoiseLite.new()
	f2.seed = rng.randi()
	f2.frequency = 0.06
	for y in range(1, s - 1):
		for x in range(1, s - 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if _near_start(p, 13.0):
				continue
			var v := f2.get_noise_2d(x, y)
			var gr := map.ground[map.idx(Vector2i(x, y))]
			if gr == MapData.JUNGLE:
				v += 0.28
			elif gr == MapData.DESERT:
				v -= 0.35
			if v > 0.32 or (v > 0.22 and rng.randf() < 0.25):
				_add_node("arbol", Vector2i(x, y))
			elif rng.randf() < 0.004:
				_add_node("arbol", Vector2i(x, y))
	# Bosque denso en los bordes del mapa.
	for y in s:
		for x in s:
			var e := mini(mini(x, y), mini(s - 1 - x, s - 1 - y))
			if e < 2 or (e < 4 and rng.randf() < 0.5):
				var t := Vector2i(x, y)
				if not taken.has(t) and not map.ground_blocks(map.idx(t)):
					taken[t] = true
					nodes.append({"kind": "arbol", "tile": t})


func _extra_mines() -> void:
	var s := map.w
	var count := starts.size() * 2 + s / 40
	for k in count:
		for t in 40:
			var p := Vector2(rng.randf_range(8, s - 8), rng.randf_range(8, s - 8))
			if _near_start(p, 22.0):
				continue
			_cluster("oro" if k % 2 == 0 else "piedra", p, rng.randi_range(3, 5))
			break


func _wild_animals() -> void:
	var s := map.w
	for k in s / 8:
		var p := Vector2(rng.randf_range(6, s - 6), rng.randf_range(6, s - 6))
		var t := MapData.to_tile(p)
		if _near_start(p, 18.0) or not _free(t):
			continue
		var kind: String = ["venado", "guajolote", "cabra"][k % 3]
		animals.append({"kind": kind, "pos": MapData.center(t)})


func _fish() -> void:
	var s := map.w
	for y in range(1, s - 1):
		for x in range(1, s - 1):
			var t := Vector2i(x, y)
			if not map.is_water(t):
				continue
			var shore := false
			for d in MapData.N8:
				var n: Vector2i = t + d
				if map.inside(n) and not map.is_water(n):
					shore = true
					break
			if shore and rng.randf() < 0.07:
				taken[t] = true
				nodes.append({"kind": "pesca", "tile": t})
