class_name MapData
extends RefCounted
## Cuadrícula del mapa: tipo de suelo, casillas bloqueadas, qué ocupa cada casilla
## y búsqueda de caminos (A*). 1 casilla = 1 unidad de mundo; el centro de la
## casilla (x, y) está en (x + 0.5, y + 0.5). En 3D, "y" del mapa es el eje Z.

enum { GRASS, WATER, SAND, DIRT, DRY, JUNGLE, DESERT }

var w := 0
var h := 0
var ground := PackedByteArray()
var solid := PackedByteArray()        # >0 = bloqueada (árbol, mina, edificio)
var reserved := PackedByteArray()     # >0 = ocupada por un edificio (aunque se pueda caminar, ej. granja)
var ent: Array = []                   # casilla -> Entity estática (recurso o edificio) o null
var astar := AStarGrid2D.new()

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
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.offset = Vector2(0.5, 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


## Llamar cuando el suelo ya está generado: marca el agua como bloqueada.
func finish_ground() -> void:
	for y in h:
		for x in w:
			if ground[y * w + x] == WATER:
				astar.set_point_solid(Vector2i(x, y), true)


func idx(t: Vector2i) -> int:
	return t.y * w + t.x


func inside(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < w and t.y < h


func is_water(t: Vector2i) -> bool:
	return inside(t) and ground[idx(t)] == WATER


## Se puede caminar por la casilla.
func is_free(t: Vector2i) -> bool:
	if not inside(t):
		return false
	var i := idx(t)
	return ground[i] != WATER and solid[i] == 0


## Libre para construir o colocar algo.
func is_open(t: Vector2i) -> bool:
	if not inside(t):
		return false
	var i := idx(t)
	return ground[i] != WATER and solid[i] == 0 and reserved[i] == 0 and ent[i] == null


func rect_open(r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not is_open(Vector2i(x, y)):
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
				astar.set_point_solid(t, true)


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
				if solid[i] == 0 and ground[i] != WATER:
					astar.set_point_solid(t, false)


func entity_at(t: Vector2i):
	if not inside(t):
		return null
	return ent[idx(t)]


static func to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func center(t: Vector2i) -> Vector2:
	return Vector2(t.x + 0.5, t.y + 0.5)


## Casilla libre más cercana (búsqueda por anillos).
func nearest_free(t: Vector2i, max_r := 20) -> Vector2i:
	if is_free(t):
		return t
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := t + Vector2i(dx, dy)
				if is_free(c):
					var d := Vector2(dx, dy).length_squared()
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return t


## Camino desde una posición hasta una casilla. Si no se puede llegar, llega lo más cerca posible.
func path_to_tile(from: Vector2, goal: Vector2i, exact_end := Vector2.INF) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := to_tile(from)
	if not is_free(a):
		a = nearest_free(a)
	if not inside(goal):
		goal = Vector2i(clampi(goal.x, 0, w - 1), clampi(goal.y, 0, h - 1))
	var g := goal
	if not is_free(g):
		g = nearest_free(goal, 6)
	if a == g:
		out.append(exact_end if exact_end != Vector2.INF and g == goal else center(g))
		return out
	var ids := astar.get_id_path(a, g, true)
	for i in range(1, ids.size()):
		out.append(center(ids[i]))
	if out.size() > 0 and exact_end != Vector2.INF and ids[ids.size() - 1] == goal:
		out[out.size() - 1] = exact_end
	return out


## Casillas libres alrededor de un rectángulo (para acercarse a un edificio o recurso).
func ring_around(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			if x >= r.position.x and x < r.end.x and y >= r.position.y and y < r.end.y:
				continue
			var t := Vector2i(x, y)
			if is_free(t):
				out.append(t)
	return out


## Camino para quedar junto a un rectángulo. Prueba las casillas cercanas en orden.
func path_to_rect(from: Vector2, r: Rect2i) -> PackedVector2Array:
	var cands := ring_around(r)
	if cands.is_empty():
		return PackedVector2Array()
	cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return center(p).distance_squared_to(from) < center(q).distance_squared_to(from))
	var first := PackedVector2Array()
	for i in mini(cands.size(), 4):
		var p := path_to_tile(from, cands[i])
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
