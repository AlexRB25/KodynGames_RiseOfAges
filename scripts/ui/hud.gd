class_name Hud
extends CanvasLayer
## Interfaz de la partida: recursos arriba, minimapa / información / acciones abajo,
## avisos, menú de pausa y pantalla de resultado.

var game: Game
var res_labels := {}
var pop_label: Label
var age_label: Label
var era_tex: TextureRect
var portrait: TextureRect
var _era_shown := -1
var time_label: Label
var idle_btn: Button
var notes: VBoxContainer
var info_title: Label
var info_body: RichTextLabel
var actions: GridContainer
var queue_box: HBoxContainer
var drag_panel: Panel
var menu_panel: PanelContainer
var result_panel: PanelContainer
var minimap: Minimap
var _btn_specs: Array = []     # [Button, Callable que devuelve motivo de bloqueo]
var _sel_sig := ""
var _t := 0.0

const BG := Color(0.13, 0.10, 0.07, 0.93)
const BORDER := Color(0.72, 0.56, 0.28)
const TEXT := Color(0.96, 0.91, 0.78)


func setup(g: Game) -> void:
	game = g
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top(root)
	_build_bottom(root)
	notes = VBoxContainer.new()
	notes.position = Vector2(12, 56)
	notes.custom_minimum_size = Vector2(560, 0)
	notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notes)
	drag_panel = Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.4, 1.0, 0.4, 0.12)
	ds.border_color = Color(0.5, 1.0, 0.5, 0.9)
	ds.set_border_width_all(1)
	drag_panel.add_theme_stylebox_override("panel", ds)
	drag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_panel.visible = false
	root.add_child(drag_panel)
	_build_menu(root)
	refresh_selection()


func _make_theme() -> Theme:
	var t := Theme.new()
	var p := StyleBoxFlat.new()
	p.bg_color = BG
	p.border_color = BORDER
	p.set_border_width_all(2)
	p.set_corner_radius_all(4)
	p.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", p)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.30, 0.22, 0.13)
	b.border_color = BORDER
	b.set_border_width_all(1)
	b.set_corner_radius_all(3)
	b.set_content_margin_all(4)
	var bh := b.duplicate()
	bh.bg_color = Color(0.42, 0.31, 0.17)
	var bd := b.duplicate()
	bd.bg_color = Color(0.18, 0.15, 0.12)
	bd.border_color = Color(0.4, 0.33, 0.22)
	t.set_stylebox("normal", "Button", b)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bh)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.42))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("font_size", "Button", 13)
	t.set_font_size("font_size", "Label", 15)
	t.set_font_size("normal_font_size", "RichTextLabel", 14)
	t.set_font_size("bold_font_size", "RichTextLabel", 14)
	var tp := p.duplicate()
	tp.set_content_margin_all(6)
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


