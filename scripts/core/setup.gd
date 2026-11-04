extends Node
## Autoload "Setup": guarda la configuración de la partida elegida en el menú.

## players: Array de Dictionary {name, civ, team, color, bot, difficulty}
var players: Array = []
var map_size := "mediano"
var seed_value := 0
var local_player := 0
var online := false


func _ready() -> void:
	if players.is_empty():
		default_skirmish()


func default_skirmish() -> void:
	players = [
		{"name": "Jugador", "civ": "mexica", "team": 1, "color": 0, "bot": false, "difficulty": "normal"},
		{"name": "Bot 1", "civ": "maya", "team": 2, "color": 1, "bot": true, "difficulty": "normal"},
	]
	local_player = 0
	online = false
	map_size = "mediano"
	seed_value = 0
