## Botón redondo junto al minimapa: carita de aldeano con "zzz".
## A color (y latiendo) cuando hay aldeanos sin hacer nada; gris si todos trabajan.
## Cada clic lleva al siguiente aldeano sin tarea; después del último vuelve al primero.
extends BaseButton

var game: Game
var count := 0
var _icon: Texture2D
var _t := 0.0


func setup(g: Game) -> void:
	game = g
	custom_minimum_size = Vector2(36, 36)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = Lang.t("Aldeanos sin tarea (tecla .)")
	pressed.connect(func() -> void: game.controller.select_next_idle())


func _process(dt: float) -> void:
	if game == null:
		return
	_t += dt
	count = game.controller.idle_villagers().size()
	_icon = Thumbs.get_icon(game, "aldeano")
	queue_redraw()


func _draw() -> void:
	var on := count > 0
	var c := size * 0.5
	var beat := 0.5 + 0.5 * sin(_t * 5.0) if on else 0.0
	var r := minf(size.x, size.y) * 0.5 - 3.0
	# Halo que late para llamar la atención.
	if on:
		draw_circle(c, r + 1.0 + 2.5 * beat, Color(1.0, 0.8, 0.25, 0.4 * (1.0 - beat)))
	var fill := Color(0.95, 0.62, 0.15) if on else Color(0.35, 0.35, 0.35)
	if is_hovered():
		fill = fill.lightened(0.15)
	draw_circle(c, r, fill)
	# Carita del aldeano recortada en círculo (el retrato trae fondo cuadrado).
	if _icon:
		var mod := Color.WHITE if on else Color(0.5, 0.5, 0.5)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var ri := r - 2.0
		for k in 32:
			var a := TAU * k / 32.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * ri)
			uvs.append(Vector2(0.5, 0.36) + d * 0.27)   # centrado en la cara
		var cols := PackedColorArray()
		cols.resize(32)
		cols.fill(mod)
		draw_polygon(pts, cols, uvs, _icon)
	draw_arc(c, r, 0.0, TAU, 40, Color(1, 0.85, 0.3) if on else Color(0.55, 0.55, 0.55), 2.0, true)
	# zzz de dormido, subiendo poco a poco.
	var font := get_theme_default_font()
	var zc := Color(1, 1, 1) if on else Color(0.7, 0.7, 0.7)
	for i in 3:
		var k := fmod(_t * 0.6 + i / 3.0, 1.0) if on else (i / 3.0)
		var p := c + Vector2(r * 0.45 + i * 4.0, -r * 0.35 - i * 6.0 - k * 3.0)
		var al := (1.0 - k * 0.6) if on else 0.8
		var fs := 9 + i * 2
		draw_string_outline(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, al))
		draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(zc, al))
