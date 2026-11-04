class_name Mat
extends RefCounted
## Materiales compartidos. Todos leen la textura de niebla de guerra
## (negro = sin explorar, oscuro = explorado, normal = a la vista).

static var fog_tex: Texture2D
static var map_size := Vector2(160, 160)
static var _cache: Dictionary = {}
static var _shader: Shader
static var _flat_cache: Dictionary = {}

const SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(160.0);
uniform float fog_on = 1.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float f = texture(fog_tex, wpos.xz / map_size).r;
	float m = f < 0.43 ? f * 1.16 : 0.5 + (f - 0.43) * 0.877;
	m = mix(1.0, m, fog_on);
	ALBEDO = albedo.rgb * m;
}
"""


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


static func setup(tex: Texture2D, size: Vector2) -> void:
	fog_tex = tex
	map_size = size
	_cache.clear()
	_flat_cache.clear()


## Material con niebla para un color.
static func of(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("fog_tex", fog_tex)
	m.set_shader_parameter("map_size", map_size)
	_cache[key] = m
	return m


## Material sin luz ni niebla (anillos de selección, barras de vida, fantasmas).
static func flat(c: Color, billboard := false) -> StandardMaterial3D:
	var key := c.to_html() + str(billboard)
	if _flat_cache.has(key):
		return _flat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 10
	_flat_cache[key] = m
	return m


# ---------- ayudas para armar modelos con figuras simples ----------

static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = of(c)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, sides := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	mi.mesh = m
	mi.material_override = of(c)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func ball(parent: Node3D, r: float, pos: Vector3, c: Color, seg := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(3, seg / 2)
	mi.mesh = m
	mi.material_override = of(c)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Techo de dos aguas (prisma) a lo largo de X.
static func roof(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = Vector3(size.z, size.y, size.x)
	mi.mesh = m
	mi.material_override = of(c)
	mi.position = pos
	mi.rotation = Vector3(0, PI / 2, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
