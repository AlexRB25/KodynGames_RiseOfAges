class_name SoloScreen
extends Control
## "Un jugador": eliges el modo (1 vs 1 … 4 vs 4, todos contra todos) y se arma la
## alineación con el aldeano nivel 5 de cada civilización. Con pocos jugadores se ven
## grandes; con muchos, cuadros con la carita y sus selectores dentro.

var home: Home
var menu: Node
var preset := "1v1"
var slots: Array = []        # {civ, team, color, bot, difficulty}
var area: Control
var preset_btns := {}
var size_opt: OptionButton
var type_opt: OptionButton
var opt_theme: Theme

const PRESETS := [
	["1v1", "1 vs 1", [1, 2]],
	["2v2", "2 vs 2", [1, 1, 2, 2]],
	["3v3", "3 vs 3", [1, 1, 1, 2, 2, 2]],
	["4v4", "4 vs 4", [1, 1, 1, 1, 2, 2, 2, 2]],
	["1v3", "1 vs 3", [1, 2, 2, 2]],
	["ffa", "Todos contra todos", [1, 2, 3, 4]],
]
const GREEN := Color(0.16, 0.48, 0.22)


func setup(h: Home, m: Node) -> void:
	home = h
	menu = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = Art.tex("ui/fondo.jpg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.05, 0.03, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	opt_theme = _make_opt_theme()
	_build()
	_set_preset("1v1")


func _make_opt_theme() -> Theme:
	var t := Theme.new()
	t.default_font = home.font
	t.default_font_size = 19
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.2, 0.13, 0.08)
	n.border_color = Color(0.85, 0.66, 0.28)
	n.set_border_width_all(2)
	n.set_corner_radius_all(8)
	n.set_content_margin_all(6)
	var hv := n.duplicate()
	hv.bg_color = Color(0.32, 0.2, 0.1)
	for k in ["normal", "focus"]:
		t.set_stylebox(k, "OptionButton", n)
	t.set_stylebox("hover", "OptionButton", hv)
	t.set_stylebox("pressed", "OptionButton", hv)
	t.set_color("font_color", "OptionButton", Color(0.98, 0.93, 0.8))
	t.set_color("font_color", "Label", Color(0.98, 0.93, 0.8))
	var pp := StyleBoxFlat.new()
	pp.bg_color = Color(0.16, 0.11, 0.07, 0.98)
	pp.border_color = Color(0.85, 0.66, 0.28)
	pp.set_border_width_all(2)
	t.set_stylebox("panel", "PopupMenu", pp)
	t.set_font_size("font_size", "PopupMenu", 19)
	return t


func _build() -> void:
	var title := home._label("UN JUGADOR", 46, Home.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 10
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)
	# Modos
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.offset_top = 78
	row.offset_bottom = 136
	add_child(row)
	for pr in PRESETS:
		var b := home.art_button(pr[1], Vector2(150 if pr[0] != "ffa" else 290, 56), 24)
		var id: String = pr[0]
		b.pressed.connect(func() -> void: _set_preset(id))
		row.add_child(b)
		preset_btns[id] = b
	# Alineación
	area = Control.new()
	area.anchor_left = 0.03
	area.anchor_right = 0.97
	area.anchor_top = 0.17
	area.anchor_bottom = 0.84
	add_child(area)
	# Abajo: mapa, volver, jugar
	var bottom := HBoxContainer.new()
	bottom.theme = opt_theme
	bottom.add_theme_constant_override("separation", 12)
	bottom.anchor_left = 0.03
	bottom.anchor_right = 0.97
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -108
	bottom.offset_bottom = -22
	add_child(bottom)
	var back := home.art_button("Volver", Vector2(170, 76), 26, Color(0.25, 0.22, 0.20))
	back.pressed.connect(queue_free)
	bottom.add_child(back)
	var ml := Label.new()
	ml.text = "Mapa:"
	bottom.add_child(ml)
	size_opt = OptionButton.new()
	for t in ["Pequeño", "Mediano", "Grande"]:
		size_opt.add_item(t)
	size_opt.select(1)
	size_opt.custom_minimum_size = Vector2(150, 50)
	size_opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(size_opt)
	var tl := Label.new()
	tl.text = "Tipo:"
	bottom.add_child(tl)
	type_opt = OptionButton.new()
	for i in Defs.MAP_TYPE_ORDER.size():
		var k: String = Defs.MAP_TYPE_ORDER[i]
		type_opt.add_item(Defs.MAP_TYPES[k]["name"])
		type_opt.set_item_tooltip(i, Defs.MAP_TYPES[k]["desc"])
	type_opt.custom_minimum_size = Vector2(210, 50)
	type_opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(type_opt)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	var play := home.art_button("¡JUGAR!", Vector2(300, 80), 40, GREEN)
	play.pressed.connect(_play)
	bottom.add_child(play)


func _set_preset(id: String) -> void:
	preset = id
	var teams: Array = []
	for pr in PRESETS:
		if pr[0] == id:
			teams = pr[2]
	# El modo elegido, en verde.
	for k in preset_btns:
		var b: Button = preset_btns[k]
		var col := GREEN if k == id else Home.RED
		b.add_theme_stylebox_override("normal", home._box(col, Home.GOLD))
		b.add_theme_stylebox_override("hover", home._box(col.lightened(0.15), Home.GOLD.lightened(0.2)))
	var old := slots
	slots = []
	for i in teams.size():
		var civ: String = Account.fav_civ() if i == 0 else String(Defs.CIV_ORDER[(i + 1) % Defs.CIV_ORDER.size()])
		var dif := "normal"
		if i < old.size():
			civ = old[i]["civ"]
			dif = old[i]["difficulty"]
		slots.append({"civ": civ, "team": teams[i], "color": i, "bot": i > 0, "difficulty": dif})
	_rebuild()


