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
var wonder_label: Label
var idle_btn: BaseButton
const IdleButton := preload("res://scripts/ui/idle_button.gd")
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
	Thumbs.clear()
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
		ic.tooltip_text = Lang.t(Defs.RES_NAMES[r])
		hb.add_child(ic)
		var l := Label.new()
		l.custom_minimum_size = Vector2(58, 0)
		l.add_theme_font_size_override("font_size", 17)
		hb.add_child(l)
		res_labels[r] = l
	var pi := ResIcon.new("pop")
	pi.tooltip_text = Lang.t("Población / máximo")
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
	# Cuenta atrás de una maravilla (se ve para todos).
	wonder_label = Label.new()
	wonder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wonder_label.add_theme_font_size_override("font_size", 18)
	wonder_label.add_theme_color_override("font_outline_color", Color.BLACK)
	wonder_label.add_theme_constant_override("outline_size", 6)
	wonder_label.visible = false
	mid.add_child(wonder_label)
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
	var mb := Button.new()
	mb.text = Lang.t("Menú")
	mb.custom_minimum_size = Vector2(70, 0)
	mb.pressed.connect(toggle_menu)
	hr.add_child(mb)


func _build_bottom(root: Control) -> void:
	# Panel de información angosto y centrado; a los lados, la navegación del mapa.
	var bar := PanelContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = (JOY_W + 8.0) if is_touch() else 4.0
	bar.offset_right = -(MAP_W + 8.0)
	bar.offset_top = -220
	bar.offset_bottom = -4
	root.add_child(bar)
	bottom_bar = bar
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
	actions.columns = 5
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 4)
	act.add_child(actions)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(120, 120)
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
	preview_row = HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 8)
	preview_row.visible = false
	info.add_child(preview_row)
	preview_ok = Button.new()
	preview_ok.custom_minimum_size = Vector2(150, 44)
	preview_ok.add_theme_font_size_override("font_size", 17)
	preview_ok.pressed.connect(_preview_confirm)
	preview_row.add_child(preview_ok)
	var back := Button.new()
	back.text = Lang.t("Volver")
	back.custom_minimum_size = Vector2(110, 44)
	back.add_theme_font_size_override("font_size", 17)
	back.pressed.connect(func() -> void: _set_preview({}))
	preview_row.add_child(back)
	_build_nav(root)
	_build_full_map(root)


const JOY_W := 170.0    # cuadro de la palanca (celular), a la izquierda
const MAP_W := 300.0    # cuadro del minimapa, a la derecha
var bottom_bar: PanelContainer
var joystick: Joystick


## Navegación del mapa fuera del panel de información.
## PC: minimapa abajo a la derecha (clic = ir ahí, clic derecho = mandar unidades).
## Celular: abajo a la izquierda, palanca + minimapa que se arrastra suave (tocarlo no
## manda lejos) + botón "Mapa" para verlo grande.
func _build_nav(root: Control) -> void:
	var box := PanelContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -220
	box.offset_bottom = -4
	root.add_child(box)
	minimap = Minimap.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -MAP_W - 4.0
	box.offset_right = -4
	# Botón redondo de aldeanos sin tarea, chico, en la esquina vacía (arriba a la
	# izquierda) del cuadro del minimapa.
	idle_btn = IdleButton.new()
	idle_btn.anchor_left = 1.0
	idle_btn.anchor_right = 1.0
	idle_btn.anchor_top = 1.0
	idle_btn.anchor_bottom = 1.0
	idle_btn.offset_left = -MAP_W + 6.0
	idle_btn.offset_right = -MAP_W + 6.0 + 36.0
	idle_btn.offset_top = -220.0 + 10.0
	idle_btn.offset_bottom = -220.0 + 10.0 + 36.0
	root.add_child(idle_btn)
	idle_btn.setup(game)
	if not is_touch():
		minimap.custom_minimum_size = Vector2(MAP_W - 20.0, 200)
		box.add_child(minimap)
		minimap.setup(game)
		return
	# Celular: palanca sola a la izquierda.
	var jb := PanelContainer.new()
	jb.anchor_top = 1.0
	jb.anchor_bottom = 1.0
	jb.offset_top = -220
	jb.offset_bottom = -4
	jb.offset_left = 4
	jb.offset_right = JOY_W + 4.0
	root.add_child(jb)
	joystick = Joystick.new()
	joystick.setup(game)
	joystick.custom_minimum_size = Vector2(150, 150)
	joystick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	joystick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	jb.add_child(joystick)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	minimap.drag_nav = true
	minimap.custom_minimum_size = Vector2(MAP_W - 20.0, 140)
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	minimap.tooltip_text = Lang.t("Arrastra el dedo sobre el mapa para mover la vista")
	vb.add_child(minimap)
	minimap.setup(game)
	var mapb := Button.new()
	mapb.text = Lang.t("Mapa grande")
	mapb.custom_minimum_size = Vector2(0, 46)
	mapb.add_theme_font_size_override("font_size", 16)
	mapb.pressed.connect(func() -> void: full_map.visible = not full_map.visible)
	vb.add_child(mapb)


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
	t.text = Lang.t("Mapa — toca o arrastra para mover la vista. Se cierra con Cerrar.")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var close := Button.new()
	close.text = Lang.t("Cerrar ✕")
	close.custom_minimum_size = Vector2(120, 48)
	close.pressed.connect(func() -> void: full_map.visible = false)
	top.add_child(close)
	var big := Minimap.new()
	big.size_flags_vertical = Control.SIZE_EXPAND_FILL
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(big)
	big.setup(game)


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
	t.text = Lang.t("Pausa")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	vb.add_child(t)
	var cont := Button.new()
	cont.text = Lang.t("Continuar")
	cont.pressed.connect(toggle_menu)
	vb.add_child(cont)
	var speed := OptionButton.new()
	for s in [Lang.t("Velocidad x1"), Lang.t("Velocidad x1.5"), Lang.t("Velocidad x2")]:
		speed.add_item(s)
	speed.item_selected.connect(func(i: int) -> void: game.time_scale = [1.0, 1.5, 2.0][i])
	speed.disabled = game.online
	vb.add_child(speed)
	var edge := CheckBox.new()
	edge.text = Lang.t("Mover cámara con los bordes")
	edge.button_pressed = true
	edge.toggled.connect(func(on: bool) -> void: game.camera.edge_scroll = on)
	vb.add_child(edge)
	vb.add_child(Sfx.volume_row("musica", 14))
	vb.add_child(Sfx.volume_row("efectos", 14))
	var help := Label.new()
	help.text = Lang.t("Clic izq: seleccionar · Arrastrar: recuadro\nClic der: mover / recolectar / atacar\nWASD o bordes: mover · Q/E o rueda central: girar\nRueda: acercar · H: centro · .: aldeano sin tarea\nCtrl+1-9: guardar grupo · Shift: varias obras")
	help.add_theme_font_size_override("font_size", 12)
	vb.add_child(help)
	var resign := Button.new()
	resign.text = Lang.t("Rendirse")
	resign.tooltip_text = Lang.t("Pierdes la partida") + (Lang.t(" (cuenta para tus puntos).") if Net.ranked else ".")
	resign.pressed.connect(func() -> void:
		var why := Lang.t("Si te rindes, [b]pierdes la partida ahora mismo[/b]: el rival gana y tu pueblo queda derrotado.")
		if Net.ranked:
			why += "\n" + Lang.t("Es una partida con rango: [b]pierdes puntos[/b] como en cualquier derrota.")
		elif not game.online and not Setup.tutorial:
			why += "\n" + Lang.t("Contra bots cuenta como derrota: solo ganas la experiencia de perder (si jugaste 5 minutos o más).")
		_confirm(Lang.t("¿Rendirte?"), why, Lang.t("Sí, rendirme"), func() -> void:
			menu_panel.visible = false
			if not game.online:
				game.paused = false
			game.issue({"k": "resign"})))
	vb.add_child(resign)
	var quit := Button.new()
	quit.text = Lang.t("Salir al menú principal") + (Lang.t(" (cuenta como derrota)") if Net.ranked else "")
	quit.pressed.connect(func() -> void:
		var why := Lang.t("Sales de la partida y vuelves al menú principal. Lo que llevas en esta partida se pierde.")
		if Net.ranked:
			why += "\n" + Lang.t("Es una partida con rango: salir [b]cuenta como derrota[/b] y pierdes puntos.")
		_confirm(Lang.t("¿Salir de la partida?"), why, Lang.t("Sí, salir"), func() -> void:
			Net.close()
			get_tree().change_scene_to_file("res://scenes/menu.tscn")))
	vb.add_child(quit)


