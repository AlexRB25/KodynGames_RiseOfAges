class_name Fog
extends RefCounted
## Niebla de guerra del equipo local. 0 = sin explorar, 1 = explorado, 2 = a la vista.

var map: MapData
var explored := PackedByteArray()
var visible := PackedByteArray()
var image: Image
var texture: ImageTexture
var _buf := PackedByteArray()
var _circles := {}
var reveal_all := false


func setup(m: MapData) -> void:
	map = m
	explored.resize(m.w * m.h)
	explored.fill(0)
	visible.resize(m.w * m.h)
	visible.fill(0)
	_buf.resize(m.w * m.h)
	_buf.fill(0)
	image = Image.create_from_data(m.w, m.h, false, Image.FORMAT_L8, _buf)
	texture = ImageTexture.create_from_image(image)


func _circle(r: int) -> PackedInt32Array:
	if _circles.has(r):
		return _circles[r]
	var out := PackedInt32Array()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r + r:
				out.append(dx)
				out.append(dy)
	_circles[r] = out
	return out


## sources: Array de [Vector2 posición, int radio de visión]
func update(sources: Array) -> void:
	if reveal_all:
		visible.fill(1)
		explored.fill(1)
	else:
		visible.fill(0)
		for s in sources:
			var p: Vector2 = s[0]
			var cx := floori(p.x)
			var cy := floori(p.y)
			var c := _circle(s[1])
			for k in range(0, c.size(), 2):
				var x := cx + c[k]
				var y := cy + c[k + 1]
				if x < 0 or y < 0 or x >= map.w or y >= map.h:
					continue
				var i := y * map.w + x
				visible[i] = 1
				explored[i] = 1
	for i in _buf.size():
		_buf[i] = 255 if visible[i] == 1 else (110 if explored[i] == 1 else 0)
	image.set_data(map.w, map.h, false, Image.FORMAT_L8, _buf)
	texture.update(image)


func is_visible(p: Vector2) -> bool:
	var x := floori(p.x)
	var y := floori(p.y)
	if x < 0 or y < 0 or x >= map.w or y >= map.h:
		return false
	return visible[y * map.w + x] == 1


func is_explored_rect(r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x >= 0 and y >= 0 and x < map.w and y < map.h and explored[y * map.w + x] == 1:
				return true
	return false


func is_visible_rect(r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x >= 0 and y >= 0 and x < map.w and y < map.h and visible[y * map.w + x] == 1:
				return true
	return false
