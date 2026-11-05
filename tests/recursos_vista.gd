extends Node3D
## Vista de prueba: todas las etapas de los recursos en fila (arte 3D de Meshy).
## godot --path . tests/recursos_vista.tscn -- --shot=C:/ruta/vista.png

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(3.2, 7.5, 9.5)
	cam.look_at(Vector3(3.2, 0, 2.6))
	if "--cabra" in OS.get_cmdline_user_args():
		cam.position = Vector3(8.2, 1.6, 1.6)
		cam.look_at(Vector3(8.2, 0.2, 0))
	cam.fov = 45
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.5, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	Mat.box(self, Vector3(14, 0.02, 10), Vector3(3, -0.01, 3), Color(0.42, 0.55, 0.28))
	var rows := [["arbol", [100, 75, 50, 25, 0]], ["pino", [100, 75, 50, 25, 0]],
		["arbusto", [100, 75, 50, 25]], ["oro", [100, 75, 50, 25]], ["piedra", [100, 75, 50, 25]]]
	for r in rows.size():
		for i in rows[r][1].size():
			var n := ResourceNode.stage_node(rows[r][0], rows[r][1][i], 0.0)
			if n:
				n.position = Vector3(i * 1.6, 0, r * 1.25)
				add_child(n)
	# cabra: viva y sus etapas de muerta
	var live := Art.stage_model_file("cabra", "viva")
	if live:
		var n := Art.fitted(live, Animal.ART_W["cabra"])
		n.rotation.y = Animal.ART_YAW["cabra"]
		n.position = Vector3(8.0, 0, 0)
		add_child(n)
		Mat.box(self, Vector3(0.12, 0.12, 0.12), Vector3(8.6, 0.06, 0), Color.RED)   # hacia +X (avanza)
	for i in 3:
		var ps := Art.stage_model("cabra", [75, 50, 25][i])
		if ps:
			var n := Art.fitted(ps, Animal.ART_W["cabra"] * 1.25, false, Animal.DEAD_SINK[[75, 50, 25][i]])
			n.position = Vector3(8.0, 0, 1.25 + i * 1.25)
			add_child(n)
	for k in 6:
		await get_tree().process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			get_viewport().get_texture().get_image().save_png(a.get_slice("=", 1))
	get_tree().quit()
