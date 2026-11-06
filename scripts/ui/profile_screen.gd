class_name ProfileScreen
extends Control
## Tu perfil: tu tarjeta como la ven los demás y tu colección (imágenes, estandartes y
## títulos). Tocar algo que tienes = ponértelo. Lo que no tienes se ve apagado con dónde
## conseguirlo (Game Pass o Tienda).

var home: Node
var body: VBoxContainer
var tab := "imagen"


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
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	Economy.changed.connect(_build)
	_build()
	if not Economy.demo:
		Economy.refresh()


func _build() -> void:
	if not is_inside_tree():
		return
	for c in body.get_children():
		c.queue_free()
	body.add_child(Kit.header(self, Lang.t("TU PERFIL"), close))
	if Economy.status.is_empty():
		var l := Kit.label(Economy.last_error if Economy.last_error != "" else Lang.t("Cargando…"), 26)
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(l)
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	body.add_child(top)
	var card := Kit.profile_card(home.player_display_name(), Economy.equipped("titulo"), home.rank_text(),
		Economy.equipped("imagen"), Economy.equipped("estandarte"), 1.6)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(card)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(tabs)
	for t in [["imagen", Lang.t("Imágenes")], ["estandarte", Lang.t("Estandartes")], ["titulo", Lang.t("Títulos")]]:
		var b := Kit.button(t[1], Vector2(210, 58), 24, Kit.RED if tab == t[0] else Kit.GREY)
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			tab = key
			_build())
		tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cc)
	var grid := GridContainer.new()
	grid.columns = 6 if tab != "titulo" else 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	cc.add_child(grid)
	# Primero lo que tienes, luego lo demás.
	var items: Dictionary = Economy.status.get("items", {})
	var ids: Array = []
	for id in items:
		if items[id].get("kind") == tab:
			ids.append(id)
	ids.sort_custom(func(a, b) -> bool:
		var oa := Economy.owns(a)
		var ob := Economy.owns(b)
		return oa and not ob if oa != ob else a < b)
	if tab == "titulo":
		grid.add_child(_slot("", true))
	for id in ids:
		grid.add_child(_slot(id, Economy.owns(id)))


func _slot(id: String, mine: bool) -> Control:
	var on := Economy.equipped(tab) == id
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 120) if tab == "titulo" else Vector2(190, 210)
	var rarity := String(Economy.item(id).get("rarity", "comun"))
	var border := Color(1, 0.88, 0.3) if on else (Kit.rarity_color(rarity) if id != "" else Color(0.5, 0.42, 0.3))
	for k in ["normal", "hover", "pressed"]:
		var sb := Kit.box(Kit.PANEL.lightened(0.08 if k == "hover" else 0.0), border, 14, 5 if on else 3)
		sb.set_content_margin_all(6)
		b.add_theme_stylebox_override(k, sb)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	if id == "":
		vb.add_child(Kit.label(Lang.t("Sin título"), 22))
	else:
		var v := Kit.item_view(id, 120 if tab != "titulo" else 80)
		v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not mine:
			v.modulate = Color(0.35, 0.35, 0.35, 0.8)
		vb.add_child(v)
		if tab != "titulo":
			var n := Kit.label(Economy.item_name(id), 16, Kit.CREAM, 5)
			n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(n)
	var tag := Kit.label("", 15, Kit.CREAM, 5)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if on:
		tag.text = "✔ " + Lang.t("Puesto")
		tag.add_theme_color_override("font_color", Color(1, 0.88, 0.3))
	elif not mine:
		tag.text = "🔒 " + _where(id)
		tag.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	vb.add_child(tag)
	b.pressed.connect(func() -> void:
		if not mine:
			Kit.ask(self, Economy.item_name(id), Lang.t("Todavía no lo tienes. Se consigue en: %s.") % _where(id))
			return
		if on:
			return
		var e: String = await Economy.equip(tab, id)
		if e != "":
			Kit.ask(self, Lang.t("Tu perfil"), e))
	return b


## Dónde se consigue: nivel del pase o la tienda.
func _where(id: String) -> String:
	for r in Economy.status.get("rewards", []):
		if r.get("item") is String and r["item"] == id:
			return (Lang.t("Premium · nivel %d") if r["track"] == "premium" else Lang.t("Pase gratis · nivel %d")) % int(r["tier"])
	for s in Economy.status.get("shop", []):
		if s["item"] == id:
			return Lang.t("Tienda")
	return Lang.t("Próximamente")


func close() -> void:
	queue_free()
