class_name PlayerState
extends RefCounted

var id := 0
var name := ""
var civ := "mexica"
var team := 1
var color := Color.WHITE
var color_idx := 0
var is_bot := false
var difficulty := "normal"
var res := {}
var pop := 0
var pop_cap := 0
var age := 1
var defeated := false
var seeds := 0
var prices := {"comida": 100.0, "madera": 100.0, "piedra": 100.0}
var start_tile := Vector2i.ZERO
var techs := {}                # mejoras investigadas (id -> true)
var wonder_t := -1.0           # cuenta atrás de su maravilla (-1 = no corre)
var stats := {"recolectado": 0.0, "entrenados": 0, "muertes": 0, "bajas": 0, "edificios": 0}


func civ_value(key: String, default_v: float) -> float:
	return float(Defs.civ_mod(civ, key, default_v))


func gather_mult(r: String) -> float:
	var g: Dictionary = Defs.civ_mod(civ, "gather", {})
	var m: float = g.get(r, 1.0)
	if is_bot:
		m *= Defs.DIFFICULTY[difficulty]["gather"]
	return m


func speed_mult() -> float:
	return Defs.DIFFICULTY[difficulty]["gather"] if is_bot else 1.0


func can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if res.get(r, 0.0) < cost[r] - 0.001:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for r in cost:
		res[r] = res.get(r, 0.0) - cost[r]


func give(cost: Dictionary) -> void:
	for r in cost:
		res[r] = res.get(r, 0.0) + cost[r]


func age_name() -> String:
	return Lang.t(Defs.AGES[age - 1]["name"])
