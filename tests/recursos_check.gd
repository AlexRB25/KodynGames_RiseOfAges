extends Node
## Etapas de los recursos y tocón de los árboles (arte 3D). Necesita pantalla:
## godot --path . res://tests/recursos_check.tscn

var fails := 0


func check(c: bool, msg: String) -> void:
	print(("OK   " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _stumps(g: Game) -> Array:
	var out := []
	for c in g.find_children("*", "Node3D", true, false):
		if c is Stump and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _ready() -> void:
	Setup.default_skirmish()
	Setup.map_size = "pequeno"
	Setup.map_type = "valle"
	Setup.seed_value = 4242
	var g: Game = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	g.paused = true
	for k in 5:
		await get_tree().process_frame
	var tree: ResourceNode = null
	var counts := {}
	for r in g.resources:
		if r.art_kind != "":
			counts[r.art_kind] = counts.get(r.art_kind, 0) + 1
		if tree == null and r.kind == "arbol":
			tree = r
	print("con arte: ", counts)
	check(counts.has("arbol") and counts.has("pino"), "hay árboles y pinos con arte")
	check(counts.has("oro") and counts.has("piedra") and counts.has("arbusto"), "minas y bayas con arte")
	check(tree._stage == 100, "árbol nuevo: etapa 100")
	tree.take_resource(30.0)
	check(tree._stage == 75, "le quedan 70: etapa 75")
	tree.take_resource(25.0)
	check(tree._stage == 50, "le quedan 45: etapa 50")
	tree.take_resource(30.0)
	check(tree._stage == 25, "le quedan 15: etapa 25")
	check(_stumps(g).is_empty(), "todavía no hay tocón")
	tree.take_resource(50.0)
	check(tree.removed, "el árbol ya no es recurso")
	await get_tree().process_frame
	var st := _stumps(g)
	check(st.size() == 1, "al acabarse queda el tocón")
	if st.size() == 1:
		var left: float = st[0].end_time - g.time
		check(left >= 120.0 and left <= 180.0, "el tocón dura 2-3 min (%.0f s)" % left)
		g.run_seconds(100.0)
		await get_tree().process_frame
		var mine = st[0]
		check(is_instance_valid(mine) and not mine.is_queued_for_deletion(), "a los 100 s sigue ahí")
		g.run_seconds(85.0)
		await get_tree().process_frame
		await get_tree().process_frame
		check(not is_instance_valid(mine) or mine.is_queued_for_deletion(), "a los 185 s ya desapareció")
	# cabra: viva con arte; al morir, etapas según la carne
	var goat: Animal = null
	for a in g.animals:
		if a.kind == "cabra":
			goat = a
			break
	check(goat != null and goat.art, "cabra con arte")
	if goat:
		goat.take_damage(999.0, null)
		goat.render(1.0, 0.016)
		check(goat._stage == 75, "cabra muerta: etapa 75")
		goat.take_resource(goat.max_food * 0.5)
		goat.render(1.0, 0.016)
		check(goat._stage == 50, "a la mitad: etapa 50")
		goat.take_resource(goat.max_food * 0.3)
		goat.render(1.0, 0.016)
		check(goat._stage == 25, "casi acabada: etapa 25 (huesos)")
	print("RESULTADO: %s (%d fallos)" % ["BIEN" if fails == 0 else "MAL", fails])
	get_tree().quit(1 if fails else 0)
