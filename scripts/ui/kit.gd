class_name Kit
## Piezas de interfaz compartidas por el menú, el Game Pass, la Tienda y el perfil:
## botones rojo/dorado, chips de monedas y gemas, estandartes, tarjeta de perfil y
## casillas de premios.

const RED := Color(0.55, 0.13, 0.10)
const GOLD := Color(0.96, 0.76, 0.30)
const CREAM := Color(0.98, 0.93, 0.80)
const GREEN := Color(0.16, 0.42, 0.22)
const GREY := Color(0.25, 0.22, 0.20)
const PURPLE := Color(0.36, 0.16, 0.50)
const PANEL := Color(0.16, 0.11, 0.07, 0.97)

static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/ui/fuentes/LilitaOne-Regular.ttf")
	return _font


static func box(bg: Color, border: Color, radius := 14, bw := 3, shadow := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 4)
	s.set_content_margin_all(10)
	return s


static func button(text: String, size: Vector2, font_size := 26, color := RED) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(CREAM, 0.55))
	b.add_theme_color_override("font_outline_color", Color(0.18, 0.06, 0.03))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("normal", box(color, GOLD))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.15), GOLD.lightened(0.2)))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.2), GOLD))
	b.add_theme_stylebox_override("disabled", box(color.darkened(0.4), GOLD.darkened(0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func label(text: String, size: int, color := CREAM, outline := 7) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.03))
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Texto normal (sin la fuente de títulos), para explicaciones.
static func text(t: String, size := 18, color := CREAM) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func icon(kind: String, px := 32) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.tex(Economy.ICONS.get(kind, ""))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Icono + cantidad (monedas o gemas) con fondo oscuro.
static func wallet_chip(kind: String, amount: int, font_size := 24) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(0.10, 0.07, 0.04, 0.88), GOLD if kind == "coins" else Color(0.45, 0.75, 1.0), 12, 2)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 14
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	hb.add_child(icon(kind, font_size + 16))
	var l := label(Money.thousands(amount), font_size)
	l.name = "Amount"
	hb.add_child(l)
	return p


## Precio en un botón: icono + número.
static func price_button(kind: String, amount: int, size := Vector2(170, 52), color := GREEN) -> Button:
	var b := button("", size, 24, color)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	hb.add_child(icon(kind, 32))
	hb.add_child(label(Money.thousands(amount), 24))
	return b


static func rarity_color(r: String) -> Color:
	return Economy.RARITY_COLORS.get(r, Economy.RARITY_COLORS["comun"])


static func rarity_name(r: String) -> String:
	return {"comun": Lang.t("Común"), "raro": Lang.t("Raro"), "epico": Lang.t("Épico"),
		"legendario": Lang.t("Legendario")}.get(r, "")


## Cómo se ve un artículo: imagen de perfil, estandarte, título, civilización o vestimenta.
static func item_view(id: String, px := 96) -> Control:
	var it := Economy.item(id)
	var kind := String(it.get("kind", ""))
	var detail: Dictionary = it.get("detail", {}) if it.get("detail") is Dictionary else {}
	match kind:
		"imagen":
			var t := TextureRect.new()
			t.texture = Art.tex(String(detail.get("file", "")))
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.custom_minimum_size = Vector2(px, px)
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return t
		"estandarte":
			var b := BannerView.new()
			b.set_colors(detail)
			b.custom_minimum_size = Vector2(px * 0.72, px)
			return b
		"titulo":
			var c := CenterContainer.new()
			c.custom_minimum_size = Vector2(px * 1.4, px)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var p := PanelContainer.new()
			var sb := box(Color(0.32, 0.18, 0.08), rarity_color(String(it.get("rarity", ""))), 20, 3, false)
			sb.content_margin_left = 14
			sb.content_margin_right = 14
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
			p.add_theme_stylebox_override("panel", sb)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var l := label(Lang.t(String(it.get("name", ""))), maxi(16, px / 5))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(px * 1.1, 0)
			p.add_child(l)
			c.add_child(p)
			return c
	# Civilización, vestimenta u otro: el nombre en un círculo.
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(px, px)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l2 := label(Lang.t(String(it.get("name", id))), maxi(14, px / 6))
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.custom_minimum_size = Vector2(px, 0)
	cc.add_child(l2)
	return cc


## Un premio del pase: monedas, gemas o un artículo.
static func reward_view(r: Dictionary, px := 76) -> Control:
	match String(r.get("kind", "")):
		"coins", "gems":
			var vb := VBoxContainer.new()
			vb.alignment = BoxContainer.ALIGNMENT_CENTER
			vb.add_theme_constant_override("separation", 0)
			vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(icon(String(r["kind"]), int(px * 0.62)))
			vb.add_child(label(Money.thousands(int(r.get("amount", 0))), 22))
			return vb
	return item_view(String(r.get("item", "")), px)


static func reward_name(r: Dictionary) -> String:
	match String(r.get("kind", "")):
		"coins":
			return Lang.t("%s monedas") % Money.thousands(int(r.get("amount", 0)))
		"gems":
			return Lang.t("%s gemas") % Money.thousands(int(r.get("amount", 0)))
	var it := Economy.item(String(r.get("item", "")))
	return "%s: %s" % [kind_name(String(it.get("kind", ""))), Lang.t(String(it.get("name", "")))]


static func kind_name(k: String) -> String:
	return {"imagen": Lang.t("Imagen de perfil"), "estandarte": Lang.t("Estandarte"), "titulo": Lang.t("Título"),
		"civ": Lang.t("Civilización"), "skin": Lang.t("Vestimenta")}.get(k, k)


