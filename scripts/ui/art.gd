class_name Art
## Busca el arte del usuario en res://assets (ver assets/LEEME.md).
## Si falta una imagen, el juego usa lo dibujado por código: nunca truena por arte faltante.

const ROOT := "res://assets/"
const ICONS := {"comida": "alimento", "madera": "madera", "oro": "oro", "piedra": "piedra", "pop": "poblacion"}

static var _cache := {}


static func tex(rel: String) -> Texture2D:
	if _cache.has(rel):
		return _cache[rel]
	var path := ROOT + rel
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[rel] = t
	return t


## Icono de recurso ("comida", "madera", "oro", "piedra", "pop").
static func icon(kind: String) -> Texture2D:
	if not ICONS.has(kind):
		return null
	return tex("ui/iconos/%s.png" % ICONS[kind])


## Insignia de la era 1-5: la de la civilización si existe, si no la común.
static func era(civ: String, age: int) -> Texture2D:
	var t := tex("civs/%s/eras/nivel%d.png" % [civ, age])
	return t if t else tex("eras/nivel%d.png" % age)


## Imagen de una unidad o edificio de una civilización en una era.
## Usa el nivel pedido; si no hay, el más cercano hacia abajo y luego hacia arriba.
static func portrait(civ: String, id: String, age: int) -> Texture2D:
	var group := "edificios" if Defs.BUILDINGS.has(id) else "unidades"
	var order: Array[int] = []
	for l in range(clampi(age, 1, 5), 0, -1):
		order.append(l)
	for l in range(clampi(age, 1, 5) + 1, 6):
		order.append(l)
	for l in order:
		var t := tex("civs/%s/%s/%s/nivel%d.png" % [civ, group, id, l])
		if t:
			return t
	return null


## Modelo 3D (.glb) de una unidad o edificio: assets/modelos/<civ>/<id>/nivelN.glb.
## Usa el nivel pedido; si no hay, el más cercano hacia abajo y luego hacia arriba.
static func model(civ: String, id: String, age: int) -> PackedScene:
	var order: Array[int] = []
	for l in range(clampi(age, 1, 5), 0, -1):
		order.append(l)
	for l in range(clampi(age, 1, 5) + 1, 6):
		order.append(l)
	for l in order:
		var rel := "modelos/%s/%s/nivel%d.glb" % [civ, id, l]
		if _cache.has(rel):
			if _cache[rel]:
				return _cache[rel]
			continue
		var path := ROOT + rel
		var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
		_cache[rel] = ps
		if ps:
			return ps
	return null


## Modelo de una etapa de un recurso: assets/modelos/recursos/<tipo>/etapaN.glb
## (N = 100, 75, 50, 25 o 0). null si no existe.
static func stage_model(kind: String, stage: int) -> PackedScene:
	return stage_model_file(kind, "etapa%d" % stage)


## Otro modelo de un recurso o animal: assets/modelos/recursos/<tipo>/<nombre>.glb
static func stage_model_file(kind: String, file: String) -> PackedScene:
	var rel := "modelos/recursos/%s/%s.glb" % [kind, file]
	if not _cache.has(rel):
		var path := ROOT + rel
		_cache[rel] = load(path) if ResourceLoader.exists(path) else null
	return _cache[rel]


## Instancia un modelo y lo ajusta: base en el suelo, centrado, y lo ancho del
## modelo ocupa "width" unidades (las casillas del edificio). by_x: medir solo
## el ancho de frente (el del dibujo) en vez del lado más largo.
## sink: fracción del alto que queda bajo el suelo (la base de pasto del dibujo).
static func fitted(ps: PackedScene, width: float, by_x := false, sink := 0.0) -> Node3D:
	var inst := ps.instantiate() as Node3D
	var box := _bounds(inst, Transform3D.IDENTITY)
	var holder := Node3D.new()
	holder.add_child(inst)
	if box.size == Vector3.ZERO:
		return holder
	var s := width / (box.size.x if by_x else maxf(box.size.x, box.size.z))
	inst.scale = Vector3.ONE * s
	var c := box.get_center()
	inst.position = Vector3(-c.x * s, -(box.position.y + box.size.y * sink) * s, -c.z * s)
	_fog_materials(inst)
	return holder


## Cambia los materiales del modelo por unos que se oscurecen con la niebla de guerra.
static func _fog_materials(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			var tex: Texture2D = null
			var col := Color.WHITE
			if m is BaseMaterial3D:
				tex = (m as BaseMaterial3D).albedo_texture
				col = (m as BaseMaterial3D).albedo_color
			mi.set_surface_override_material(i, Mat.textured(tex, col))
	for ch in n.get_children():
		_fog_materials(ch)


static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b: AABB = here * (n as MeshInstance3D).mesh.get_aabb()
		out = b
		first = false
	for ch in n.get_children():
		var cb := _bounds(ch, here)
		if cb.size == Vector3.ZERO:
			continue
		out = cb if first else out.merge(cb)
		first = false
	return out
