class_name Stump
extends Node3D
## Tocón que deja un árbol talado: solo se ve (no estorba ni da madera) y desaparece
## solo después de 2-3 minutos de partida, o antes si construyen encima.

var game: Game
var rect: Rect2i
var end_time := 0.0


func setup(g: Game, r: Rect2i, model: Node3D, seconds: float) -> void:
	game = g
	rect = r
	end_time = g.time + seconds
	add_child(model)


func _process(_dt: float) -> void:
	if game == null or not is_instance_valid(game):
		return
	var i := game.map.idx(rect.position)
	if game.time >= end_time or game.map.ent[i] != null:
		queue_free()
		return
	if game.fog:
		visible = game.fog.is_explored_rect(rect)
