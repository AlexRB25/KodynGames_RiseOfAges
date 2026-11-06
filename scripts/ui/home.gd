class_name Home
extends Control
## Pantalla principal: tu aldeano nivel 5 de tu civilización favorita (girando en 3D),
## las formas de juego a la derecha con el Game Pass encima, arriba tu tarjeta de perfil,
## tus monedas y gemas, Tienda y Configuración.

var menu: Node
var font: Font
var civ_label: Label
var civ_desc: Label
var card_slot: Control      # tarjeta de perfil (se rehace al cambiar)
var wallet: HBoxContainer   # monedas y gemas
var pass_slot: Control      # botón del Game Pass
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
	Economy.changed.connect(_refresh_chip)
	Economy.message.connect(func(t: String) -> void: Kit.ask(self, Lang.t("Tienda"), t))
	_refresh_chip()
	_show_civ()
	# La primera vez: directo al tutorial (dentro está "Omitir tutorial").
	if not Account.tutorial_done() and not OS.has_feature("headless") and DisplayServer.get_name() != "headless":
		menu.start_tutorial.call_deferred()
	# Tu cuenta (de invitado si no tienes otra): monedas, gemas, pase y nivel en línea.
	if Account.accounts_ready() and not Economy.demo:
		_load_account()
	# Desarrollo: --abrir=pase|tienda|gemas|perfil abre esa página.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--abrir="):
			match a.get_slice("=", 1):
				"pase":
					open_pass.call_deferred()
				"tienda":
					open_store.call_deferred("articulos")
				"gemas":
					open_store.call_deferred("gemas")
				"perfil":
					open_profile.call_deferred()


func _load_account() -> void:
	if not Account.signed_in():
		if await Account.sign_in() != "":
			return
	Economy.refresh()


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
	wallet = HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 8)
	top.add_child(wallet)
	var shop := art_button(Lang.t("Tienda"), Vector2(140, 58), 24, Color(0.16, 0.42, 0.22))
	shop.pressed.connect(open_store.bind("articulos"))
	top.add_child(shop)
	var cfg := art_button(Lang.t("Configuración"), Vector2(200, 58), 24, Color(0.25, 0.22, 0.20))
	cfg.pressed.connect(_config)
	top.add_child(cfg)
	if not OS.has_feature("web"):
		var quit := art_button(Lang.t("Salir"), Vector2(110, 58), 24, Color(0.25, 0.22, 0.20))
		quit.pressed.connect(func() -> void: get_tree().quit())
		top.add_child(quit)
	# Tu tarjeta de perfil, junto al logo (tócala para ver tu colección).
	card_slot = Control.new()
	card_slot.position = Vector2(372, 22)
	card_slot.size = Vector2(420, 96)
	add_child(card_slot)
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
	var ch := art_button(Lang.t("Cambiar civilización"), Vector2(360, 60), 26)
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
	# Encima de las formas de juego: el Game Pass de la temporada.
	pass_slot = Control.new()
	pass_slot.anchor_left = 0.62
	pass_slot.anchor_right = 0.95
	pass_slot.offset_top = 100
	pass_slot.offset_bottom = 236
	add_child(pass_slot)
	right.add_child(_mode(Lang.t("UN JUGADOR"), Lang.t("Contra bots, de 1 vs 1 hasta 4 vs 4"), func() -> void: menu.open_mode("solo")))
	right.add_child(_mode(Lang.t("JUGAR CON RANGO"), Lang.t("En línea: te emparejamos con alguien de tu nivel"), func() -> void: menu.open_mode("rango")))
	right.add_child(_mode(Lang.t("SALA CON AMIGOS"), Lang.t("Crea una sala y comparte el código"), func() -> void: menu.open_mode("amigos")))
	right.add_child(_mode(Lang.t("TORNEOS"), Lang.t("Próximamente"), func() -> void:
		_soon(Lang.t("Torneos"), Lang.t("Torneos rápidos que empiezan solos y torneos especiales con hora fija, con premios para los mejores.\n\nPróximamente.")), Color(0.30, 0.24, 0.16)))


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
	civ_label.text = Lang.t(d.get("name", civ))
	civ_desc.text = Lang.t(d.get("desc", ""))
	fig_view.set_civ(civ)


## Nombre que se muestra (el guardado en este equipo o el de la cuenta).
func player_display_name() -> String:
	var n := Account.player_name if Account.player_name != "" else String(Account.profile.get("name", ""))
	return n if n != "" else Lang.t("Jugador")


