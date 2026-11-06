class_name StoreScreen
extends Control
## Tienda: artículos (con monedas o gemas) y paquetes de gemas (con dinero, por Stripe).
## También lleva al Game Pass. Los precios vienen de Supabase (roa_shop, roa_gem_prices).

var home: Node
var body: VBoxContainer
var tab := "articulos"


func setup(h: Node, first_tab := "articulos") -> void:
	home = h
	tab = first_tab
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


func show_tab(t: String) -> void:
	tab = t
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	for c in body.get_children():
		c.queue_free()
	body.add_child(Kit.header(self, Lang.t("TIENDA"), close))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	body.add_child(tabs)
	for t in [["articulos", Lang.t("Artículos")], ["gemas", Lang.t("Gemas")]]:
		var on: bool = tab == t[0]
		var b := Kit.button(t[1], Vector2(220, 56), 26, Kit.RED if on else Kit.GREY)
		var key: String = t[0]
		b.pressed.connect(func() -> void: show_tab(key))
		tabs.add_child(b)
	var pass_b := Kit.button(Lang.t("Game Pass"), Vector2(220, 56), 26, Kit.PURPLE)
	pass_b.pressed.connect(func() -> void:
		close()
		home.open_pass())
	tabs.add_child(pass_b)
	if Economy.status.is_empty():
		var msg := Economy.last_error if Economy.last_error != "" else Lang.t("Cargando la tienda…")
		var l := Kit.label(msg, 26)
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(l)
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cc)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	cc.add_child(grid)
	if tab == "gemas":
		grid.columns = 4
		for p in Economy.status.get("packs", []):
			grid.add_child(_pack_card(p))
		var note := Kit.text(Lang.t("El pago se hace con Stripe (tarjeta). Las gemas llegan a tu cuenta en cuanto se confirma el pago. Sirven para los artículos especiales de la Tienda."), 16, Color(0.85, 0.8, 0.68))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(note)
	else:
		grid.columns = 4
		for s in Economy.status.get("shop", []):
			grid.add_child(_item_card(s))
		if Economy.status.get("shop", []).is_empty():
			body.add_child(Kit.label(Lang.t("Pronto habrá artículos nuevos."), 24))


func _card(rarity_col: Color) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Kit.PANEL, rarity_col, 16, 3))
	p.custom_minimum_size = Vector2(300, 330)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	return vb


func _item_card(s: Dictionary) -> Control:
	var id := String(s["item"])
	var it := Economy.item(id)
	var rarity := String(it.get("rarity", "comun"))
	var vb := _card(Kit.rarity_color(rarity))
	var kind := Kit.label(Kit.kind_name(String(it.get("kind", ""))) + " · " + Kit.rarity_name(rarity), 16, Kit.rarity_color(rarity), 5)
	vb.add_child(kind)
	var view := Kit.item_view(id, 150)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(view)
	var n := Kit.label(Economy.item_name(id), 24)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(n)
	if Economy.owns(id):
		var own := Kit.button("✔ " + Lang.t("Lo tienes"), Vector2(200, 52), 22, Kit.GREY)
		own.disabled = true
		own.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(own)
	else:
		var cur := "coins" if s.get("coins") != null else "gems"
		var price := int(s[cur])
		var b := Kit.price_button(cur, price, Vector2(200, 52), Kit.GREEN if cur == "coins" else Kit.PURPLE.lightened(0.1))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_buy_item.bind(id, cur, price))
		vb.add_child(b)
	return vb.get_parent()


func _buy_item(id: String, cur: String, price: int) -> void:
	var have := Economy.coins() if cur == "coins" else Economy.gems()
	var what := Lang.t("monedas") if cur == "coins" else Lang.t("gemas")
	if have < price:
		if cur == "gems":
			Kit.ask(self, Lang.t("Te faltan gemas"), Lang.t("Cuesta %d gemas y tienes %d.") % [price, have], Lang.t("Conseguir gemas"),
				func() -> void: show_tab("gemas"))
		else:
			Kit.ask(self, Lang.t("Te faltan monedas"), Lang.t("Cuesta %d monedas y tienes %d. Ganas monedas jugando y en el Game Pass.") % [price, have])
		return
	Kit.ask(self, Economy.item_name(id), Lang.t("¿Comprarlo por %d %s?") % [price, what], Lang.t("Comprar"), func() -> void:
		var e: String = await Economy.buy_item(id)
		if e != "":
			Kit.ask(self, Lang.t("Tienda"), e)
		else:
			Kit.ask(self, Lang.t("¡Es tuyo!"), Lang.t("Póntelo desde tu perfil (toca tu tarjeta en el menú).")))


func _pack_card(p: Dictionary) -> Control:
	var gems_n := int(p["gems"])
	var bonus := int(p.get("bonus", 0))
	var vb := _card(Color(0.45, 0.75, 1.0))
	if bonus > 0:
		vb.add_child(Kit.label(Lang.t("+%d de regalo") % bonus, 20, Color(0.6, 1, 0.6), 5))
	else:
		vb.add_child(Kit.label(" ", 20))
	# Más gemas = más iconos.
	var pile := HBoxContainer.new()
	pile.alignment = BoxContainer.ALIGNMENT_CENTER
	pile.add_theme_constant_override("separation", -40)
	vb.add_child(pile)
	var count := 1 if gems_n < 500 else (2 if gems_n < 1000 else (3 if gems_n < 2000 else 4))
	for i in count:
		pile.add_child(Kit.icon("gems", 110 if count == 1 else 90))
	vb.add_child(Kit.label(Lang.t("%s gemas") % Money.thousands(gems_n + bonus), 30))
	var prices: Dictionary = p.get("prices", {})
	var cur := Money.pick(prices)
	var amount := float(prices.get(cur, 0))
	var b := Kit.button(Money.format(amount, cur), Vector2(220, 56), 24, Kit.GREEN)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pid := String(p["id"])
	b.pressed.connect(func() -> void:
		b.disabled = true
		b.text = Lang.t("Abriendo el pago…")
		var e: String = await Economy.buy_gems(pid)
		if not is_instance_valid(b):
			return
		b.disabled = false
		b.text = Money.format(amount, cur)
		if e != "":
			Kit.ask(self, Lang.t("Tienda"), e)
		elif not OS.has_feature("web"):
			Kit.ask(self, Lang.t("Pago abierto"), Lang.t("Termina el pago en tu navegador. Las gemas aparecen aquí solas en cuanto se confirme.")))
	vb.add_child(b)
	return vb.get_parent()


func close() -> void:
	queue_free()
