class_name Minimap
extends Control
## Minimapa: terreno explorado, recursos, unidades/edificios visibles y el área de la cámara.

var game: Game
var img: Image
var tex: ImageTexture
var base: PackedByteArray      # colores RGB del terreno
var _t := 0.0


func setup(g: Game) -> void:
	game = g
	var w := g.map.w
	img = Image.create(w, w, false, Image.FORMAT_RGB8)
	base = PackedByteArray()
	base.resize(w * w * 3)
	for i in w * w:
		var gi: int = g.map.ground[i]
		var c: Color = Color(0.18, 0.45, 0.66) if gi == MapData.WATER else TerrainView.GROUND_COLORS[gi]
		if gi == MapData.CLIFF:
			c = c.darkened(0.25)
		elif g.map.height[i] > 0.1:
			c = c.lightened(0.12)
		base[i * 3] = int(c.r * 255)
		base[i * 3 + 1] = int(c.g * 255)
		base[i * 3 + 2] = int(c.b * 255)
	tex = ImageTexture.create_from_image(img)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()


func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0.0:
		_t = 0.4
		_refresh()
	queue_redraw()


func _refresh() -> void:
	var w := game.map.w
	var buf := base.duplicate()
	var fog := game.fog
	for r in game.resources:
		if not r.visible:
			continue
		var c: Color
		match r.kind:
			"arbol":
				c = Color(0.16, 0.32, 0.12)
			"oro":
				c = Color(1.0, 0.85, 0.2)
			"piedra":
				c = Color(0.75, 0.75, 0.78)
			"arbusto":
				c = Color(0.85, 0.3, 0.4)
			_:
				c = Color(0.4, 0.7, 0.9)
		_put(buf, r.rect.position, c, w)
	for i in w * w:
		if fog.visible[i] == 1:
			continue
		var f := 0.5 if fog.explored[i] == 1 else 0.0
		buf[i * 3] = int(buf[i * 3] * f)
		buf[i * 3 + 1] = int(buf[i * 3 + 1] * f)
		buf[i * 3 + 2] = int(buf[i * 3 + 2] * f)
	for b in game.buildings:
		if not b.visible:
			continue
		var c := game.players[b.owner_id].color
		for y in range(b.rect.position.y, b.rect.end.y):
			for x in range(b.rect.position.x, b.rect.end.x):
				_put(buf, Vector2i(x, y), c, w)
	for a in game.animals:
		if a.visible:
			_put(buf, MapData.to_tile(a.pos), Color(0.95, 0.95, 0.85), w)
	for u in game.units:
		if u.visible and not u.dead:
			var t := MapData.to_tile(u.pos)
			var c := game.players[u.owner_id].color
			_put(buf, t, c, w)
			_put(buf, t + Vector2i(1, 0), c, w)
	img.set_data(w, w, false, Image.FORMAT_RGB8, buf)
	tex.update(img)


func _put(buf: PackedByteArray, t: Vector2i, c: Color, w: int) -> void:
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= w:
		return
	var i := (t.y * w + t.x) * 3
	buf[i] = int(c.r * 255)
	buf[i + 1] = int(c.g * 255)
	buf[i + 2] = int(c.b * 255)


## Transformación mapa -> control: rombo girado igual que la cámara.
func _xform() -> Transform2D:
	var w := float(game.map.w)
	var yaw := game.camera.yaw if game.camera else deg_to_rad(45.0)
	var th := -PI * 0.5 - atan2(-cos(yaw), -sin(yaw))
	var diag := w * sqrt(2.0)
	var sx := size.x / diag
	var sy := size.y / diag
	if full_square:
		sx = minf(sx, sy)
		sy = sx
	var xa := Vector2(sx * cos(th), sy * sin(th))
	var ya := Vector2(-sx * sin(th), sy * cos(th))
	var t := Transform2D(xa, ya, Vector2.ZERO)
	t.origin = size * 0.5 - t.basis_xform(Vector2(w, w) * 0.5)
	return t


var full_square := false


func _draw() -> void:
	var xf := _xform()
	draw_set_transform_matrix(xf)
	var w := float(game.map.w)
	draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(w, w)), false)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, w)), Color(0.75, 0.6, 0.3), false, 2.0 / maxf(xf.x.length(), 0.01))
	if game.camera:
		var vp := game.get_viewport().get_visible_rect().size
		var pts := PackedVector2Array()
		for sp in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]:
			var g := game.camera.screen_to_ground(sp)
			pts.append(Vector2(clampf(g.x, 0, w), clampf(g.y, 0, w)))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.95), 1.5 / maxf(xf.x.length(), 0.01))
	draw_set_transform_matrix(Transform2D.IDENTITY)


signal jumped


func _gui_input(ev: InputEvent) -> void:
	var press: bool = ev is InputEventMouseButton and ev.pressed
	var drag: bool = ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not (press or drag):
		return
	var p: Vector2 = _xform().affine_inverse() * ev.position
	var w := float(game.map.w)
	if p.x < 0 or p.y < 0 or p.x > w or p.y > w:
		return
	if press and ev.button_index == MOUSE_BUTTON_RIGHT:
		var us := game.controller.own_units_selected()
		if not us.is_empty():
			game.order_units(us, null, p, false)
		accept_event()
		return
	game.camera.focus(p)
	jumped.emit()
	accept_event()
