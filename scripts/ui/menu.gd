extends Control
## Menú principal y configuración de partida contra bots (hasta 8 jugadores, 4 vs 4).

var rows: Array = []     # cada fila: {type: OptionButton, civ, team, color}
var type_opt: OptionButton
var size_opt: OptionButton
var list: VBoxContainer
var main_box: VBoxContainer
var setup_box: VBoxContainer
var online_box: VBoxContainer
var lobby_box: VBoxContainer
var name_edit: LineEdit
var code_edit: LineEdit
var status_label: Label
var ranked_box: VBoxContainer
var profile_label: RichTextLabel
var rk_name: LineEdit
var rk_civ: OptionButton
var rk_status: Label
var rk_modes: HBoxContainer
var rk_cancel: Button
var acct_box: VBoxContainer

const TYPES := ["Cerrado", "Tú", "Bot Fácil", "Bot Normal", "Bot Difícil", "Bot Experto"]


func _ready() -> void:
	Sfx.game = null
	Sfx.music("menu")
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.09, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var fondo := Art.tex("ui/fondo.jpg")
	if fondo:
		var ft := TextureRect.new()
		ft.texture = fondo
		ft.set_anchors_preset(Control.PRESET_FULL_RECT)
		ft.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ft.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(ft)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_center = center
	var panel := PanelContainer.new()
	panel.theme = _theme()
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	_scroll.add_child(root)
	_root = root
	var logo := Art.tex("ui/logo.png")
	if logo:
		var lt := TextureRect.new()
		_logo = lt
		lt.texture = logo
		lt.custom_minimum_size = Vector2(380, 190)
		lt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		root.add_child(lt)
	else:
		var title := Label.new()
		title.text = Lang.t("RISE OF AGES")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 52)
		title.add_theme_color_override("font_color", Color(0.98, 0.82, 0.38))
		root.add_child(title)
	var sub := Label.new()
	sub.text = Lang.t("Beta · Civilizaciones de Mesoamérica")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	profile_label = RichTextLabel.new()
	profile_label.bbcode_enabled = true
	profile_label.fit_content = true
	profile_label.custom_minimum_size = Vector2(420, 0)
	root.add_child(profile_label)
	Account.changed.connect(_refresh_profile)
	_refresh_profile()

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 10)
	root.add_child(main_box)
	var solo := _big_button(Lang.t("Un jugador (contra bots)"))
	solo.pressed.connect(func() -> void:
		main_box.visible = false
		setup_box.visible = true)
	main_box.add_child(solo)
	var rk := _big_button(Lang.t("Jugar con rango (en línea)"))
	rk.tooltip_text = Lang.t("Te emparejamos con alguien de tu nivel. Ganar suma puntos, perder resta.")
	rk.pressed.connect(_open_ranked)
	main_box.add_child(rk)
	var online := _big_button(Lang.t("Sala con amigos (código)"))
	online.pressed.connect(func() -> void:
		main_box.visible = false
		online_box.visible = true)
	main_box.add_child(online)
	var quit := _big_button(Lang.t("Salir"))
	quit.pressed.connect(func() -> void: get_tree().quit())
	if OS.has_feature("web"):
		quit.visible = false
	main_box.add_child(quit)

	setup_box = VBoxContainer.new()
	setup_box.visible = false
	setup_box.add_theme_constant_override("separation", 8)
	root.add_child(setup_box)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	setup_box.add_child(presets)
	var pl := Label.new()
	pl.text = Lang.t("Rápido:")
	presets.add_child(pl)
	for pr in [[Lang.t("1 vs 1"), [1, 2]], [Lang.t("2 vs 2"), [1, 1, 2, 2]], [Lang.t("3 vs 3"), [1, 1, 1, 2, 2, 2]],
			[Lang.t("4 vs 4"), [1, 1, 1, 1, 2, 2, 2, 2]], [Lang.t("1 vs 3"), [1, 2, 2, 2]], [Lang.t("Todos contra todos (4)"), [1, 2, 3, 4]]]:
		var b := Button.new()
		b.text = pr[0]
		var teams: Array = pr[1]
		b.pressed.connect(func() -> void: _preset(teams))
		presets.add_child(b)
	var head := HBoxContainer.new()
	for h in [[Lang.t("Jugador"), 170], [Lang.t("Civilización"), 170], [Lang.t("Equipo"), 110], [Lang.t("Color"), 120]]:
		var l := Label.new()
		l.text = h[0]
		l.custom_minimum_size = Vector2(h[1], 0)
		head.add_child(l)
	setup_box.add_child(head)
	list = VBoxContainer.new()
	setup_box.add_child(list)
	for i in 8:
		_add_row(i)
	var opts := HBoxContainer.new()
	var ml := Label.new()
	ml.text = Lang.t("Mapa:")
	opts.add_child(ml)
	size_opt = OptionButton.new()
	size_opt.add_item(Lang.t("Pequeño (120)"))
	size_opt.add_item(Lang.t("Mediano (160)"))
	size_opt.add_item(Lang.t("Grande (220)"))
	size_opt.select(1)
	opts.add_child(size_opt)
	var tl := Label.new()
	tl.text = Lang.t("  Tipo:")
	opts.add_child(tl)
	type_opt = _type_pick("azar", true, func(_v: String) -> void: pass)
	opts.add_child(type_opt)
	setup_box.add_child(opts)
	var civ_info := Label.new()
	civ_info.add_theme_font_size_override("font_size", 13)
	civ_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	civ_info.custom_minimum_size = Vector2(600, 0)
	var txt := ""
	for c in Defs.CIV_ORDER:
		txt += "%s: %s\n" % [Lang.t(Defs.CIVS[c]["name"]), Lang.t(Defs.CIVS[c]["desc"])]
	civ_info.text = txt
	setup_box.add_child(civ_info)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	setup_box.add_child(bh)
	var back := _big_button(Lang.t("Volver"))
	back.pressed.connect(func() -> void:
		setup_box.visible = false
		main_box.visible = true)
	bh.add_child(back)
	var start := _big_button(Lang.t("¡Comenzar!"))
	start.pressed.connect(_start)
	bh.add_child(start)
	# Dos columnas: jugadores a la izquierda, civilizaciones a la derecha (cabe sin desplazarse).
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	for n in [presets, head, list, opts, bh]:
		n.reparent(left)
	civ_info.custom_minimum_size = Vector2(400, 0)
	civ_info.reparent(cols)
	setup_box.add_child(cols)
	_preset([1, 2])
	_build_online(root)
	_build_ranked(root)
	Net.room_changed.connect(_refresh_lobby)
	Net.queue_changed.connect(_refresh_queue)
	Net.failed.connect(func(msg: String) -> void:
		_status(msg)
		if rk_status:
			rk_status.text = msg)
	Net.closed.connect(func() -> void:
		_lobby_civ_sent = false
		_status(Lang.t("Se cerró la conexión."))
		if ranked_box.visible:
			_refresh_queue()
			return
		lobby_box.visible = false
		online_box.visible = true)
	Net.started.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/carga.tscn"))
	Setup.online = false
	Net.close()
	# Pantalla principal nueva (tu aldeano, formas de juego, tienda, configuración).
	var white := Image.create(4, 4, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	Mat.setup(ImageTexture.create_from_image(white), Vector2(1000, 1000))
	_home = Home.new()
	add_child(_home)
	_home.setup(self)
	apply_fav_civ()
	# Desarrollo: --rank abre la pantalla con rango, --shot=archivo.png guarda una captura.
	for arg in OS.get_cmdline_user_args():
		if arg == "--rank":
			_open_ranked()
		elif arg.begins_with("--solo="):
			open_mode("solo")
			for ch in get_children():
				if ch is SoloScreen:
					ch._set_preset(arg.get_slice("=", 1))
		elif arg == "--tienda":
			_home.open_store()
		elif arg == "--tienda-gemas":
			_home.open_store("gemas")
		elif arg == "--pase":
			_home.open_pass()
		elif arg == "--subir-rango":
			LevelUp.play(self, "rango", 4, 5, Lang.t("%d puntos") % 412)
		elif arg == "--subir-pase":
			LevelUp.play(self, "pase", 12, 13, Lang.t("Tienes premios para reclamar"))
		elif arg == "--solo":
			main_box.visible = false
			setup_box.visible = true
		elif arg.begins_with("--shot="):
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png(arg.get_slice("=", 1))
			get_tree().quit()


var _center: Control
var _home: Home
var _lobby_civ_sent := false


## Desde la pantalla principal: abrir una forma de juego.
func open_mode(k: String) -> void:
	match k:
		"solo":
			var ss := SoloScreen.new()
			add_child(ss)
			ss.setup(_home, self)
		"rango":
			_open_ranked()
		"amigos":
			main_box.visible = false
			online_box.visible = true


## Partida guiada: tú contra un rival que no ataca, en un mapa pequeño y tranquilo.
func start_tutorial() -> void:
	var fav := Account.fav_civ()
	var other: String = Defs.CIV_ORDER[1] if Defs.CIV_ORDER[0] == fav else Defs.CIV_ORDER[0]
	Setup.players = [
		{"name": Account.player_name if Account.player_name != "" else Lang.t("Tú"), "civ": fav, "team": 1, "color": 0, "bot": false, "difficulty": "normal"},
		{"name": Lang.t("Rival de práctica"), "civ": other, "team": 2, "color": 1, "bot": false, "difficulty": "normal"},
	]
	Setup.local_player = 0
	Setup.online = false
	Setup.tutorial = true
	Setup.map_size = "pequeno"
	Setup.map_type = "valle"
	Setup.seed_value = 4242
	get_tree().change_scene_to_file("res://scenes/carga.tscn")


## Tu civilización favorita queda elegida en todas las formas de juego.
func apply_fav_civ() -> void:
	var idx := maxi(0, Defs.CIV_ORDER.find(Account.fav_civ()))
	if not rows.is_empty():
		rows[0]["civ"].select(idx)
	if rk_civ:
		rk_civ.select(idx)


var _scroll: ScrollContainer
var _root: VBoxContainer
var _logo: TextureRect


## El panel se ajusta solo a la ventana: logo grande solo en la pantalla principal y,
## si el contenido no cabe a lo alto, el panel se desplaza con la rueda o el dedo.
func _process(_dt: float) -> void:
	if _home:
		_home.visible = main_box.visible
		_center.visible = not main_box.visible
	if _scroll == null:
		return
	if _logo:
		var h := 190.0 if main_box.visible else 96.0
		var vh0 := get_viewport_rect().size.y
		if vh0 < 700.0:
			h *= 0.6
		_logo.custom_minimum_size = Vector2(380, h)
	var want := _root.get_combined_minimum_size()
	var vh := get_viewport_rect().size.y - 70.0   # márgenes del panel y de la ventana
	var sz := Vector2(want.x + 14.0, minf(want.y, vh))
	if not _scroll.custom_minimum_size.is_equal_approx(sz):
		_scroll.custom_minimum_size = sz


func _theme() -> Theme:
	var t := Theme.new()
	var p := StyleBoxFlat.new()
	p.bg_color = Color(0.18, 0.13, 0.09, 0.96)
	p.border_color = Color(0.72, 0.56, 0.28)
	p.set_border_width_all(2)
	p.set_corner_radius_all(6)
	p.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", p)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.36, 0.26, 0.15)
	b.border_color = Color(0.72, 0.56, 0.28)
	b.set_border_width_all(1)
	b.set_corner_radius_all(4)
	b.set_content_margin_all(6)
	var bh := b.duplicate()
	bh.bg_color = Color(0.48, 0.35, 0.19)
	t.set_stylebox("normal", "Button", b)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bh)
	t.set_stylebox("normal", "OptionButton", b)
	t.set_stylebox("hover", "OptionButton", bh)
	t.set_color("font_color", "Label", Color(0.96, 0.91, 0.78))
	t.set_color("font_color", "Button", Color(0.96, 0.91, 0.78))
	t.set_color("font_color", "OptionButton", Color(0.96, 0.91, 0.78))
	return t