## Pregunta en medio de la pantalla antes de algo que no se puede deshacer.
func _confirm(title: String, body: String, yes_text: String, on_yes: Callable) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	get_child(0).add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(520, 0)
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
	vb.add_child(t)
	var b := RichTextLabel.new()
	b.bbcode_enabled = true
	b.fit_content = true
	b.add_theme_font_size_override("normal_font_size", 19)
	b.add_theme_font_size_override("bold_font_size", 19)
	b.text = body
	vb.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var no := Button.new()
	no.text = Lang.t("No, seguir jugando")
	no.custom_minimum_size = Vector2(220, 52)
	no.pressed.connect(shade.queue_free)
	row.add_child(no)
	var yes := Button.new()
	yes.text = yes_text
	yes.custom_minimum_size = Vector2(220, 52)
	yes.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	yes.pressed.connect(func() -> void:
		shade.queue_free()
		on_yes.call())
	row.add_child(yes)


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
	t.text = Lang.t("¡VICTORIA!") if win else Lang.t("DERROTA")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 36)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if win else Color(0.9, 0.35, 0.3))
	vb.add_child(t)
	var st := RichTextLabel.new()
	st.bbcode_enabled = true
	st.fit_content = true
	var txt := ""
	for p in game.players:
		txt += Lang.t("[color=#%s]■[/color] %s (%s): recolectó %d, entrenó %d, perdió %d unidades\n") % [
			p.color.to_html(false), p.name, Lang.t(Defs.CIVS[p.civ]["name"]), int(p.stats["recolectado"]),
			p.stats["entrenados"], p.stats["muertes"]]
	st.text = txt
	vb.add_child(st)
	rating_label = RichTextLabel.new()
	rating_label.bbcode_enabled = true
	rating_label.fit_content = true
	rating_label.visible = false
	vb.add_child(rating_label)
	prize_label = RichTextLabel.new()
	prize_label.bbcode_enabled = true
	prize_label.fit_content = true
	prize_label.visible = false
	vb.add_child(prize_label)
	if Net.ranked:
		rating_label.visible = true
		rating_label.text = Lang.t("[center]Calculando tus puntos…[/center]")
		if not Net.last_rated.is_empty():
			show_rating(Net.last_rated)
	elif not Setup.online and not Setup.tutorial:
		_bot_prize(win)
	var b := Button.new()
	b.text = Lang.t("Volver al menú")
	b.pressed.connect(func() -> void:
		Net.close()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	vb.add_child(b)
	await get_tree().process_frame
	result_panel.position = (get_viewport().get_visible_rect().size - result_panel.size) * 0.5


var rating_label: RichTextLabel
var prize_label: RichTextLabel
var _start_level := Account.level()    # para saber si subió de rango en esta partida
var _start_tier := Economy.tier()      # y de nivel del Game Pass
var _anims: Array = []                 # animaciones de subir de nivel en fila


## Muestra una animación de subir de nivel (una tras otra si hay varias).
func _queue_level_up(k: String, from_n: int, to_n: int, sub: String) -> void:
	_anims.append([k, from_n, to_n, sub])
	if _anims.size() == 1:
		_next_level_up()


func _next_level_up() -> void:
	if _anims.is_empty():
		return
	var a: Array = _anims[0]
	var l := LevelUp.play(get_child(0), a[0], a[1], a[2], a[3])
	l.closed.connect(func() -> void:
		_anims.pop_front()
		_next_level_up())


## Contra bots: experiencia de temporada y monedas (con tope diario, ver supabase/temporadas.sql).
func _bot_prize(win: bool) -> void:
	if not Account.accounts_ready() and not Economy.demo:
		return
	prize_label.visible = true
	prize_label.text = Lang.t("[center]Guardando tu experiencia…[/center]")
	var d: Dictionary = await Economy.bot_result(win, int(game.time))
	if not is_instance_valid(prize_label):
		return
	if d.is_empty():
		prize_label.text = Lang.t("[center][color=#cbb894]No se pudo guardar la experiencia (sin conexión).[/color][/center]")
	elif d.get("why", "") == "off":
		prize_label.visible = false
	elif not d.get("ok", false):
		var why := {"short": Lang.t("Las partidas de menos de 5 minutos no dan experiencia."),
			"limit": Lang.t("Ya jugaste las partidas contra bots con premio de hoy. Las de con rango siguen dando experiencia."),
			"soon": Lang.t("Esta partida no dio experiencia: fue muy seguida de la anterior.")}
		prize_label.text = "[center][color=#cbb894]%s[/color][/center]" % why.get(String(d.get("why", "")), "")
	else:
		_show_prize(d)


## "+100 xp de temporada · +25 monedas".
func _show_prize(d: Dictionary) -> void:
	prize_label.visible = true
	var t := Lang.t("[center][font_size=20][color=#ffd75a]+%d xp de temporada[/color]  ·  [color=#ffe08a]+%d monedas[/color][/font_size]") % [
		int(d.get("xp", 0)), int(d.get("coins", 0))]
	if d.has("tier"):
		t += "\n" + Lang.t("Game Pass: nivel %d") % int(d["tier"])
		if int(d["tier"]) > _start_tier:
			_queue_level_up("pase", _start_tier, int(d["tier"]), Lang.t("Tienes premios para reclamar"))
			_start_tier = int(d["tier"])
	prize_label.text = t + "[/center]"


## Puntos ganados o perdidos en la partida con rango.
func show_rating(m: Dictionary) -> void:
	if rating_label == null:
		return
	rating_label.visible = true
	var you = m.get("you")
	if not you is Dictionary:
		rating_label.text = Lang.t("[center]Esta partida no contó para el rango.[/center]")
		return
	var d := int(you.get("delta", 0))
	var col := "#7dff7d" if d >= 0 else "#ff8a7a"
	var txt := Lang.t("[center][font_size=22][color=%s]%s%d puntos[/color][/font_size]\nAhora: %d puntos · Nivel %d") % [
		col, "+" if d >= 0 else "", d, int(you.get("points", 0)), int(you.get("level", 1))]
	if bool(m.get("forfeit", false)):
		txt += Lang.t("\n(el rival abandonó la partida)")
	rating_label.text = txt + "[/center]"
	var lv := int(you.get("level", 1))
	if lv > _start_level:
		_queue_level_up("rango", _start_level, lv, Lang.t("%d puntos") % int(you.get("points", 0)))
		_start_level = lv
	if m.get("prize") is Dictionary and prize_label:
		_show_prize(m["prize"])
		Economy.refresh()


var _drag_line: Line2D
var _drag_icon: TextureRect


## Línea de la orden arrastrada con el dedo, con el icono de la acción en la punta.
func set_drag_line(a: Vector2, b: Vector2, action: String) -> void:
	if _drag_line == null:
		_drag_line = Line2D.new()
		_drag_line.width = 5.0
		_drag_line.default_color = Color(1.0, 0.85, 0.3, 0.9)
		_drag_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_drag_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		get_child(0).add_child(_drag_line)
		_drag_icon = TextureRect.new()
		_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drag_icon.size = Vector2(48, 48)
		_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		get_child(0).add_child(_drag_icon)
	var on := a != b
	_drag_line.visible = on
	_drag_icon.visible = on
	if not on:
		return
	_drag_line.points = PackedVector2Array([a, b])
	var hostile := action == "atacar"
	_drag_line.default_color = Color(1.0, 0.35, 0.3, 0.9) if hostile else Color(1.0, 0.85, 0.3, 0.9)
	var t: Texture2D = Cursors.texture(action) if action != "mover" else null
	_drag_icon.texture = t
	_drag_icon.visible = t != null
	_drag_icon.position = b + Vector2(-12, -64)


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
	_tick_hold(dt)
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
		age_label.text = (Lang.t("Nivel %d") % p.age) if et else (Lang.t("Nivel %d · %s") % [p.age, p.age_name()])
		age_label.tooltip_text = "%s — %s" % [p.age_name(), Lang.t(Defs.CIVS[p.civ]["name"])]
	var t := int(game.time)
	time_label.text = "%02d:%02d" % [t / 60, t % 60]
	var wc := game.wonder_countdown()
	wonder_label.visible = not wc.is_empty()
	if not wc.is_empty():
		var wt := ceili(wc["t"])
		wonder_label.text = Lang.t("Maravilla de %s: %d:%02d") % [wc["name"], wt / 60, wt % 60]
		wonder_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if wc["mine"] else Color(1, 0.45, 0.35))
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
		s += str(game.players[game.local_id].age) + str(game.players[game.local_id].bell)
	return s


