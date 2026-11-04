class_name Entity
extends Node3D
## Base de todo lo que hay en el mapa: unidades, animales, edificios y recursos.

var game: Game
var id := 0
var kind := ""
var owner_id := -1          # -1 = naturaleza
var hp := 1.0
var max_hp := 1.0
var dead := false
var removed := false
var sight := 0
var pos := Vector2.ZERO      # posición en el mapa (x, z)
var radius := 0.3
var rect := Rect2i()         # para estáticos: casillas que ocupa
var selected := false
var seen_once := false       # el jugador local ya lo vio (edificios enemigos)

var _ring: MeshInstance3D
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_t := 0.0


func is_unit() -> bool:
	return false


func is_building() -> bool:
	return false


func is_mobile() -> bool:
	return false


func is_static() -> bool:
	return false


## Tiene recurso que se pueda recolectar ahora mismo.
func has_resource() -> bool:
	return false


func res_type() -> String:
	return ""


func res_group() -> String:
	return ""


func take_resource(_amount: float) -> float:
	return 0.0


func remaining() -> float:
	return 0.0


func display_name() -> String:
	return kind


func team() -> int:
	return game.team_of(owner_id)


## Existe y no fue retirada del mapa (un animal cazado sigue siendo válido).
static func valid(e) -> bool:
	return e != null and is_instance_valid(e) and not e.removed


## Existe y está viva.
static func live(e) -> bool:
	return valid(e) and not e.dead


func center() -> Vector2:
	if is_static():
		return Vector2(rect.position) + Vector2(rect.size) * 0.5
	return pos


## Distancia desde un punto hasta el borde de esta entidad.
func dist_to(p: Vector2) -> float:
	if is_static():
		return MapData.dist_to_rect(p, rect)
	return maxf(0.0, p.distance_to(pos) - radius)


func take_damage(_amount: float, _from: Entity) -> void:
	pass


func sim(_dt: float) -> void:
	pass


func set_selected(on: bool) -> void:
	selected = on
	if on and _ring == null:
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		var r := radius + 0.15
		if is_static():
			r = maxf(rect.size.x, rect.size.y) * 0.62
		tm.inner_radius = r
		tm.outer_radius = r + 0.08
		tm.rings = 24
		tm.ring_segments = 4
		_ring.mesh = tm
		_ring.position = Vector3(0, 0.03, 0)
		_ring.material_override = Mat.flat(_ring_color())
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	if _ring:
		_ring.visible = on
	_update_bar_visibility()


func _ring_color() -> Color:
	if owner_id < 0:
		return Color(0.95, 0.95, 0.9)
	if game and owner_id == game.local_id:
		return Color(0.4, 1.0, 0.4)
	if game and game.team_of(owner_id) == game.team_of(game.local_id):
		return Color(0.4, 0.8, 1.0)
	return Color(1.0, 0.35, 0.3)


func bar_height() -> float:
	return 1.4


## Barra de vida sobre la entidad (se ve al seleccionar o al recibir daño).
func refresh_bar() -> void:
	if max_hp <= 0:
		return
	if _bar == null:
		_bar = Node3D.new()
		var bg := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 0.12)
		bg.mesh = q
		bg.material_override = Mat.flat(Color(0.1, 0.1, 0.1), true)
		_bar.add_child(bg)
		_bar_fill = MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(0.86, 0.08)
		_bar_fill.mesh = q2
		_bar_fill.material_override = Mat.flat(Color(0.3, 0.95, 0.3), true)
		_bar.add_child(_bar_fill)
		_bar.position = Vector3(0, bar_height(), 0)
		add_child(_bar)
	var f := clampf(hp / max_hp, 0.0, 1.0)
	_bar_fill.scale = Vector3(maxf(f, 0.01), 1, 1)
	# QuadMesh centrado: se recorre en pantalla, así que basta con escalar.
	var col := Color(0.3, 0.95, 0.3) if f > 0.5 else (Color(0.95, 0.8, 0.2) if f > 0.25 else Color(0.95, 0.25, 0.2))
	_bar_fill.material_override = Mat.flat(col, true)
	_update_bar_visibility()


func flash_bar() -> void:
	_bar_t = 3.0
	refresh_bar()


func _update_bar_visibility() -> void:
	if _bar:
		_bar.visible = (selected or _bar_t > 0.0) and not dead


func tick_bar(dt: float) -> void:
	if _bar_t > 0.0:
		_bar_t -= dt
		if _bar_t <= 0.0:
			_update_bar_visibility()
