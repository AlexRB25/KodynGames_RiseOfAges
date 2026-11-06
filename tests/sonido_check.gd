extends Node
## Revisa que carguen los sonidos y que la música y los efectos suenen. Necesita pantalla:
## godot --path . res://tests/sonido_check.tscn

func _ready() -> void:
	var fails := 0
	var missing: Array = []
	for n in Sfx.SOUNDS:
		if Sfx._streams.get(n, []).size() != max(1, int(Sfx.SOUNDS[n])):
			missing.append(n)
	print(("OK   " if missing.is_empty() else "FAIL ") + "cargan todos los sonidos " + str(missing))
	fails += 0 if missing.is_empty() else 1
	Sfx.play("era")
	var any := false
	for p in Sfx._pool:
		any = any or p.playing
	print(("OK   " if any else "FAIL ") + "suena un efecto")
	fails += 0 if any else 1
	Sfx.music("menu")
	await get_tree().create_timer(2.5).timeout
	print(("OK   " if Sfx._music.playing else "FAIL ") + "suena la música (%s)" % str(Sfx._music.stream.loop_mode if Sfx._music.stream else -1))
	fails += 0 if Sfx._music.playing else 1
	print("RESULTADO: %s (%d fallos)" % ["BIEN" if fails == 0 else "MAL", fails])
	get_tree().quit(1 if fails > 0 else 0)
