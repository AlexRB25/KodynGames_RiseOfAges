class_name Cursors
extends RefCounted
## Cursores de acción dibujados por código (provisionales hasta tener arte).
## La punta de la herramienta queda arriba a la izquierda (ahí "hace clic").

const SIZE := 40
const OUTLINE := Color(0.05, 0.04, 0.03)
const WOOD := Color(0.58, 0.38, 0.18)
const METAL := Color(0.80, 0.82, 0.86)
const DARK_METAL := Color(0.45, 0.47, 0.52)
const GOLD := Color(0.95, 0.78, 0.25)

static var _cache := {}

## Cada icono: lista de trazos [punto_a, punto_b, grosor, color] o discos [centro, radio, color].
static func _shapes(kind: String) -> Array:
	match kind:
		"construir":   # martillo
			return [[Vector2(32, 35), Vector2(13, 15), 3.5, WOOD], [Vector2(5, 15), Vector2(17, 3), 7.0, DARK_METAL], [Vector2(4, 16), Vector2(7, 13), 4.0, METAL]]
		"talar":       # hacha
			return [[Vector2(34, 36), Vector2(13, 13), 3.5, WOOD], [Vector2(14, 14), Vector2(3, 11), 3.0, METAL], [Vector2(14, 14), Vector2(11, 3), 3.0, METAL],
				[Vector2(13, 13), Vector2(7, 7), 6.0, METAL], [Vector2(3, 11), Vector2(11, 3), 3.0, Color.WHITE], [Vector2(15, 11), Vector2(18, 8), 3.0, DARK_METAL]]
		"minar":       # pico
			return [[Vector2(33, 35), Vector2(15, 15), 3.5, WOOD], [Vector2(3, 22), Vector2(9, 10), 4.0, DARK_METAL], [Vector2(9, 10), Vector2(21, 3), 4.0, DARK_METAL], [Vector2(3, 22), Vector2(4, 19), 2.0, METAL], [Vector2(21, 3), Vector2(18, 4), 2.0, METAL]]
		"cazar":       # cuchillo
			return [[Vector2(34, 34), Vector2(24, 24), 5.0, WOOD], [Vector2(25, 25), Vector2(7, 7), 4.5, METAL], [Vector2(8, 8), Vector2(3, 3), 2.5, METAL], [Vector2(26, 22), Vector2(22, 26), 3.0, DARK_METAL]]
		"atacar":      # espada
			return [[Vector2(29, 29), Vector2(4, 4), 4.0, METAL], [Vector2(6, 6), Vector2(3, 3), 2.0, Color.WHITE], [Vector2(23, 33), Vector2(33, 23), 3.5, GOLD], [Vector2(29, 29), Vector2(37, 37), 4.5, WOOD]]
		"recolectar":  # canasta con bayas
			return [[Vector2(9, 25), Vector2(31, 25), 12.0, WOOD], [Vector2(9, 21), Vector2(31, 21), 2.0, WOOD.darkened(0.3)], [Vector2(9, 18), Vector2(20, 8), 2.0, WOOD], [Vector2(20, 8), Vector2(31, 18), 2.0, WOOD],
				[Vector2(14, 17), 3.5, Color(0.85, 0.12, 0.2)], [Vector2(20, 15), 3.5, Color(0.9, 0.18, 0.25)], [Vector2(26, 17), 3.5, Color(0.8, 0.1, 0.2)]]
		"pescar":      # caña con anzuelo
			return [[Vector2(37, 37), Vector2(16, 4), 2.5, WOOD], [Vector2(16, 4), Vector2(8, 6), 1.0, Color.WHITE], [Vector2(8, 6), Vector2(8, 22), 1.0, Color.WHITE],
				[Vector2(8, 22), Vector2(11, 27), 2.0, METAL], [Vector2(11, 27), Vector2(15, 24), 2.0, METAL], [Vector2(15, 24), Vector2(14, 21), 2.0, METAL]]
		"cosechar":    # hoz
			return [[Vector2(35, 35), Vector2(25, 25), 4.0, WOOD], [Vector2(25, 25), Vector2(17, 12), 3.0, METAL], [Vector2(17, 12), Vector2(9, 8), 3.0, METAL], [Vector2(9, 8), Vector2(3, 12), 3.0, METAL], [Vector2(3, 12), Vector2(4, 17), 2.0, METAL]]
		"pastorear":   # cayado de pastor
			return [[Vector2(30, 37), Vector2(16, 12), 3.0, WOOD], [Vector2(16, 12), Vector2(12, 5), 3.0, WOOD], [Vector2(12, 5), Vector2(6, 4), 3.0, WOOD],
				[Vector2(6, 4), Vector2(3, 8), 3.0, WOOD], [Vector2(3, 8), Vector2(5, 12), 3.0, WOOD], [Vector2(26, 27), 4.0, Color(0.95, 0.94, 0.9)]]
		"depositar":   # costal
			return [[Vector2(20, 26), 10.0, Color(0.80, 0.68, 0.45)], [Vector2(20, 16), Vector2(20, 10), 6.0, Color(0.80, 0.68, 0.45)], [Vector2(15, 14), Vector2(25, 14), 2.5, WOOD], [Vector2(20, 26), 3.0, GOLD]]
	return []


static func hotspot(kind: String) -> Vector2:
	match kind:
		"recolectar", "depositar":
			return Vector2(20, 20)
		"pescar":
			return Vector2(12, 25)
	return Vector2(4, 4)


static func texture(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var shapes := _shapes(kind)
	for pass_i in 2:
		for sh in shapes:
			var outline := pass_i == 0
			if sh[0] is Vector2 and sh[1] is Vector2:
				_line(img, sh[0], sh[1], sh[2] + (2.4 if outline else 0.0), OUTLINE if outline else sh[3])
			else:
				_disc(img, sh[0], sh[1] + (1.2 if outline else 0.0), OUTLINE if outline else sh[2])
	var t := ImageTexture.create_from_image(img)
	_cache[kind] = t
	return t


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(floori(c.y - r), ceili(c.y + r) + 1):
		for x in range(floori(c.x - r), ceili(c.x + r) + 1):
			if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, col)


static func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := maxi(1, int(a.distance_to(b) * 2.0))
	for i in n + 1:
		_disc(img, a.lerp(b, float(i) / n), w * 0.5, col)
