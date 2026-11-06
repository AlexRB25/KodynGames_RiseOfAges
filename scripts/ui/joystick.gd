class_name Joystick
extends Control
## Palanca para mover la cámara con un dedo (celular). Mientras se empuja, la cámara
## avanza hacia ese lado; al soltar, se detiene. Más fácil que mover con dos dedos.

var game: Game
var _held := false
var vec := Vector2.ZERO

const R := 46.0        # radio de recorrido de la perilla


func setup(g: Game) -> void:
	game = g
	custom_minimum_size = Vector2(120, 120)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = Lang.t("Palanca: empuja para mover la vista del mapa")


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_held = ev.pressed
		if _held:
			_aim(ev.position)
		else:
			vec = Vector2.ZERO
		accept_event()
	elif ev is InputEventMouseMotion and _held:
		_aim(ev.position)
		accept_event()


func _aim(p: Vector2) -> void:
	var d := (p - size * 0.5) / R
	vec = d.normalized() if d.length() > 1.0 else d
	if vec.length() < 0.15:
		vec = Vector2.ZERO   # zona muerta en el centro


func _process(_dt: float) -> void:
	if game and game.camera:
		game.camera.joy = vec
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, R + 14.0, Color(0, 0, 0, 0.35))
	draw_arc(c, R + 14.0, 0.0, TAU, 40, Color(0.72, 0.56, 0.28, 0.9), 2.0, true)
	# flechas en los cuatro lados
	for a in 4:
		var dir := Vector2.from_angle(a * PI * 0.5)
		var tip := c + dir * (R + 8.0)
		var side := dir.orthogonal() * 6.0
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 9.0 + side, tip - dir * 9.0 - side]), Color(0.96, 0.91, 0.78, 0.7))
	var k := c + vec * R
	draw_circle(k, 22.0, Color(0.95, 0.78, 0.3, 0.95 if _held else 0.75))
	draw_arc(k, 22.0, 0.0, TAU, 32, Color(0.35, 0.25, 0.1), 2.0, true)