func _rebuild() -> void:
	for c in area.get_children():
		c.queue_free()
	var team_ids: Array = []
	for s in slots:
		if not team_ids.has(s["team"]):
			team_ids.append(s["team"])
	var big := slots.size() <= 4
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	area.add_child(row)
	for ti in team_ids.size():
		if ti > 0:
			var vs := home._label("VS", 64, Home.GOLD)
			vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(vs)
		var side_slots: Array = []
		for i in slots.size():
			if slots[i]["team"] == team_ids[ti]:
				side_slots.append(i)
		var side: Container
		if big:
			side = HBoxContainer.new()
			side.add_theme_constant_override("separation", 14)
		else:
			side = GridContainer.new()
			(side as GridContainer).columns = 2 if side_slots.size() > 2 else 1
			side.add_theme_constant_override("h_separation", 12)
			side.add_theme_constant_override("v_separation", 12)
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(side)
		for i in side_slots:
			side.add_child(_card(i, big, side_slots.size(), team_ids.size()))


## Tarjeta de un jugador: su aldeano (o su carita), civilización y nivel del bot.
func _card(i: int, big: bool, per_side: int, n_teams: int) -> Control:
	var s: Dictionary = slots[i]
	var col: Color = Defs.PLAYER_COLORS[s["color"]]
	var p := PanelContainer.new()
	p.theme = opt_theme
	p.add_theme_stylebox_override("panel", home._box(Color(0.14, 0.09, 0.06, 0.9), col.lightened(0.15), 14, 4))
	var who := ("Tú" if Account.player_name == "" else Account.player_name) if not s["bot"] else "Bot %d" % i
	var civ_opt := OptionButton.new()
	for c in Defs.CIV_ORDER:
		civ_opt.add_item(Defs.CIVS[c]["name"])
	civ_opt.select(maxi(0, Defs.CIV_ORDER.find(s["civ"])))
	var dif_opt: OptionButton = null
	if s["bot"]:
		dif_opt = OptionButton.new()
		for d in Defs.DIFF_ORDER:
			dif_opt.add_item("Nivel: " + String(Defs.DIFFICULTY[d]["name"]))
		dif_opt.select(maxi(0, Defs.DIFF_ORDER.find(s["difficulty"])))
		dif_opt.item_selected.connect(func(j: int) -> void: slots[i]["difficulty"] = Defs.DIFF_ORDER[j])
	if big:
		var w := 420.0 if per_side == 1 and n_teams == 2 else 330.0
		if n_teams > 2:
			w = 300.0
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		p.add_child(vb)
		var fig := CivFigure.new(s["civ"], col)
		fig.custom_minimum_size = Vector2(w, w * 0.92 if per_side == 1 else w * 0.85)
		vb.add_child(fig)
		var name_l := home._label(who, 28, col.lightened(0.45))
		vb.add_child(name_l)
		civ_opt.custom_minimum_size = Vector2(w, 48)
		vb.add_child(civ_opt)
		if dif_opt:
			dif_opt.custom_minimum_size = Vector2(w, 44)
			vb.add_child(dif_opt)
		civ_opt.item_selected.connect(func(j: int) -> void:
			slots[i]["civ"] = Defs.CIV_ORDER[j]
			fig.set_civ(Defs.CIV_ORDER[j]))
	else:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		p.add_child(hb)
		var face := CivFigure.new(s["civ"], col, true)
		face.custom_minimum_size = Vector2(118, 118)
		hb.add_child(face)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		hb.add_child(vb)
		var name_l := home._label(who, 22, col.lightened(0.45))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.add_child(name_l)
		civ_opt.custom_minimum_size = Vector2(190, 40)
		vb.add_child(civ_opt)
		if dif_opt:
			dif_opt.custom_minimum_size = Vector2(190, 40)
			vb.add_child(dif_opt)
		civ_opt.item_selected.connect(func(j: int) -> void:
			slots[i]["civ"] = Defs.CIV_ORDER[j]
			face.set_civ(Defs.CIV_ORDER[j]))
	return p


func _play() -> void:
	var players: Array = []
	for i in slots.size():
		var s: Dictionary = slots[i]
		var nm := "Tú" if Account.player_name == "" else Account.player_name
		if s["bot"]:
			nm = "%s (%s)" % [Defs.CIVS[s["civ"]]["name"], Defs.DIFFICULTY[s["difficulty"]]["name"]]
		players.append({"name": nm, "civ": s["civ"], "team": s["team"], "color": s["color"],
			"bot": s["bot"], "difficulty": s["difficulty"]})
	Setup.players = players
	Setup.online = false
	Setup.tutorial = false
	Setup.local_player = 0
	Setup.map_size = ["pequeno", "mediano", "grande"][size_opt.selected]
	Setup.map_type = Defs.MAP_TYPE_ORDER[type_opt.selected]
	Setup.seed_value = 0
	get_tree().change_scene_to_file("res://scenes/game.tscn")