## Tarjeta del jugador: imagen, nombre, título y nivel, con el estandarte de fondo.
static func profile_card(player: String, title_id: String, sub: String, image_id: String, banner_id: String,
		scale := 1.0) -> PanelContainer:
	var detail: Dictionary = Economy.item(banner_id).get("detail", {}) if Economy.item(banner_id).get("detail") is Dictionary else {}
	var bg := Color.html(String(detail.get("bg", "#4a2f1c")))
	var edge := Color.html(String(detail.get("edge", "#c9a36a")))
	var p := PanelContainer.new()
	var sb := box(Color(bg, 0.95), edge, int(14 * scale), maxi(2, int(3 * scale)))
	sb.content_margin_left = 8 * scale
	sb.content_margin_right = 16 * scale
	sb.content_margin_top = 6 * scale
	sb.content_margin_bottom = 6 * scale
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", int(10 * scale))
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	# Imagen en un marco del color del estandarte.
	var frame := PanelContainer.new()
	var fs := box(bg.darkened(0.35), edge, int(10 * scale), maxi(2, int(3 * scale)), false)
	fs.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(frame)
	var img := Economy.item(image_id)
	var tex := TextureRect.new()
	tex.texture = Art.tex(String(img.get("detail", {}).get("file", "civs/maya/unidades/aldeano/nivel1.png")))
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(64, 64) * scale
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tex)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var n := label(player, int(24 * scale))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(n)
	if title_id != "":
		var t := label(Lang.t(String(Economy.item(title_id).get("name", ""))), int(16 * scale),
			Color.html(String(detail.get("mark", "#f5c24c"))), 5)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.add_child(t)
	if sub != "":
		var s := RichTextLabel.new()
		s.bbcode_enabled = true
		s.fit_content = true
		s.autowrap_mode = TextServer.AUTOWRAP_OFF
		s.scroll_active = false
		s.add_theme_font_override("normal_font", font())
		s.add_theme_font_size_override("normal_font_size", int(16 * scale))
		s.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
		s.add_theme_constant_override("outline_size", 5)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.text = sub
		vb.add_child(s)
	return p


## Fondo oscuro de pantalla completa que tapa el menú (las páginas van encima).
static func backdrop(parent: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.045, 0.025, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	return bg


## Ventanita de confirmación o aviso sobre una página. on_yes vacío = solo aviso.
static func ask(parent: Control, title: String, body: String, yes_text := "", on_yes := Callable()) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, GOLD, 16, 3))
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(520, 0)
	vb.add_theme_constant_override("separation", 14)
	p.add_child(vb)
	vb.add_child(label(title, 34, GOLD))
	var t := text(body, 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	if on_yes.is_valid():
		var y := button(yes_text, Vector2(220, 56), 24, GREEN)
		y.pressed.connect(func() -> void:
			dim.queue_free()
			on_yes.call())
		row.add_child(y)
	var n := button(Lang.t("Cancelar") if on_yes.is_valid() else Lang.t("Cerrar"), Vector2(180, 56), 24, GREY)
	n.pressed.connect(dim.queue_free)
	row.add_child(n)
	return dim

## Barra de arriba de las páginas: Volver, título y monedero.
static func header(page: Control, title: String, on_back: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var back := Kit.button("◀ " + Lang.t("Volver"), Vector2(170, 58), 24, Kit.GREY)
	back.pressed.connect(on_back)
	row.add_child(back)
	var t := Kit.label(title, 44, Kit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	row.add_child(Kit.wallet_chip("coins", Economy.coins()))
	var gems := Kit.wallet_chip("gems", Economy.gems())
	row.add_child(gems)
	var plus := Kit.button("+", Vector2(52, 52), 30, Kit.GREEN)
	plus.tooltip_text = Lang.t("Conseguir gemas")
	plus.pressed.connect(func() -> void:
		if page.has_method("show_tab"):
			page.show_tab("gemas")
			return
		var h = page.get("home")
		if page.has_method("close"):
			page.close()
		if h and h.has_method("open_store"):
			h.open_store("gemas"))
	row.add_child(plus)
	return row


## Estandarte dibujado: banderín con borde y un sol en medio.
class BannerView extends Control:
	var bg := Color("#4a2f1c")
	var edge := Color("#c9a36a")
	var mark := Color("#c9a36a")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_colors(d: Dictionary) -> void:
		bg = Color.html(String(d.get("bg", "#4a2f1c")))
		edge = Color.html(String(d.get("edge", "#c9a36a")))
		mark = Color.html(String(d.get("mark", "#c9a36a")))
		queue_redraw()

	func _draw() -> void:
		var w := minf(size.x, size.y * 0.72)
		var h := w / 0.72
		var o := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)
		var pts := PackedVector2Array([o, o + Vector2(w, 0), o + Vector2(w, h), o + Vector2(w * 0.5, h * 0.8), o + Vector2(0, h)])
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(0, 4))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
		draw_colored_polygon(pts, bg)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, edge, maxf(2.0, w * 0.06), true)
		# barra de arriba (el palo)
		draw_rect(Rect2(o + Vector2(-w * 0.08, -w * 0.06), Vector2(w * 1.16, w * 0.1)), edge.darkened(0.2))
		# sol de cuatro puntas
		var c := o + Vector2(w * 0.5, h * 0.4)
		var r := w * 0.3
		var star := PackedVector2Array()
		for i in 16:
			var a := i * PI / 8.0 - PI / 2.0
			var rr := r if i % 2 == 0 else r * 0.42
			if i % 4 == 2:
				rr = r * 0.62
			star.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(star, mark)
		draw_circle(c, r * 0.24, bg)
		draw_circle(c, r * 0.14, mark)