var tabs_row: HBoxContainer
var tab := "aldeanos"
var _tab_btns := {}

const TAB_NAMES := {"recursos": "Recursos", "pueblo": "Pueblo", "guerra": "Guerra", "aldeanos": "Aldeanos", "seleccion": "Selección"}
## Recursos: siembra, cosecha, comida, madera, minas y pesca.
const RECURSOS := ["granja", "molino", "corral", "maderero", "minero", "muelle"]
## Pueblo: casas, centros y edificios de la aldea.
const PUEBLO := ["casa", "centro", "mercado", "herreria", "universidad", "monasterio", "maravilla"]
## Guerra: donde se entrena el ejército y las defensas.
const GUERRA := ["cuartel", "arqueria", "establo", "taller", "castillo", "torre", "muralla", "puerta"]


func set_tab(t: String) -> void:
	tab = {"campo": "recursos", "edificios": "pueblo"}.get(t, t)
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
	var tabs := ["recursos", "pueblo", "guerra", "aldeanos"]
	if _has_selection_actions():
		tabs.append("seleccion")
	elif tab == "seleccion":
		tab = "aldeanos"
	for t in tabs:
		var tb := Button.new()
		tb.text = Lang.t(TAB_NAMES[t])
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
	_preview = {}
	match tab:
		"recursos":
			_seed_button()
			for k in RECURSOS:
				_build_button(k)
		"pueblo":
			for k in PUEBLO:
				_build_button(k)
		"guerra":
			for k in GUERRA:
				_build_button(k)
		"aldeanos":
			_villager_tab()
		"seleccion":
			_selection_tab()
	_refresh_info()
	_refresh_buttons()


