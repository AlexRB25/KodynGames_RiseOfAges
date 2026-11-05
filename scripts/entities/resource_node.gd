class_name ResourceNode
extends Entity
## Recurso fijo en una casilla: árbol, mina de oro/piedra, arbusto de bayas o banco de peces.

var def: Dictionary
var amount := 0.0
var max_amount := 1.0
var visual: Node3D
var felled := false
var _fall_t := 0.0
var _rng_seed := 0

## Etapas con el arte en 3D (assets/modelos/recursos/<tipo>/etapaN.glb): 100, 75, 50
## y 25 % de lo que le queda; los árboles tienen además el tocón (0), que se queda
## 2-3 minutos después de talarlo. Si falta el modelo se usa la figura por código.
const STAGE_W := {"arbol": 1.3, "pino": 1.05, "arbusto": 0.9, "oro": 1.05, "piedra": 0.95}
## Ancho de cada etapa en el dibujo (px): así guardan su tamaño entre ellas.
const STAGE_PX := {
	"arbol": {100: 295, 75: 257, 50: 230, 25: 216, 0: 205},
	"pino": {100: 263, 75: 224, 50: 203, 25: 202, 0: 190},
	"arbusto": {100: 381, 75: 354, 50: 350, 25: 345},
	"oro": {100: 413, 75: 390, 50: 367, 25: 360},
	"piedra": {100: 264, 75: 258, 50: 256, 25: 254},
}
## Parte del alto que se hunde bajo el suelo: la base de pasto del dibujo no se ve
## y el recurso queda sobre el piso del mapa.
const STAGE_SINK := {"arbol": 0.07, "pino": 0.07, "arbusto": 0.08, "oro": 0.06, "piedra": 0.08}
const STUMP_SINK := 0.16
const STAGE_SINK_X := {"oro": {50: 0.13, 25: 0.2}}   # etapas bajas: la base pesa más
const STUMP_TIME := Vector2(120.0, 180.0)   # segundos que dura el tocón

var art_kind := ""     # "arbol", "pino", "arbusto", "oro", "piedra" si hay modelos
var _stage := -1
var _yaw := 0.0

const TREE_GREENS := [Color(0.25, 0.45, 0.18), Color(0.30, 0.50, 0.20), Color(0.22, 0.40, 0.20), Color(0.36, 0.52, 0.22)]


func is_static() -> bool:
	return true


func has_resource() -> bool:
	return amount > 0.0 and not removed


func res_type() -> String:
	return def["res"]


func res_group() -> String:
	return def["group"]


func remaining() -> float:
	return amount


func display_name() -> String:
	return Lang.t(def["name"])


func init(g: Game, k: String, tile: Vector2i, seed_v: int) -> void:
	game = g
	kind = k
	def = Defs.NODES[k]
	amount = def["amount"]
	max_amount = amount
	rect = Rect2i(tile, Vector2i(1, 1))
	pos = MapData.center(tile)
	position = Vector3(pos.x, MapData.active.tile_h(tile) if MapData.active else 0.0, pos.y)
	max_hp = 0
	_rng_seed = seed_v
	_build_visual()


## Etapa del arte según lo que le queda (fracción 0-1).
static func stage_of(f: float) -> int:
	if f > 0.75:
		return 100
	if f > 0.5:
		return 75
	if f > 0.25:
		return 50
	return 25