func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 48)
	b.add_theme_font_size_override("font_size", 20)
	return b


func _add_row(i: int) -> void:
	var hb := HBoxContainer.new()
	var type := OptionButton.new()
	for t in TYPES:
		type.add_item(t)
	type.custom_minimum_size = Vector2(170, 0)
	if i == 0:
		type.select(1)
		type.disabled = true
	hb.add_child(type)
	var civ := OptionButton.new()
	for c in Defs.CIV_ORDER:
		civ.add_item(Lang.t(Defs.CIVS[c]["name"]))
	civ.select(i % Defs.CIV_ORDER.size())
	civ.custom_minimum_size = Vector2(170, 0)
	hb.add_child(civ)
	var team := OptionButton.new()
	for t in 4:
		team.add_item(Lang.t("Equipo %d") % (t + 1))
	team.custom_minimum_size = Vector2(110, 0)
	hb.add_child(team)
	var col := OptionButton.new()
	for c in Defs.COLOR_NAMES.size():
		col.add_item(Lang.t(Defs.COLOR_NAMES[c]))
	col.select(i)
	col.custom_minimum_size = Vector2(120, 0)
	hb.add_child(col)
	list.add_child(hb)
	rows.append({"type": type, "civ": civ, "team": team, "color": col})


func _preset(teams: Array) -> void:
	for i in rows.size():
		var r: Dictionary = rows[i]
		if i < teams.size():
			if i > 0:
				r["type"].select(3)
			r["team"].select(teams[i] - 1)
		else:
			r["type"].select(0)


