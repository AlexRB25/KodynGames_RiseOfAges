class_name StoreScreen
extends Control
## Tienda en una sola página que se recorre hacia abajo, por secciones:
##   Oferta especial (Game Pass Premium) · Ofertas del día (regalo gratis + 5 artículos con
##   descuento que cambian cada día) · Artículos · Gemas (con dinero, Stripe) · Monedas (con gemas).
## Arriba hay botones para saltar a cada sección. Precios y ofertas vienen de Supabase
## (roa_status: shop, deals, packs, coin_packs).

const COLS := 3
const CARD := Vector2(330, 360)

var home: Node
var body: VBoxContainer
var scroll: ScrollContainer
var tab := "ofertas"          # sección a la que se salta al abrir
var _sections := {}
var _timer_label: Label
var _timer_t := 0.0
var _keep_scroll := -1


func setup(h: Node, first_tab := "ofertas") -> void:
	home = h
	tab = {"articulos": "articulos", "gemas": "gemas"}.get(first_tab, first_tab)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Kit.backdrop(self)
	body = VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 28
	body.offset_right = -28
	body.offset_top = 18
	body.offset_bottom = -18
	body.add_theme_constant_override("separation", 12)
	add_child(body)
	Economy.changed.connect(_rebuild_keep)
	_build()
	if not Economy.demo:
		Economy.refresh()


## Saltar a una sección (ofertas, articulos, gemas, monedas).
func show_tab(t: String) -> void:
	tab = t
	_scroll_to(t)


func _rebuild_keep() -> void:
	_keep_scroll = scroll.scroll_vertical if scroll else -1
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	for c in body.get_children():
		c.queue_free()
	_sections.clear()
	_timer_label = null
	body.add_child(Kit.header(self, Lang.t("TIENDA"), close))
	var jumps := HBoxContainer.new()
	jumps.add_theme_constant_override("separation", 10)
	body.add_child(jumps)
	for t in [["ofertas", Lang.t("Ofertas"), Kit.RED], ["articulos", Lang.t("Artículos"), Kit.GREY],
			["gemas", Lang.t("Gemas"), Color(0.15, 0.32, 0.55)], ["monedas", Lang.t("Monedas"), Color(0.55, 0.38, 0.08)]]:
		var b := Kit.button(t[1], Vector2(190, 50), 22, t[2])
		var key: String = t[0]
		b.pressed.connect(func() -> void: show_tab(key))
		jumps.add_child(b)
	var pass_b := Kit.button(Lang.t("Game Pass"), Vector2(190, 50), 22, Kit.PURPLE)
	pass_b.pressed.connect(func() -> void:
		close()
		home.open_pass())
	jumps.add_child(pass_b)
	if Economy.status.is_empty():
		var msg := Economy.last_error if Economy.last_error != "" else Lang.t("Cargando la tienda…")
		var l := Kit.label(msg, 26)
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(l)
		return
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 18)
	scroll.add_child(page)
	_build_special(page)
	_build_deals(page)
	_build_items(page)
	_build_gems(page)
	_build_coins(page)
	var note := Kit.text(Lang.t("Las gemas se pagan con tarjeta (Stripe) y llegan a tu cuenta en cuanto se confirma el pago. Las monedas se ganan jugando, en el Game Pass y en el regalo diario, o se cambian por gemas."), 16, Color(0.85, 0.8, 0.68))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(note)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 20)
	page.add_child(pad)
	await get_tree().process_frame
	if not is_instance_valid(scroll):
		return
	if _keep_scroll >= 0:
		scroll.scroll_vertical = _keep_scroll
		_keep_scroll = -1
	elif tab != "ofertas":
		_scroll_to(tab)


