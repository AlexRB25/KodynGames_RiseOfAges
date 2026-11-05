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
