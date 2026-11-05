extends Node3D
## Dibuja al aldeano caído (para la pantalla de error de la web) y lo guarda en
## server/public/img/caido.png. Uso: godot --path . res://tools/render_caido.tscn

func _ready() -> void:
	var white := Image.create(4, 4, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	Mat.setup(ImageTexture.create_from_image(white), Vector2(1000, 1000))
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 400)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	# Aldeano nivel 1 tirado de espaldas, con su herramienta a un lado.
	var body := Node3D.new()
	body.rotation = Vector3(0, 0, PI * 0.5)
	body.position = Vector3(0.35, 0.17, 0)
	root.add_child(body)
	var parts := Look.person(body, "aldeano", 1, Defs.PLAYER_COLORS[0], 0.0, Color(0.6, 0.4, 0.26))
	(parts["arm"] as Node3D).rotation.z = -1.4
	# ojos en X
	for ez in [-0.065, 0.065]:
		Mat.box(body, Vector3(0.022, 0.09, 0.02), Vector3(0.162, 0.63, ez), Color(0.08, 0.06, 0.05), Vector3(0.8, 0, 0))
		Mat.box(body, Vector3(0.022, 0.09, 0.02), Vector3(0.162, 0.63, ez), Color(0.08, 0.06, 0.05), Vector3(-0.8, 0, 0))
	var tool := Node3D.new()
	tool.position = Vector3(-0.2, 0.03, 0.42)
	tool.rotation = Vector3(PI * 0.5, 0.6, 0)
	root.add_child(tool)
	Mat.box(tool, Vector3(0.05, 0.6, 0.05), Vector3.ZERO, Color(0.45, 0.32, 0.2))
	Mat.box(tool, Vector3(0.16, 0.08, 0.07), Vector3(0, 0.3, 0), Color(0.4, 0.4, 0.44))
	# piso de pasto y unas estrellitas de mareo
	Mat.box(root, Vector3(2.4, 0.06, 1.4), Vector3(0, -0.03, 0), Color(0.48, 0.62, 0.26))
	for i in 3:
		var a := TAU * i / 3.0
		Mat.box(root, Vector3(0.07, 0.07, 0.07), Vector3(-0.42 + cos(a) * 0.18, 0.62, sin(a) * 0.18), Color(1.0, 0.85, 0.25), Vector3(0.6, a, 0.6))
	var cam := Camera3D.new()
	cam.fov = 26
	cam.look_at_from_position(Vector3(1.2, 2.1, 3.0), Vector3(-0.05, 0.12, 0), Vector3.UP)
	root.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.15
	root.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.76, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	root.add_child(env)
	for k in 6:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("res://server/public/img/caido.png")
	print("listo caido.png")
	get_tree().quit()