func _start() -> void:
	var players: Array = []
	var diffs := {2: "facil", 3: "normal", 4: "dificil", 5: "experto"}
	for i in rows.size():
		var r: Dictionary = rows[i]
		var t: int = r["type"].selected
		if t == 0:
			continue
		players.append({
			"name": Lang.t("Tú") if t == 1 else "%s (%s)" % [Lang.t(Defs.CIVS[Defs.CIV_ORDER[r["civ"].selected]]["name"]), Lang.t(TYPES[t]).replace("Bot ", "")],
			"civ": Defs.CIV_ORDER[r["civ"].selected],
			"team": r["team"].selected + 1,
			"color": r["color"].selected,
			"bot": t >= 2,
			"difficulty": diffs.get(t, "normal"),
		})
	var teams := {}
	for p in players:
		teams[p["team"]] = true
	if teams.size() < 2:
		_warn(Lang.t("Debe haber al menos dos equipos distintos."))
		return
	Setup.players = players
	Setup.online = false
	Setup.tutorial = false
	Setup.local_player = 0
	Setup.map_size = ["pequeno", "mediano", "grande"][size_opt.selected]
	Setup.map_type = Defs.MAP_TYPE_ORDER[type_opt.selected]
	Setup.seed_value = 0
	get_tree().change_scene_to_file("res://scenes/carga.tscn")


