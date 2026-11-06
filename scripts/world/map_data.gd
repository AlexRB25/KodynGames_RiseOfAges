class_name MapData
extends RefCounted
## Cuadrícula del mapa: tipo de suelo, casillas bloqueadas, qué ocupa cada casilla
## y búsqueda de caminos (A*). 1 casilla = 1 unidad de mundo; el centro de la
## casilla (x, y) está en (x + 0.5, y + 0.5). En 3D, "y" del mapa es el eje Z.

enum { GRASS, WATER, SAND, DIRT, DRY, JUNGLE, DESERT, CLIFF }

const LEVEL_H := 2.2       # alto de una meseta
const WATER_Y := -0.14     # superficie del agua
const WATER_BED := -0.75   # fondo del agua

## Mapa de la partida en curso (para que las figuras sepan a qué altura pararse).
static var active: MapData

var w := 0
var h := 0
var ground := PackedByteArray()
var solid := PackedByteArray()        # >0 = bloqueada (árbol, mina, edificio)
var reserved := PackedByteArray()     # >0 = ocupada por un edificio (aunque se pueda caminar, ej. granja)
var ent: Array = []                   # casilla -> Entity estática (recurso o edificio) o null
var height := PackedFloat32Array()    # altura del suelo de cada casilla (0 llano, LEVEL_H meseta)
var astar := AStarGrid2D.new()        # caminos por tierra (las puertas cerradas)
var water := AStarGrid2D.new()        # caminos por agua (barcos)
var gate_team := PackedInt32Array()   # casilla -> equipo dueño de la puerta (0 = no hay)
var team_grids := {}                  # equipo -> AStarGrid2D por tierra con SUS puertas abiertas

## Modo de paso ("nav"): 0 = por tierra sin puertas; >0 = por tierra, equipo que abre
## sus puertas; WATER_NAV = por agua.
const WATER_NAV := -1

const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


func setup(size: int) -> void:
	w = size
	h = size
	ground.resize(w * h)
	ground.fill(GRASS)
	solid.resize(w * h)
	solid.fill(0)
	reserved.resize(w * h)
	reserved.fill(0)
	ent.resize(w * h)
	ent.fill(null)
	height.resize(w * h)
	height.fill(0.0)
	gate_team.resize(w * h)
	gate_team.fill(0)
	active = self
	_init_grid(astar)
	_init_grid(water)


func _init_grid(g: AStarGrid2D) -> void:
	g.region = Rect2i(0, 0, w, h)
	g.cell_size = Vector2(1, 1)
	g.offset = Vector2(0.5, 0.5)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()


## Rejilla de caminos para un modo de paso.
func grid(nav: int) -> AStarGrid2D:
	if nav == WATER_NAV:
		return water
	return team_grids.get(nav, astar)


## Recalcula si una casilla se puede cruzar, en todas las rejillas.
func refresh_tile(t: Vector2i) -> void:
	astar.set_point_solid(t, not is_free(t, 0))
	water.set_point_solid(t, not is_free(t, WATER_NAV))
	for team in team_grids:
		team_grids[team].set_point_solid(t, not is_free(t, team))


## Puerta de un equipo en una casilla (0 = quitarla). Crea la rejilla del equipo si hace falta.
func set_gate(t: Vector2i, team: int) -> void:
	if not inside(t):
		return
	gate_team[idx(t)] = team
	if team > 0 and not team_grids.has(team):
		var g := AStarGrid2D.new()
		_init_grid(g)
		team_grids[team] = g
		for y in h:
			for x in w:
				var c := Vector2i(x, y)
				if not is_free(c, team):
					g.set_point_solid(c, true)
	refresh_tile(t)


## Llamar cuando el suelo ya está generado: marca el agua y los barrancos como bloqueados.
func finish_ground() -> void:
	for y in h:
		for x in w:
			var i := y * w + x
			if ground[i] == WATER:
				height[i] = WATER_BED
			if ground_blocks(i):
				astar.set_point_solid(Vector2i(x, y), true)
			if ground[i] != WATER:
				water.set_point_solid(Vector2i(x, y), true)


## Agua o barranco: no se camina ni se construye.
func ground_blocks(i: int) -> bool:
	return ground[i] == WATER or ground[i] == CLIFF


func tile_h(t: Vector2i) -> float:
	if not inside(t):
		return 0.0
	var i := idx(t)
	return WATER_Y if ground[i] == WATER else height[i]


## Altura del suelo en un punto: suave en las rampas, plana junto a barrancos y agua.
func height_at(p: Vector2) -> float:
	var t := to_tile(p)
	if not inside(t):
		return 0.0
	var h0 := tile_h(t)
	var c := center(t)
	var sx := 1 if p.x >= c.x else -1
	var sy := 1 if p.y >= c.y else -1
	var fx := absf(p.x - c.x)
	var fy := absf(p.y - c.y)
	var hx := _near_h(t + Vector2i(sx, 0), h0)
	var hy := _near_h(t + Vector2i(0, sy), h0)
	var hxy := _near_h(t + Vector2i(sx, sy), h0)
	return lerpf(lerpf(h0, hx, fx), lerpf(hy, hxy, fx), fy)


