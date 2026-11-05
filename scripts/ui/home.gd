class_name Home
extends Control
## Pantalla principal: tu aldeano nivel 5 de tu civilización favorita (girando en 3D),
## las formas de juego a la derecha, y arriba tu nivel en línea, Tienda y Configuración.

var menu: Node
var font: Font
var civ_label: Label
var civ_desc: Label
var chip: RichTextLabel
var fig_view: CivFigure
var overlay: Control

const RED := Color(0.55, 0.13, 0.10)
const GOLD := Color(0.96, 0.76, 0.30)
const CREAM := Color(0.98, 0.93, 0.80)


func setup(m: Node) -> void:
	menu = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/ui/fuentes/LilitaOne-Regular.ttf")
	_build()
	Account.changed.connect(_refresh_chip)
	_refresh_chip()
	_show_civ()
	# La primera vez: ofrecer el tutorial (se puede omitir).
	if not Account.tutorial_done():
		_welcome()
	# Si ya jugaste en línea en este equipo, carga tu nivel.
	if Account.accounts_ready() and Account.refresh_token != "" and not Account.signed_in():
		Account.sign_in()


# ---------------- estilo ----------------

func _box(bg: Color, border: Color, radius := 14, bw := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 4)
	s.set_content_margin_all(10)
	return s


## Botón con el estilo de las insignias del juego: rojo con borde dorado.
func art_button(text: String, size: Vector2, font_size := 30, color := RED) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0.18, 0.06, 0.03))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("normal", _box(color, GOLD))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.15), GOLD.lightened(0.2)))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.2), GOLD))
	b.add_theme_stylebox_override("disabled", _box(color.darkened(0.4), GOLD.darkened(0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _label(text: String, size: int, color := CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.03))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# ---------------- pantalla ----------------

func _build() -> void:
	# Logo arriba a la izquierda.
	var logo := TextureRect.new()
	logo.texture = Art.tex("ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.position = Vector2(26, 14)
	logo.size = Vector2(330, 190)
	add_child(logo)
	# Versión abajo a la izquierda (se cambia en project.godot: application/config/version).
	var ver := Label.new()
	ver.text = "V" + str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	ver.add_theme_font_override("font", font)
	ver.add_theme_font_size_override("font_size", 20)
	ver.add_theme_color_override("font_color", Color(CREAM, 0.85))
	ver.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	ver.add_theme_constant_override("outline_size", 6)
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 20
	ver.offset_top = -40
	ver.offset_bottom = -12
	ver.offset_right = 200
	add_child(ver)
	# Arriba a la derecha: nivel en línea, Tienda, Configuración (y Salir en PC).
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_right = -24
	top.offset_top = 22
	add_child(top)
	var chip_panel := PanelContainer.new()
	chip_panel.add_theme_stylebox_override("panel", _box(Color(0.12, 0.08, 0.05, 0.85), GOLD, 12, 2))
	top.add_child(chip_panel)
	chip = RichTextLabel.new()
	chip.bbcode_enabled = true
	chip.fit_content = true
	chip.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.custom_minimum_size = Vector2(240, 0)
	chip.add_theme_font_override("normal_font", font)
	chip.add_theme_font_size_override("normal_font_size", 20)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_panel.add_child(chip)
	var shop := art_button("Tienda", Vector2(140, 58), 24, Color(0.16, 0.42, 0.22))
	shop.pressed.connect(func() -> void: _soon("Tienda", "Aquí podrás conseguir civilizaciones especiales, vestimentas y estandartes para tu pueblo.\n\nPróximamente."))
	top.add_child(shop)
	var cfg := art_button("Configuración", Vector2(200, 58), 24, Color(0.25, 0.22, 0.20))
	cfg.pressed.connect(_config)
	top.add_child(cfg)
	if not OS.has_feature("web"):
		var quit := art_button("Salir", Vector2(110, 58), 24, Color(0.25, 0.22, 0.20))
		quit.pressed.connect(func() -> void: get_tree().quit())
		top.add_child(quit)
	# Al centro-izquierda: tu aldeano nivel 5 girando sobre un pedestal.
	var left := VBoxContainer.new()
	left.anchor_left = 0.08
	left.anchor_right = 0.5
	left.anchor_top = 0.2
	left.anchor_bottom = 0.98
	left.add_theme_constant_override("separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	fig_view = CivFigure.new(Account.fav_civ(), Defs.PLAYER_COLORS[0])
	fig_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fig_view)
	civ_label = _label("", 46, GOLD)
	left.add_child(civ_label)
	civ_desc = _label("", 18)
	civ_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	civ_desc.add_theme_constant_override("outline_size", 6)
	left.add_child(civ_desc)
	var ch := art_button("Cambiar civilización", Vector2(360, 60), 26)
	ch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ch.pressed.connect(_civ_picker)
	left.add_child(ch)
	# A la derecha: las formas de juego.
	var right := VBoxContainer.new()
	right.anchor_left = 0.62
	right.anchor_right = 0.95
	right.anchor_top = 0.28
	right.anchor_bottom = 0.92
	right.add_theme_constant_override("separation", 16)
	add_child(right)
	right.add_child(_mode("UN JUGADOR", "Contra bots, de 1 vs 1 hasta 4 vs 4", func() -> void: menu.open_mode("solo")))
	right.add_child(_mode("JUGAR CON RANGO", "En línea: te emparejamos con alguien de tu nivel", func() -> void: menu.open_mode("rango")))
	right.add_child(_mode("SALA CON AMIGOS", "Crea una sala y comparte el código", func() -> void: menu.open_mode("amigos")))
	right.add_child(_mode("TORNEOS", "Próximamente", func() -> void:
		_soon("Torneos", "Torneos rápidos que empiezan solos y torneos especiales con hora fija, con premios para los mejores.\n\nPróximamente."), Color(0.30, 0.24, 0.16)))


func _mode(title: String, sub: String, cb: Callable, color := RED) -> Button:
	var b := art_button(title, Vector2(0, 96), 36, color)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var s := Label.new()
	s.text = sub
	s.add_theme_font_size_override("font_size", 15)
	s.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	s.offset_top = -26
	s.offset_bottom = -6
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(s)
	b.add_theme_constant_override("h_separation", 0)
	# subir un poco el título para que quepa la línea de abajo
	var st: StyleBoxFlat = b.get_theme_stylebox("normal")
	for k in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(k).duplicate()
		sb.content_margin_bottom = 30
		b.add_theme_stylebox_override(k, sb)
	b.pressed.connect(cb)
	return b


## Muestra el aldeano nivel 5 de tu civilización favorita.
func _show_civ() -> void:
	var civ := Account.fav_civ()
	var d: Dictionary = Defs.CIVS.get(civ, {})
	civ_label.text = String(d.get("name", civ))
	civ_desc.text = String(d.get("desc", ""))
	fig_view.set_civ(civ)


func _refresh_chip() -> void:
	var n := Account.player_name if Account.player_name != "" else String(Account.profile.get("name", ""))
	var t := "[center]"
	if n != "":
		t += "[color=#f5e8c7]%s[/color]  " % n
	if Account.profile.has("points"):
		t += "[color=#ffd75a]Nivel %d[/color] · %d pts" % [Account.level(), Account.points()]
	else:
		t += "[color=#cbb894]Nivel en línea: juega con rango[/color]"
	chip.text = t + "[/center]"


# ---------------- ventanas ----------------

func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


func _window(title: String, width := 640.0) -> VBoxContainer:
	_close_overlay()
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.16, 0.11, 0.07, 0.97), GOLD, 16, 3))
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(width, 0)
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	vb.add_child(_label(title, 40, GOLD))
	return vb