func _warn(t: String) -> void:
	var d := AcceptDialog.new()
	d.dialog_text = t
	add_child(d)
	d.popup_centered()


# ---------------- en línea ----------------

func _status(t: String) -> void:
	if status_label:
		status_label.text = t


func _build_online(root: VBoxContainer) -> void:
	online_box = VBoxContainer.new()
	online_box.visible = false
	online_box.add_theme_constant_override("separation", 10)
	root.add_child(online_box)
	var l := Label.new()
	l.text = Lang.t("Tu nombre:")
	online_box.add_child(l)
	name_edit = LineEdit.new()
	name_edit.max_length = 16
	name_edit.placeholder_text = Lang.t("Nombre")
	name_edit.text = Account.player_name
	name_edit.custom_minimum_size = Vector2(320, 44)
	online_box.add_child(name_edit)
	var create := _big_button(Lang.t("Crear sala"))
	create.pressed.connect(func() -> void:
		if _name() == "":
			_status(Lang.t("Escribe tu nombre."))
			return
		_status(Lang.t("Conectando…"))
		Net.create_room(_name()))
	online_box.add_child(create)
	var jl := Label.new()
	jl.text = Lang.t("¿Tu amigo ya creó una sala? Escribe su código:")
	online_box.add_child(jl)
	var jh := HBoxContainer.new()
	online_box.add_child(jh)
	code_edit = LineEdit.new()
	code_edit.max_length = 4
	code_edit.placeholder_text = Lang.t("CÓDIGO")
	code_edit.custom_minimum_size = Vector2(150, 48)
	code_edit.add_theme_font_size_override("font_size", 22)
	jh.add_child(code_edit)
	var join := _big_button(Lang.t("Unirse"))
	join.custom_minimum_size = Vector2(160, 48)
	join.pressed.connect(func() -> void:
		if _name() == "" or code_edit.text.strip_edges().length() < 4:
			_status(Lang.t("Escribe tu nombre y el código de 4 letras."))
			return
		_status(Lang.t("Conectando…"))
		Net.join_room(_name(), code_edit.text))
	jh.add_child(join)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.5))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(320, 0)
	online_box.add_child(status_label)
	var back := _big_button(Lang.t("Volver"))
	back.pressed.connect(func() -> void:
		Net.close()
		online_box.visible = false
		main_box.visible = true)
	online_box.add_child(back)
	lobby_box = VBoxContainer.new()
	lobby_box.visible = false
	lobby_box.add_theme_constant_override("separation", 8)
	root.add_child(lobby_box)