func _near_h(t: Vector2i, h0: float) -> float:
	if not inside(t) or ground_blocks(idx(t)):
		return h0
	var hn := height[idx(t)]
	return hn if absf(hn - h0) <= LEVEL_H * 0.55 else h0


## Altura del suelo para las figuras 3D (0 si no hay partida).
static func ground_y(p: Vector2) -> float:
	return active.height_at(p) if active else 0.0


func idx(t: Vector2i) -> int:
	return t.y * w + t.x


func inside(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < w and t.y < h


func is_water(t: Vector2i) -> bool:
	return inside(t) and ground[idx(t)] == WATER


## Se puede pasar por la casilla (nav: ver WATER_NAV).
func is_free(t: Vector2i, nav := 0) -> bool:
	if not inside(t):
		return false
	var i := idx(t)
	if nav == WATER_NAV:
		return ground[i] == WATER and solid[i] == 0
	if ground_blocks(i):
		return false
	return solid[i] == 0 or (nav > 0 and gate_team[i] == nav and solid[i] == 1)


## Libre para construir o colocar algo.
func is_open(t: Vector2i) -> bool:
	if not inside(t):
		return false
	var i := idx(t)
	return not ground_blocks(i) and solid[i] == 0 and reserved[i] == 0 and ent[i] == null


## Libre para poner algo en el agua (trampa para peces).
func is_open_water(t: Vector2i) -> bool:
	if not inside(t):
		return false
	var i := idx(t)
	return ground[i] == WATER and solid[i] == 0 and reserved[i] == 0 and ent[i] == null


func rect_open(r: Rect2i) -> bool:
	if not inside(r.position):
		return false
	var h0 := height[idx(r.position)]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not is_open(t) or height[idx(t)] != h0:   # todo el edificio a la misma altura
				return false
	return true


func occupy(r: Rect2i, e, blocks: bool) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not inside(t):
				continue
			var i := idx(t)
			ent[i] = e
			reserved[i] = 1
			if blocks:
				solid[i] += 1
				refresh_tile(t)


func release(r: Rect2i, e, blocks: bool) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not inside(t):
				continue
			var i := idx(t)
			if ent[i] == e:
				ent[i] = null
			reserved[i] = 0
			if blocks and solid[i] > 0:
				solid[i] -= 1
				refresh_tile(t)


func entity_at(t: Vector2i):
	if not inside(t):
		return null
	return ent[idx(t)]


static func to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func center(t: Vector2i) -> Vector2:
	return Vector2(t.x + 0.5, t.y + 0.5)


## Casilla libre más cercana (búsqueda por anillos).
func nearest_free(t: Vector2i, max_r := 20, nav := 0) -> Vector2i:
	if is_free(t, nav):
		return t
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := t + Vector2i(dx, dy)
				if is_free(c, nav):
					var d := Vector2(dx, dy).length_squared()
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return t


## Camino desde una posición hasta una casilla. Si no se puede llegar, llega lo más cerca posible.
func path_to_tile(from: Vector2, goal: Vector2i, exact_end := Vector2.INF, nav := 0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := to_tile(from)
	if not is_free(a, nav):
		a = nearest_free(a, 20, nav)
	if not inside(goal):
		goal = Vector2i(clampi(goal.x, 0, w - 1), clampi(goal.y, 0, h - 1))
	var g := goal
	if not is_free(g, nav):
		g = nearest_free(goal, 6, nav)
	if a == g:
		out.append(exact_end if exact_end != Vector2.INF and g == goal else center(g))
		return out
	var ids := grid(nav).get_id_path(a, g, true)
	for i in range(1, ids.size()):
		out.append(center(ids[i]))
	if out.size() > 0 and exact_end != Vector2.INF and ids[ids.size() - 1] == goal:
		out[out.size() - 1] = exact_end
	return out


## Casillas libres alrededor de un rectángulo (para acercarse a un edificio o recurso).
func ring_around(r: Rect2i, nav := 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			if x >= r.position.x and x < r.end.x and y >= r.position.y and y < r.end.y:
				continue
			var t := Vector2i(x, y)
			if is_free(t, nav):
				out.append(t)
	return out


## Camino para quedar junto a un rectángulo. Prueba las casillas cercanas en orden.
func path_to_rect(from: Vector2, r: Rect2i, nav := 0) -> PackedVector2Array:
	var cands := ring_around(r, nav)
	if cands.is_empty():
		return PackedVector2Array()
	cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return center(p).distance_squared_to(from) < center(q).distance_squared_to(from))
	var first := PackedVector2Array()
	for i in mini(cands.size(), 4):
		var p := path_to_tile(from, cands[i], Vector2.INF, nav)
		if i == 0:
			first = p
		var end_t := to_tile(p[p.size() - 1]) if p.size() > 0 else to_tile(from)
		if end_t == cands[i]:
			return p
	return first


## Distancia de un punto al borde de un rectángulo de casillas.
static func dist_to_rect(p: Vector2, r: Rect2i) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)
