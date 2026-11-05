class_name Tutorial
extends CanvasLayer
## Tutorial guiado dentro de una partida tranquila (el rival no ataca).
## Oscurece la pantalla menos un círculo iluminado sobre lo que hay que tocar,
## con flecha, globo de texto y "Omitir". Cada paso avanza solo al hacerlo.
## Para agregar pasos: añadir un diccionario a _steps() (ver los que ya hay).

var game: Game
var dim: ColorRect
var deco: Control
var bubble: PanelContainer
var title: Label
var text: RichTextLabel
var next_btn: Button
var skip_btn: Button
var steps: Array = []
var i := -1
var target_pos := Vector2.ZERO
var target_r := 0.0
var _t := 0.0
var _villager: Unit
var _villager2: Unit   # el segundo aldeano (para la comida)
var _spot := Vector2.ZERO          # lugar marcado para "mueve el aldeano aquí"
var _start_vills := 0
var _marker: MeshInstance3D

const SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(-1000.0);
uniform float radius = 0.0;
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform float alpha = 0.62;
void fragment() {
	vec2 p = UV * rect_size;
	float d = distance(p, center);
	float a = radius > 0.0 ? smoothstep(radius, radius + 22.0, d) : 1.0;
	COLOR = vec4(0.0, 0.0, 0.0, a * alpha);
}
"""


func setup(g: Game) -> void:
	game = g
	layer = 20
	dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE   # deja tocar lo que está debajo
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	dim.material = mat
	add_child(dim)
	deco = Control.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_deco)
	add_child(deco)
	bubble = PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.16, 0.11, 0.07, 0.96)
	bs.border_color = Color(0.96, 0.76, 0.30)
	bs.set_border_width_all(3)
	bs.set_corner_radius_all(14)
	bs.set_content_margin_all(16)
	bubble.add_theme_stylebox_override("panel", bs)
	add_child(bubble)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(520, 0)
	vb.add_theme_constant_override("separation", 8)
	bubble.add_child(vb)
	var font: Font = load("res://assets/ui/fuentes/LilitaOne-Regular.ttf")
	title = Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.30))
	vb.add_child(title)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.add_theme_font_size_override("normal_font_size", 19)
	text.add_theme_font_size_override("bold_font_size", 19)
	text.add_theme_color_override("default_color", Color(0.98, 0.93, 0.80))
	vb.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	skip_btn = Button.new()
	skip_btn.text = "Omitir tutorial"
	skip_btn.custom_minimum_size = Vector2(170, 42)
	skip_btn.pressed.connect(_skip)
	row.add_child(skip_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	next_btn = Button.new()
	next_btn.custom_minimum_size = Vector2(170, 42)
	next_btn.pressed.connect(_on_next)
	row.add_child(next_btn)
	for b in [skip_btn, next_btn]:
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 20)
	steps = _steps()
	for u in game.units:
		if u.owner_id == game.local_id and u.is_villager():
			_start_vills += 1
	_go(0)


func _touch() -> bool:
	return Hud.is_touch()


## Los pasos. "target" devuelve [posición en pantalla, radio] o [] para ninguno;
## "done" devuelve true cuando el jugador ya lo hizo; sin "done", hay botón Siguiente.
func _steps() -> Array:
	var tap := "Toca" if _touch() else "Haz clic en"
	var order := "toca" if _touch() else "haz [b]clic derecho[/b] en"
	return [
		{"title": "¡Bienvenido a Rise of Ages!",
			"text": "Este es tu [b]Centro[/b], el corazón de tu pueblo: aquí llegan los recursos y se compran aldeanos.\nSi te quedas sin Centros, pierdes.",
			"start": func() -> void: game.camera.focus(_centro().center()),
			"target": func() -> Array: return _ent(_centro(), 2.0, 1.2)},
		{"title": "Selecciona un aldeano",
			"text": "%s este aldeano para elegirlo." % tap,
			"start": func() -> void:
				_villager = _a_villager()
				game.camera.focus(_villager.pos),
			"target": func() -> Array: return _ent(_villager, 0.4, 0.35),
			"tap_select": func() -> Unit: return _villager,
			"done": func() -> bool:
				# Vale cualquier aldeano tuyo: seguimos con el que eligió.
				for u in game.controller.own_units_selected():
					if u.is_villager():
						_villager = u
						return true
				return false},
		{"title": "Muévelo",
			"text": ("Ahora toca el lugar marcado: tu aldeano caminará hasta ahí.\n[i](También puedes dejar el dedo sobre el aldeano y arrastrarlo.)[/i]" if _touch()
				else "Con el aldeano elegido, haz [b]clic derecho[/b] en el lugar marcado para que camine hasta ahí."),
			"start": func() -> void:
				_spot = _free_spot(_villager.pos, 5.0)
				_show_marker(_spot),
			"target": func() -> Array: return _point(_spot, 0.9),
			"done": func() -> bool: return Entity.live(_villager) and _villager.pos.distance_to(_spot) < 1.6},
		{"title": "Junta madera",
			"text": "Para construir necesitas madera. Con el aldeano elegido, %s este [b]árbol[/b]: lo cortará y llevará la madera al Centro él solo." % order,
			"start": func() -> void:
				_hide_marker()
				game.camera.focus(_tree().center()),
			"target": func() -> Array: return _ent(_tree(), 0.6, 0.6),
			"done": func() -> bool: return _anyone("madera")},
		{"title": "Elige otro aldeano",
			"text": "Tu primer aldeano ya está cortando madera. Ahora %s este otro aldeano [b]sin tarea[/b]." % tap.to_lower(),
			"start": func() -> void:
				_villager2 = _a_villager(_villager)
				game.camera.focus(_villager2.pos),
			"target": func() -> Array: return _ent(_villager2, 0.4, 0.35),
			"tap_select": func() -> Unit: return _villager2,
			"done": func() -> bool:
				for u in game.controller.own_units_selected():
					if u.is_villager() and u != _villager:
						_villager2 = u
						return true
				return false},
		{"title": "Junta comida",
			"text": "Con este aldeano elegido, %s estas [b]bayas[/b]. La comida sirve para comprar más aldeanos.
[i](Las cabras se pueden pastorear: más adelante te dan comida sin matarlas.)[/i]" % order,
			"start": func() -> void: game.camera.focus(_food().center()),
			"target": func() -> Array: return _ent(_food(), 0.4, 0.5),
			"done": func() -> bool: return _anyone("comida")},
		{"title": "Compra un aldeano",
			"text": ("Abajo, en la pestaña [b]Aldeanos[/b], toca [b]Aldeano[/b] y luego [b]Comprar[/b].\n[i](Si dejas el dedo encima, se compra solo.)[/i]" if _touch()
				else "Abajo, en la pestaña [b]Aldeanos[/b], haz clic en [b]Aldeano[/b]. Cuesta 50 de comida."),
			"start": func() -> void: game.hud.set_tab("aldeanos"),
			"target": func() -> Array: return _button("Aldeano"),
			"done": func() -> bool: return _centro().queue.has("aldeano") or _vills() > _start_vills},
		{"title": "Construye una casa",
			"text": "Cada casa te deja tener 5 personas más. Abre [b]Edificios[/b], elige [b]Casa[/b] y %s un lugar libre del mapa." % ("toca" if _touch() else "haz clic en"),
			"target": func() -> Array:
				if game.hud.tab != "edificios":
					return _tab("edificios")
				if game.controller.placing == "":
					return _button("Casa")
				return [],
			"done": func() -> bool: return game.count_buildings(game.local_id, ["casa"], false) > 0},
		{"title": "Tus recursos",
			"text": "Arriba ves tu [b]alimento, madera, oro, piedra[/b] y tu [b]población[/b]. Los aldeanos sin tarea muestran un [b]![/b] y te avisan.",
			"target": func() -> Array: return _rect(game.hud.res_labels["comida"].get_parent().get_parent())},
		{"title": "Sube de era",
			"text": "Al centro de arriba está tu [b]era[/b] (nivel 1 a 5). Para subir necesitas recursos y ciertos edificios; el Centro te dice cuáles faltan. Cada era, tu gente y tus edificios se ven mejor.",
			"target": func() -> Array: return _rect(game.hud.era_tex)},
		{"title": "¡Listo!",
			"text": "Ya sabes lo básico. Junta recursos, crece tu pueblo, arma un ejército y deja al rival [b]sin ningún Centro[/b] para ganar.\nEn esta partida el rival no ataca: sigue practicando o vuelve al menú.",
			"target": func() -> Array: return [],
			"last": true},
	]


# ---------------- avance ----------------

func _go(n: int) -> void:
	i = n
	if i >= steps.size():
		_finish(false)
		return
	var st: Dictionary = steps[i]
	title.text = String(st["title"])
	text.text = String(st["text"])
	if st.has("start"):
		st["start"].call()
	var waits := st.has("done")
	next_btn.visible = not waits
	next_btn.text = "Ir al menú" if st.get("last", false) else "Siguiente"
	skip_btn.text = "Seguir jugando" if st.get("last", false) else "Omitir tutorial"


func _on_next() -> void:
	if steps[i].get("last", false):
		_finish(true)
	else:
		_go(i + 1)


func _skip() -> void:
	if i < steps.size() and steps[i].get("last", false):
		_finish(false)   # "Seguir jugando"
		return
	_finish(false)


func _finish(to_menu: bool) -> void:
	Account.set_tutorial_done(true)
	_hide_marker()
	if to_menu:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	queue_free()


## En el paso "selecciona un aldeano", tocar dentro del círculo lo elige siempre,
## aunque haya otro aldeano más cerca del dedo.
func _input(ev: InputEvent) -> void:
	if i < 0 or i >= steps.size() or not steps[i].has("tap_select"):
		return
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var who: Unit = steps[i]["tap_select"].call()
	if target_r <= 0.0 or not Entity.live(who):
		return
	if ev.position.distance_to(target_pos) > maxf(target_r, 40.0) + 16.0:
		return
	get_viewport().set_input_as_handled()
	if not ev.pressed:
		game.controller.set_selection([who])


func _process(dt: float) -> void:
	if i < 0 or i >= steps.size():
		return
	_t += dt
	var st: Dictionary = steps[i]
	if st.has("done") and st["done"].call():
		_go(i + 1)
		return
	var tg: Array = st["target"].call()
	var vs := get_viewport().get_visible_rect().size
	if tg.is_empty():
		target_pos = Vector2(-1000, -1000)
		target_r = 0.0
	else:
		target_pos = tg[0]
		target_r = tg[1] * (1.0 + 0.06 * sin(_t * 5.0))
	var m: ShaderMaterial = dim.material
	m.set_shader_parameter("center", target_pos)
	m.set_shader_parameter("radius", target_r)
	m.set_shader_parameter("rect_size", vs)
	m.set_shader_parameter("alpha", 0.62 if target_r > 0.0 else 0.45)
	# Globo arriba si lo iluminado está abajo, y al revés.
	var bsz := bubble.get_combined_minimum_size()
	var bx := clampf((target_pos.x if target_r > 0.0 else vs.x * 0.5) - bsz.x * 0.5, 16, vs.x - bsz.x - 16)
	var by := 90.0
	if target_r > 0.0 and target_pos.y < vs.y * 0.45:
		by = minf(target_pos.y + target_r + 40.0, vs.y - bsz.y - 240.0)
	elif target_r <= 0.0:
		by = (vs.y - bsz.y) * 0.4
	bubble.position = Vector2(bx, by)
	bubble.size = bsz
	deco.queue_redraw()


func _draw_deco() -> void:
	if target_r <= 0.0:
		return
	var gold := Color(1.0, 0.82, 0.3)
	deco.draw_arc(target_pos, target_r + 4.0, 0, TAU, 48, gold, 4.0, true)
	# Flecha desde el globo hacia el círculo.
	var bc := bubble.position + bubble.size * 0.5
	var dir := (target_pos - bc)
	if dir.length() < target_r + 60.0:
		return
	dir = dir.normalized()
	var tip := target_pos - dir * (target_r + 10.0)
	var base := tip - dir * 46.0
	var side := Vector2(-dir.y, dir.x)
	var bob := sin(_t * 6.0) * 6.0
	tip += dir * bob
	base += dir * bob
	deco.draw_line(base - dir * 30.0, base, gold, 9.0, true)
	deco.draw_colored_polygon(PackedVector2Array([tip, base + side * 18.0, base - side * 18.0]), gold)


# ---------------- ayudas ----------------

func _centro() -> Building:
	return game.main_center(game.local_id)


func _vills() -> int:
	var n := 0
	for u in game.units:
		if u.owner_id == game.local_id and u.is_villager() and not u.dead:
			n += 1
	return n


func _a_villager(except: Unit = null) -> Unit:
	for u in game.units:
		if u != except and u.owner_id == game.local_id and u.is_villager() and not u.dead and u.is_idle():
			return u
	for u in game.units:
		if u != except and u.owner_id == game.local_id and u.is_villager() and not u.dead:
			return u
	return null


## ¿Algún aldeano tuyo está juntando ese recurso?
func _anyone(res: String) -> bool:
	for u in game.units:
		if u.owner_id != game.local_id or u.dead or not u.is_villager():
			continue
		if u.carry_type == res and u.carry > 0.0:
			return true
		if Entity.valid(u.target) and u.state == Unit.S.GATHER and u.target.res_type() == res:
			return true
	return false


func _tree() -> Entity:
	return game.find_resource_near("arbol", _centro().center(), 40.0, game.local_id)


## Bayas cercanas (o un venado). Las cabras se pastorean, así que no sirven aquí.
func _food() -> Entity:
	var b := game.find_resource_near("arbusto", _centro().center(), 40.0, game.local_id)
	if b:
		return b
	var best: Entity = null
	var bd := INF
	for a in game.animals:
		if not a.dead and not a.tame and a.pos.distance_to(_centro().center()) < bd:
			bd = a.pos.distance_to(_centro().center())
			best = a
	return best


func _free_spot(from: Vector2, d: float) -> Vector2:
	var c := _centro().center()
	var away := (from - c).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var p := from + away * d
	return MapData.center(game.map.nearest_free(MapData.to_tile(p)))


func _ent(e: Entity, h: float, r_world: float) -> Array:
	if not Entity.valid(e):
		return []
	var c := game.controller._screen_of(e.center(), h)
	var edge := game.controller._screen_of(e.center() + Vector2(r_world, 0), h)
	return [c, maxf(46.0, c.distance_to(edge) + 26.0)]


func _point(p: Vector2, r_world: float) -> Array:
	var c := game.controller._screen_of(p, 0.0)
	var edge := game.controller._screen_of(p + Vector2(r_world, 0), 0.0)
	return [c, maxf(46.0, c.distance_to(edge) + 20.0)]


func _rect(c: Control) -> Array:
	if c == null or not c.is_visible_in_tree():
		return []
	var r := c.get_global_rect()
	return [r.get_center(), maxf(r.size.x, r.size.y) * 0.5 + 14.0]


func _button(label: String) -> Array:
	for s in game.hud._btn_specs:
		var b: Button = s[0]
		if is_instance_valid(b) and b.text == label:
			return _rect(b)
	return []


func _tab(t: String) -> Array:
	var b: Control = game.hud._tab_btns.get(t)
	return _rect(b)


func _show_marker(p: Vector2) -> void:
	_hide_marker()
	_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.62
	tm.rings = 24
	tm.ring_segments = 6
	_marker.mesh = tm
	_marker.material_override = Mat.flat(Color(1.0, 0.85, 0.3))
	_marker.position = Vector3(p.x, game.map.height_at(p) + 0.06, p.y)
	game.add_child(_marker)


func _hide_marker() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