func _name() -> String:
	var n := name_edit.text.strip_edges()
	if n != "":
		Account.set_player_name(n)
	return n


# ---------------- con rango ----------------

func _refresh_profile() -> void:
	if profile_label == null:
		return
	var n := Account.player_name
	if n == "" and Account.profile.is_empty():
		profile_label.text = ""
		return
	var txt := "[center][b]%s[/b]" % (n if n != "" else String(Account.profile.get("name", Lang.t("Jugador"))))
	if not Account.profile.is_empty():
		txt += Lang.t("  ·  [color=#ffd75a]Nivel %d[/color]  ·  %d puntos") % [Account.level(), Account.points()]
		if Account.profile.has("wins"):
			txt += Lang.t("  ·  %d ganadas / %d perdidas") % [int(Account.profile["wins"]), int(Account.profile["losses"])]
	profile_label.text = txt + "[/center]"


func _open_ranked() -> void:
	main_box.visible = false
	ranked_box.visible = true
	rk_name.text = Account.player_name
	_refresh_account()
	_refresh_queue()
	if Account.accounts_ready():
		rk_status.text = Lang.t("Conectando tu cuenta…")
		var err: String = await Account.sign_in()
		rk_status.text = err
		rk_name.text = Account.player_name
		_refresh_account()


func _build_ranked(root: VBoxContainer) -> void:
	ranked_box = VBoxContainer.new()
	ranked_box.visible = false
	ranked_box.add_theme_constant_override("separation", 10)
	root.add_child(ranked_box)
	var info := Label.new()
	info.text = Lang.t("Te emparejamos con el jugador en línea más cercano a tu nivel.\nGanar suma puntos y perder resta; cada 100 puntos subes de nivel.")
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ranked_box.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ranked_box.add_child(row)
	var nl := Label.new()
	nl.text = Lang.t("Nombre:")
	row.add_child(nl)
	rk_name = LineEdit.new()
	rk_name.max_length = 16
	rk_name.placeholder_text = Lang.t("Tu nombre")
	rk_name.custom_minimum_size = Vector2(220, 44)
	row.add_child(rk_name)
	var cl := Label.new()
	cl.text = Lang.t("Civilización:")
	row.add_child(cl)
	rk_civ = _civ_pick(Defs.CIV_ORDER[0], true, func(_v: String) -> void: pass)
	row.add_child(rk_civ)
	rk_modes = HBoxContainer.new()
	rk_modes.add_theme_constant_override("separation", 8)
	ranked_box.add_child(rk_modes)
	for md in [["1v1", Lang.t("Buscar 1 vs 1")], ["2v2", Lang.t("Buscar 2 vs 2")], ["4v4", Lang.t("Buscar 4 vs 4")]]:
		var b := _big_button(md[1])
		b.custom_minimum_size = Vector2(200, 52)
		var mode: String = md[0]
		b.pressed.connect(func() -> void: _search(mode))
		rk_modes.add_child(b)
	rk_status = Label.new()
	rk_status.add_theme_color_override("font_color", Color(1, 0.8, 0.5))
	rk_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rk_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rk_status.custom_minimum_size = Vector2(600, 0)
	ranked_box.add_child(rk_status)
	rk_cancel = _big_button(Lang.t("Cancelar búsqueda"))
	rk_cancel.pressed.connect(func() -> void:
		Net.unqueue()
		rk_status.text = Lang.t("Búsqueda cancelada.")
		_refresh_queue())
	ranked_box.add_child(rk_cancel)
	acct_box = VBoxContainer.new()
	acct_box.add_theme_constant_override("separation", 6)
	ranked_box.add_child(acct_box)
	var back := _big_button(Lang.t("Volver"))
	back.pressed.connect(func() -> void:
		if not Net.queue_info.is_empty():
			Net.unqueue()
		ranked_box.visible = false
		main_box.visible = true)
	ranked_box.add_child(back)