func _build_button(k: String) -> void:
	var d: Dictionary = Defs.BUILDINGS[k]
	var cost := game.build_cost(game.local_id, k)
	var ctext := Defs.cost_text(cost) if not d.get("seed", false) else Lang.t("1 siembra (tienes %d)") % game.players[game.local_id].seeds
	var nm := game.building_name(game.local_id, k)
	var fisher := String(d.get("builder", "aldeano")) == "barco_pesca"
	_meta = {"age": int(d.get("age", 1)), "cost": cost}
	_add_btn(nm, Lang.t("%s\nCosto: %s\n%s\n\nSi no tienes aldeanos seleccionados, va el más cercano sin tarea.") % [nm, ctext, Lang.t(d["desc"])],
		func() -> void: game.controller.start_placing(k),
		func() -> String:
			var r := game.build_block_reason(game.local_id, k)
			if r == "" and game.controller.any_builder(k) == null:
				return Lang.t("No tienes barcos pesqueros.") if fisher else Lang.t("No tienes aldeanos.")
			return r, Thumbs.get_icon(game, k))


func _seed_button() -> void:
	_meta = {"cost": Defs.SEED_COST}
	_add_btn(Lang.t("Siembra"), Lang.t("Comprar 1 siembra (%s) en el Centro.\nCada siembra = 1 granja de 4 cuadros.\nPuedes guardar varias: cuando una granja se acaba, se resiembra sola.") % Defs.cost_text(Defs.SEED_COST),
		func() -> void:
			if game.players[game.local_id].can_afford(Defs.SEED_COST):
				game.issue({"k": "seed"})
			else:
				notify(Lang.t("Faltan recursos."), Vector2.INF),
		func() -> String:
			return "" if game.players[game.local_id].can_afford(Defs.SEED_COST) else Lang.t("Faltan recursos."))


