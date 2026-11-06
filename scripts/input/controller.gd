class_name Controller
extends Node
## Entrada del jugador local: selecciÃ³n, Ã³rdenes y colocaciÃ³n de edificios.
## Clic izq = seleccionar (arrastrar = recuadro, Shift = aÃ±adir, doble clic = todos los del mismo tipo).
## Clic der = orden segÃºn el objetivo. Teclas: Esc, Supr, H (centro), . (aldeano sin tarea),
## Ctrl+1..9 guardar grupo, 1..9 recuperarlo, Espacio = ir a la selecciÃ³n.

var game: Game
var selection: Array[Entity] = []
var placing := ""
var drag_start := Vector2.ZERO
var dragging := false
var drag_rect := Rect2()
var wall_start := Vector2i(-1, -1)
var groups := {}
var _ghost: Node3D
var _ghost_parts: Array[MeshInstance3D] = []
var _last_click_t := 0.0
var _last_click_kind := ""
var _idle_i := 0
var _press_pos := Vector2.ZERO
var _touch_long_t := -1.0


func setup(g: Game) -> void:
	game = g


func forget(e: Entity) -> void:
	if selection.has(e):
		selection.erase(e)
		game.hud.refresh_selection()
	for k in groups:
		groups[k].erase(e)


func cam() -> RtsCamera:
	return game.camera


# ---------------- selecciÃ³n ----------------

func set_selection(list: Array) -> void:
	var before := selection.duplicate()
	_selection_sound(list, before)
	for e in selection:
		if is_instance_valid(e):
			e.set_selected(false)
	selection.clear()
	for e in list:
		if Entity.live(e) or (e is Animal and Entity.valid(e)):
			selection.append(e)
			e.set_selected(true)
	game.hud.refresh_selection()


## Al elegir algo nuevo: "¿sí?" si son unidades propias; toc si es un edificio.
func _selection_sound(list: Array, before: Array) -> void:
	if list.is_empty() or list == before:
		return
	var e = list[0]
	if not Entity.valid(e) or e.owner_id != game.local_id:
		return
	if e is Unit:
		Sfx.order_voice(list, true)
	elif e is Building:
		Sfx.play("seleccion", -3.0)


func add_to_selection(list: Array) -> void:
	var s := selection.duplicate()
	for e in list:
		if s.has(e):
			s.erase(e)
		else:
			s.append(e)
	set_selection(s)


func own_units_selected() -> Array[Unit]:
	var out: Array[Unit] = []
	for e in selection:
		if e is Unit and e.owner_id == game.local_id and not e.dead:
			out.append(e)
	return out


func own_animals_selected() -> Array[Animal]:
	var out: Array[Animal] = []
	for e in selection:
		if e is Animal and e.owner_id == game.local_id and not e.dead:
			out.append(e)
	return out


func own_building_selected() -> Building:
	for e in selection:
		if e is Building and e.owner_id == game.local_id:
			return e
	return null


func _screen_of(p: Vector2, h: float) -> Vector2:
	return cam().cam.unproject_position(Vector3(p.x, h + game.map.height_at(p), p.y))


func _on_screen(p: Vector2, h: float) -> bool:
	return not cam().cam.is_position_behind(Vector3(p.x, h + game.map.height_at(p), p.y))


## Entidad bajo el cursor.
func pick(sp: Vector2) -> Entity:
	var best: Entity = null
	var bd := 34.0 if Hud.is_touch() else 20.0
	for u in game.units:
		if u.dead or not u.visible:
			continue
		var d := _screen_of(u.pos, 0.6).distance_to(sp)
		if d < bd:
			bd = d
			best = u
	for a in game.animals:
		if not a.visible:
			continue
		var d := _screen_of(a.pos, 0.3).distance_to(sp)
		if d < bd:
			bd = d
			best = a
	for rl in game.relics:
		if not rl.visible or not rl.on_ground():
			continue
		var d := _screen_of(rl.pos, 0.3).distance_to(sp)
		if d < bd:
			bd = d
			best = rl
	if best:
		return best
	var g := cam().screen_to_ground(sp)
	var e = game.map.entity_at(MapData.to_tile(g))
	if e and e.visible:
		return e
	# edificios altos: comparar con el centro proyectado
	bd = 9999.0
	for b in game.buildings:
		if not b.visible:
			continue
		var s: float = b.def["size"]
		var d := _screen_of(b.center(), s * 0.4).distance_to(sp)
		var lim := 900.0 / cam().dist * s * 0.4
		if d < lim and d < bd:
			bd = d
			best = b
	return best