func _scroll_to(t: String) -> void:
	if scroll and _sections.has(t) and is_instance_valid(_sections[t]):
		var target: float = _sections[t].position.y
		create_tween().tween_property(scroll, "scroll_vertical", int(target), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	if _timer_label == null or not is_instance_valid(_timer_label):
		return
	_timer_t -= dt
	if _timer_t <= 0.0:
		_timer_t = 1.0
		_timer_label.text = Lang.t("Nuevas ofertas en %s") % _time_text(Economy.deals_left())


static func _time_text(sec: int) -> String:
	var h := sec / 3600
	var m := (sec % 3600) / 60
	if h > 0:
		return Lang.t("%d h %d min") % [h, m]
	return Lang.t("%d min %d s") % [m, sec % 60]


# ---------------------------------------------------------------- secciones

## Cinta con el título de la sección (y un texto chico abajo).
func _section(page: VBoxContainer, key: String, title: String, color: Color, sub := "") -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 14)
	page.add_child(holder)
	_sections[key] = holder
	var ribbon := PanelContainer.new()
	var sb := Kit.box(color, Kit.GOLD, 10, 4)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	ribbon.add_theme_stylebox_override("panel", sb)
	holder.add_child(ribbon)
	ribbon.add_child(Kit.label(title, 40, Kit.CREAM, 9))
	if sub != "":
		var s := Kit.label(sub, 20, Color(0.95, 0.88, 0.7), 5)
		holder.add_child(s)
		if key == "ofertas":
			_timer_label = s
	return holder


func _grid(holder: VBoxContainer, cols := COLS) -> GridContainer:
	var cc := CenterContainer.new()
	holder.add_child(cc)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	cc.add_child(grid)
	return grid


## Oferta especial: el Game Pass Premium de la temporada (si no lo tienes).
func _build_special(page: VBoxContainer) -> void:
	var s := Economy.season()
	if s.is_empty() or Economy.premium():
		return
	var holder := _section(page, "especial", Lang.t("Oferta especial"), Color(0.62, 0.36, 0.06))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Color(0.30, 0.12, 0.42, 0.98), Kit.GOLD, 18, 4))
	holder.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	p.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	left.add_child(top)
	top.add_child(Kit.icon("premium", 64))
	var t := Kit.label(Lang.t("GAME PASS PREMIUM"), 46, Kit.GOLD, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(t)
	var sn := Kit.label(Lang.t(String(s.get("name", ""))), 24, Kit.CREAM, 6)
	sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(sn)
	var n_prem := 0
	for r in Economy.status.get("rewards", []):
		if r["track"] == "premium":
			n_prem += 1
	var why := Kit.text("• " + Lang.t("%d premios más en la fila premium") % n_prem + "\n• " +
		Lang.t("+%d %% de experiencia toda la temporada") % roundi(float(s.get("premium_bonus", 0.2)) * 100) + "\n• " +
		Lang.t("Lo que ya alcanzaste se reclama al momento"), 20)
	left.add_child(why)
	# Lo mejor de la fila premium.
	var best := best_premium(4)
	var shelf := HBoxContainer.new()
	shelf.add_theme_constant_override("separation", 10)
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(shelf)
	for r in best:
		var cell := PanelContainer.new()
		var rar := String(Economy.item(String(r.get("item", ""))).get("rarity", "comun"))
		cell.add_theme_stylebox_override("panel", Kit.box(Color(0.2, 0.08, 0.28), Kit.rarity_color(rar), 12, 3))
		cell.custom_minimum_size = Vector2(130, 150)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(vb)
		var v := Kit.reward_view(r, 92)
		v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(v)
		vb.add_child(Kit.label(Kit.rarity_name(rar), 15, Kit.rarity_color(rar), 5))
		shelf.add_child(cell)
	var prices := Economy.premium_prices()
	var cur := Money.pick(prices)
	var price_text := Money.format(float(prices.get(cur, 0)), cur) if prices.has(cur) else ""
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var b := Kit.button(Lang.t("Obtener") + ("\n" + price_text if price_text != "" else ""), Vector2(250, 96), 28, Kit.GREEN)
	b.pressed.connect(func() -> void:
		Kit.ask(self, Lang.t("Game Pass Premium"), Lang.t("¿Obtener el Premium de esta temporada por %s? El pago se hace con tarjeta (Stripe).") % price_text,
			Lang.t("Pagar"), func() -> void:
				var e: String = await Economy.buy_premium()
				if e != "":
					Kit.ask(self, Lang.t("Game Pass Premium"), e)
				elif not OS.has_feature("web"):
					Kit.ask(self, Lang.t("Pago abierto"), Lang.t("Termina el pago en tu navegador. El Premium se activa aquí solo en cuanto se confirme."))))
	right.add_child(b)
	var see := Kit.button(Lang.t("Ver premios"), Vector2(250, 50), 20, Kit.PURPLE)
	see.pressed.connect(func() -> void:
		close()
		home.open_pass())
	right.add_child(see)


## Los premios más valiosos de la fila premium (legendarios primero).
static func best_premium(n: int) -> Array:
	var order := {"legendario": 0, "epico": 1, "raro": 2, "comun": 3}
	var list: Array = []
	for r in Economy.status.get("rewards", []):
		if r["track"] == "premium" and r["kind"] == "item" and String(Economy.item(String(r["item"])).get("kind", "")) != "titulo":
			list.append(r)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = order.get(String(Economy.item(String(a["item"])).get("rarity", "comun")), 3)
		var rb: int = order.get(String(Economy.item(String(b["item"])).get("rarity", "comun")), 3)
		return ra < rb if ra != rb else int(a["tier"]) > int(b["tier"]))
	return list.slice(0, n)