func _villager_tab() -> void:
	var c := game.main_center(game.local_id)
	if c:
		var d: Dictionary = Defs.UNITS["aldeano"]
		_meta = {"cost": Defs.cost_of("aldeano", game.players[game.local_id].civ)}
		_add_btn(Lang.t("Aldeano"), Lang.t("Entrenar un aldeano en el Centro principal.\nCosto: %s\nNecesitas espacio de población (casas).") % Defs.cost_text(Defs.cost_of("aldeano", game.players[game.local_id].civ)),
			func() -> void:
				var cc := game.main_center(game.local_id)
				if cc:
					_try(game.train_block_reason(game.local_id, cc, "aldeano"), {"k": "train", "e": cc.id, "b": "aldeano"}),
			func() -> String:
				var cc := game.main_center(game.local_id)
				return game.train_block_reason(game.local_id, cc, "aldeano") if cc else Lang.t("Sin centro."),
			Thumbs.get_icon(game, "aldeano"))
		_age_button(c)
	_add_btn(Lang.t("Sin tarea"), Lang.t("Ir al siguiente aldeano sin tarea (tecla .)"),
		func() -> void: game.controller.select_next_idle(),
		func() -> String: return "" if not game.controller.idle_villagers().is_empty() else Lang.t("Todos trabajan."))
	_add_btn(Lang.t("Todos"), Lang.t("Seleccionar a todos tus aldeanos"),
		func() -> void:
			var all: Array = []
			for u in game.units:
				if u.owner_id == game.local_id and u.is_villager():
					all.append(u)
			game.controller.set_selection(all),
		func() -> String: return "")
	_add_btn(Lang.t("Ir al centro"), Lang.t("Ver y seleccionar el centro principal (tecla H)"),
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
		req += "\n· " + Lang.t(r[2])
	_meta = {"cost": nxt["cost"]}
	_add_btn(Lang.t("Subir de era"), Lang.t("Avanzar a la era %s (en el Centro)\nCosto: %s\nRequisitos:%s") % [
		Lang.t(nxt["name"]), Defs.cost_text(nxt["cost"]), req],
		func() -> void:
			var cc := game.main_center(game.local_id)
			if cc:
				_try(game.age_block_reason(game.local_id, cc), {"k": "age", "e": cc.id}),
		func() -> String:
			var cc := game.main_center(game.local_id)
			return game.age_block_reason(game.local_id, cc) if cc else Lang.t("Sin centro."),
		Art.era(p.civ, p.age + 1))


func _selection_tab() -> void:
	var us := game.controller.own_units_selected()
	var b := game.controller.own_building_selected()
	if not us.is_empty():
		if is_touch():
			_add_btn(Lang.t("Soltar"), Lang.t("Quitar la selección"), func() -> void: game.controller.set_selection([]), func() -> String: return "")
		_add_btn(Lang.t("Detener"), Lang.t("Detener la tarea actual"), func() -> void:
			game.issue({"k": "stop", "u": game._ids(game.controller.own_units_selected())}), func() -> String: return "")
		_add_btn(Lang.t("Borrar"), Lang.t("Eliminar las unidades seleccionadas (tecla Supr)"), func() -> void:
			game.issue({"k": "kill", "u": game._ids(game.controller.own_units_selected())}), func() -> String: return "")
		return
	if b == null:
		return
	if b.complete:
		for k in b.def.get("trains", []):
			var d: Dictionary = Defs.UNITS[k]
			var kk: String = k
			var bb := b
			_meta = {"age": int(d.get("age", 1)), "cost": Defs.cost_of(k, game.players[game.local_id].civ)}
			_add_btn(Lang.t(d["name"]), Lang.t("%s\nCosto: %s\nVida %d · Ataque %d%s\n%s") % [Lang.t(d["name"]),
				Defs.cost_text(Defs.cost_of(k, game.players[game.local_id].civ)), d["hp"], d["atk"],
				(Lang.t(" · Alcance %d") % d["range"]) if d["range"] > 0 else "", Lang.t(d["desc"])],
				func() -> void:
					_try(game.train_block_reason(game.local_id, bb, kk), {"k": "train", "e": bb.id, "b": kk}),
				func() -> String: return game.train_block_reason(game.local_id, bb, kk),
				Thumbs.get_icon(game, kk))
		if b.kind == "mercado":
			for r in ["comida", "madera", "piedra"]:
				var rr: String = r
				_add_btn(Lang.t("Comprar %s") % Lang.t(Defs.RES_NAMES[r]).to_lower(), Lang.t("Comprar 100 de %s con oro") % Lang.t(Defs.RES_NAMES[r]).to_lower(),
					func() -> void: game.issue({"k": "buy", "r": rr}),
					func() -> String:
						return "" if game.players[game.local_id].res["oro"] >= game.market_price(game.local_id, rr) else Lang.t("Faltan recursos."))
				_add_btn(Lang.t("Vender %s") % Lang.t(Defs.RES_NAMES[r]).to_lower(), Lang.t("Vender 100 de %s por oro") % Lang.t(Defs.RES_NAMES[r]).to_lower(),
					func() -> void: game.issue({"k": "sell", "r": rr}),
					func() -> String:
						return "" if game.players[game.local_id].res[rr] >= 100 else Lang.t("Faltan recursos."))
		if b.kind == "centro":
			var on: bool = game.players[game.local_id].bell
			_add_btn(Lang.t("Volver al trabajo") if on else Lang.t("Campana"),
				Lang.t("Tocar otra vez la campana: los aldeanos salen y vuelven a lo que estaban haciendo.") if on else
				Lang.t("Tocar la campana: todos los aldeanos corren a refugiarse en el centro urbano (caben 15 por centro y desde adentro disparan flechas). Tócala otra vez para que vuelvan a sus labores."),
				func() -> void: game.issue({"k": "bell"}),
				func() -> String: return "",
				bell_icon(on))
			_seed_button()
			_age_button(b)
		if b.kind == "muelle":
			_build_button("trampa")
		if b.kind == "monasterio":
			var bm := b
			_meta = {"cost": Defs.RELIC_COST}
			_add_btn(Lang.t("Crear reliquia"), Lang.t("Crear una reliquia\nCosto: %s\nNecesitas un santo junto al monasterio. Tarda %d s y aparece en un lugar al azar del mapa: un santo la recoge y la lleva a tu maravilla.") % [
				Defs.cost_text(Defs.RELIC_COST), int(Defs.RELIC_TIME)],
				func() -> void: _try(game.relic_block_reason(game.local_id, bm), {"k": "relic", "e": bm.id}),
				func() -> String: return game.relic_block_reason(game.local_id, bm))
		for t in Defs.TECHS:
			if Defs.TECHS[t]["at"] == b.kind and not game.players[game.local_id].techs.has(t):
				_tech_button(b, t)
		if int(b.stat("garrison", 0)) > 0 and b.kind != "centro":
			var bg := b
			_add_btn(Lang.t("Sacar arqueros"), Lang.t("Sacar a los arqueros de la torre (%d / %d adentro).") % [b.garrison.size(), int(b.stat("garrison", 0))],
				func() -> void: game.issue({"k": "eject", "e": bg.id}),
				func() -> String: return "" if not bg.garrison.is_empty() else Lang.t("No hay arqueros adentro."))
	var bb3 := b
	_add_btn(Lang.t("Destruir"), Lang.t("Derribar este edificio"), func() -> void:
		game.issue({"k": "destroy", "e": bb3.id}), func() -> String: return "")


func _tech_button(b: Building, t: String) -> void:
	var d: Dictionary = Defs.TECHS[t]
	var bb := b
	_meta = {"age": int(d["age"]), "cost": d["cost"]}
	_add_btn(Lang.t(d["name"]), Lang.t("%s (mejora)\nCosto: %s\n%s") % [Lang.t(d["name"]), Defs.cost_text(d["cost"]), Lang.t(d["desc"])],
		func() -> void: _try(game.tech_block_reason(game.local_id, bb, t), {"k": "research", "e": bb.id, "t": t}),
		func() -> String: return game.tech_block_reason(game.local_id, bb, t))


## Si no hay motivo de bloqueo, manda la orden; si no, avisa.
func _try(reason: String, cmd: Dictionary) -> void:
	if reason == "":
		game.issue(cmd)
	else:
		notify(reason, Vector2.INF)
		Sfx.play("error")


## Datos del siguiente botón: nivel que pide y costo (para el candado de nivel y
## para decir qué recursos faltan). Se usa una vez y se borra.
var _meta := {}


## Lo que falta para pagar un costo: "50 madera, 20 oro" ("" si alcanza).
func _missing_text(cost: Dictionary) -> String:
	var p := game.players[game.local_id]
	var miss := {}
	for r in cost:
		var need := ceili(float(cost[r]) - p.res.get(r, 0.0))
		if need > 0:
			miss[r] = need
	return Defs.cost_text(miss) if not miss.is_empty() else ""


## Motivo de bloqueo explicado: qué recursos faltan exactamente.
func _explain(reason: String, meta: Dictionary) -> String:
	if reason == Lang.t("Faltan recursos.") and meta.has("cost"):
		var m := _missing_text(meta["cost"])
		if m != "":
			return Lang.t("Te faltan: %s.") % m
	return reason


static var _bell_tex := {}


## Icono de la campana: dorada en reposo; roja con ondas cuando está sonando.
static func bell_icon(on: bool) -> Texture2D:
	if _bell_tex.has(on):
		return _bell_tex[on]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.95, 0.42, 0.22) if on else Color(1.0, 0.8, 0.28)
	var dark := Color(0.3, 0.16, 0.04)
	var inside := func(x: float, y: float) -> bool:
		if y >= 10.0 and y < 22.0:
			return Vector2(x - 32.0, y - 22.0).length() <= 12.0
		if y >= 22.0 and y <= 46.0:
			var t := (y - 22.0) / 24.0
			return absf(x - 32.0) <= 12.0 + 10.0 * pow(t, 1.8)
		if y > 46.0 and y <= 50.0:
			return absf(x - 32.0) <= 24.0
		if Vector2(x - 32.0, y - 53.0).length() <= 5.0:
			return true
		var r := Vector2(x - 32.0, y - 7.0).length()
		return r <= 5.0 and r >= 2.5
	for y in n:
		for x in n:
			var fx := float(x)
			var fy := float(y)
			if bool(inside.call(fx, fy)):
				var edge: bool = not (inside.call(fx - 1.5, fy) and inside.call(fx + 1.5, fy) and inside.call(fx, fy - 1.5) and inside.call(fx, fy + 1.5))
				var c: Color = dark if edge else body
				if not edge and fx < 28.0 and fy > 14.0 and fy < 44.0:
					c = c.lightened(0.3)
				img.set_pixel(x, y, c)
			elif on:
				# Ondas a los lados: está sonando.
				var d := Vector2(fx - 32.0, fy - 30.0)
				var l := d.length()
				if absf(d.y) < absf(d.x) * 0.6 and ((l > 26.0 and l < 28.5) or (l > 31.0 and l < 33.0)):
					img.set_pixel(x, y, Color(1, 0.9, 0.5))
	var tex := ImageTexture.create_from_image(img)
	_bell_tex[on] = tex
	return tex


