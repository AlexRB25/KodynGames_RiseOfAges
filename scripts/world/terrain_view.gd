class_name TerrainView
extends Node3D
## Dibuja el suelo en bloques (estilo voxel): cada casilla a su altura, paredes de
## roca en los barrancos, orillas que bajan al fondo del agua y encima una capa de
## agua animada (turquesa en la orilla, azul en lo hondo, con espuma).

const GROUND_COLORS := {
	MapData.GRASS: Color(0.56, 0.62, 0.28),
	MapData.DRY: Color(0.72, 0.66, 0.36),
	MapData.DIRT: Color(0.62, 0.47, 0.30),
	MapData.SAND: Color(0.88, 0.80, 0.56),
	MapData.WATER: Color(0.16, 0.38, 0.45),
	MapData.JUNGLE: Color(0.30, 0.46, 0.18),
	MapData.DESERT: Color(0.88, 0.76, 0.50),
	MapData.CLIFF: Color(0.50, 0.47, 0.42),
}

const ROCK := Color(0.44, 0.40, 0.35)

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D ground_tex : filter_linear, source_color, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 map_size;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / map_size;
	vec3 c = texture(ground_tex, uv).rgb;
	if (COLOR.a > 0.5) {
		// Paredes: color propio con vetas de roca horizontales.
		c = COLOR.rgb;
		float band = hash(vec2(floor(wpos.y * 5.0), floor((wpos.x + wpos.z) * 1.5)));
		c *= 0.86 + band * 0.2;
		c *= 0.72 + 0.28 * smoothstep(-0.8, 2.2, wpos.y);   // más oscuro abajo
	} else {
		// Grano fino para que el suelo no se vea plano.
		c += vec3(hash(floor(wpos.xz * 4.0)) * 0.08 - 0.04);
	}
	float f = texture(fog_tex, uv).r;
	float m = f < 0.43 ? f * 1.16 : 0.5 + (f - 0.43) * 0.877;
	ALBEDO = c * m;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 map_size;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / map_size;
	vec2 mk = texture(mask_tex, uv).rg;
	if (mk.r < 0.5) discard;
	float shore = mk.g;
	float t = TIME;
	float w = sin(wpos.x * 1.7 + t * 1.3) * 0.5 + sin(wpos.z * 2.3 - t * 1.1) * 0.5
		+ sin((wpos.x + wpos.z) * 3.7 + t * 2.1) * 0.25;
	vec3 deep = vec3(0.05, 0.30, 0.52);
	vec3 shallow = vec3(0.22, 0.74, 0.76);
	vec3 c = mix(deep, shallow, smoothstep(0.05, 0.95, shore));
	c += vec3(w * 0.035);
	float foam = smoothstep(0.80, 0.97, shore + w * 0.05 + sin(t * 1.6 + wpos.x * 0.8) * 0.03);
	c = mix(c, vec3(0.93, 0.98, 1.0), foam * 0.75);
	float f = texture(fog_tex, uv).r;
	float m = f < 0.43 ? f * 1.16 : 0.5 + (f - 0.43) * 0.877;
	ALBEDO = c * m;
	ALPHA = mix(0.9, 0.62, shore) + (1.0 - min(f * 2.5, 1.0)) * 0.4;
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
}
"""

var map: MapData
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()


func build(m: MapData, fog_tex: Texture2D) -> void:
	map = m
	var img := Image.create(m.w, m.h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in m.h:
		for x in m.w:
			var i := y * m.w + x
			var g: int = m.ground[i]
			var c: Color = GROUND_COLORS[g]
			if g != MapData.WATER:
				c = c.lightened(rng.randf_range(-0.03, 0.03))
				if m.height[i] > 0.1 and g != MapData.CLIFF:
					c = c.lightened(0.05)   # lo alto, un poco más claro
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("ground_tex", tex)
	mat.set_shader_parameter("fog_tex", fog_tex)
	mat.set_shader_parameter("map_size", Vector2(m.w, m.h))
	_build_mesh(rng)
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	_build_water(fog_tex)
	# Fondo negro fuera del mapa.
	var outer := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(m.w * 4, m.h * 4)
	outer.mesh = om
	outer.material_override = Mat.flat(Color.BLACK)
	outer.position = Vector3(m.w * 0.5, MapData.WATER_BED - 0.05, m.h * 0.5)
	add_child(outer)


func _top(i: int) -> float:
	return MapData.WATER_BED if map.ground[i] == MapData.WATER else map.height[i]


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	# a-b-c-d en sentido horario visto desde el lado de la normal.
	_v.append_array([a, b, c, a, c, d])
	for k in 6:
		_n.append(n)
		_c.append(col)


func _build_mesh(rng: RandomNumberGenerator) -> void:
	var w := map.w
	var h := map.h
	var flat := Color(1, 1, 1, 0)   # alfa 0 = usar el color del suelo
	# Tapas: una franja por cada tramo de la fila con la misma altura.
	for y in h:
		var x := 0
		while x < w:
			var ht := _top(y * w + x)
			var x2 := x + 1
			while x2 < w and _top(y * w + x2) == ht:
				x2 += 1
			_quad(Vector3(x, ht, y), Vector3(x2, ht, y), Vector3(x2, ht, y + 1), Vector3(x, ht, y + 1), Vector3.UP, flat)
			x = x2
	# Paredes donde la casilla vecina está más abajo.
	var dirs := [[Vector2i(1, 0), Vector3(1, 0, 0)], [Vector2i(-1, 0), Vector3(-1, 0, 0)],
		[Vector2i(0, 1), Vector3(0, 0, 1)], [Vector2i(0, -1), Vector3(0, 0, -1)]]
	for y in h:
		for x in w:
			var i := y * w + x
			var top := _top(i)
			for dd in dirs:
				var d: Vector2i = dd[0]
				var nt := Vector2i(x, y) + d
				if not map.inside(nt):
					continue
				var low := _top(map.idx(nt))
				if low >= top:
					continue
				var col := ROCK
				var g: int = map.ground[i]
				if g == MapData.CLIFF or top - low > MapData.LEVEL_H * 0.9:
					col = ROCK.lightened(rng.randf_range(-0.06, 0.06))
				elif low <= MapData.WATER_BED + 0.01:
					col = (GROUND_COLORS[MapData.SAND] if g == MapData.SAND else GROUND_COLORS[MapData.DIRT]).darkened(0.18)
				else:
					col = GROUND_COLORS[MapData.DIRT].darkened(0.1)
				col.a = 1.0
				var n3: Vector3 = dd[1]
				# Esquinas de la arista compartida con la vecina.
				var e0: Vector3
				var e1: Vector3
				if d.x == 1:
					e0 = Vector3(x + 1, 0, y + 1)
					e1 = Vector3(x + 1, 0, y)
				elif d.x == -1:
					e0 = Vector3(x, 0, y)
					e1 = Vector3(x, 0, y + 1)
				elif d.y == 1:
					e0 = Vector3(x, 0, y + 1)
					e1 = Vector3(x + 1, 0, y + 1)
				else:
					e0 = Vector3(x + 1, 0, y)
					e1 = Vector3(x, 0, y)
				_quad(Vector3(e0.x, top, e0.z), Vector3(e1.x, top, e1.z), Vector3(e1.x, low, e1.z), Vector3(e0.x, low, e0.z), n3, col)


func _build_water(fog_tex: Texture2D) -> void:
	var w := map.w
	var h := map.h
	# Cercanía a la orilla (0 = hondo, 1 = pegado a tierra), por capas desde la orilla.
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(99)
	var front: Array[Vector2i] = []
	var any_water := false
	for y in h:
		for x in w:
			var t := Vector2i(x, y)
			if not map.is_water(t):
				continue
			any_water = true
			for d in MapData.N8:
				var n: Vector2i = t + d
				if map.inside(n) and not map.is_water(n):
					dist[map.idx(t)] = 1
					front.append(t)
					break
	if not any_water:
		return
	for step in range(2, 6):
		var nxt: Array[Vector2i] = []
		for t in front:
			for d in MapData.N8:
				var n: Vector2i = t + d
				if map.is_water(n) and dist[map.idx(n)] > step:
					dist[map.idx(n)] = step
					nxt.append(n)
		front = nxt
	var img := Image.create(w, h, false, Image.FORMAT_RG8)
	for y in h:
		for x in w:
			var i := y * w + x
			if map.ground[i] == MapData.WATER:
				var close := clampf(1.0 - float(dist[i] - 1) / 4.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1.0, close, 0))
			else:
				img.set_pixel(x, y, Color(0, 1.0, 0))
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("mask_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("fog_tex", fog_tex)
	mat.set_shader_parameter("map_size", Vector2(w, h))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(w * 0.5, MapData.WATER_Y, h * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