func _build_deals(page: VBoxContainer) -> void:
	var holder := _section(page, "ofertas", Lang.t("Ofertas del día"), Kit.RED,
		Lang.t("Nuevas ofertas en %s") % _time_text(Economy.deals_left()))
	var grid := _grid(holder)
	grid.add_child(_gift_card())
	for d in Economy.deals():
		grid.add_child(_item_card(d, true))


## Regalo del día: monedas gratis una vez al día.
func _gift_card() -> Control:
	var ready := Economy.gift_ready()
	var vb := _card(Color(0.45, 1.0, 0.5), Color(0.12, 0.36, 0.16, 0.98) if ready else Kit.PANEL)
	vb.add_child(Kit.label(Lang.t("Regalo del día"), 26, Kit.GOLD, 6))
	var pile := HBoxContainer.new()
	pile.alignment = BoxContainer.ALIGNMENT_CENTER
	pile.add_theme_constant_override("separation", -46)
	vb.add_child(pile)
	for i in 3:
		pile.add_child(Kit.icon("coins", 96))
	vb.add_child(Kit.label("+%d" % Economy.gift_coins(), 34))
	if ready:
		var b := Kit.button(Lang.t("¡GRATIS!"), Vector2(230, 58), 30, Kit.GREEN.lightened(0.1))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			b.disabled = true
			var e: String = await Economy.claim_gift()
			if e != "":
				Kit.ask(self, Lang.t("Tienda"), e)
			else:
				Sfx.play("listo"))
		vb.add_child(b)
	else:
		var l := Kit.label("✔ " + Lang.t("Reclamado · vuelve mañana"), 18, Color(0.6, 1, 0.6), 5)
		vb.add_child(l)
	return _root(vb)


func _build_items(page: VBoxContainer) -> void:
	var holder := _section(page, "articulos", Lang.t("Artículos"), Color(0.30, 0.22, 0.14), Lang.t("Estandartes, títulos e imágenes para tu perfil"))
	var deal_ids := {}
	for d in Economy.deals():
		deal_ids[d["item"]] = true
	var list: Array = []
	for s in Economy.status.get("shop", []):
		if not deal_ids.has(s["item"]):
			list.append(s)
	# Primero lo que no tienes; luego por tipo.
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := Economy.owns(String(a["item"]))
		var ob := Economy.owns(String(b["item"]))
		if oa != ob:
			return ob
		return String(Economy.item(String(a["item"])).get("kind", "")) < String(Economy.item(String(b["item"])).get("kind", "")))
	if list.is_empty():
		holder.add_child(Kit.label(Lang.t("Pronto habrá artículos nuevos."), 24))
		return
	var grid := _grid(holder, 4)
	for s in list:
		grid.add_child(_item_card(s, false))


func _build_gems(page: VBoxContainer) -> void:
	var holder := _section(page, "gemas", Lang.t("Gemas"), Color(0.15, 0.32, 0.55), Lang.t("Para artículos especiales, monedas y saltar niveles del Game Pass"))
	var grid := _grid(holder)
	var packs: Array = Economy.status.get("packs", [])
	for i in packs.size():
		var tag := ""
		if String(packs[i]["id"]) == "gemas_1000":
			tag = Lang.t("Más popular")
		elif i == packs.size() - 1 and packs.size() > 2:
			tag = Lang.t("Mejor valor")
		grid.add_child(_pack_card(packs[i], tag))