# ---------------- entrada ----------------

var _fingers := 0
const TAP_SLOP_TOUCH := 28.0      # con el dedo, moverse menos que esto sigue siendo un toque
var _cmd_drag: Dictionary = {}    # orden arrastrada desde una unidad (celular)


func _update_cmd_drag(p: Vector2) -> void:
	var from: Entity = _cmd_drag["from"]
	if not Entity.live(from):
		_cmd_drag = {}
		game.hud.set_drag_line(Vector2.ZERO, Vector2.ZERO, "")
		return
	var a := _screen_of(from.pos, 0.4)
	if p.distance_to(_cmd_drag["start"]) <= TAP_SLOP_TOUCH:
		game.hud.set_drag_line(Vector2.ZERO, Vector2.ZERO, "")
		return
	# El icono de la acciÃ³n que harÃ¡ al soltar (talar, minar, atacarâ€¦).
	var keep := selection.duplicate()
	selection.assign(_cmd_drag["units"])
	var act := action_for(pick(p))
	selection.assign(keep)
	game.hud.set_drag_line(a, p, act if act != "" else "mover")
var _two_finger := false


## Contar los dedos aquÃ­ (antes que los botones) y por Ã­ndice: si un botÃ³n se quedaba
## con el "levantar" del dedo, el contador quedaba en 1 y luego todo toque parecÃ­a
## de dos dedos y se ignoraba.
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventScreenTouch):
		return
	if ev.pressed and not ev.canceled:
		# El dedo 0 solo baja cuando no hay otro dedo: limpiar dedos "pegados".
		if ev.index == 0:
			_finger_ids.clear()
		_finger_ids[ev.index] = true
	else:
		_finger_ids.erase(ev.index)
	_fingers = _finger_ids.size()
	if _fingers == 0:
		_two_finger = false
	elif _fingers >= 2:
		# Con dos dedos se mueve la cÃ¡mara: cancelar el recuadro de selecciÃ³n.
		_two_finger = true
		if not _cmd_drag.is_empty():
			_cmd_drag = {}
			game.hud.set_drag_line(Vector2.ZERO, Vector2.ZERO, "")
		if dragging:
			dragging = false
			game.hud.set_drag_rect(Rect2())
var _finger_ids: Dictionary = {}


func _unhandled_input(ev: InputEvent) -> void:
	if game.over:
		return
	if ev is InputEventScreenTouch:
		return
	if _two_finger and ev is InputEventMouseButton:
		return
	if ev is InputEventMouseButton:
		_mouse_button(ev)
	elif ev is InputEventMouseMotion:
		if not _cmd_drag.is_empty():
			_update_cmd_drag(ev.position)
			return
		if dragging:
			var cur: Vector2 = ev.position
			drag_rect = Rect2(drag_start, cur - drag_start).abs()
			game.hud.set_drag_rect(drag_rect if drag_rect.size.length() > 6.0 else Rect2())
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev)


func _mouse_button(ev: InputEventMouseButton) -> void:
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if placing != "":
				if Defs.BUILDINGS[placing].get("wall", false):
					wall_start = MapData.to_tile(cam().screen_to_ground(ev.position))
				else:
					_place_at(ev.position, ev.shift_pressed)
				return
			if Hud.is_touch():
				var e := pick(ev.position)
				if e and e.owner_id == game.local_id and ((e is Unit and not e.dead) or (e is Animal and not e.dead)):
					var group: Array = selection.duplicate() if selection.has(e) else [e]
					_cmd_drag = {"units": group, "from": e, "start": ev.position}
					return
			dragging = true
			drag_start = ev.position
			drag_rect = Rect2()
		else:
			if placing != "" and wall_start.x >= 0:
				_place_wall(ev.position, ev.shift_pressed)
				return
			if not _cmd_drag.is_empty():
				var cd := _cmd_drag
				_cmd_drag = {}
				game.hud.set_drag_line(Vector2.ZERO, Vector2.ZERO, "")
				if ev.position.distance_to(cd["start"]) > TAP_SLOP_TOUCH:
					var alive: Array = []
					for u in cd["units"]:
						if Entity.live(u):
							alive.append(u)
					set_selection(alive)
					_command(ev.position, false)
				else:
					_click_select(ev.position, false)
				return
			if not dragging:
				return
			dragging = false
			game.hud.set_drag_rect(Rect2())
			if drag_rect.size.length() > (TAP_SLOP_TOUCH if Hud.is_touch() else 6.0):
				_box_select(drag_rect, ev.shift_pressed)
			else:
				_click_select(ev.position, ev.shift_pressed)
	elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		if placing != "":
			cancel_placing()
			return
		_command(ev.position, ev.shift_pressed)


