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
	return def["name"]


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


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
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
		_fall_t = 0.001
		game.release_static(self, false)   # el árbol cae: su casilla se puede caminar
	_refresh_scale()
	if amount <= 0.0:
		game.remove_entity(self)
	return t


func _refresh_scale() -> void:
	var f := clampf(amount / max_amount, 0.0, 1.0)
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