## Modelo de una etapa ya ajustado a su tamaño en el mapa (null si no hay arte).
static func stage_node(ak: String, stage: int, yaw: float) -> Node3D:
	if not STAGE_W.has(ak):
		return null
	var ps := Art.stage_model("arbol" if stage == 0 else ak, stage)
	if ps == null:
		return null
	var px: Dictionary = STAGE_PX[ak]
	var n := Art.fitted(ps, STAGE_W[ak] * float(px.get(stage, px[100])) / float(px[100]), true,
		STUMP_SINK if stage == 0 else STAGE_SINK_X.get(ak, {}).get(stage, STAGE_SINK[ak]))
	n.rotation.y = yaw
	return n


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	# Arte en 3D por etapas, si existe.
	if kind in ["arbol", "oro", "piedra", "arbusto"]:
		var ak := kind
		if kind == "arbol":
			ak = "pino" if rng.randf() < 0.5 else "arbol"
		# vistos de frente o un poco de lado, como en el dibujo
		_yaw = rng.randf_range(-0.6, 0.6)
		if Art.stage_model(ak, 100):
			art_kind = ak
			visual.position = Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
			_set_stage(100)
			return
	match kind:
		"arbol":
			var s := rng.randf_range(0.8, 1.2)
			var trunk := Color(0.40, 0.28, 0.16)
			var gr: int = game.map.ground[game.map.idx(rect.position)]
			var g: Color = TREE_GREENS[rng.randi() % TREE_GREENS.size()]
			if gr == MapData.JUNGLE:
				if rng.randf() < 0.5:
					# palmera
					var tr := Mat.cyl(visual, 0.06 * s, 0.09 * s, 1.6 * s, Vector3(0.05, 0.8 * s, 0), trunk.lightened(0.1), 5)
					tr.rotation.z = 0.08
					for k in 6:
						var leaf := Node3D.new()
						leaf.position = Vector3(0.12, 1.62 * s, 0)
						leaf.rotation = Vector3(0, k * TAU / 6, 0.6)
						visual.add_child(leaf)
						Mat.box(leaf, Vector3(0.75 * s, 0.03, 0.18), Vector3(0.35 * s, 0, 0), Color(0.20, 0.50, 0.18))
				else:
					# ceiba grande de selva
					Mat.cyl(visual, 0.1 * s, 0.16 * s, 1.3 * s, Vector3(0, 0.65 * s, 0), trunk, 5)
					var dg := Color(0.16, 0.36, 0.14).lightened(rng.randf() * 0.1)
					Mat.ball(visual, 0.6 * s, Vector3(0, 1.5 * s, 0), dg, 6)
					Mat.ball(visual, 0.4 * s, Vector3(0.3 * s, 1.75 * s, 0.15 * s), dg.lightened(0.06), 6)
			elif gr == MapData.DESERT:
				# mezquite seco
				var dry := Color(0.50, 0.52, 0.28)
				var tr := Mat.cyl(visual, 0.04 * s, 0.08 * s, 0.7 * s, Vector3(0, 0.35 * s, 0), trunk, 5)
				tr.rotation.z = 0.2
				Mat.ball(visual, 0.32 * s, Vector3(0.12, 0.8 * s, 0), dry, 5)
				Mat.ball(visual, 0.22 * s, Vector3(-0.15, 0.75 * s, 0.1), dry.darkened(0.1), 5)
			else:
				Mat.cyl(visual, 0.07 * s, 0.11 * s, 0.9 * s, Vector3(0, 0.45 * s, 0), trunk, 5)
				if rng.randf() < 0.5:
					Mat.ball(visual, 0.45 * s, Vector3(0, 1.1 * s, 0), g, 6)
					Mat.ball(visual, 0.32 * s, Vector3(0.22 * s, 1.35 * s, 0.1 * s), g.lightened(0.08), 6)
				else:
					Mat.cyl(visual, 0.0, 0.48 * s, 0.9 * s, Vector3(0, 1.0 * s, 0), g.darkened(0.1), 6)
					Mat.cyl(visual, 0.0, 0.36 * s, 0.7 * s, Vector3(0, 1.45 * s, 0), g, 6)
			visual.rotation.y = rng.randf() * TAU
			visual.position = Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		"oro", "piedra":
			var c := Color(0.92, 0.76, 0.22) if kind == "oro" else Color(0.60, 0.60, 0.62)
			var rock := Color(0.48, 0.45, 0.42)
			for k in 4:
				var p := Vector3(rng.randf_range(-0.25, 0.25), 0.15, rng.randf_range(-0.25, 0.25))
				var sz := rng.randf_range(0.25, 0.42)
				Mat.box(visual, Vector3(sz, sz * 0.8, sz), p, c if k % 2 == 0 else rock,
					Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5))
		"arbusto":
			var g := Color(0.28, 0.48, 0.20)
			Mat.ball(visual, 0.38, Vector3(0, 0.28, 0), g, 6)
			for k in 5:
				var a := rng.randf() * TAU
				Mat.ball(visual, 0.06, Vector3(cos(a) * 0.3, 0.3 + rng.randf() * 0.2, sin(a) * 0.3), Color(0.85, 0.12, 0.25), 4)
		"pesca":
			Mat.cyl(visual, 0.35, 0.35, 0.02, Vector3(0, 0.01, 0), Color(0.40, 0.65, 0.80), 10)
			var fish := Mat.box(visual, Vector3(0.28, 0.06, 0.1), Vector3(0.05, 0.05, 0), Color(0.75, 0.70, 0.55))
			fish.name = "fish"


func take_resource(a: float) -> float:
	if amount <= 0.0:
		return 0.0
	var t := minf(a, amount)
	amount -= t
	if kind == "arbol" and not felled:
		felled = true
		if art_kind == "":
			_fall_t = 0.001   # figura por código: el árbol cae
		game.release_static(self, false)   # ya talado, su casilla se puede caminar
	_refresh_scale()
	if amount <= 0.0:
		_leave_stump()
		game.remove_entity(self)
	return t


## Al acabarse un árbol queda su tocón unos minutos.
func _leave_stump() -> void:
	if kind != "arbol" or art_kind == "" or game.headless:
		return
	var n := stage_node(art_kind, 0, _yaw)
	if n == null:
		return
	var st := Stump.new()
	get_parent().add_child(st)
	st.position = position + visual.position
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	st.setup(game, rect, n, rng.randf_range(STUMP_TIME.x, STUMP_TIME.y))


func _set_stage(stage: int) -> void:
	if stage == _stage:
		return
	var n := stage_node(art_kind, stage, _yaw)
	if n == null:
		return
	_stage = stage
	for c in visual.get_children():
		c.queue_free()
	visual.add_child(n)


func _refresh_scale() -> void:
	var f := clampf(amount / max_amount, 0.0, 1.0)
	if art_kind != "":
		_set_stage(stage_of(f))
		return
	match kind:
		"oro", "piedra", "arbusto":
			visual.scale = Vector3.ONE * (0.45 + 0.55 * f)
		"arbol":
			if felled:
				visual.scale = Vector3(1.0, 0.5 + 0.5 * f, 1.0)


func _process(dt: float) -> void:
	if _fall_t > 0.0 and _fall_t < 1.0:
		_fall_t = minf(1.0, _fall_t + dt * 1.8)
		visual.rotation.z = -PI * 0.5 * ease(_fall_t, 2.0)
		visual.position.y = 0.1 * _fall_t
	if kind == "pesca":
		var f := visual.get_node_or_null("fish")
		if f:
			var t := Time.get_ticks_msec() * 0.002 + _rng_seed
			f.position = Vector3(cos(t) * 0.18, 0.05 + absf(sin(t * 2.0)) * 0.08, sin(t) * 0.18)
			f.rotation.y = -t
