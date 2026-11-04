extends Control
## Menú principal y configuración de partida contra bots (hasta 8 jugadores, 4 vs 4).

var rows: Array = []     # cada fila: {type: OptionButton, civ, team, color}
var size_opt: OptionButton
var list: VBoxContainer
var main_box: VBoxContainer
var setup_box: VBoxContainer
var online_box: VBoxContainer
var lobby_box: VBoxContainer
var name_edit: LineEdit
var code_edit: LineEdit
var status_label: Label

const TYPES := ["Cerrado", "Tú", "Bot Fácil", "Bot Normal", "Bot Difícil", "Bot Experto"]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.09, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme = _theme()
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var title := Label.new()
	title.text = "CONQUISTA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.98, 0.82, 0.38))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "Civilizaciones de Mesoamérica"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 10)
	root.add_child(main_box)
	var solo := _big_button("Un jugador (contra bots)")
	solo.pressed.connect(func() -> void:
		main_box.visible = false
		setup_box.visible = true)
	main_box.add_child(solo)
	var online := _big_button("En línea con amigos (beta)")
	online.pressed.connect(func() -> void:
		main_box.visible = false
		online_box.visible = true)
	main_box.add_child(online)
	var quit := _big_button("Salir")
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
	pl.text = "Rápido:"
	presets.add_child(pl)
	for pr in [["1 vs 1", [1, 2]], ["2 vs 2", [1, 1, 2, 2]], ["3 vs 3", [1, 1, 1, 2, 2, 2]],
			["4 vs 4", [1, 1, 1, 1, 2, 2, 2, 2]], ["1 vs 3", [1, 2, 2, 2]], ["Todos contra todos (4)", [1, 2, 3, 4]]]:
		var b := Button.new()
		b.text = pr[0]
		var teams: Array = pr[1]
		b.pressed.connect(func() -> void: _preset(teams))
		presets.add_child(b)
	var head := HBoxContainer.new()
	for h in [["Jugador", 170], ["Civilización", 170], ["Equipo", 110], ["Color", 120]]:
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
	ml.text = "Mapa:"
	opts.add_child(ml)
	size_opt = OptionButton.new()
	size_opt.add_item("Pequeño (120)")
	size_opt.add_item("Mediano (160)")
	size_opt.add_item("Grande (220)")
	size_opt.select(1)
	opts.add_child(size_opt)
	setup_box.add_child(opts)
	var civ_info := Label.new()
	civ_info.add_theme_font_size_override("font_size", 13)
	civ_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	civ_info.custom_minimum_size = Vector2(600, 0)
	var txt := ""
	for c in Defs.CIV_ORDER:
		txt += "%s: %s\n" % [Defs.CIVS[c]["name"], Defs.CIVS[c]["desc"]]
	civ_info.text = txt
	setup_box.add_child(civ_info)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	setup_box.add_child(bh)
	var back := _big_button("Volver")
	back.pressed.connect(func() -> void:
		setup_box.visible = false
		main_box.visible = true)
	bh.add_child(back)
	var start := _big_button("¡Comenzar!")
	start.pressed.connect(_start)
	bh.add_child(start)
	_preset([1, 2])
	_build_online(root)
	Net.room_changed.connect(_refresh_lobby)
	Net.failed.connect(func(msg: String) -> void: _status(msg))
	Net.closed.connect(func() -> void:
		_status("Se cerró la conexión.")
		lobby_box.visible = false
		online_box.visible = true)
	Net.started.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/game.tscn"))
	Setup.online = false
	Net.close()


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
		civ.add_item(Defs.CIVS[c]["name"])
	civ.select(i % Defs.CIV_ORDER.size())
	civ.custom_minimum_size = Vector2(170, 0)
	hb.add_child(civ)
	var team := OptionButton.new()
	for t in 4:
		team.add_item("Equipo %d" % (t + 1))
	team.custom_minimum_size = Vector2(110, 0)
	hb.add_child(team)
	var col := OptionButton.new()
	for c in Defs.COLOR_NAMES.size():
		col.add_item(Defs.COLOR_NAMES[c])
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
			"name": "Tú" if t == 1 else "%s (%s)" % [Defs.CIVS[Defs.CIV_ORDER[r["civ"].selected]]["name"], TYPES[t].replace("Bot ", "")],
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
		_warn("Debe haber al menos dos equipos distintos.")
		return
	Setup.players = players
	Setup.online = false
	Setup.local_player = 0
	Setup.map_size = ["pequeno", "mediano", "grande"][size_opt.selected]
	Setup.seed_value = 0
	get_tree().change_scene_to_file("res://scenes/game.tscn")


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
	l.text = "Tu nombre:"
	online_box.add_child(l)
	name_edit = LineEdit.new()
	name_edit.max_length = 16
	name_edit.placeholder_text = "Nombre"
	name_edit.text = Net.player_name if Net.player_name != "Jugador" else ""
	name_edit.custom_minimum_size = Vector2(320, 44)
	online_box.add_child(name_edit)
	var create := _big_button("Crear sala")
	create.pressed.connect(func() -> void:
		if _name() == "":
			_status("Escribe tu nombre.")
			return
		_status("Conectando…")
		Net.create_room(_name()))
	online_box.add_child(create)
	var jl := Label.new()
	jl.text = "¿Tu amigo ya creó una sala? Escribe su código:"
	online_box.add_child(jl)
	var jh := HBoxContainer.new()
	online_box.add_child(jh)
	code_edit = LineEdit.new()
	code_edit.max_length = 4
	code_edit.placeholder_text = "CÓDIGO"
	code_edit.custom_minimum_size = Vector2(150, 48)
	code_edit.add_theme_font_size_override("font_size", 22)
	jh.add_child(code_edit)
	var join := _big_button("Unirse")
	join.custom_minimum_size = Vector2(160, 48)
	join.pressed.connect(func() -> void:
		if _name() == "" or code_edit.text.strip_edges().length() < 4:
			_status("Escribe tu nombre y el código de 4 letras.")
			return
		_status("Conectando…")
		Net.join_room(_name(), code_edit.text))
	jh.add_child(join)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.5))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(320, 0)
	online_box.add_child(status_label)
	var back := _big_button("Volver")
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
	return name_edit.text.strip_edges()


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
	title.text = "Sala  %s" % r.get("code", "")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.98, 0.82, 0.38))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_box.add_child(title)
	var hint := Label.new()
	hint.text = "Pásale este código a tu amigo para que se una." + ("" if host else "\nEl anfitrión elige el mapa y los bots y comienza la partida.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_box.add_child(hint)
	var me := int(r.get("you", -1))
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
		n.text = "   Bot %s" % Defs.DIFFICULTY.get(String(bt["difficulty"]), {"name": ""})["name"]
		n.custom_minimum_size = Vector2(190, 0)
		hb.add_child(n)
		hb.add_child(_civ_pick(String(bt["civ"]), host, func(v: String) -> void: _edit_bot(idx, "civ", v)))
		hb.add_child(_team_pick(int(bt["team"]), host, func(v: int) -> void: _edit_bot(idx, "team", v)))
		var dif := OptionButton.new()
		for d in Defs.DIFF_ORDER:
			dif.add_item(Defs.DIFFICULTY[d]["name"])
		dif.select(maxi(0, Defs.DIFF_ORDER.find(String(bt["difficulty"]))))
		dif.disabled = not host
		dif.item_selected.connect(func(j: int) -> void: _edit_bot(idx, "difficulty", Defs.DIFF_ORDER[j]))
		hb.add_child(dif)
		if host:
			var del := Button.new()
			del.text = "Quitar"
			del.pressed.connect(func() -> void:
				var bl: Array = Net.room.get("bots", []).duplicate(true)
				bl.remove_at(idx)
				Net.set_config(String(Net.room.get("map", "mediano")), bl))
			hb.add_child(del)
		lobby_box.add_child(hb)
	var opts := HBoxContainer.new()
	var ml := Label.new()
	ml.text = "Mapa:"
	opts.add_child(ml)
	var mo := OptionButton.new()
	var maps := ["pequeno", "mediano", "grande"]
	for m in ["Pequeño", "Mediano", "Grande"]:
		mo.add_item(m)
	mo.select(maxi(0, maps.find(String(r.get("map", "mediano")))))
	mo.disabled = not host
	mo.item_selected.connect(func(j: int) -> void: Net.set_config(maps[j], Net.room.get("bots", [])))
	opts.add_child(mo)
	if host:
		var add := Button.new()
		add.text = "+ Agregar bot"
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
	var leave := _big_button("Salir de la sala")
	leave.custom_minimum_size = Vector2(220, 48)
	leave.pressed.connect(func() -> void:
		Net.close()
		lobby_box.visible = false
		online_box.visible = true
		status_label = null)
	bh.add_child(leave)
	if host:
		var go := _big_button("¡Comenzar!")
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
		o.add_item(Defs.CIVS[c]["name"])
	o.select(maxi(0, Defs.CIV_ORDER.find(cur)))
	o.disabled = not enabled
	o.custom_minimum_size = Vector2(150, 0)
	o.item_selected.connect(func(j: int) -> void: on_pick.call(Defs.CIV_ORDER[j]))
	return o


func _team_pick(cur: int, enabled: bool, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for t in 4:
		o.add_item("Equipo %d" % (t + 1))
	o.select(clampi(cur - 1, 0, 3))
	o.disabled = not enabled
	o.item_selected.connect(func(j: int) -> void: on_pick.call(j + 1))
	return o


func _color_pick(cur: int, enabled: bool, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for c in Defs.COLOR_NAMES.size():
		o.add_item(Defs.COLOR_NAMES[c])
	o.select(clampi(cur, 0, Defs.COLOR_NAMES.size() - 1))
	o.disabled = not enabled
	o.item_selected.connect(func(j: int) -> void: on_pick.call(j))
	return o
