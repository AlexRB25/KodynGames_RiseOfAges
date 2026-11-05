class_name RtsCamera
extends Node3D
## Cámara de estrategia: WASD/flechas/bordes para mover, Q/E o botón central
## para girar, rueda para acercar. En el celular: 2 dedos mueven, pellizco acerca.

var cam: Camera3D
var game: Game
var yaw := deg_to_rad(45.0)
var pitch := deg_to_rad(52.0)
var dist := 24.0
var target_dist := 24.0
var edge_scroll := true
var _rotating := false
var _touches := {}
var _pinch_d := 0.0

const MIN_D := 9.0
const MAX_D := 60.0


func setup(g: Game) -> void:
	game = g
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.5
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	_apply()


func focus(p: Vector2) -> void:
	position = Vector3(p.x, 0, p.y)
	_apply()


func ground_pos() -> Vector2:
	return Vector2(position.x, position.z)


func _apply() -> void:
	var off := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * dist
	cam.position = off
	cam.look_at(global_position, Vector3.UP)


func _process(dt: float) -> void:
	var move := Vector2.ZERO
	if not _typing():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1
		if Input.is_key_pressed(KEY_Q):
			yaw += dt * 1.6
		if Input.is_key_pressed(KEY_E):
			yaw -= dt * 1.6
	if edge_scroll and not Hud.is_touch() and DisplayServer.window_is_focused() and _touches.is_empty():
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var s := vp.get_visible_rect().size
		var e := 6.0
		if m.x >= 0 and m.y >= 0 and m.x <= s.x and m.y <= s.y:
			if m.x < e:
				move.x -= 1
			elif m.x > s.x - e:
				move.x += 1
			if m.y < e:
				move.y -= 1
			elif m.y > s.y - e:
				move.y += 1
	if move != Vector2.ZERO:
		var sp := dist * 1.1 * dt
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var d := (right * move.x - fwd * move.y) * sp
		position += Vector3(d.x, 0, d.y)
	dist = lerpf(dist, target_dist, minf(1.0, dt * 10.0))
	if game:
		position.x = clampf(position.x, 0, game.map.w)
		position.z = clampf(position.z, 0, game.map.h)
	_apply()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			target_dist = maxf(MIN_D, target_dist * 0.88)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			target_dist = minf(MAX_D, target_dist * 1.13)
		elif ev.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = ev.pressed
	elif ev is InputEventMouseMotion and _rotating:
		yaw -= ev.relative.x * 0.006
		pitch = clampf(pitch + ev.relative.y * 0.004, deg_to_rad(30), deg_to_rad(80))
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		_pinch_d = 0.0
	elif ev is InputEventScreenDrag and _touches.size() >= 2:
		var old: Vector2 = _touches[ev.index] if _touches.has(ev.index) else ev.position
		_touches[ev.index] = ev.position
		var pts: Array = _touches.values()
		var d: float = (pts[0] as Vector2).distance_to(pts[1])
		if _pinch_d > 0.0:
			target_dist = clampf(target_dist * _pinch_d / maxf(d, 1.0), MIN_D, MAX_D)
		_pinch_d = d
		var rel: Vector2 = (ev.position - old) * 0.5
		var sp := dist * 0.0025
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var mv: Vector2 = (-right * rel.x + fwd * rel.y) * sp
		position += Vector3(mv.x, 0, mv.y)


## Punto del suelo (y = 0) bajo una posición de pantalla.
func screen_to_ground(sp: Vector2) -> Vector2:
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return Vector2(o.x, o.z)
	# Con mesetas: cortar el rayo con el suelo a la altura del punto (unas vueltas bastan).
	var gy := 0.0
	var p := o
	for k in 4:
		p = o + d * ((gy - o.y) / d.y)
		var ny := MapData.ground_y(Vector2(p.x, p.z))
		if absf(ny - gy) < 0.02:
			break
		gy = ny
	return Vector2(p.x, p.z)