## "Nivel 3 · 240 pts" en línea, con color.
func rank_text() -> String:
	if Account.profile.has("points"):
		return Lang.t("[color=#ffd75a]Nivel %d[/color] · %d pts") % [Account.level(), Account.points()]
	return Lang.t("[color=#cbb894]Rango: juega en línea[/color]")


func _refresh_chip() -> void:
	if card_slot == null:
		return
	# Tarjeta de perfil.
	for c in card_slot.get_children():
		c.queue_free()
	var card := Kit.profile_card(player_display_name(), Economy.equipped("titulo"), rank_text(),
		Economy.equipped("imagen"), Economy.equipped("estandarte"))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = Lang.t("Tu perfil: imágenes, estandartes y títulos")
	card.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			open_profile())
	card_slot.add_child(card)
	# Monedas y gemas.
	for c in wallet.get_children():
		c.queue_free()
	if Economy.ready_to_use():
		wallet.add_child(Kit.wallet_chip("coins", Economy.coins()))
		wallet.add_child(Kit.wallet_chip("gems", Economy.gems()))
		var plus := Kit.button("+", Vector2(48, 48), 28, Kit.GREEN)
		plus.tooltip_text = Lang.t("Conseguir gemas")
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus.pressed.connect(open_store.bind("gemas"))
		wallet.add_child(plus)
	# Game Pass.
	for c in pass_slot.get_children():
		c.queue_free()
	pass_slot.add_child(_pass_button())


func _pass_button() -> Control:
	var b := art_button("", Vector2.ZERO, 30, Color(0.30, 0.13, 0.42))
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.pressed.connect(open_pass)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 18
	hb.offset_right = -18
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ic := Kit.icon("premium", 76)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var t := Kit.label(Lang.t("GAME PASS") + ("  · PREMIUM" if Economy.premium() else ""), 32, GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(t)
	var s := Economy.season()
	if s.is_empty():
		var sub := Kit.label(Lang.t("Temporadas con premios: gratis y Premium") if Economy.status.is_empty() \
			else Lang.t("La próxima temporada empieza pronto"), 18)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.add_child(sub)
		return b
	var line := Kit.label(Lang.t("Nivel %d de %d") % [Economy.tier(), Economy.tiers()] + "   ·   " + Lang.t("Quedan %d días") % Economy.days_left(), 18)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(line)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	bar.max_value = 1.0
	bar.value = Economy.tier_progress()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Kit.box(Color(0.08, 0.05, 0.03), GOLD.darkened(0.3), 8, 2, false)
	bg.set_content_margin_all(0)
	var fg := Kit.box(Color(0.95, 0.68, 0.18), Color(1, 0.9, 0.5), 8, 1, false)
	fg.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	vb.add_child(bar)
	var n := Economy.claimable_count()
	if n > 0:
		var badge := PanelContainer.new()
		var bs := Kit.box(Color(0.75, 0.12, 0.1), Color(1, 0.9, 0.5), 18, 3, false)
		bs.content_margin_left = 12
		bs.content_margin_right = 12
		bs.content_margin_top = 2
		bs.content_margin_bottom = 2
		badge.add_theme_stylebox_override("panel", bs)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(Kit.label(Lang.t("¡%d por reclamar!") % n, 18))
		hb.add_child(badge)
	return b


# ---------------- páginas ----------------

func _cloud_ready() -> bool:
	if Economy.demo or Account.accounts_ready():
		return true
	_soon(Lang.t("Tienda"), Lang.t("Las cuentas en línea aún no están listas en esta versión."))
	return false


func open_pass() -> void:
	if not _cloud_ready():
		return
	var p := SeasonScreen.new()
	add_child(p)
	p.setup(self)


func open_store(tab := "articulos") -> void:
	if not _cloud_ready():
		return
	var p := StoreScreen.new()
	add_child(p)
	p.setup(self, tab)


func open_profile() -> void:
	if not _cloud_ready():
		return
	var p := ProfileScreen.new()
	add_child(p)
	p.setup(self)


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
	var ok := art_button(Lang.t("Cerrar"), Vector2(200, 56), 24)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_close_overlay)
	vb.add_child(ok)


func _welcome() -> void:
	var vb := _window(Lang.t("¡Bienvenido a Rise of Ages!"), 600)
	var l := Label.new()
	l.text = Lang.t("¿Aprendemos lo básico? Te enseñamos a mover aldeanos, juntar recursos, comprar aldeanos y construir. Son unos 2 minutos.")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", CREAM)
	vb.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var go := art_button(Lang.t("Empezar tutorial"), Vector2(260, 60), 26, Color(0.16, 0.42, 0.22))
	go.pressed.connect(func() -> void: menu.start_tutorial())
	row.add_child(go)
	var skip := art_button(Lang.t("Omitir"), Vector2(160, 60), 26, Color(0.25, 0.22, 0.20))
	skip.pressed.connect(func() -> void:
		Account.set_tutorial_done(true)
		_close_overlay())
	row.add_child(skip)


