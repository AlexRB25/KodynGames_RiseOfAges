class_name Thumbs
extends RefCounted
## Miniaturas para los botones: si hay arte del usuario (Art.portrait) se usa ese;
## si no, se toma una "foto" del edificio o unidad en 3D en un SubViewport aparte.
## Cambian solas por civilización y era.

static var _cache := {}
static var _white: ImageTexture


static func get_icon(game: Game, kind: String) -> Texture2D:
	var p: PlayerState = game.players[game.local_id]
	var key := "%s|%s|%d" % [p.civ, kind, p.age]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = Art.portrait(p.civ, kind, p.age)
	if t == null:
		t = _render(game, kind)
	_cache[key] = t
	return t


static func _render(game: Game, kind: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(112, 112)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_3d = Viewport.MSAA_4X
	# Los materiales leen la niebla de guerra: para la foto, una niebla "todo visible".
	var real_fog := Mat.fog_tex
	var real_size := Mat.map_size
	if _white == null:
		var img := Image.create(4, 4, false, Image.FORMAT_L8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	Mat.setup(_white, Vector2(1000, 1000))
	var obj: Node3D
	var size := 1.0
	if Defs.BUILDINGS.has(kind):
		var b := Building.new()
		b.game = game
		b.kind = kind
		b.owner_id = game.local_id
		b.def = Defs.BUILDINGS[kind]
		b.complete = true
		b.progress = 1.0
		b.sow = 1.0
		b.food = b.def.get("food", 0.0)
		b.visual = Node3D.new()
		b.add_child(b.visual)
		b._rebuild_visual()
		obj = b
		size = float(b.def["size"])
	else:
		var u := Unit.new()
		u.game = game
		u.kind = kind
		u.owner_id = game.local_id
		u.def = Defs.UNITS[kind]
		u._build_visual()
		u.idle_label.visible = false
		obj = u
		size = 1.0
	Mat.setup(real_fog, real_size)
	obj.set_process(false)
	obj.set_physics_process(false)
	vp.add_child(obj)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var h := maxf(size, 1.2)
	cam.size = h * 1.45 if Defs.BUILDINGS.has(kind) else 1.7
	var target := Vector3(0, h * 0.3 if Defs.BUILDINGS.has(kind) else 0.55, 0)
	var dir := Vector3(1.0, 0.95, 1.0).normalized()
	cam.look_at_from_position(target + dir * 20.0, target, Vector3.UP)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.68)
	e.ambient_light_energy = 0.8
	env.environment = e
	vp.add_child(env)
	# El SubViewport tiene que estar en el árbol para dibujarse una vez.
	game.add_child(vp)
	return vp.get_texture()


## Al cambiar de era o de partida, volver a tomar las fotos.
static func clear() -> void:
	_cache.clear()