func _click_select(sp: Vector2, add: bool) -> void:
	var e := pick(sp)
	# TÃ¡ctil: con tus unidades seleccionadas, tocar otra cosa (suelo, recurso, enemigo) es una orden.
	if Hud.is_touch() and (not own_units_selected().is_empty() or not own_animals_selected().is_empty()):
		var own: bool = e != null and (e is Unit or e is Building or e is Animal) and e.owner_id == game.local_id
		var useful_building: bool = own and e is Building and action_for(e) != ""
		if not own or useful_building:
			_command(sp, false)
			return
	var now := Time.get_ticks_msec() / 1000.0
	if e == null:
		if not add:
			set_selection([])
		return
	# doble clic: todos los de ese tipo en pantalla
	if e is Unit and e.owner_id == game.local_id and now - _last_click_t < 0.35 and _last_click_kind == e.kind:
		var vis := game.get_viewport().get_visible_rect()
		var all: Array = []
		for u in game.units:
			if u.owner_id == game.local_id and u.kind == e.kind and not u.dead and vis.has_point(_screen_of(u.pos, 0.6)):
				all.append(u)
		set_selection(all)
		return
	_last_click_t = now
	_last_click_kind = e.kind
	if add and e.owner_id == game.local_id:
		add_to_selection([e])
	else:
		set_selection([e])


func _box_select(r: Rect2, add: bool) -> void:
	var found: Array = []
	for u in game.units:
		if u.owner_id == game.local_id and not u.dead and _on_screen(u.pos, 0.6) and r.has_point(_screen_of(u.pos, 0.6)):
			found.append(u)
	if found.is_empty():
		for a in game.animals:
			if a.owner_id == game.local_id and not a.dead and _on_screen(a.pos, 0.3) and r.has_point(_screen_of(a.pos, 0.3)):
				found.append(a)
	if found.is_empty():
		for b in game.buildings:
			if b.owner_id == game.local_id and r.has_point(_screen_of(b.center(), 0.5)):
				found.append(b)
				break
	# Si hay militares y aldeanos, el recuadro prefiere a los militares solo con Alt.
	if add:
		var s := selection.duplicate()
		for e in found:
			if not s.has(e):
				s.append(e)
		set_selection(s)
	else:
		set_selection(found)


func _command(sp: Vector2, queue: bool) -> void:
	var g := cam().screen_to_ground(sp)
	var target := pick(sp)
	var us := own_units_selected()
	if not us.is_empty():
		if target and target is ResourceNode and not game.fog.is_explored_rect(target.rect):
			target = null
		game.order_units(us, target, g, queue)
		Sfx.order_voice(us)
		_marker(g, target)
		return
	var herd := own_animals_selected()
	if not herd.is_empty():
		game.issue({"k": "order", "u": game._ids(herd), "t": target.id if target else 0, "x": g.x, "y": g.y, "q": false})
		_marker(g, null)
		return
	var b := own_building_selected()
	if b:
		game.issue({"k": "rally", "e": b.id, "x": g.x, "y": g.y, "t": target.id if target else 0})
		_marker(g, target)


func _marker(p: Vector2, target: Entity) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.42
	tm.rings = 16
	tm.ring_segments = 4
	mi.mesh = tm
	var c := Color(0.4, 1.0, 0.4)
	if target and game.is_enemy(game.local_id, target.owner_id):
		c = Color(1.0, 0.3, 0.3)
	elif target and (target.has_resource() or target is Animal):
		c = Color(1.0, 0.85, 0.3)
	mi.material_override = Mat.flat(c)
	mi.position = Vector3(p.x, 0.05 + game.map.height_at(p), p.y)
	game.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 1, 0.2), 0.5)
	tw.tween_callback(mi.queue_free)


