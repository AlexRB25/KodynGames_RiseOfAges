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
	custom_minimum_size = Vector2(50, 50)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = Lang.t("Aldeanos sin tarea (tecla .)")
	pressed.connect(func() -> void: game.controller.select_next_idle())


func _process(dt: float) -> void:
	if game == null:
		return
	_t += dt
	var n := game.controller.idle_villagers().size()
	if n != count:
		count = n
	_icon = Thumbs.get_icon(game, "aldeano")
	queue_redraw()


func _draw() -> void:
	var on := count > 0
	var c := size * 0.5
	var beat := 0.5 + 0.5 * sin(_t * 5.0) if on else 0.0
	var r := minf(size.x, size.y) * 0.5 - 4.0
	var k0 := r / 30.0    # escala de lo de adentro
	# Halo que late para llamar la atención.
	if on:
		draw_circle(c, r + 1.0 + 3.0 * beat, Color(1.0, 0.8, 0.25, 0.35 * (1.0 - beat)))
	var fill := Color(0.95, 0.62, 0.15) if on else Color(0.35, 0.35, 0.35)
	if is_hovered():
		fill = fill.lightened(0.15)
	if button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		fill = fill.darkened(0.15)
	draw_circle(c, r, Color(0, 0, 0, 0.55))
	draw_circle(c, r - 3.0, fill)
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 0.93, 0.7) if on else Color(0.6, 0.6, 0.6), 2.5, true)
	# Carita del aldeano.
	if _icon:
		var s := r * 2.3
		var rect := Rect2(c - Vector2(s, s) * 0.5 + Vector2(0, 2), Vector2(s, s))
		var mod := Color.WHITE if on else Color(0.55, 0.55, 0.55, 0.85)
		draw_texture_rect(_icon, rect, false, mod)
	# zzz de dormido, subiendo poco a poco.
	var font := get_theme_default_font()
	var zc := Color(1, 1, 1) if on else Color(0.75, 0.75, 0.75)
	for i in 3:
		var k := fmod(_t * 0.6 + i / 3.0, 1.0) if on else (i / 3.0)
		var p := c + Vector2(r * 0.35 + i * 6.0 * k0, -r * 0.25 - (i * 9.0 + k * 4.0) * k0)
		var a := (1.0 - k * 0.6) if on else 0.8
		draw_string_outline(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int((12 + i * 3) * k0), 3, Color(0, 0, 0, a))
		draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int((12 + i * 3) * k0), Color(zc, a))
	# Cuántos hay.
	if on:
		var bp := c + Vector2(-r * 0.72, r * 0.62)
		draw_circle(bp, 9.0, Color(0.8, 0.12, 0.1))
		draw_arc(bp, 9.0, 0.0, TAU, 24, Color.WHITE, 1.5, true)
		var txt := str(count)
		var fs := 12 if count < 10 else 10
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, bp + Vector2(-w * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
