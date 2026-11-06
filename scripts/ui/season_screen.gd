class_name SeasonScreen
extends Control
## Game Pass: la línea de la temporada con sus niveles. Arriba la fila Premium y abajo la
## gratis; cada nivel pide experiencia de temporada (se gana jugando, aparte del rango).
## Lo alcanzado se reclama tocándolo o con "Reclamar todo".

const COL_W := 132.0
const CELL_H := 190.0

var home: Node
var body: VBoxContainer
var line_scroll: ScrollContainer
var _scrolled := false


func setup(h: Node) -> void:
	home = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Kit.backdrop(self)
	body = VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 28
	body.offset_right = -28
	body.offset_top = 18
	body.offset_bottom = -18
	body.add_theme_constant_override("separation", 14)
	add_child(body)
	Economy.changed.connect(_build)
	_build()
	if not Economy.demo:
		Economy.refresh()


func _build() -> void:
	if not is_inside_tree():
		return
	var keep := line_scroll.scroll_horizontal if line_scroll else -1
	for c in body.get_children():
		c.queue_free()
	line_scroll = null
	body.add_child(Kit.header(self, Lang.t("GAME PASS"), close))
	var s := Economy.season()
	if s.is_empty():
		var msg := Lang.t("Cargando la temporada…") if Economy.loading or Economy.status.is_empty() and Economy.last_error == "" \
			else (Economy.last_error if Economy.last_error != "" else Lang.t("No hay temporada en curso. ¡Pronto empieza la siguiente!"))
		var l := Kit.label(msg, 26)
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(l)
		return
	_build_top(s)
	_build_line()
	_build_bottom()
	# Al abrir, la línea se acomoda en tu nivel; al reclamar se queda donde estaba.
	await get_tree().process_frame
	if line_scroll:
		if keep >= 0 and _scrolled:
			line_scroll.scroll_horizontal = keep
		else:
			line_scroll.scroll_horizontal = int(maxf(0.0, (Economy.tier() - 3) * COL_W))
			_scrolled = true


