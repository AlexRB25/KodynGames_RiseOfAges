class_name Relic
extends Entity
## Reliquia: la crea un santo en el monasterio y aparece en un lugar al azar del mapa.
## Cualquier santo la puede recoger y llevar a la maravilla de su pueblo.
## Si el santo muere, la reliquia cae donde estaba.

var carrier: Unit = null      # santo que la lleva
var wonder: Building = null   # maravilla donde está guardada
var visual: Node3D
var _t := 0.0


func is_mobile() -> bool:
	return true


func display_name() -> String:
	return Lang.t("Reliquia")


func init(g: Game, p: Vector2) -> void:
	game = g
	kind = "reliquia"
	owner_id = -1
	pos = p
	radius = 0.3
	sight = 0
	max_hp = 0.0
	hp = 1.0
	position = Vector3(p.x, MapData.ground_y(p), p.y)
	visual = Node3D.new()
	add_child(visual)
	var gold := Color(0.95, 0.78, 0.25)
	Mat.box(visual, Vector3(0.36, 0.08, 0.26), Vector3(0, 0.04, 0), Color(0.45, 0.3, 0.16))
	Mat.box(visual, Vector3(0.3, 0.26, 0.2), Vector3(0, 0.21, 0), gold)
	Mat.box(visual, Vector3(0.34, 0.06, 0.24), Vector3(0, 0.37, 0), gold.lightened(0.2))
	Mat.box(visual, Vector3(0.06, 0.1, 0.06), Vector3(0, 0.45, 0), Look.JADE)


func on_ground() -> bool:
	return carrier == null and wonder == null


## Sigue al santo que la lleva (o queda guardada en la maravilla).
func sim(_dt: float) -> void:
	if carrier and (not Entity.valid(carrier) or carrier.dead):
		drop_at(carrier.pos if is_instance_valid(carrier) else pos)
	if carrier:
		pos = carrier.pos


func drop_at(p: Vector2) -> void:
	if carrier and is_instance_valid(carrier) and carrier.relic == self:
		carrier.relic = null
	carrier = null
	wonder = null
	pos = MapData.center(game.map.nearest_free(MapData.to_tile(p)))
	visible = true


func render(dt: float) -> void:
	_t += dt
	if wonder:
		visible = false
		return
	var y := MapData.ground_y(pos)
	if carrier:
		y += 1.25
		visible = carrier.visible
	visual.rotation.y = _t * 1.5
	position = Vector3(pos.x, y + 0.08 * sin(_t * 3.0), pos.y)