func _civ_picker() -> void:
	var vb := _window(Lang.t("Elige tu civilización"), 980)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for c in Defs.CIV_ORDER:
		var d: Dictionary = Defs.CIVS[c]
		var mine: bool = c == Account.fav_civ()
		var locked := Economy.civ_locked(c)
		var b := art_button(Lang.t(d["name"]), Vector2(310, 150), 28, Color(0.35, 0.10, 0.08) if not mine else Color(0.62, 0.42, 0.12))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var desc := Label.new()
		desc.text = Lang.t(d.get("desc", ""))
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
		if locked:
			b.text = "🔒 " + b.text
			b.modulate = Color(0.7, 0.7, 0.7)
		b.pressed.connect(func() -> void:
			if locked:
				Kit.ask(self, Lang.t(Defs.CIVS[cc]["name"]), Lang.t("Esta civilización se consigue en el Game Pass o en la Tienda."))
				return
			Account.set_fav_civ(cc)
			_show_civ()
			menu.apply_fav_civ()
			_close_overlay())
		grid.add_child(b)
	var back := art_button(Lang.t("Volver"), Vector2(200, 56), 24, Color(0.25, 0.22, 0.20))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_overlay)
	vb.add_child(back)


func _config() -> void:
	var vb := _window(Lang.t("Configuración"), 560)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var nl := Label.new()
	nl.text = Lang.t("Tu nombre:")
	nl.add_theme_font_size_override("font_size", 20)
	row.add_child(nl)
	var ne := LineEdit.new()
	ne.text = Account.player_name
	ne.max_length = 16
	ne.custom_minimum_size = Vector2(300, 44)
	ne.placeholder_text = Lang.t("Nombre")
	row.add_child(ne)
	var fs := CheckBox.new()
	fs.text = Lang.t("Pantalla completa")
	fs.add_theme_font_size_override("font_size", 20)
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	vb.add_child(fs)
	vb.add_child(Sfx.volume_row("musica", 20))
	vb.add_child(Sfx.volume_row("efectos", 20))
	# Idioma: al cambiarlo se vuelve a armar el menú para que todo salga en el nuevo idioma.
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 12)
	vb.add_child(lrow)
	var ll := Label.new()
	ll.text = Lang.t("Idioma:")
	ll.add_theme_font_size_override("font_size", 20)
	lrow.add_child(ll)
	var lang_opt := OptionButton.new()
	lang_opt.custom_minimum_size = Vector2(220, 44)
	lang_opt.add_theme_font_size_override("font_size", 20)
	lang_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # cada idioma con su propio nombre
	var codes: Array = Lang.LANGS.keys()
	for c in codes:
		lang_opt.add_item(Lang.LANGS[c])
	lang_opt.select(codes.find(Lang.code))
	lang_opt.item_selected.connect(func(i: int) -> void:
		if ne.text.strip_edges().length() >= 2:
			Account.set_player_name(ne.text.strip_edges())
		Lang.set_lang(codes[i])
		get_tree().reload_current_scene())
	lrow.add_child(lang_opt)
	var acc := Label.new()
	acc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acc.add_theme_font_size_override("font_size", 16)
	acc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.68))
	if Account.signed_in() and not Account.is_anonymous:
		acc.text = Lang.t("Cuenta Kodyn Games: %s") % Account.email
	else:
		acc.text = Lang.t("Tu cuenta es de invitado. En \"Jugar con rango\" puedes guardar tu progreso con correo o entrar con tu cuenta de Kodyn Games (la de Zombie War).")
	vb.add_child(acc)
	var tut := art_button(Lang.t("Repetir tutorial"), Vector2(240, 52), 22, Color(0.16, 0.42, 0.22))
	tut.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tut.pressed.connect(func() -> void: menu.start_tutorial())
	vb.add_child(tut)
	var ok := art_button(Lang.t("Guardar"), Vector2(200, 56), 24)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		if ne.text.strip_edges().length() >= 2:
			Account.set_player_name(ne.text.strip_edges())
			if Account.signed_in():
				Account.refresh_profile()
		_refresh_chip()
		_close_overlay())
	vb.add_child(ok)
