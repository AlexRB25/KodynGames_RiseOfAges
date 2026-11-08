class_name LevelUp
extends Control
## Animación de subir de nivel, a pantalla completa: rayos de sol que giran, la piedra
## del sol (rango) o de jade (Game Pass) que entra rebotando, el número que cambia del
## nivel anterior al nuevo con un golpe, chispas y sonido. Toca para seguir.
##   LevelUp.play(parent, "rango", 4, 5)   /   LevelUp.play(parent, "pase", 12, 13)

signal closed

var kind := "rango"
var old_n := 1
var new_n := 2
var sub_text := ""
var _t := 0.0
var _alpha := 0.0
var _badge := 0.0        # escala de la insignia
var _flash := 0.0
var _num: Label
var _title: Label
var _sub: Label
var _hint: Label
var _sparks: CPUParticles2D
var _closing := false
var _swapped := false


static func play(parent: Node, k: String, from_n: int, to_n: int, sub := "") -> LevelUp:
	var l := LevelUp.new()
	l.kind = k
	l.old_n = from_n
	l.new_n = to_n
	l.sub_text = sub
	parent.add_child(l)
	return l


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_num = Kit.label(str(old_n), 120, Color.WHITE, 14)
	_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_num)
	_title = Kit.label(Lang.t("¡SUBISTE DE RANGO!") if kind == "rango" else Lang.t("¡NUEVO NIVEL DEL GAME PASS!"), 54, Kit.GOLD, 12)
	_title.modulate.a = 0.0
	add_child(_title)
	_sub = Kit.label(sub_text if sub_text != "" else (Lang.t("Nivel %d") % new_n), 30, Color(0.75, 1.0, 0.75) if kind == "pase" else Kit.CREAM, 8)
	_sub.modulate.a = 0.0
	add_child(_sub)
	_hint = Kit.label(Lang.t("Toca para continuar"), 22, Color(1, 1, 1, 0.8), 6)
	_hint.modulate.a = 0.0
	add_child(_hint)
	_sparks = CPUParticles2D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 90
	_sparks.lifetime = 1.6
	_sparks.explosiveness = 0.95
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 260.0
	_sparks.initial_velocity_max = 620.0
	_sparks.gravity = Vector2(0, 520)
	_sparks.scale_amount_min = 4.0
	_sparks.scale_amount_max = 9.0
	_sparks.damping_min = 40.0
	_sparks.damping_max = 90.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.95, 0.6))
	grad.set_color(1, Color(1, 0.55, 0.1, 0.0))
	if kind == "pase":
		grad.set_color(0, Color(0.7, 1, 0.75))
		grad.set_color(1, Color(0.2, 0.8, 0.5, 0.0))
	_sparks.color_ramp = grad
	add_child(_sparks)
	resized.connect(_layout)
	_layout()
	Sfx.play("subir_nivel")
	var tw := create_tween()
	tw.tween_property(self, "_alpha", 1.0, 0.25)
	tw.tween_property(self, "_badge", 1.25, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_badge", 1.0, 0.18)
	tw.tween_interval(0.2)
	tw.tween_callback(_swap_number)
	tw.tween_property(_title, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(_sub, "modulate:a", 1.0, 0.4)
	tw.tween_interval(0.5)
	tw.tween_property(_hint, "modulate:a", 1.0, 0.4)


func _layout() -> void:
	var c := _center()
	var r := _radius()
	_num.size = Vector2(r * 2, r * 2)
	_num.position = c - _num.size * 0.5
	_num.pivot_offset = _num.size * 0.5
	_title.size = Vector2(size.x, 70)
	_title.position = Vector2(0, c.y + r * 1.35)
	_sub.size = Vector2(size.x, 44)
	_sub.position = Vector2(0, c.y + r * 1.35 + 74)
	_hint.size = Vector2(size.x, 30)
	_hint.position = Vector2(0, size.y - 60)
	_sparks.position = c


func _center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.42)


func _radius() -> float:
	return minf(size.x, size.y) * 0.17


## El número cambia del nivel anterior al nuevo con un golpe, destello y chispas.
func _swap_number() -> void:
	_swapped = true
	_num.text = str(new_n)
	_num.scale = Vector2(1.8, 1.8)
	create_tween().tween_property(_num, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flash = 1.0
	create_tween().tween_property(self, "_flash", 0.0, 0.6)
	_sparks.restart()
	_sparks.emitting = true


func _process(dt: float) -> void:
	_t += dt
	_num.modulate.a = clampf(_badge * 1.5, 0.0, 1.0)
	_num.visible = _badge > 0.05
	_num.position = _center() - _num.size * 0.5
	queue_redraw()


func _draw() -> void:
	var c := _center()
	var r := _radius()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.06, 0.82 * _alpha))
	var gold := Color(1.0, 0.8, 0.3) if kind == "rango" else Color(0.45, 1.0, 0.6)
	# Rayos que giran.
	var rays := 18
	var far := size.length()
	for i in rays:
		var a := _t * 0.35 + TAU * i / rays
		var w := TAU / rays * 0.32
		var pts := PackedVector2Array([c, c + Vector2.from_angle(a - w) * far, c + Vector2.from_angle(a + w) * far])
		draw_colored_polygon(pts, Color(gold, 0.10 * _alpha))
	# Halo.
	for k in 6:
		draw_circle(c, r * (2.2 - k * 0.2), Color(gold, 0.04 * _alpha * (k + 1)))
	if _badge <= 0.01:
		return
	var s := _badge
	var R := r * s
	# Piedra del sol: puntas alrededor.
	var spikes := 16
	var star := PackedVector2Array()
	for i in spikes * 2:
		var a := -PI / 2 + TAU * i / (spikes * 2) + _t * 0.15
		var rr := R * (1.42 if i % 2 == 0 else 1.12)
		star.append(c + Vector2.from_angle(a) * rr)
	draw_colored_polygon(star, gold.darkened(0.15))
	draw_polyline(star + PackedVector2Array([star[0]]), gold.darkened(0.55), maxf(2.0, R * 0.03), true)
	# Anillos.
	draw_circle(c, R * 1.12, gold.darkened(0.55))
	draw_circle(c, R * 1.05, gold)
	draw_circle(c, R * 0.92, gold.darkened(0.35))
	var inner := Color(0.22, 0.10, 0.32) if kind == "rango" else Color(0.06, 0.32, 0.22)
	draw_circle(c, R * 0.86, inner)
	draw_circle(c, R * 0.86, inner.lightened(0.18), false, maxf(2.0, R * 0.04), true)
	# Marcas como glifos en el anillo.
	for i in 12:
		var a := TAU * i / 12.0 - _t * 0.1
		draw_circle(c + Vector2.from_angle(a) * R * 0.985, R * 0.035, gold.darkened(0.5))
	# Brillo diagonal.
	draw_circle(c + Vector2(-R * 0.3, -R * 0.35), R * 0.28, Color(1, 1, 1, 0.06))
	if _flash > 0.0:
		draw_circle(c, R * (1.0 + (1.0 - _flash) * 1.4), Color(1, 1, 1, 0.5 * _flash))


func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed)
	if tap:
		accept_event()
		if _t > 1.0 and not _closing:
			close()


func close() -> void:
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())
