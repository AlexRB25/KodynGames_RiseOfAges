extends Node
## Música y efectos de sonido. Los archivos los genera tools/sonidos.py en
## assets/sonidos. Solo suena lo del jugador local o lo que está cerca de la
## cámara (y a la vista); nunca toca la simulación ni su azar.
## Volúmenes guardados en user://cuenta.cfg [sonido] musica / efectos (0..1).

const DIR := "res://assets/sonidos/"
## nombre -> cuántas variantes hay (nombre_1, nombre_2...); 0 = un solo archivo.
const SOUNDS := {
	"ok_aldeano": 4, "sel_aldeano": 2, "ok_guerrero": 3, "sel_guerrero": 2,
	"clic": 0, "seleccion": 0, "colocar": 0, "terminado": 0, "era": 0, "listo": 0,
	"mejora": 0, "campana": 0, "alerta": 0, "flecha": 0, "piedra": 0, "golpe": 3,
	"derribo": 0, "error": 0, "reliquia": 0, "hacha": 2, "pico": 2, "cosecha": 0,
	"martillo": 0, "victoria": 0, "derrota": 0,
}
## Tiempo mínimo entre dos veces el mismo sonido (para que no se amontone).
const GAP := {"golpe": 0.07, "flecha": 0.06, "voz": 0.35, "clic": 0.04, "terminado": 0.4, "listo": 0.25,
	"derribo": 0.3, "error": 0.25, "hacha": 0.12, "pico": 0.12, "cosecha": 0.2, "martillo": 0.12}
const CFG := "user://cuenta.cfg"

var off := false
var vol_music := 0.55
var vol_sfx := 0.8
var game: Game = null
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _last := {}
var _rng := RandomNumberGenerator.new()
var _music: AudioStreamPlayer
var _music_name := ""
var _work_t := 0.0
var _bus_music := 0
var _bus_sfx := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	off = DisplayServer.get_name() == "headless"
	if off:
		return
	_rng.randomize()
	_bus_music = _add_bus("Musica")
	_bus_sfx = _add_bus("Efectos")
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	vol_music = float(cfg.get_value("sonido", "musica", vol_music))
	vol_sfx = float(cfg.get_value("sonido", "efectos", vol_sfx))
	_apply_volumes()
	for n in SOUNDS:
		var list: Array = []
		var c: int = SOUNDS[n]
		for i in (range(1, c + 1) if c > 0 else [0]):
			var path: String = DIR + (n if c == 0 else "%s_%d" % [n, i]) + ".wav"
			if ResourceLoader.exists(path):
				list.append(load(path))
		_streams[n] = list
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Efectos"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Musica"
	add_child(_music)
	_music.finished.connect(func() -> void:
		if _music_name != "":
			_music.play())
	# Cada botón del juego hace un clic de madera al tocarlo.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton and not n.has_meta("sin_clic"):
			n.pressed.connect(func() -> void: play("clic", -4.0)))


func _add_bus(n: String) -> int:
	var i := AudioServer.get_bus_index(n)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, n)
	AudioServer.set_bus_send(i, "Master")
	return i


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(_bus_music, linear_to_db(maxf(vol_music, 0.0001)))
	AudioServer.set_bus_mute(_bus_music, vol_music <= 0.001)
	AudioServer.set_bus_volume_db(_bus_sfx, linear_to_db(maxf(vol_sfx, 0.0001)))
	AudioServer.set_bus_mute(_bus_sfx, vol_sfx <= 0.001)


## kind: "musica" o "efectos"; v de 0 a 1. Se guarda.
func set_volume(kind: String, v: float) -> void:
	if kind == "musica":
		vol_music = clampf(v, 0.0, 1.0)
	else:
		vol_sfx = clampf(v, 0.0, 1.0)
	if off:
		return
	_apply_volumes()
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("sonido", kind, v)
	cfg.save(CFG)


