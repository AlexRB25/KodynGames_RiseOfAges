class_name TerrainView
extends Node3D
## Dibuja el suelo con un solo plano y una textura (1 píxel por casilla).

const GROUND_COLORS := {
	MapData.GRASS: Color(0.56, 0.62, 0.28),
	MapData.DRY: Color(0.72, 0.66, 0.36),
	MapData.DIRT: Color(0.62, 0.47, 0.30),
	MapData.SAND: Color(0.84, 0.76, 0.52),
	MapData.WATER: Color(0.18, 0.42, 0.62),
	MapData.JUNGLE: Color(0.30, 0.46, 0.18),
	MapData.DESERT: Color(0.88, 0.76, 0.50),
}

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D ground_tex : filter_linear, source_color, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 map_size;
uniform float time_s = 0.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / map_size;
	vec3 c = texture(ground_tex, uv).rgb;
	// Grano fino para que no se vea plano.
	float n = hash(floor(wpos.xz * 4.0)) * 0.08 - 0.04;
	c += vec3(n);
	float f = texture(fog_tex, uv).r;
	float m = f < 0.43 ? f * 1.16 : 0.5 + (f - 0.43) * 0.877;
	ALBEDO = c * m;
}
"""

var map: MapData


func build(m: MapData, fog_tex: Texture2D) -> void:
	map = m
	var img := Image.create(m.w, m.h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in m.h:
		for x in m.w:
			var g: int = m.ground[y * m.w + x]
			var c: Color = GROUND_COLORS[g]
			if g == MapData.WATER:
				# Agua más oscura lejos de la orilla.
				var deep := 0
				for d in MapData.N8:
					if m.is_water(Vector2i(x, y) + d * 2):
						deep += 1
				c = c.darkened(deep * 0.025)
			else:
				c = c.lightened(rng.randf_range(-0.03, 0.03))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("ground_tex", tex)
	mat.set_shader_parameter("fog_tex", fog_tex)
	mat.set_shader_parameter("map_size", Vector2(m.w, m.h))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(m.w, m.h)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(m.w * 0.5, 0, m.h * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Fondo negro fuera del mapa.
	var outer := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(m.w * 4, m.h * 4)
	outer.mesh = om
	outer.material_override = Mat.flat(Color.BLACK)
	outer.position = Vector3(m.w * 0.5, -0.05, m.h * 0.5)
	add_child(outer)
