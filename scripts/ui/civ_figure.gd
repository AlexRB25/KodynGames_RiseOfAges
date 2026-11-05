class_name CivFigure
extends SubViewportContainer
## Aldeano nivel 5 de una civilización, en 3D, girando sobre un pedestal.
## face = true: solo la carita (para cuadros chicos).

var civ := ""
var color := Color.WHITE
var face := false
var spin := 0.6
var _stage: Node3D
var _fig: Node3D
var _cam: Camera3D


func _init(c := "", col := Color(0.2, 0.45, 0.9), only_face := false) -> void:
	civ = c
	color = col
	face = only_face
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	_stage = Node3D.new()
	vp.add_child(_stage)
	_cam = Camera3D.new()
	_cam.fov = 28
	if face:
		_cam.look_at_from_position(Vector3(2.5, 1.2, 0.65), Vector3(0, 0.95, 0), Vector3.UP)
	else:
		_cam.look_at_from_position(Vector3(4.6, 1.7, 1.2), Vector3(0, 0.72, 0), Vector3.UP)
	_stage.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	sun.light_energy = 1.15
	_stage.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.76, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	_stage.add_child(env)
	if not face:
		# Pedestal de piedra escalonado.
		Mat.box(_stage, Vector3(1.25, 0.16, 1.25), Vector3(0, -0.08, 0), Color(0.55, 0.52, 0.46))
		Mat.box(_stage, Vector3(1.0, 0.12, 1.0), Vector3(0, 0.04, 0), Color(0.66, 0.62, 0.54))
		Mat.box(_stage, Vector3(1.02, 0.025, 1.02), Vector3(0, 0.105, 0), Color(0.72, 0.55, 0.25))
	set_civ(civ, color)


func set_civ(c: String, col: Color = color) -> void:
	civ = c
	color = col
	if _stage == null:
		return
	if _fig:
		_fig.queue_free()
	_fig = Node3D.new()
	_fig.position = Vector3(0, 0.12, 0)
	if face:
		_fig.rotation.y = 0.35
	_stage.add_child(_fig)
	var d: Dictionary = Defs.CIVS.get(civ, {})
	var sk: Array = d.get("look", {}).get("skin", [0.62, 0.42, 0.28])
	var body := Node3D.new()
	body.scale = Vector3.ONE * 1.25
	_fig.add_child(body)
	Look.person(body, "aldeano", 5, color, 0.0, Color(sk[0], sk[1], sk[2]))


func _process(dt: float) -> void:
	if _fig and not face:
		_fig.rotation.y += dt * spin