func _build_coins(page: VBoxContainer) -> void:
	var packs := Economy.coin_packs()
	if packs.is_empty():
		return
	var holder := _section(page, "monedas", Lang.t("Monedas"), Color(0.55, 0.38, 0.08), Lang.t("Cambia gemas por monedas"))
	var grid := _grid(holder)
	for i in packs.size():
		grid.add_child(_coin_card(packs[i], i))


# ---------------------------------------------------------------- tarjetas

## Tarjeta: un cuadro (para poder poner cintas encima) con el panel adentro.
## Devuelve la columna de contenido; la tarjeta es _root(vb).
func _card(border: Color, bg := Kit.PANEL) -> VBoxContainer:
	var holder := Control.new()
	holder.custom_minimum_size = CARD
	holder.pivot_offset = CARD * 0.5
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(bg, border, 16, 3))
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(p)
	p.mouse_entered.connect(func() -> void: create_tween().tween_property(holder, "scale", Vector2(1.03, 1.03), 0.12))
	p.mouse_exited.connect(func() -> void: create_tween().tween_property(holder, "scale", Vector2.ONE, 0.12))
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	return vb


func _root(vb: Control) -> Control:
	return vb.get_parent().get_parent()


## Cinta en la esquina de una tarjeta ("-25 %", "Más popular"...).
func _ribbon(card: Control, text: String, color: Color) -> void:
	var r := PanelContainer.new()
	var sb := Kit.box(color, Kit.GOLD, 8, 2, false)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	r.add_theme_stylebox_override("panel", sb)
	r.position = Vector2(-8, -12)
	r.rotation = -0.12
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(Kit.label(text, 20, Kit.CREAM, 6))
	card.add_child(r)


## s: {item, coins, gems} (y old_coins/old_gems si es oferta del día).
func _item_card(s: Dictionary, deal: bool) -> Control:
	var id := String(s["item"])
	var it := Economy.item(id)
	var rarity := String(it.get("rarity", "comun"))
	var vb := _card(Kit.rarity_color(rarity))
	vb.add_child(Kit.label(Kit.kind_name(String(it.get("kind", ""))) + " · " + Kit.rarity_name(rarity), 16, Kit.rarity_color(rarity), 5))
	var view := Kit.item_view(id, 140)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(view)
	var n := Kit.label(Economy.item_name(id), 24)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(n)
	var cur := "coins" if s.get("coins") != null else "gems"
	var price := int(s[cur])
	if Economy.owns(id):
		var own := Kit.button("✔ " + Lang.t("Lo tienes"), Vector2(210, 52), 22, Kit.GREY)
		own.disabled = true
		own.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(own)
	else:
		if deal and s.get("old_" + cur) != null and int(s["old_" + cur]) > price:
			vb.add_child(_old_price(cur, int(s["old_" + cur])))
		var b := Kit.price_button(cur, price, Vector2(210, 52), Kit.GREEN if cur == "coins" else Kit.PURPLE.lightened(0.1))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_buy_item.bind(id, cur, price))
		vb.add_child(b)
	var card: Control = _root(vb)
	if deal:
		_ribbon(card, "-%d %%" % roundi(float(Economy.status.get("deal_off", 0.25)) * 100), Color(0.75, 0.12, 0.1))
	return card


## Precio de antes, tachado.
func _old_price(cur: String, amount: int) -> Control:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 4)
	hb.modulate = Color(1, 1, 1, 0.75)
	hb.add_child(Kit.icon(cur, 22))
	var l := Kit.label(Money.thousands(amount), 20, Color(0.85, 0.8, 0.7), 4)
	hb.add_child(l)
	var line := ColorRect.new()
	line.color = Color(1, 0.3, 0.25)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_right = 1.0
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_left = -30
	line.offset_right = 4
	line.offset_top = -1.5
	line.offset_bottom = 1.5
	line.rotation = -0.1
	l.add_child(line)
	return hb