func _search(mode: String) -> void:
	var n := rk_name.text.strip_edges()
	if n.length() < 2:
		rk_status.text = Lang.t("Escribe tu nombre (mínimo 2 letras).")
		return
	var changed_name := n != Account.player_name
	Account.set_player_name(n)
	if Account.accounts_ready():
		if not Account.signed_in():
			rk_status.text = Lang.t("Conectando tu cuenta…")
			var err: String = await Account.sign_in()
			if err != "":
				rk_status.text = err
				return
		elif changed_name:
			await Account.refresh_profile()
	rk_status.text = Lang.t("Conectando…")
	Net.queue(mode, Defs.CIV_ORDER[rk_civ.selected])


func _refresh_queue() -> void:
	if rk_modes == null:
		return
	var q := Net.queue_info
	var searching := not q.is_empty()
	rk_modes.visible = not searching
	rk_cancel.visible = searching
	rk_name.editable = not searching
	rk_civ.disabled = searching
	if searching:
		var need := int(q.get("need", 0))
		var names := {"1v1": Lang.t("1 vs 1"), "2v2": Lang.t("2 vs 2"), "4v4": Lang.t("4 vs 4")}
		rk_status.text = Lang.t("Buscando partida %s…  (%d de %d jugadores en la cola)\nSi no hay nadie de tu nivel, te toca con quien esté conectado.") % [
			names.get(String(q.get("mode", "")), ""), int(q.get("waiting", 0)), need]


func _refresh_account() -> void:
	for c in acct_box.get_children():
		c.queue_free()
	if not Account.accounts_ready():
		var l := Label.new()
		l.text = Lang.t("Modo prueba: los puntos se guardan en el servidor por nombre y se borran si se reinicia.")
		l.add_theme_font_size_override("font_size", 13)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		acct_box.add_child(l)
		return
	if Account.signed_in() and not Account.is_anonymous:
		var hb := HBoxContainer.new()
		var l := Label.new()
		l.text = Lang.t("Cuenta Kodyn Games: %s") % Account.email
		hb.add_child(l)
		var out := Button.new()
		out.text = Lang.t("Cerrar sesión")
		out.pressed.connect(func() -> void:
			Account.logout()
			_refresh_account())
		hb.add_child(out)
		acct_box.add_child(hb)
		return
	var t := Label.new()
	t.text = Lang.t("Juegas como invitado. Guarda tu progreso con correo, o entra con tu cuenta de Kodyn Games (la misma de Zombie War):")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(600, 0)
	t.add_theme_font_size_override("font_size", 13)
	acct_box.add_child(t)
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 6)
	acct_box.add_child(hb2)
	var em := LineEdit.new()
	em.placeholder_text = "correo"
	em.custom_minimum_size = Vector2(220, 40)
	hb2.add_child(em)
	var pw := LineEdit.new()
	pw.placeholder_text = Lang.t("contraseña")
	pw.secret = true
	pw.custom_minimum_size = Vector2(160, 40)
	hb2.add_child(pw)
	var save := Button.new()
	save.text = Lang.t("Guardar progreso")
	save.pressed.connect(func() -> void:
		var e: String = await Account.link_email(em.text.strip_edges(), pw.text)
		rk_status.text = e if e != "" else Lang.t("Listo: revisa tu correo para confirmarlo."))
	hb2.add_child(save)
	var enter := Button.new()
	enter.text = Lang.t("Ya tengo cuenta: entrar")
	enter.pressed.connect(func() -> void:
		var e: String = await Account.login(em.text.strip_edges(), pw.text)
		rk_status.text = e if e != "" else Lang.t("Entraste.")
		rk_name.text = Account.player_name
		_refresh_account())
	hb2.add_child(enter)