func _soon(title: String, text: String) -> void:
	var vb := _window(title, 560)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", CREAM)
	vb.add_child(l)
	var ok := art_button("Cerrar", Vector2(200, 56), 24)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_close_overlay)
	vb.add_child(ok)


func _welcome() -> void:
	var vb := _window("¡Bienvenido a Rise of Ages!", 600)
	var l := Label.new()
	l.text = "¿Aprendemos lo básico? Te enseñamos a mover aldeanos, juntar recursos, comprar aldeanos y construir. Son unos 2 minutos."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", CREAM)
	vb.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var go := art_button("Empezar tutorial", Vector2(260, 60), 26, Color(0.16, 0.42, 0.22))
	go.pressed.connect(func() -> void: menu.start_tutorial())
	row.add_child(go)
	var skip := art_button("Omitir", Vector2(160, 60), 26, Color(0.25, 0.22, 0.20))
	skip.pressed.connect(func() -> void:
		Account.set_tutorial_done(true)
		_close_overlay())
	row.add_child(skip)


func _civ_picker() -> void:
	var vb := _window("Elige tu civilización", 980)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for c in Defs.CIV_ORDER:
		var d: Dictionary = Defs.CIVS[c]
		var mine: bool = c == Account.fav_civ()
		var b := art_button(String(d["name"]), Vector2(310, 150), 28, Color(0.35, 0.10, 0.08) if not mine else Color(0.62, 0.42, 0.12))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var desc := Label.new()
		desc.text = String(d.get("desc", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
		desc.set_anchors_preset(Control.PRESET_FULL_RECT)
		desc.offset_top = 56
		desc.offset_left = 12
		desc.offset_right = -12
		desc.offset_bottom = -8
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(desc)
		for k in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(k).duplicate()
			sb.content_margin_bottom = 90
			b.add_theme_stylebox_override(k, sb)
		var cc: String = c
		b.pressed.connect(func() -> void:
			Account.set_fav_civ(cc)
			_show_civ()
			menu.apply_fav_civ()
			_close_overlay())
		grid.add_child(b)
	var back := art_button("Volver", Vector2(200, 56), 24, Color(0.25, 0.22, 0.20))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_overlay)
	vb.add_child(back)


func _config() -> void:
	var vb := _window("Configuración", 560)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var nl := Label.new()
	nl.text = "Tu nombre:"
	nl.add_theme_font_size_override("font_size", 20)
	row.add_child(nl)
	var ne := LineEdit.new()
	ne.text = Account.player_name
	ne.max_length = 16
	ne.custom_minimum_size = Vector2(300, 44)
	ne.placeholder_text = "Nombre"
	row.add_child(ne)
	var fs := CheckBox.new()
	fs.text = "Pantalla completa"
	fs.add_theme_font_size_override("font_size", 20)
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	vb.add_child(fs)
	var acc := Label.new()
	acc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acc.add_theme_font_size_override("font_size", 16)
	acc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.68))
	if Account.signed_in() and not Account.is_anonymous:
		acc.text = "Cuenta Kodyn Games: %s" % Account.email
	else:
		acc.text = "Tu cuenta es de invitado. En \"Jugar con rango\" puedes guardar tu progreso con correo o entrar con tu cuenta de Kodyn Games (la de Zombie War)."
	vb.add_child(acc)
	var tut := art_button("Repetir tutorial", Vector2(240, 52), 22, Color(0.16, 0.42, 0.22))
	tut.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tut.pressed.connect(func() -> void: menu.start_tutorial())
	vb.add_child(tut)
	var ok := art_button("Guardar", Vector2(200, 56), 24)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		if ne.text.strip_edges().length() >= 2:
			Account.set_player_name(ne.text.strip_edges())
			if Account.signed_in():
				Account.refresh_profile()
		_refresh_chip()
		_close_overlay())
	vb.add_child(ok)