func _buy_item(id: String, cur: String, price: int) -> void:
	var have := Economy.coins() if cur == "coins" else Economy.gems()
	var what := Lang.t("monedas") if cur == "coins" else Lang.t("gemas")
	if have < price:
		if cur == "gems":
			Kit.ask(self, Lang.t("Te faltan gemas"), Lang.t("Cuesta %d gemas y tienes %d.") % [price, have], Lang.t("Conseguir gemas"),
				func() -> void: show_tab("gemas"))
		else:
			Kit.ask(self, Lang.t("Te faltan monedas"), Lang.t("Cuesta %d monedas y tienes %d. Ganas monedas jugando, en el Game Pass y en el regalo diario, o cámbialas por gemas.") % [price, have],
				Lang.t("Ver monedas"), func() -> void: show_tab("monedas"))
		return
	Kit.ask(self, Economy.item_name(id), Lang.t("¿Comprarlo por %d %s?") % [price, what], Lang.t("Comprar"), func() -> void:
		var e: String = await Economy.buy_item(id)
		if e != "":
			Kit.ask(self, Lang.t("Tienda"), e)
		else:
			Sfx.play("mejora")
			Kit.ask(self, Lang.t("¡Es tuyo!"), Lang.t("Póntelo desde tu perfil (toca tu tarjeta en el menú).")))


func _pack_card(p: Dictionary, tag: String) -> Control:
	var gems_n := int(p["gems"])
	var bonus := int(p.get("bonus", 0))
	var vb := _card(Color(0.45, 0.75, 1.0), Color(0.10, 0.12, 0.22, 0.97))
	if bonus > 0:
		vb.add_child(Kit.label(Lang.t("%s + %s de regalo") % [Money.thousands(gems_n), Money.thousands(bonus)], 18, Color(0.6, 1, 0.6), 5))
	else:
		vb.add_child(Kit.label(" ", 18))
	# Más gemas = más montón.
	var pile := HBoxContainer.new()
	pile.alignment = BoxContainer.ALIGNMENT_CENTER
	pile.add_theme_constant_override("separation", -52)
	vb.add_child(pile)
	var total := gems_n + bonus
	var count := 1 if total < 300 else (2 if total < 1000 else (3 if total < 2500 else (4 if total < 6000 else 5)))
	for i in count:
		pile.add_child(Kit.icon("gems", 110 if count == 1 else 92))
	vb.add_child(Kit.label(Lang.t("%s gemas") % Money.thousands(total), 32))
	var prices: Dictionary = p.get("prices", {})
	var cur := Money.pick(prices)
	var amount := float(prices.get(cur, 0))
	var b := Kit.button(Money.format(amount, cur), Vector2(230, 58), 24, Kit.GREEN)
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
	var card: Control = _root(vb)
	if tag != "":
		_ribbon(card, tag, Color(0.12, 0.45, 0.2) if tag == Lang.t("Mejor valor") else Color(0.7, 0.35, 0.05))
	return card


func _coin_card(c: Dictionary, i: int) -> Control:
	var coins_n := int(c["coins"])
	var price := int(c["gems"])
	var vb := _card(Kit.GOLD, Color(0.24, 0.16, 0.05, 0.97))
	vb.add_child(Kit.label([Lang.t("Bolsa de monedas"), Lang.t("Cofre de monedas"), Lang.t("Tesoro de monedas")][mini(i, 2)], 24, Kit.GOLD, 6))
	var pile := HBoxContainer.new()
	pile.alignment = BoxContainer.ALIGNMENT_CENTER
	pile.add_theme_constant_override("separation", -56)
	vb.add_child(pile)
	for k in [2, 3, 5][mini(i, 2)]:
		pile.add_child(Kit.icon("coins", 92))
	vb.add_child(Kit.label(Money.thousands(coins_n), 34))
	var b := Kit.price_button("gems", price, Vector2(210, 52), Kit.PURPLE.lightened(0.1))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pid := String(c["id"])
	b.pressed.connect(func() -> void:
		if Economy.gems() < price:
			Kit.ask(self, Lang.t("Te faltan gemas"), Lang.t("Cuesta %d gemas y tienes %d.") % [price, Economy.gems()], Lang.t("Conseguir gemas"),
				func() -> void: show_tab("gemas"))
			return
		Kit.ask(self, Lang.t("Monedas"), Lang.t("¿Cambiar %d gemas por %s monedas?") % [price, Money.thousands(coins_n)], Lang.t("Cambiar"), func() -> void:
			var e: String = await Economy.buy_coins(pid)
			if e != "":
				Kit.ask(self, Lang.t("Tienda"), e)
			else:
				Sfx.play("listo")))
	vb.add_child(b)
	return _root(vb)


func close() -> void:
	queue_free()