func _build_top(root: Control) -> void:
	# Barra compacta arriba a la izquierda: icono + número.
	var bar := PanelContainer.new()
	bar.position = Vector2(8, 6)
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	bar.add_child(hb)
	for r in Defs.RES:
		var ic := ResIcon.new(r)
		ic.tooltip_text = Defs.RES_NAMES[r]
		hb.add_child(ic)
		var l := Label.new()
		l.custom_minimum_size = Vector2(58, 0)
		l.add_theme_font_size_override("font_size", 17)
		hb.add_child(l)
		res_labels[r] = l
	var pi := ResIcon.new("pop")
	pi.tooltip_text = "Población / máximo"
	hb.add_child(pi)
	pop_label = Label.new()
	pop_label.custom_minimum_size = Vector2(66, 0)
	pop_label.add_theme_font_size_override("font_size", 17)
	hb.add_child(pop_label)
	# Al centro: la insignia de la era (nivel 1-5).
	var mid := VBoxContainer.new()
	mid.anchor_left = 0.5
	mid.anchor_right = 0.5
	mid.offset_left = -125
	mid.offset_right = 125
	mid.offset_top = 0
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_theme_constant_override("separation", -6)
	root.add_child(mid)
	era_tex = TextureRect.new()
	era_tex.custom_minimum_size = Vector2(250, 76)
	era_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	era_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mid.add_child(era_tex)
	age_label = Label.new()
	age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	age_label.add_theme_font_size_override("font_size", 15)
	age_label.add_theme_color_override("font_outline_color", Color.BLACK)
	age_label.add_theme_constant_override("outline_size", 5)
	age_label.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(age_label)
	# A la derecha: tiempo, aldeanos sin tarea, mapa (táctil) y menú.
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.position.y = 6
	right.offset_right = -8
	root.add_child(right)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	right.add_child(hr)
	time_label = Label.new()
	hr.add_child(time_label)
	idle_btn = Button.new()
	idle_btn.tooltip_text = "Aldeanos sin tarea (tecla .)"
	idle_btn.pressed.connect(func() -> void: game.controller.select_next_idle())
	hr.add_child(idle_btn)
	if is_touch():
		var mapb := Button.new()
		mapb.text = "Mapa"
		mapb.custom_minimum_size = Vector2(90, 40)
		mapb.pressed.connect(func() -> void: full_map.visible = not full_map.visible)
		hr.add_child(mapb)
	var mb := Button.new()
	mb.text = "Menú"
	mb.custom_minimum_size = Vector2(70, 0)
	mb.pressed.connect(toggle_menu)
	hr.add_child(mb)