func _add_btn(text: String, tip: String, on_press: Callable, block: Callable, icon: Texture2D = null) -> void:
	var meta := _meta
	_meta = {}
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.custom_minimum_size = Vector2(108, 40)
	btn.clip_text = true
	if icon:
		# Miniatura arriba y el nombre abajo, para reconocerlo de un vistazo.
		btn.icon = icon
		btn.expand_icon = true
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.custom_minimum_size = Vector2(108, 82)
		btn.add_theme_font_size_override("font_size", 12)
	# Lo que cuesta algo se puede ver antes de comprarlo: en celular el primer toque
	# muestra la información con "Comprar"; en PC, al pasar el mouse.
	var costs := tip.contains(Lang.t("Costo")) or text.begins_with(Lang.t("Comprar")) or text.begins_with(Lang.t("Vender")) or text == Lang.t("Siembra")
	if costs:
		var verb := Lang.t("Comprar")
		var close := false
		if tip.contains(Lang.t("Si no tienes aldeanos seleccionados")):
			verb = Lang.t("Construir")
			close = true
		elif text == Lang.t("Subir de era"):
			verb = Lang.t("Subir de era")
			close = true
		elif tip.contains(Lang.t("(mejora)")) or text == Lang.t("Crear reliquia"):
			verb = Lang.t("Investigar") if tip.contains(Lang.t("(mejora)")) else Lang.t("Crear")
			close = true
		elif text.begins_with(Lang.t("Vender")):
			verb = Lang.t("Vender")
		var spec := {"name": text, "tip": tip, "press": on_press, "block": block, "icon": icon, "verb": verb, "close": close, "meta": meta}
		btn.pressed.connect(func() -> void:
			if not is_touch():
				var why: String = block.call()
				if why != "":
					# Bloqueado: mostrar qué falta (recursos o nivel) en vez de no hacer nada.
					spec["hover"] = false
					_set_preview(spec)
					notify(_explain(why, meta), Vector2.INF)
				else:
					on_press.call())
		# Celular: toque corto = ver información; dejar el dedo = comprar (barra que se llena).
		btn.button_down.connect(func() -> void:
			if is_touch():
				_hold = {"spec": spec, "btn": btn, "t": 0.0, "fired": false})
		btn.button_up.connect(func() -> void:
			if is_touch() and _hold.get("btn") == btn:
				var fired: bool = _hold["fired"]
				_end_hold()
				if not fired:
					_set_preview(spec))
		btn.mouse_entered.connect(func() -> void:
			if not is_touch():
				spec["hover"] = true
				_set_preview(spec))
		btn.mouse_exited.connect(func() -> void:
			if not is_touch() and _preview.get("name", "") == text:
				_set_preview({}))
	else:
		btn.pressed.connect(func() -> void:
			var why: String = block.call()
			if why != "":
				notify(_explain(why, meta), Vector2.INF)
			else:
				on_press.call())
	# Candado de nivel: la insignia de la era en que se desbloquea.
	var need_age := int(meta.get("age", 1))
	if need_age > 1:
		var badge := TextureRect.new()
		badge.name = "Nivel"
		badge.texture = Art.era(game.players[game.local_id].civ, need_age)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_WIDE)
		badge.offset_top = 2
		badge.offset_bottom = 30
		btn.add_child(badge)
		var lk := Label.new()
		lk.name = "NivelTexto"
		lk.text = Lang.t("Nivel %d") % need_age
		lk.add_theme_font_size_override("font_size", 12)
		lk.add_theme_color_override("font_outline_color", Color.BLACK)
		lk.add_theme_constant_override("outline_size", 4)
		lk.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.set_anchors_preset(Control.PRESET_TOP_WIDE)
		lk.offset_top = 28
		btn.add_child(lk)
	actions.add_child(btn)
	_btn_specs.append([btn, block, tip, need_age, meta])


func _refresh_buttons() -> void:
	for s in _btn_specs:
		var btn: Button = s[0]
		if not is_instance_valid(btn):
			continue
		var reason: String = s[1].call()
		var locked: bool = s.size() > 3 and int(s[3]) > game.players[game.local_id].age
		# Nunca se desactiva: tocarlo dice qué falta (recursos o nivel).
		btn.disabled = false
		var badge := btn.get_node_or_null("Nivel")
		if badge:
			badge.visible = locked
			btn.get_node("NivelTexto").visible = locked
		if locked:
			btn.self_modulate = Color(0.62, 0.62, 0.62)
		elif reason == Lang.t("Faltan recursos."):
			btn.self_modulate = Color(1, 0.72, 0.68)
		elif reason != "":
			btn.self_modulate = Color(0.7, 0.7, 0.7)
		else:
			btn.self_modulate = Color.WHITE
		btn.tooltip_text = s[2] + ("\n\n" + _explain(reason, s[4] if s.size() > 4 else {}) if reason != "" else "")


var preview_row: HBoxContainer
var preview_ok: Button
var _preview: Dictionary = {}


const HOLD_TIME := 1.2   # segundos con el dedo encima para comprar uno
var _hold: Dictionary = {}


func _hold_bar(btn: Button) -> ProgressBar:
	var bar := btn.get_node_or_null("Llenado") as ProgressBar
	if bar == null:
		bar = ProgressBar.new()
		bar.name = "Llenado"
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
		bar.offset_top = 3
		bar.offset_left = 4
		bar.offset_right = -4
		bar.offset_bottom = 10
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.6)
		bg.set_corner_radius_all(3)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(1.0, 0.8, 0.3)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		bar.max_value = 1.0
		btn.add_child(bar)
	return bar


func _tick_hold(dt: float) -> void:
	if _hold.is_empty():
		return
	var btn: Button = _hold["btn"]
	if not is_instance_valid(btn):
		_hold = {}
		return
	var spec: Dictionary = _hold["spec"]
	if _hold["t"] < -1.0:
		return   # ya compró lo que tocaba; espera a que suelte el dedo
	_hold["t"] += dt
	var bar := _hold_bar(btn)
	bar.visible = true
	bar.value = clampf(_hold["t"] / HOLD_TIME, 0.0, 1.0)
	if _hold["t"] < HOLD_TIME:
		return
	_hold["t"] = 0.0
	_hold["fired"] = true
	var reason: String = spec["block"].call()
	if reason != "":
		notify(_explain(reason, spec.get("meta", {})), Vector2.INF)
		_end_hold(true)
		return
	spec["press"].call()
	if spec.get("close", false):
		_end_hold(true)   # construir o subir de era: solo una vez