## Sonido sin lugar (interfaz, avisos del jugador local).
func play(n: String, db := 0.0, pitch_var := 0.05) -> void:
	if off or not _streams.has(n) or _streams[n].is_empty():
		return
	var key := "voz" if n.begins_with("ok_") or n.begins_with("sel_") else n
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(key, -10.0)) < float(GAP.get(key, 0.05)):
		return
	_last[key] = now
	var p := _free_player()
	var list: Array = _streams[n]
	p.stream = list[_rng.randi() % list.size()]
	p.volume_db = db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


## Sonido en un punto del mapa: solo si está cerca de la cámara y a la vista; más
## bajo mientras más lejos.
func at(n: String, p: Vector2, db := 0.0) -> void:
	if off or not _near(p):
		return
	var cam: Vector2 = game.camera.ground_pos()
	var r := _radius()
	play(n, db - 14.0 * clampf(cam.distance_to(p) / r, 0.0, 1.0))


func _radius() -> float:
	return maxf(14.0, game.camera.dist * 1.5)


func _near(p: Vector2) -> bool:
	if game == null or not is_instance_valid(game) or game.camera == null:
		return false
	if game.fog and not game.fog.is_visible(p):
		return false
	return game.camera.ground_pos().distance_to(p) <= _radius()


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	# Todos ocupados: el que lleva más tiempo sonando.
	var best := _pool[0]
	for p in _pool:
		if p.get_playback_position() > best.get_playback_position():
			best = p
	return best


## Música de fondo, con cambio suave. "" la apaga.
func music(n: String) -> void:
	if off or n == _music_name:
		return
	_music_name = n
	var tw := create_tween()
	if _music.playing:
		tw.tween_property(_music, "volume_db", -40.0, 1.0)
	tw.tween_callback(func() -> void:
		_music.stop()
		if n == "":
			return
		var path := DIR + "musica_" + n + ".wav"
		if not ResourceLoader.exists(path):
			return
		var s: AudioStream = load(path)
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		_music.stream = s
		_music.volume_db = -30.0
		_music.play())
	tw.tween_property(_music, "volume_db", 0.0, 1.5)


## Fila "Música/Efectos: ----o----" para los menús.
func volume_row(kind: String, font := 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = Lang.t("Música:") if kind == "musica" else Lang.t("Efectos:")
	l.custom_minimum_size = Vector2(110, 0)
	l.add_theme_font_size_override("font_size", font)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = vol_music if kind == "musica" else vol_sfx
	s.custom_minimum_size = Vector2(200, 32)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void: set_volume(kind, v))
	if kind == "efectos":
		s.drag_ended.connect(func(_c: bool) -> void: play("listo"))
	row.add_child(s)
	return row


## Voz de "¡sí!" al darle una orden a unidades propias.
func order_voice(units: Array, select := false) -> void:
	if off or units.is_empty():
		return
	var u = units[0]
	if not (u is Unit):
		return
	var civil: bool = u.is_villager() or u.def.get("civil", false) or u.is_fisher()
	var pre := "sel_" if select else "ok_"
	play(pre + ("aldeano" if civil else "guerrero"), -2.0, 0.08)


func _process(dt: float) -> void:
	if off or game == null or not is_instance_valid(game) or game.paused:
		return
	# Ruidos de trabajo: de vez en cuando, un aldeano que trabaja cerca de la cámara.
	_work_t -= dt
	if _work_t > 0.0:
		return
	_work_t = 0.45
	var cands: Array = []
	for u in game.units:
		if u.working and not u.dead and _near(u.pos):
			cands.append(u)
	if cands.is_empty():
		return
	var w: Unit = cands[_rng.randi() % cands.size()]
	var s := ""
	if w.state == Unit.S.BUILD:
		s = "martillo"
	elif w.state == Unit.S.GATHER and Entity.valid(w.target):
		match String(w.target.res_group()):
			"arbol", "pino":
				s = "hacha"
			"oro", "piedra":
				s = "pico"
			"granja", "arbusto":
				s = "cosecha"
	if s != "":
		at(s, w.pos, -6.0)