func _key(ev: InputEventKey) -> void:
	match ev.keycode:
		KEY_ESCAPE:
			if placing != "":
				cancel_placing()
			elif not selection.is_empty():
				set_selection([])
			else:
				game.hud.toggle_menu()
		KEY_DELETE:
			var kill: Array = []
			for e in selection:
				if not Entity.valid(e) or e.owner_id != game.local_id:
					continue
				if e is Unit:
					kill.append(e.id)
				elif e is Building:
					game.issue({"k": "destroy", "e": e.id})
			if not kill.is_empty():
				game.issue({"k": "kill", "u": kill})
		KEY_H:
			for b in game.buildings:
				if b.owner_id == game.local_id and b.kind == "centro":
					set_selection([b])
					cam().focus(b.center())
					break
		KEY_PERIOD:
			select_next_idle()
		KEY_SPACE:
			if not selection.is_empty() and Entity.valid(selection[0]):
				cam().focus(selection[0].center())
		KEY_F3:
			game.paused = not game.paused
	if ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
		var n: int = ev.keycode - KEY_0
		if ev.ctrl_pressed:
			groups[n] = selection.duplicate()
		elif groups.has(n):
			var live: Array = []
			for e in groups[n]:
				if Entity.live(e):
					live.append(e)
			set_selection(live)
			if ev.shift_pressed and not live.is_empty():
				cam().focus(live[0].center())


func idle_villagers() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in game.units:
		if u.owner_id == game.local_id and u.is_worker() and u.is_idle():
			out.append(u)
	return out


func select_next_idle() -> void:
	var list := idle_villagers()
	if list.is_empty():
		return
	_idle_i = (_idle_i + 1) % list.size()
	set_selection([list[_idle_i]])
	cam().focus(list[_idle_i].pos)


# ---------------- colocar edificios ----------------

func start_placing(k: String) -> void:
	var reason := game.build_block_reason(game.local_id, k)
	if reason == "" and any_builder(k) == null:
		reason = Lang.t("No tienes barcos pesqueros.") if _fisher_build(k) else Lang.t("No tienes aldeanos.")
	if reason != "":
		game.hud.notify(reason, Vector2.INF)
		return
	cancel_placing()
	placing = k
	_ghost = Node3D.new()
	game.add_child(_ghost)
	_ghost_parts.clear()


func cancel_placing() -> void:
	placing = ""
	wall_start = Vector2i(-1, -1)
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_ghost_parts.clear()


func _ghost_tile(sp: Vector2) -> Vector2i:
	var g := cam().screen_to_ground(sp)
	var sz: int = Defs.BUILDINGS[placing]["size"]
	return Vector2i(floori(g.x - sz * 0.5 + 0.5), floori(g.y - sz * 0.5 + 0.5))


func _wall_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := b - a
	var n := maxi(absi(d.x), absi(d.y))
	for i in n + 1:
		var t := Vector2i(roundi(a.x + d.x * float(i) / maxf(n, 1)), roundi(a.y + d.y * float(i) / maxf(n, 1)))
		if out.is_empty() or out[out.size() - 1] != t:
			out.append(t)
	return out


var _cursor := ""
var _cursor_t := 0.0


## QuÃ© harÃ­a la selecciÃ³n con clic derecho sobre esa entidad ("" = moverse).
func action_for(target: Entity) -> String:
	var us := own_units_selected()
	if us.is_empty() or target == null:
		return ""
	for u in us:
		if u.kind == "santo" and target is Relic and target.on_ground():
			return "recolectar"
		if u.kind == "santo" and u.relic and target is Building and target.owner_id == game.local_id and target.def.get("wonder", false):
			return "depositar"
		if u.kind == "arquero" and target is Building and target.owner_id == game.local_id and target.garrison_space() > 0:
			return "depositar"
		if u.is_fisher():
			if target is Building and target.owner_id == game.local_id and target.kind == "trampa":
				return "pescar" if target.complete else "construir"
			if target is ResourceNode and target.kind == "pesca":
				return "pescar"
	if target is Relic:
		return ""
	if target is Animal and not target.dead and target.tame and target.owner_id != game.local_id:
		for u in us:
			if u.is_villager():
				return "pastorear"
	if target.owner_id >= 0 and game.is_enemy(game.local_id, target.owner_id) and not target.dead:
		for u in us:
			if u.can_hit(target):
				return "atacar"
		return ""
	var vill := false
	var carrying := {}
	for u in us:
		if u.is_villager():
			vill = true
			if u.carry > 0.0:
				carrying[u.carry_type] = true
	if not vill:
		if target is Animal and not target.dead:
			return "atacar"
		return ""
	if target is Building and target.owner_id == game.local_id:
		if not target.complete:
			return "construir"
		if target.kind == "granja":
			return "cosechar"
		for r in carrying:
			if target.def.get("drop", []).has(r):
				return "depositar"
		return ""
	if target is Animal:
		return "cazar"
	if target is ResourceNode and target.has_resource():
		match target.kind:
			"arbol":
				return "talar"
			"piedra", "oro":
				return "minar"
			"arbusto":
				return "recolectar"
			"pesca":
				return "pescar"
	return ""