func _end_hold(keep_fired := false) -> void:
	if _hold.is_empty():
		return
	var btn: Button = _hold["btn"]
	if is_instance_valid(btn):
		var bar := btn.get_node_or_null("Llenado")
		if bar:
			bar.visible = false
	if keep_fired:
		_hold["t"] = -INF   # sigue "presionado" pero ya no compra más hasta soltar
	else:
		_hold = {}


func _set_preview(spec: Dictionary) -> void:
	_preview = spec
	_refresh_info()


func _preview_confirm() -> void:
	if _preview.is_empty():
		return
	var spec := _preview
	spec["press"].call()
	if spec.get("close", false):
		_set_preview({})
	else:
		_refresh_info()


## Costo con los iconos de cada recurso, para leerlo de un vistazo.
static func _cost_icons(t: String) -> String:
	# Los nombres vienen traducidos ("food", "comida"…): cambiar cada uno por su icono.
	var icons := {"comida": "alimento", "madera": "madera", "oro": "oro", "piedra": "piedra"}
	for r in Defs.RES:
		var re := RegEx.new()
		re.compile("(\\d+) " + Lang.t(Defs.RES_NAMES[r]).to_lower())
		t = re.sub(t, "[img=22]res://assets/ui/iconos/%s.png[/img] [b]$1[/b]" % icons[r], true)
	return t


func _render_preview() -> void:
	var spec := _preview
	info_title.text = String(spec["name"])
	var reason: String = spec["block"].call()
	# Primero el costo y lo que falta (para que siempre se vea), luego la descripción.
	var cost_line := ""
	var rest: Array[String] = []
	for ln in String(spec["tip"]).split("\n"):
		if ln.begins_with(Lang.t("Costo:")):
			cost_line = Lang.t("Costo:") + " " + _cost_icons(ln.trim_prefix(Lang.t("Costo:")).strip_edges())
		elif reason != "" and (ln.begins_with("· ") or ln == Lang.t("Requisitos:")):
			continue   # los requisitos que faltan ya salen en el motivo
		elif ln.strip_edges() != "" and ln != spec["name"] and not ln.begins_with(Lang.t("Si no tienes aldeanos")):
			rest.append(ln)
	var lines: Array[String] = []
	if cost_line != "":
		lines.append(cost_line)
	if reason != "":
		var meta: Dictionary = spec.get("meta", {})
		var need_age := int(meta.get("age", 1))
		if need_age > game.players[game.local_id].age:
			# Se desbloquea en otro nivel: la insignia de esa era.
			var et := Art.era(game.players[game.local_id].civ, need_age)
			var badge := ("[img=110]%s[/img] " % et.resource_path) if et and et.resource_path != "" else ""
			lines.append(badge + "[color=#ffd75a]%s[/color]" % (Lang.t("Se desbloquea en el nivel %d (%s).") % [need_age, Lang.t(Defs.AGES[need_age - 1]["name"])]))
			var miss := _missing_text(meta.get("cost", {}))
			if miss != "":
				lines.append("[color=#ff8a7a]%s[/color]" % _cost_icons(Lang.t("Además te faltan: %s.") % miss))
		else:
			lines.append("[color=#ff8a7a]%s[/color]" % _cost_icons(_explain(reason, meta)))
	lines.append_array(rest)
	info_body.text = "\n".join(lines)
	var ic: Texture2D = spec.get("icon")
	portrait.texture = ic
	portrait.visible = ic != null
	var hover: bool = spec.get("hover", false)
	preview_row.visible = not hover
	preview_ok.text = String(spec["verb"])
	preview_ok.disabled = reason != ""


