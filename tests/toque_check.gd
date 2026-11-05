extends Node
## Entra por la pantalla de carga al tutorial (como el jugador) y revisa que nada
## invisible tape los toques sobre el mapa.

func _ready() -> void:
	Setup.tutorial = true
	# Cargar la pantalla de carga al lado de esta (cambiar de escena borraría esta prueba).
	var carga: Node = load("res://scenes/carga.tscn").instantiate()
	get_tree().root.add_child.call_deferred(carga)
	await get_tree().create_timer(12.0).timeout
	var vp := get_tree().root
	var vs := vp.get_visible_rect().size
	var fails := 0
	for p in [Vector2(0.5, 0.45), Vector2(0.7, 0.5), Vector2(0.3, 0.6), Vector2(0.65, 0.3)]:
		var sp: Vector2 = vs * p
		var hit := _control_at(vp, sp)
		print("en ", sp, ": ", hit if hit else "nada (bien)")
		if hit:
			fails += 1
	print("RESULTADO: ", "BIEN" if fails == 0 else "MAL (%d tapados)" % fails)
	get_tree().quit(1 if fails else 0)


## El Control visible más arriba que se quedaría con un toque en sp.
func _control_at(n: Node, sp: Vector2) -> String:
	var found := ""
	for c in n.get_children():
		var r := _control_at(c, sp)
		if r != "":
			found = r
	if found != "":
		return found
	if n is Control and n.is_visible_in_tree() and n.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and n.get_global_rect().has_point(sp):
		return "%s (%s, filtro %d)" % [n.get_path(), n.get_class(), n.mouse_filter]
	return ""