func _build_top(s: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	body.add_child(row)
	# Nivel y barra de experiencia.
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", Kit.box(Kit.PANEL, Kit.GOLD, 16, 3))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var ib := HBoxContainer.new()
	ib.add_theme_constant_override("separation", 18)
	info.add_child(ib)
	var badge := PanelContainer.new()
	var bs := Kit.box(Kit.RED, Kit.GOLD, 40, 4, false)
	bs.set_content_margin_all(6)
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(110, 110)
	ib.add_child(badge)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", -6)
	badge.add_child(bv)
	bv.add_child(Kit.label(Lang.t("NIVEL"), 18, Kit.GOLD, 5))
	bv.add_child(Kit.label(str(Economy.tier()), 52))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	ib.add_child(mid)
	var name_l := Kit.label(Lang.t(String(s.get("name", ""))), 30, Kit.GOLD)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(name_l)
	mid.add_child(_xp_bar())
	var sub := Kit.label("", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if Economy.tier() >= Economy.tiers():
		sub.text = Lang.t("¡Completaste la temporada!") + "   ·   " + Lang.t("Quedan %d días") % Economy.days_left()
	else:
		sub.text = Lang.t("%d / %d xp para el nivel %d") % [Economy.xp() % Economy.tier_xp(), Economy.tier_xp(), Economy.tier() + 1] \
			+ "   ·   " + Lang.t("Quedan %d días") % Economy.days_left()
	mid.add_child(sub)
	# Premium.
	var prem := PanelContainer.new()
	prem.add_theme_stylebox_override("panel", Kit.box(Color(0.30, 0.13, 0.42, 0.97), Kit.GOLD, 16, 3))
	prem.custom_minimum_size = Vector2(470, 0)
	row.add_child(prem)
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 8)
	prem.add_child(pv)
	var ph := HBoxContainer.new()
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	ph.add_theme_constant_override("separation", 10)
	pv.add_child(ph)
	ph.add_child(Kit.icon("premium", 44))
	ph.add_child(Kit.label(Lang.t("PREMIUM"), 32, Kit.GOLD))
	if Economy.premium():
		pv.add_child(Kit.label(Lang.t("¡Activo! Fila premium abierta y +%d %% de experiencia.") % roundi(float(s.get("premium_bonus", 0.2)) * 100), 18))
	else:
		var why := Kit.text(Lang.t("Abre la fila premium (más monedas, gemas, imágenes, estandartes y títulos) y gana +%d %% de experiencia el resto de la temporada.") % roundi(float(s.get("premium_bonus", 0.2)) * 100), 16)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(why)
		var cost := int(s.get("premium_gems", 500))
		var b := Kit.price_button("gems", cost, Vector2(300, 54), Kit.PURPLE.lightened(0.1))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var hb: HBoxContainer = b.get_child(0)
		var l0 := Kit.label(Lang.t("Obtener"), 24)
		hb.add_child(l0)
		hb.move_child(l0, 0)
		b.pressed.connect(_buy_premium.bind(cost))
		pv.add_child(b)


func _xp_bar() -> Control:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 26)
	bar.max_value = 1.0
	bar.value = Economy.tier_progress()
	var bg := Kit.box(Color(0.08, 0.05, 0.03), Kit.GOLD.darkened(0.3), 13, 2, false)
	bg.set_content_margin_all(0)
	var fg := Kit.box(Color(0.95, 0.68, 0.18), Color(1, 0.9, 0.5), 13, 2, false)
	fg.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _build_line() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	# Nombres de las filas a la izquierda.
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 8)
	names.custom_minimum_size = Vector2(120, 0)
	row.add_child(names)
	names.add_child(_row_tag(Lang.t("PREMIUM"), Kit.PURPLE, "premium"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 44)
	names.add_child(gap)
	names.add_child(_row_tag(Lang.t("GRATIS"), Kit.GREEN, ""))
	line_scroll = ScrollContainer.new()
	line_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(line_scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	line_scroll.add_child(cols)
	for t in range(1, Economy.tiers() + 1):
		cols.add_child(_column(t))


func _row_tag(t: String, color: Color, icon_kind: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(color, Kit.GOLD, 12, 3))
	p.custom_minimum_size = Vector2(120, CELL_H)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(vb)
	if icon_kind != "":
		var ic := Kit.icon(icon_kind, 46)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(ic)
	vb.add_child(Kit.label(t, 20))
	return p


func _column(t: int) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(COL_W, 0)
	col.add_theme_constant_override("separation", 8)
	col.add_child(_cell(t, "premium"))
	# El número del nivel sobre la línea de progreso.
	var mid := Control.new()
	mid.custom_minimum_size = Vector2(COL_W, 44)
	col.add_child(mid)
	var reached := t <= Economy.tier()
	var line := ColorRect.new()
	line.color = Color(0.95, 0.68, 0.18) if reached else Color(0.25, 0.2, 0.15)
	line.position = Vector2(0, 18)
	line.size = Vector2(COL_W, 8)
	mid.add_child(line)
	if t == Economy.tier() + 1:
		var part := ColorRect.new()
		part.color = Color(0.95, 0.68, 0.18)
		part.position = Vector2(0, 18)
		part.size = Vector2(COL_W * 0.5 * Economy.tier_progress() + 0.0, 8)
		mid.add_child(part)
	var dot := PanelContainer.new()
	var ds := Kit.box(Color(0.95, 0.68, 0.18) if reached else Color(0.2, 0.15, 0.1), Kit.GOLD if reached else Color(0.5, 0.42, 0.3), 20, 3, false)
	ds.set_content_margin_all(0)
	dot.add_theme_stylebox_override("panel", ds)
	dot.custom_minimum_size = Vector2(44, 40)
	dot.position = Vector2(COL_W * 0.5 - 22, 2)
	mid.add_child(dot)
	var n := Kit.label(str(t), 20, Color(0.2, 0.08, 0.02) if reached else Kit.CREAM, 0 if reached else 5)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.add_child(n)
	col.add_child(_cell(t, "free"))
	return col


func _cell(t: int, track: String) -> Control:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_left", 5)
	holder.add_theme_constant_override("margin_right", 5)
	holder.custom_minimum_size = Vector2(COL_W, CELL_H)
	var r := Economy.reward(t, track)
	if r.is_empty():
		var empty := Panel.new()
		var es := Kit.box(Color(0.1, 0.07, 0.05, 0.35), Color(0.3, 0.24, 0.18, 0.35), 12, 2, false)
		empty.add_theme_stylebox_override("panel", es)
		holder.add_child(empty)
		return holder
	var got := Economy.claimed(t, track)
	var can := Economy.can_claim(t, track)
	var locked_premium := track == "premium" and not Economy.premium()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var rarity := String(Economy.item(String(r.get("item", ""))).get("rarity", "comun")) if r["kind"] == "item" else "comun"
	var base := Color(0.32, 0.16, 0.42) if track == "premium" else Color(0.18, 0.30, 0.16)
	if t > Economy.tier():
		base = base.darkened(0.45)
	var border := Kit.rarity_color(rarity) if r["kind"] == "item" else Color(0.55, 0.45, 0.3)
	if can:
		border = Color(1, 0.88, 0.3)
	for k in ["normal", "hover", "pressed", "disabled"]:
		var sb := Kit.box(base.lightened(0.12 if k == "hover" else 0.0), border, 12, 5 if can else 3, k != "disabled")
		sb.set_content_margin_all(4)
		b.add_theme_stylebox_override(k, sb)
	b.tooltip_text = Kit.reward_name(r)
	holder.add_child(b)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var view := Kit.reward_view(r, 100)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if got or (t > Economy.tier()):
		view.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(view)
	var tag := Kit.label("", 15, Kit.CREAM, 5)
	if got:
		tag.text = "✔ " + Lang.t("Tuyo")
		tag.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	elif can:
		tag.text = Lang.t("¡Reclamar!")
		tag.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
	elif locked_premium:
		tag.text = "🔒 " + Lang.t("Premium")
	elif r["kind"] == "item":
		tag.text = Kit.kind_name(String(Economy.item(String(r["item"])).get("kind", "")))
	vb.add_child(tag)
	b.pressed.connect(func() -> void:
		if can:
			var e: String = await Economy.claim(t, track)
			if e != "":
				Kit.ask(self, Lang.t("Game Pass"), e)
		else:
			_explain(t, track, r, got, locked_premium))
	return holder


func _explain(t: int, track: String, r: Dictionary, got: bool, locked_premium: bool) -> void:
	var why := ""
	if got:
		why = Lang.t("Ya es tuyo.")
	elif locked_premium:
		why = Lang.t("Es de la fila premium: consigue el Game Pass Premium para reclamarlo.")
		if t > Economy.tier():
			why += " " + Lang.t("Y llega al nivel %d.") % t
	else:
		why = Lang.t("Llega al nivel %d del pase para reclamarlo.") % t
	Kit.ask(self, Kit.reward_name(r), why)


func _build_bottom() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	body.add_child(row)
	var p: Dictionary = Economy.status.get("prizes", {})
	var how := Kit.text(Lang.t("Ganas experiencia en cada partida (aparte de tus puntos de rango). Con rango: +%d al ganar, +%d al perder. Contra bots: +%d al ganar, +%d al perder (partidas de 5 minutos o más, hasta %d al día; hoy llevas %d).") % [
		int(p.get("ranked_win", {}).get("xp", 200)), int(p.get("ranked_loss", {}).get("xp", 80)),
		int(p.get("bots_win", {}).get("xp", 100)), int(p.get("bots_loss", {}).get("xp", 40)),
		int(Economy.status.get("bot_daily", 8)), int(Economy.status.get("bot_games_today", 0))], 16, Color(0.9, 0.84, 0.7))
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	how.add_theme_constant_override("outline_size", 4)
	row.add_child(how)
	var n := Economy.claimable_count()
	var all := Kit.button(Lang.t("Reclamar todo") + (" (%d)" % n if n > 0 else ""), Vector2(300, 64), 26, Kit.GREEN)
	all.disabled = n == 0
	all.pressed.connect(func() -> void:
		var e: String = await Economy.claim_all()
		if e != "":
			Kit.ask(self, Lang.t("Game Pass"), e))
	row.add_child(all)


func _buy_premium(cost: int) -> void:
	if Economy.gems() < cost:
		Kit.ask(self, Lang.t("Te faltan gemas"), Lang.t("El Game Pass Premium cuesta %d gemas y tienes %d. Consigue gemas en la Tienda.") % [cost, Economy.gems()],
			Lang.t("Ir a la Tienda"), func() -> void:
				close()
				home.open_store("gemas"))
		return
	Kit.ask(self, Lang.t("Game Pass Premium"), Lang.t("¿Usar %d gemas para obtener el Premium de esta temporada? Lo que ya alcanzaste de la fila premium se puede reclamar enseguida.") % cost,
		Lang.t("Obtener"), func() -> void:
			var e: String = await Economy.buy_premium()
			Kit.ask(self, Lang.t("Game Pass Premium"), e if e != "" else Lang.t("¡Listo! Ya tienes el Premium.")))


func close() -> void:
	queue_free()