func _refresh_info() -> void:
	for c in queue_box.get_children():
		c.queue_free()
	_queue_card()
	if not _preview.is_empty():
		_render_preview()
		return
	if preview_row:
		preview_row.visible = false
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
		if is_touch():
			info_body.text = Lang.t("Toca un aldeano y luego toca a dónde ir o qué recolectar.\nO deja el dedo sobre él y arrástralo hasta un árbol, mina, animal o enemigo: al soltar, va y lo hace.")
		else:
			info_body.text = Lang.t("Selecciona aldeanos para recolectar o construir.\nClic derecho sobre árboles, minas, bayas, animales o peces.")
		return
	if sel.size() == 1:
		var e: Entity = sel[0]
		var owner_txt := Lang.t("Naturaleza") if e.owner_id < 0 else game.players[e.owner_id].name
		info_title.text = "%s — %s" % [e.display_name(), owner_txt]
		var lines: Array[String] = []
		if e.max_hp > 0 and not (e is Animal and e.dead):
			lines.append(Lang.t("Vida: %d / %d") % [ceili(e.hp), int(e.max_hp)])
		if e is Unit:
			lines.append(e.status_text())
			if e.carry > 0.0:
				lines.append(Lang.t("Carga: %d %s") % [int(e.carry), Lang.t(Defs.RES_NAMES[e.carry_type]).to_lower()])
			if e.idle_notice != "":
				lines.append("[color=#ffd75a]%s[/color]" % e.idle_notice)
			if e.relic:
				lines.append(Lang.t("[color=#ffd75a]Lleva una reliquia: clic derecho en tu maravilla para guardarla.[/color]"))
			lines.append(Lang.t("Ataque %d · Armadura %d%s") % [e.def["atk"], e.armor(),
				(Lang.t(" · Alcance %d") % e.attack_range()) if e.attack_range() > 0 else ""])
		elif e is Building:
			if not e.complete:
				lines.append(Lang.t("En construcción: %d %%") % int(e.progress * 100))
			elif e.kind == "granja":
				if e.sowing():
					lines.append(Lang.t("Sembrando: %d %%") % int(e.sow * 100))
				else:
					lines.append(Lang.t("Alimento restante: %d") % int(e.food))
				lines.append(Lang.t("Siembras guardadas: %d") % game.players[e.owner_id].seeds)
			if e.kind == "centro" and e.owner_id == game.local_id:
				lines.append(Lang.t("Siembras guardadas: %d") % game.players[game.local_id].seeds)
				if game.main_center(game.local_id) == e:
					lines.append(Lang.t("[color=#ffd75a]Centro principal[/color]"))
				var reqs := game.age_requirements(game.local_id)
				if not reqs.is_empty():
					var txt := Lang.t("Para la siguiente era: ")
					for r in reqs:
						txt += "[color=%s]%s %d/%d[/color]  " % ["#7dff7d" if r["ok"] else "#ff8a7a", r["text"], mini(r["have"], r["need"]), r["need"]]
					lines.append(txt)
			lines.append(Lang.t(e.def["desc"]))
			if e.kind == "trampa" and e.complete:
				lines.append(Lang.t("Alimento restante: %d") % int(e.food))
			if e.kind == "centro" and e.complete:
				lines.append(Lang.t("Refugiados adentro: %d / %d") % [e.garrison.size(), int(e.stat("garrison", 0))])
			elif int(e.stat("garrison", 0)) > 0:
				lines.append(Lang.t("Arqueros adentro: %d / %d (cada uno dispara una flecha más)") % [e.garrison.size(), int(e.stat("garrison", 0))])
			if e.def.get("wonder", false):
				lines.append(Lang.t("Reliquias: %d / %d") % [e.relics.size(), Defs.WONDER_RELICS])
				var wp: PlayerState = game.players[e.owner_id]
				if wp.wonder_t >= 0.0:
					lines.append(Lang.t("[color=#ffd75a]Cuenta atrás: %d:%02d[/color]") % [ceili(wp.wonder_t) / 60, ceili(wp.wonder_t) % 60])
			if e.kind == "corral" and e.complete:
				lines.append(Lang.t("Animales pastando: %d / %d  (+%.1f de alimento por segundo)") % [e.grazers, Defs.CORRAL_CAP, e.grazers * Defs.GRAZE_RATE])
			if e.kind == "mercado" and e.owner_id == game.local_id:
				var mp := Lang.t("Precios (100 u.): ")
				for r in ["comida", "madera", "piedra"]:
					var pr := game.market_price(game.local_id, r)
					mp += Lang.t("%s compra %d / vende %d oro   ") % [Lang.t(Defs.RES_NAMES[r]), pr, floorf(pr * 0.75)]
				lines.append(mp)
			if e.owner_id == game.local_id and not e.queue.is_empty() and e.waiting_pop:
				lines.append(Lang.t("[color=#ff8a7a]Esperando población: construye casas.[/color]"))
		elif e is Relic:
			lines.append(Lang.t("Llévala con un santo a tu maravilla. Con 3 reliquias dentro empieza la cuenta atrás para ganar."))
		elif e.has_resource() or e is ResourceNode or e is Animal:
			if e is Animal and not e.dead:
				lines.append(Lang.t("Vida: %d · Carne: %d") % [ceili(e.hp), int(e.food)])
				if e.tame and e.owner_id < 0:
					lines.append(Lang.t("Salvaje. Un aldeano lo puede pastorear %d segundos seguidos y será tuyo (clic derecho con el aldeano).") % int(Defs.HERD_TIME))
				elif e.tame and e.owner_id == game.local_id:
					if e.grazing():
						lines.append(Lang.t("[color=#7dff7d]Pastando en tu corral: da %.1f de alimento por segundo y engorda.[/color]") % Defs.GRAZE_RATE)
					else:
						lines.append(Lang.t("Clic derecho en un Corral tuyo para llevarlo a pastar. Con un aldeano, clic derecho en él para sacrificarlo."))
				elif e.tame:
					lines.append(Lang.t("Un aldeano tuyo se lo puede llevar si lo pastorea %d segundos seguidos.") % int(Defs.HERD_TIME))
			else:
				lines.append(Lang.t("Queda: %d de %s") % [int(e.remaining()), Lang.t(Defs.RES_NAMES.get(e.res_type(), "")).to_lower()])
		info_body.text = "\n".join(lines)
	else:
		info_title.text = Lang.t("%d seleccionados") % sel.size()
		var counts := {}
		for e in sel:
			counts[e.display_name()] = counts.get(e.display_name(), 0) + 1
		var parts: Array[String] = []
		for k in counts:
			parts.append("%s ×%d" % [k, counts[k]])
		info_body.text = ", ".join(parts)


## Cuadrito de lo que se está creando (abajo de la descripción): icono, nombre,
## barrita de avance, cuántos más esperan y botón para cancelar el último.
## Muestra el edificio seleccionado; si no hay uno, el Centro principal.
func _queue_card() -> void:
	var b := game.controller.own_building_selected()
	if b == null or b.queue.is_empty():
		var only_units := true
		for e in game.controller.selection:
			if e is Building:
				only_units = false
		b = game.main_center(game.local_id) if only_units else null
	if b == null or b.queue.is_empty():
		return
	var k: String = b.queue[0]
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	st.border_color = Color(0.72, 0.56, 0.28)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", st)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_box.add_child(card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	card.add_child(hb)
	var ic: Texture2D = null
	if k == "era":
		ic = Art.era(game.players[game.local_id].civ, game.players[game.local_id].age + 1)
	elif Defs.UNITS.has(k):
		ic = Thumbs.get_icon(game, k)
	if ic:
		var tr := TextureRect.new()
		tr.texture = ic
		tr.custom_minimum_size = Vector2(44, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tr)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var verb := Lang.t("Creando: %s")
	if k == "era":
		verb = Lang.t("Subiendo de era: %s")
	elif k.begins_with("tech:"):
		verb = Lang.t("Investigando: %s")
	var t := Label.new()
	var more := b.queue.size() - 1
	t.text = (verb % _qname(k)) + (("   " + Lang.t("(+%d en cola)") % more) if more > 0 else "")
	if b.waiting_pop:
		t.text += "   " + Lang.t("· Faltan casas")
	elif b.waiting_santo:
		t.text += "   " + Lang.t("· Falta un santo junto al monasterio")
	t.add_theme_font_size_override("font_size", 14)
	t.clip_text = true
	t.custom_minimum_size = Vector2(10, 0)
	vb.add_child(t)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = b.queue_progress()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.6, 0.2) if b.waiting_pop or b.waiting_santo else Color(0.35, 0.85, 0.35)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	vb.add_child(bar)
	var bq := b
	var x := Button.new()
	x.text = "✕"
	x.tooltip_text = Lang.t("Cancelar el último de la cola")
	x.custom_minimum_size = Vector2(40, 40)
	x.pressed.connect(func() -> void: game.issue({"k": "cancel", "e": bq.id}))
	hb.add_child(x)


func _qname(k: String) -> String:
	if k == "era":
		return Lang.t("Era")
	if k.begins_with("tech:"):
		return Lang.t(Defs.TECHS[k.trim_prefix("tech:")]["name"])
	if k == "reliquia":
		return Lang.t("Reliquia")
	return Lang.t(Defs.UNITS[k]["name"])