func _set_cursor(kind: String) -> void:
	if kind == _cursor:
		return
	_cursor = kind
	if kind == "":
		Input.set_custom_mouse_cursor(null)
	else:
		Input.set_custom_mouse_cursor(Cursors.texture(kind), Input.CURSOR_ARROW, Cursors.hotspot(kind))


func _update_cursor(dt: float) -> void:
	_cursor_t -= dt
	if _cursor_t > 0.0:
		return
	_cursor_t = 0.05
	if placing != "" or dragging or game.over:
		_set_cursor("")
		return
	# Sobre la interfaz: cursor normal.
	var hovered := game.get_viewport().gui_get_hovered_control()
	if hovered and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_set_cursor("")
		return
	var sp := game.get_viewport().get_mouse_position()
	var t := pick(sp)
	if t is ResourceNode and not game.fog.is_explored_rect(t.rect):
		t = null
	_set_cursor(action_for(t))


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)


func _process(dt: float) -> void:
	_update_cursor(dt)
	if placing == "" or _ghost == null:
		return
	var sp := game.get_viewport().get_mouse_position()
	var tiles: Array[Vector2i] = []
	if Defs.BUILDINGS[placing].get("wall", false) and wall_start.x >= 0:
		tiles = _wall_tiles(wall_start, MapData.to_tile(cam().screen_to_ground(sp)))
	else:
		tiles = [_ghost_tile(sp)]
	var sz: int = Defs.BUILDINGS[placing]["size"]
	while _ghost_parts.size() < tiles.size():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sz, 0.6 if sz > 1 else 1.0, sz)
		mi.mesh = bm
		_ghost.add_child(mi)
		_ghost_parts.append(mi)
	for i in _ghost_parts.size():
		var mi := _ghost_parts[i]
		mi.visible = i < tiles.size()
		if not mi.visible:
			continue
		var t := tiles[i]
		mi.position = Vector3(t.x + sz * 0.5, 0.3 + game.map.tile_h(t), t.y + sz * 0.5)
		var ok := game.can_place_ui(placing, t)
		mi.material_override = Mat.flat(Color(0.3, 1.0, 0.3, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45))


func _place_at(sp: Vector2, keep: bool) -> void:
	var k := placing
	var t := _ghost_tile(sp)
	if not game.can_place_ui(k, t):
		game.hud.notify(Lang.t("No se puede construir ahí."), Vector2.INF)
		return
	var reason := game.build_block_reason(game.local_id, k)
	if reason != "":
		game.hud.notify(reason, Vector2.INF)
		cancel_placing()
		return
	_issue_place(k, [t], keep)
	if not keep:
		cancel_placing()


func _place_wall(sp: Vector2, keep: bool) -> void:
	var k := placing
	var tiles: Array = []
	for t in _wall_tiles(wall_start, MapData.to_tile(cam().screen_to_ground(sp))):
		if game.can_place_ui(k, t):
			tiles.append(t)
	wall_start = Vector2i(-1, -1)
	if tiles.is_empty():
		game.hud.notify(Lang.t("No se puede construir ahí."), Vector2.INF)
	else:
		_issue_place(k, tiles, keep)
	if not keep:
		cancel_placing()


## Manda la orden de construir; si no hay aldeanos seleccionados, el juego elige el mÃ¡s cercano.
func _issue_place(k: String, tiles: Array, queue: bool) -> void:
	var ids: Array = []
	for u in own_units_selected():
		if (u.is_fisher() if _fisher_build(k) else u.is_villager()):
			ids.append(u.id)
	var tl: Array = []
	for t in tiles:
		tl.append([t.x, t.y])
	game.issue({"k": "place", "b": k, "tiles": tl, "u": ids, "q": queue})
	Sfx.play("colocar")


func any_villager() -> Unit:
	for u in game.units:
		if u.owner_id == game.local_id and u.is_villager() and not u.dead:
			return u
	return null


## Lo construyen los barcos pesqueros (trampa para peces) en vez de los aldeanos.
func _fisher_build(k: String) -> bool:
	return String(Defs.BUILDINGS[k].get("builder", "aldeano")) == "barco_pesca"


## Alguien que pueda construir ese edificio.
func any_builder(k: String) -> Unit:
	if not _fisher_build(k):
		return any_villager()
	for u in game.units:
		if u.owner_id == game.local_id and u.is_fisher() and not u.dead:
			return u
	return null