func _refresh_lobby() -> void:
	var r := Net.room
	if r.is_empty():
		return
	online_box.visible = false
	lobby_box.visible = true
	for c in lobby_box.get_children():
		c.queue_free()
	var host := Net.is_host()
	var title := Label.new()
	title.text = Lang.t("Sala  %s") % r.get("code", "")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.98, 0.82, 0.38))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_box.add_child(title)
	var hint := Label.new()
	hint.text = Lang.t("Pásale este código a tu amigo para que se una.") + ("" if host else Lang.t("\nEl anfitrión elige el mapa y los bots y comienza la partida."))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_box.add_child(hint)
	var me := int(r.get("you", -1))
	if not _lobby_civ_sent:
		for p in r.get("players", []):
			if int(p["id"]) == me:
				_lobby_civ_sent = true
				if String(p["civ"]) != Account.fav_civ():
					Net.set_me(Account.fav_civ(), int(p["team"]), int(p["color"]))
	for p in r.get("players", []):
		var hb := HBoxContainer.new()
		var n := Label.new()
		n.text = ("★ " if int(p["id"]) == int(r.get("host", -1)) else "   ") + String(p["name"])
		n.custom_minimum_size = Vector2(190, 0)
		hb.add_child(n)
		var mine := int(p["id"]) == me
		hb.add_child(_civ_pick(String(p["civ"]), mine, func(v: String) -> void: Net.set_me(v, int(p["team"]), int(p["color"]))))
		hb.add_child(_team_pick(int(p["team"]), mine, func(v: int) -> void: Net.set_me(String(p["civ"]), v, int(p["color"]))))
		hb.add_child(_color_pick(int(p["color"]), mine, func(v: int) -> void: Net.set_me(String(p["civ"]), int(p["team"]), v)))
		lobby_box.add_child(hb)
	var bots: Array = r.get("bots", [])
	for i in bots.size():
		var bt: Dictionary = bots[i]
		var idx := i
		var hb := HBoxContainer.new()
		var n := Label.new()
		n.text = Lang.t("   Bot %s") % Lang.t(Defs.DIFFICULTY.get(String(bt["difficulty"]), {"name": ""})["name"])
		n.custom_minimum_size = Vector2(190, 0)
		hb.add_child(n)
		hb.add_child(_civ_pick(String(bt["civ"]), host, func(v: String) -> void: _edit_bot(idx, "civ", v)))
		hb.add_child(_team_pick(int(bt["team"]), host, func(v: int) -> void: _edit_bot(idx, "team", v)))
		var dif := OptionButton.new()
		for d in Defs.DIFF_ORDER:
			dif.add_item(Lang.t(Defs.DIFFICULTY[d]["name"]))
		dif.select(maxi(0, Defs.DIFF_ORDER.find(String(bt["difficulty"]))))
		dif.disabled = not host
		dif.item_selected.connect(func(j: int) -> void: _edit_bot(idx, "difficulty", Defs.DIFF_ORDER[j]))
		hb.add_child(dif)
		if host:
			var del := Button.new()
			del.text = Lang.t("Quitar")
			del.pressed.connect(func() -> void:
				var bl: Array = Net.room.get("bots", []).duplicate(true)
				bl.remove_at(idx)
				Net.set_config(String(Net.room.get("map", "mediano")), bl))
			hb.add_child(del)
		lobby_box.add_child(hb)
	var opts := HBoxContainer.new()
	var ml := Label.new()
	ml.text = Lang.t("Mapa:")
	opts.add_child(ml)
	var mo := OptionButton.new()
	var maps := ["pequeno", "mediano", "grande"]
	for m in [Lang.t("Pequeño"), Lang.t("Mediano"), Lang.t("Grande")]:
		mo.add_item(m)
	mo.select(maxi(0, maps.find(String(r.get("map", "mediano")))))
	mo.disabled = not host
	mo.item_selected.connect(func(j: int) -> void: Net.set_config(maps[j], Net.room.get("bots", [])))
	opts.add_child(mo)
	opts.add_child(_type_pick(String(r.get("type", "azar")), host, func(v: String) -> void:
		Net.set_config(String(Net.room.get("map", "mediano")), Net.room.get("bots", []), v)))
	if host:
		var add := Button.new()
		add.text = Lang.t("+ Agregar bot")
		add.disabled = r.get("players", []).size() + bots.size() >= 8
		add.pressed.connect(func() -> void:
			var bl: Array = Net.room.get("bots", []).duplicate(true)
			bl.append({"civ": Defs.CIV_ORDER[bl.size() % Defs.CIV_ORDER.size()], "team": 2, "difficulty": "normal"})
			Net.set_config(String(Net.room.get("map", "mediano")), bl))
		opts.add_child(add)
	lobby_box.add_child(opts)
	var sl := Label.new()
	sl.add_theme_color_override("font_color", Color(1, 0.8, 0.5))
	lobby_box.add_child(sl)
	status_label = sl
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	lobby_box.add_child(bh)
	var leave := _big_button(Lang.t("Salir de la sala"))
	leave.custom_minimum_size = Vector2(220, 48)
	leave.pressed.connect(func() -> void:
		Net.close()
		lobby_box.visible = false
		online_box.visible = true
		status_label = null)
	bh.add_child(leave)
	if host:
		var go := _big_button(Lang.t("¡Comenzar!"))
		go.custom_minimum_size = Vector2(220, 48)
		go.pressed.connect(func() -> void: Net.start_game())
		bh.add_child(go)