func _build_bottom(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -220
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)
	# Acciones por secciones: Campo / Edificios / Aldeanos / Selección
	var act := VBoxContainer.new()
	act.custom_minimum_size = Vector2(572, 0)
	act.add_theme_constant_override("separation", 6)
	hb.add_child(act)
	tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 4)
	act.add_child(tabs_row)
	actions = GridContainer.new()
	actions.columns = 4
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 4)
	act.add_child(actions)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(150, 150)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.visible = false
	hb.add_child(portrait)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(260, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	info_title = Label.new()
	info_title.add_theme_font_size_override("font_size", 19)
	info.add_child(info_title)
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.fit_content = false
	info_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_body.scroll_active = false
	info_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(info_body)
	queue_box = HBoxContainer.new()
	info.add_child(queue_box)
	# Minimapa en rombo abajo a la derecha (PC/Web). En celular/tablet: botón "Mapa".
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(400, 200)
	hb.add_child(minimap)
	minimap.setup(game)
	minimap.visible = not is_touch()
	_build_full_map(root)


static func is_touch() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		return true
	return "--touch" in OS.get_cmdline_user_args()


var full_map: PanelContainer


func _build_full_map(root: Control) -> void:
	full_map = PanelContainer.new()
	full_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_map.visible = false
	root.add_child(full_map)
	var vb := VBoxContainer.new()
	full_map.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	var t := Label.new()
	t.text = "Mapa — toca para ir a ese lugar"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var close := Button.new()
	close.text = "Cerrar ✕"
	close.custom_minimum_size = Vector2(120, 48)
	close.pressed.connect(func() -> void: full_map.visible = false)
	top.add_child(close)
	var big := Minimap.new()
	big.size_flags_vertical = Control.SIZE_EXPAND_FILL
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(big)
	big.setup(game)
	big.jumped.connect(func() -> void: full_map.visible = false)


func _build_menu(root: Control) -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.visible = false
	root.add_child(menu_panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(300, 0)
	vb.add_theme_constant_override("separation", 8)
	menu_panel.add_child(vb)
	var t := Label.new()
	t.text = "Pausa"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	vb.add_child(t)
	var cont := Button.new()
	cont.text = "Continuar"
	cont.pressed.connect(toggle_menu)
	vb.add_child(cont)
	var speed := OptionButton.new()
	for s in ["Velocidad x1", "Velocidad x1.5", "Velocidad x2"]:
		speed.add_item(s)
	speed.item_selected.connect(func(i: int) -> void: game.time_scale = [1.0, 1.5, 2.0][i])
	speed.disabled = game.online
	vb.add_child(speed)
	var edge := CheckBox.new()
	edge.text = "Mover cámara con los bordes"
	edge.button_pressed = true
	edge.toggled.connect(func(on: bool) -> void: game.camera.edge_scroll = on)
	vb.add_child(edge)
	var help := Label.new()
	help.text = "Clic izq: seleccionar · Arrastrar: recuadro\nClic der: mover / recolectar / atacar\nWASD o bordes: mover · Q/E o rueda central: girar\nRueda: acercar · H: centro · .: aldeano sin tarea\nCtrl+1-9: guardar grupo · Shift: varias obras"
	help.add_theme_font_size_override("font_size", 12)
	vb.add_child(help)
	var resign := Button.new()
	resign.text = "Rendirse"
	resign.tooltip_text = "Pierdes la partida" + (" (cuenta para tus puntos)." if Net.ranked else ".")
	resign.pressed.connect(func() -> void:
		menu_panel.visible = false
		if not game.online:
			game.paused = false
		game.issue({"k": "resign"}))
	vb.add_child(resign)
	var quit := Button.new()
	quit.text = "Salir al menú principal" + (" (cuenta como derrota)" if Net.ranked else "")
	quit.pressed.connect(func() -> void:
		Net.close()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	vb.add_child(quit)


func toggle_menu() -> void:
	if game.over:
		return
	menu_panel.visible = not menu_panel.visible
	if not game.online:
		game.paused = menu_panel.visible
	menu_panel.position = (get_viewport().get_visible_rect().size - menu_panel.size) * 0.5


func show_result(win: bool) -> void:
	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	get_child(0).add_child(result_panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(380, 0)
	vb.add_theme_constant_override("separation", 10)
	result_panel.add_child(vb)
	var t := Label.new()
	t.text = "¡VICTORIA!" if win else "DERROTA"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 36)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if win else Color(0.9, 0.35, 0.3))
	vb.add_child(t)
	var st := RichTextLabel.new()
	st.bbcode_enabled = true
	st.fit_content = true
	var txt := ""
	for p in game.players:
		txt += "[color=#%s]■[/color] %s (%s): recolectó %d, entrenó %d, perdió %d unidades\n" % [
			p.color.to_html(false), p.name, Defs.CIVS[p.civ]["name"], int(p.stats["recolectado"]),
			p.stats["entrenados"], p.stats["muertes"]]
	st.text = txt
	vb.add_child(st)
	rating_label = RichTextLabel.new()
	rating_label.bbcode_enabled = true
	rating_label.fit_content = true
	rating_label.visible = false
	vb.add_child(rating_label)
	if Net.ranked:
		rating_label.visible = true
		rating_label.text = "[center]Calculando tus puntos…[/center]"
		if not Net.last_rated.is_empty():
			show_rating(Net.last_rated)
	var b := Button.new()
	b.text = "Volver al menú"
	b.pressed.connect(func() -> void:
		Net.close()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	vb.add_child(b)
	await get_tree().process_frame
	result_panel.position = (get_viewport().get_visible_rect().size - result_panel.size) * 0.5


var rating_label: RichTextLabel


## Puntos ganados o perdidos en la partida con rango.
func show_rating(m: Dictionary) -> void:
	if rating_label == null:
		return
	rating_label.visible = true
	var you = m.get("you")
	if not you is Dictionary:
		rating_label.text = "[center]Esta partida no contó para el rango.[/center]"
		return
	var d := int(you.get("delta", 0))
	var col := "#7dff7d" if d >= 0 else "#ff8a7a"
	var txt := "[center][font_size=22][color=%s]%s%d puntos[/color][/font_size]\nAhora: %d puntos · Nivel %d" % [
		col, "+" if d >= 0 else "", d, int(you.get("points", 0)), int(you.get("level", 1))]
	if bool(m.get("forfeit", false)):
		txt += "\n(el rival abandonó la partida)"
	rating_label.text = txt + "[/center]"


func set_drag_rect(r: Rect2) -> void:
	drag_panel.visible = r.size != Vector2.ZERO
	drag_panel.position = r.position
	drag_panel.size = r.size


func notify(text: String, _p: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	notes.add_child(l)
	while notes.get_child_count() > 6:
		notes.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


# ---------------- actualización ----------------

func _process(dt: float) -> void:
	if game == null:
		return
	var p := game.players[game.local_id]
	for r in Defs.RES:
		res_labels[r].text = str(int(p.res[r]))
	pop_label.text = "%d/%d" % [p.pop, p.pop_cap]
	pop_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if p.pop >= p.pop_cap else TEXT)
	if _era_shown != p.age:
		_era_shown = p.age
		var et := Art.era(p.civ, p.age)
		era_tex.texture = et
		era_tex.visible = et != null
		age_label.text = ("Nivel %d" % p.age) if et else ("Nivel %d · %s" % [p.age, p.age_name()])
		age_label.tooltip_text = "%s — %s" % [p.age_name(), Defs.CIVS[p.civ]["name"]]
	var t := int(game.time)
	time_label.text = "%02d:%02d" % [t / 60, t % 60]
	var idle := game.controller.idle_villagers().size()
	idle_btn.text = "Sin tarea: %d" % idle
	idle_btn.disabled = idle == 0
	_t -= dt
	if _t <= 0.0:
		_t = 0.25
		_refresh_info()
		_refresh_buttons()
		var sig := _selection_sig()
		if sig != _sel_sig:
			refresh_selection()


func _selection_sig() -> String:
	var s := ""
	for e in game.controller.selection:
		if Entity.valid(e):
			s += "%d:%s;" % [e.id, str(e.complete) if e is Building else ""]
	if game.controller.selection.size() > 0 and game.controller.selection[0] is Building:
		s += str(game.players[game.local_id].age)
	return s


var tabs_row: HBoxContainer
var tab := "aldeanos"
var _tab_btns := {}

const TAB_NAMES := {"campo": "Campo", "edificios": "Edificios", "aldeanos": "Aldeanos", "seleccion": "Selección"}
const CAMPO := ["granja", "molino", "maderero", "minero"]
const EDIFICIOS := ["casa", "cuartel", "arqueria", "establo", "torre", "muralla", "mercado", "templo", "castillo", "centro"]


func set_tab(t: String) -> void:
	tab = t
	_rebuild_actions()


func refresh_selection() -> void:
	if game == null or actions == null:
		return
	var sig := _selection_sig()
	var changed := sig != _sel_sig
	_sel_sig = sig
	# Al elegir un edificio con acciones, mostrar su pestaña.
	if changed:
		var b := game.controller.own_building_selected()
		if b and b.complete and _has_selection_actions():
			tab = "seleccion"
		elif tab == "seleccion" and not _has_selection_actions():
			tab = "aldeanos"
	_rebuild_actions()


func _has_selection_actions() -> bool:
	return not game.controller.own_units_selected().is_empty() or game.controller.own_building_selected() != null


func _rebuild_actions() -> void:
	for c in tabs_row.get_children():
		c.queue_free()
	_tab_btns.clear()
	var tabs := ["campo", "edificios", "aldeanos"]
	if _has_selection_actions():
		tabs.append("seleccion")
	elif tab == "seleccion":
		tab = "aldeanos"
	for t in tabs:
		var tb := Button.new()
		tb.text = TAB_NAMES[t]
		tb.toggle_mode = true
		tb.button_pressed = t == tab
		tb.custom_minimum_size = Vector2(110, 32)
		tb.add_theme_font_size_override("font_size", 15)
		if t == tab:
			tb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		var tt: String = t
		tb.pressed.connect(func() -> void: set_tab(tt))
		tabs_row.add_child(tb)
		_tab_btns[t] = tb
	for c in actions.get_children():
		c.queue_free()
	_btn_specs.clear()
	match tab:
		"campo":
			for k in CAMPO:
				_build_button(k)
			_seed_button()
		"edificios":
			for k in EDIFICIOS:
				_build_button(k)
		"aldeanos":
			_villager_tab()
		"seleccion":
			_selection_tab()
	_refresh_info()
	_refresh_buttons()


func _build_button(k: String) -> void:
	var d: Dictionary = Defs.BUILDINGS[k]
	var cost := Defs.cost_of(k, game.players[game.local_id].civ)
	var ctext := Defs.cost_text(cost) if not d.get("seed", false) else "1 siembra (tienes %d)" % game.players[game.local_id].seeds
	_add_btn(d["name"], "%s\nCosto: %s\n%s\n\nSi no tienes aldeanos seleccionados, va el más cercano sin tarea." % [d["name"], ctext, d["desc"]],
		func() -> void: game.controller.start_placing(k),
		func() -> String:
			var r := game.build_block_reason(game.local_id, k)
			if r == "" and game.controller.any_villager() == null:
				return "No tienes aldeanos."
			return r)


func _seed_button() -> void:
	_add_btn("Comprar siembra", "Comprar 1 siembra (%s) en el Centro.\nCada siembra = 1 granja de 4 cuadros.\nPuedes guardar varias: cuando una granja se acaba, se resiembra sola." % Defs.cost_text(Defs.SEED_COST),
		func() -> void:
			if game.players[game.local_id].can_afford(Defs.SEED_COST):
				game.issue({"k": "seed"})
			else:
				notify("Faltan recursos.", Vector2.INF),
		func() -> String:
			return "" if game.players[game.local_id].can_afford(Defs.SEED_COST) else "Faltan recursos.")


func _villager_tab() -> void:
	var c := game.main_center(game.local_id)
	if c:
		var d: Dictionary = Defs.UNITS["aldeano"]
		_add_btn("Entrenar aldeano", "Comprar un aldeano en el Centro principal.\nCosto: %s\nNecesitas espacio de población (casas)." % Defs.cost_text(Defs.cost_of("aldeano", game.players[game.local_id].civ)),
			func() -> void:
				var cc := game.main_center(game.local_id)
				if cc:
					_try(game.train_block_reason(game.local_id, cc, "aldeano"), {"k": "train", "e": cc.id, "b": "aldeano"}),
			func() -> String:
				var cc := game.main_center(game.local_id)
				return game.train_block_reason(game.local_id, cc, "aldeano") if cc else "Sin centro.")
		_age_button(c)
	_add_btn("Sin tarea", "Ir al siguiente aldeano sin tarea (tecla .)",
		func() -> void: game.controller.select_next_idle(),
		func() -> String: return "" if not game.controller.idle_villagers().is_empty() else "Todos trabajan.")
	_add_btn("Todos los aldeanos", "Seleccionar a todos tus aldeanos",
		func() -> void:
			var all: Array = []
			for u in game.units:
				if u.owner_id == game.local_id and u.is_villager():
					all.append(u)
			game.controller.set_selection(all),
		func() -> String: return "")
	_add_btn("Ir al centro", "Ver y seleccionar el centro principal (tecla H)",
		func() -> void:
			var cc := game.main_center(game.local_id)
			if cc:
				game.controller.set_selection([cc])
				game.camera.focus(cc.center()),
		func() -> String: return "")


func _age_button(c: Building) -> void:
	var p := game.players[game.local_id]
	if p.age >= Defs.AGES.size():
		return
	var nxt: Dictionary = Defs.AGES[p.age]
	var req := ""
	for r in nxt["req"]:
		req += "\n· " + r[2]
	_add_btn("Avanzar a %s" % nxt["name"], "Avanzar a la era %s (en el Centro)\nCosto: %s\nRequisitos:%s" % [
		nxt["name"], Defs.cost_text(nxt["cost"]), req],
		func() -> void:
			var cc := game.main_center(game.local_id)
			if cc:
				_try(game.age_block_reason(game.local_id, cc), {"k": "age", "e": cc.id}),
		func() -> String:
			var cc := game.main_center(game.local_id)
			return game.age_block_reason(game.local_id, cc) if cc else "Sin centro.")


func _selection_tab() -> void:
	var us := game.controller.own_units_selected()
	var b := game.controller.own_building_selected()
	if not us.is_empty():
		if is_touch():
			_add_btn("Soltar", "Quitar la selección", func() -> void: game.controller.set_selection([]), func() -> String: return "")
		_add_btn("Detener", "Detener la tarea actual", func() -> void:
			game.issue({"k": "stop", "u": game._ids(game.controller.own_units_selected())}), func() -> String: return "")
		_add_btn("Borrar", "Eliminar las unidades seleccionadas (tecla Supr)", func() -> void:
			game.issue({"k": "kill", "u": game._ids(game.controller.own_units_selected())}), func() -> String: return "")
		return
	if b == null:
		return
	if b.complete:
		for k in b.def.get("trains", []):
			var d: Dictionary = Defs.UNITS[k]
			var kk: String = k
			var bb := b
			_add_btn(d["name"], "%s\nCosto: %s\nVida %d · Ataque %d%s\n%s" % [d["name"],
				Defs.cost_text(Defs.cost_of(k, game.players[game.local_id].civ)), d["hp"], d["atk"],
				(" · Alcance %d" % d["range"]) if d["range"] > 0 else "", d["desc"]],
				func() -> void:
					_try(game.train_block_reason(game.local_id, bb, kk), {"k": "train", "e": bb.id, "b": kk}),
				func() -> String: return game.train_block_reason(game.local_id, bb, kk))
		if b.kind == "mercado":
			for r in ["comida", "madera", "piedra"]:
				var rr: String = r
				_add_btn("Comprar %s" % Defs.RES_NAMES[r].to_lower(), "Comprar 100 de %s con oro" % Defs.RES_NAMES[r].to_lower(),
					func() -> void: game.issue({"k": "buy", "r": rr}),
					func() -> String:
						return "" if game.players[game.local_id].res["oro"] >= game.market_price(game.local_id, rr) else "Faltan recursos.")
				_add_btn("Vender %s" % Defs.RES_NAMES[r].to_lower(), "Vender 100 de %s por oro" % Defs.RES_NAMES[r].to_lower(),
					func() -> void: game.issue({"k": "sell", "r": rr}),
					func() -> String:
						return "" if game.players[game.local_id].res[rr] >= 100 else "Faltan recursos.")
		if b.kind == "centro":
			_seed_button()
			_age_button(b)
	var bb3 := b
	_add_btn("Destruir", "Derribar este edificio", func() -> void:
		game.issue({"k": "destroy", "e": bb3.id}), func() -> String: return "")


## Si no hay motivo de bloqueo, manda la orden; si no, avisa.
func _try(reason: String, cmd: Dictionary) -> void:
	if reason == "":
		game.issue(cmd)
	else:
		notify(reason, Vector2.INF)


func _add_btn(text: String, tip: String, on_press: Callable, block: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.custom_minimum_size = Vector2(138, 40)
	btn.clip_text = true
	btn.pressed.connect(on_press)
	actions.add_child(btn)
	_btn_specs.append([btn, block, tip])


func _refresh_buttons() -> void:
	for s in _btn_specs:
		var btn: Button = s[0]
		if not is_instance_valid(btn):
			continue
		var reason: String = s[1].call()
		btn.disabled = reason != "" and reason != "Faltan recursos."
		btn.modulate = Color(1, 0.75, 0.7) if reason == "Faltan recursos." else Color.WHITE
		btn.tooltip_text = s[2] + ("\n\n" + reason if reason != "" else "")


func _refresh_info() -> void:
	for c in queue_box.get_children():
		c.queue_free()
	var sel: Array = []
	for e in game.controller.selection:
		if Entity.valid(e):
			sel.append(e)
	var pt: Texture2D = null
	if not sel.is_empty() and (sel[0] is Unit or sel[0] is Building) and sel[0].owner_id >= 0:
		var op: PlayerState = game.players[sel[0].owner_id]
		pt = Art.portrait(op.civ, sel[0].kind, op.age)
	portrait.texture = pt
	portrait.visible = pt != null
	if sel.is_empty():
		info_title.text = ""
		info_body.text = "Selecciona aldeanos para recolectar o construir.\nClic derecho sobre árboles, minas, bayas, animales o peces."
		return
	if sel.size() == 1:
		var e: Entity = sel[0]
		var owner_txt := "Naturaleza" if e.owner_id < 0 else game.players[e.owner_id].name
		info_title.text = "%s — %s" % [e.display_name(), owner_txt]
		var lines: Array[String] = []
		if e.max_hp > 0 and not (e is Animal and e.dead):
			lines.append("Vida: %d / %d" % [ceili(e.hp), int(e.max_hp)])
		if e is Unit:
			lines.append(e.status_text())
			if e.carry > 0.0:
				lines.append("Carga: %d %s" % [int(e.carry), Defs.RES_NAMES[e.carry_type].to_lower()])
			if e.idle_notice != "":
				lines.append("[color=#ffd75a]%s[/color]" % e.idle_notice)
			lines.append("Ataque %d · Armadura %d%s" % [e.def["atk"], e.def["armor"],
				(" · Alcance %d" % e.attack_range()) if e.attack_range() > 0 else ""])
		elif e is Building:
			if not e.complete:
				lines.append("En construcción: %d %%" % int(e.progress * 100))
			elif e.kind == "granja":
				if e.sowing():
					lines.append("Sembrando: %d %%" % int(e.sow * 100))
				else:
					lines.append("Alimento restante: %d" % int(e.food))
				lines.append("Siembras guardadas: %d" % game.players[e.owner_id].seeds)
			if e.kind == "centro" and e.owner_id == game.local_id:
				lines.append("Siembras guardadas: %d" % game.players[game.local_id].seeds)
				if game.main_center(game.local_id) == e:
					lines.append("[color=#ffd75a]Centro principal[/color]")
				var reqs := game.age_requirements(game.local_id)
				if not reqs.is_empty():
					var txt := "Para la siguiente era: "
					for r in reqs:
						txt += "[color=%s]%s %d/%d[/color]  " % ["#7dff7d" if r["ok"] else "#ff8a7a", r["text"], mini(r["have"], r["need"]), r["need"]]
					lines.append(txt)
			lines.append(e.def["desc"])
			if e.kind == "mercado" and e.owner_id == game.local_id:
				var mp := "Precios (100 u.): "
				for r in ["comida", "madera", "piedra"]:
					var pr := game.market_price(game.local_id, r)
					mp += "%s compra %d / vende %d oro   " % [Defs.RES_NAMES[r], pr, floorf(pr * 0.75)]
				lines.append(mp)
			if e.owner_id == game.local_id and not e.queue.is_empty():
				lines.append("Entrenando: %s %d %%" % [_qname(e.queue[0]), int(e.queue_progress() * 100)])
				if e.waiting_pop:
					lines.append("[color=#ff8a7a]Esperando población: construye casas.[/color]")
				var bq: Building = e
				for i in e.queue.size():
					var qb := Button.new()
					qb.text = _qname(e.queue[i]).left(3)
					qb.tooltip_text = "Cancelar el último de la cola"
					qb.custom_minimum_size = Vector2(36, 26)
					qb.pressed.connect(func() -> void: game.issue({"k": "cancel", "e": bq.id}))
					queue_box.add_child(qb)
		elif e.has_resource() or e is ResourceNode or e is Animal:
			if e is Animal and not e.dead:
				lines.append("Vida: %d · Comida: %d" % [ceili(e.hp), int(e.food)])
			else:
				lines.append("Queda: %d de %s" % [int(e.remaining()), Defs.RES_NAMES.get(e.res_type(), "").to_lower()])
		info_body.text = "\n".join(lines)
	else:
		info_title.text = "%d seleccionados" % sel.size()
		var counts := {}
		for e in sel:
			counts[e.display_name()] = counts.get(e.display_name(), 0) + 1
		var parts: Array[String] = []
		for k in counts:
			parts.append("%s ×%d" % [k, counts[k]])
		info_body.text = ", ".join(parts)


func _qname(k: String) -> String:
	if k == "era":
		return "Era"
	return Defs.UNITS[k]["name"]