func _edit_bot(i: int, key: String, v) -> void:
	var bl: Array = Net.room.get("bots", []).duplicate(true)
	if i < bl.size():
		bl[i][key] = v
		Net.set_config(String(Net.room.get("map", "mediano")), bl)


func _civ_pick(cur: String, enabled: bool, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for c in Defs.CIV_ORDER:
		o.add_item(Lang.t(Defs.CIVS[c]["name"]))
	o.select(maxi(0, Defs.CIV_ORDER.find(cur)))
	o.disabled = not enabled
	o.custom_minimum_size = Vector2(150, 0)
	o.item_selected.connect(func(j: int) -> void: on_pick.call(Defs.CIV_ORDER[j]))
	return o


func _type_pick(cur: String, enabled: bool, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in Defs.MAP_TYPE_ORDER.size():
		var k: String = Defs.MAP_TYPE_ORDER[i]
		o.add_item(Lang.t(Defs.MAP_TYPES[k]["name"]))
		o.set_item_tooltip(i, Lang.t(Defs.MAP_TYPES[k]["desc"]))
	o.select(maxi(0, Defs.MAP_TYPE_ORDER.find(cur)))
	o.disabled = not enabled
	o.tooltip_text = Lang.t("Tipo de mapa. El terreno se genera al azar en cada partida.")
	o.item_selected.connect(func(j: int) -> void: on_pick.call(Defs.MAP_TYPE_ORDER[j]))
	return o


func _team_pick(cur: int, enabled: bool, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for t in 4:
		o.add_item(Lang.t("Equipo %d") % (t + 1))
	o.select(clampi(cur - 1, 0, 3))
	o.disabled = not enabled
	o.item_selected.connect(func(j: int) -> void: on_pick.call(j + 1))
	return o


func _color_pick(cur: int, enabled: bool, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for c in Defs.COLOR_NAMES.size():
		o.add_item(Lang.t(Defs.COLOR_NAMES[c]))
	o.select(clampi(cur, 0, Defs.COLOR_NAMES.size() - 1))
	o.disabled = not enabled
	o.item_selected.connect(func(j: int) -> void: on_pick.call(j))
	return o
