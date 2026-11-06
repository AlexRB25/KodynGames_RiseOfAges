extends Control
## Pantalla de carga al empezar una partida: imagen del juego, un consejo al azar y
## una barra que avanza mientras se crea el mapa. Luego se desvanece y queda la partida.

const TIPS := [
	"Los aldeanos sin tarea muestran un [b]![/b] encima. Toca el botón [b]Sin tarea[/b] para encontrarlos.",
	"Cada [b]casa[/b] te deja tener 5 personas más. Constrúyelas antes de quedarte sin espacio.",
	"Un [b]campamento[/b] cerca de los árboles o las minas hace que tus aldeanos caminen menos y junten más.",
	"Las [b]granjas[/b] necesitan siembra: cómprala en el Centro. Si guardas siembras, se resiembran solas.",
	"Pastorea [b]cabras y guajolotes[/b] con un aldeano 10 segundos y llévalos a un [b]Corral[/b]: te dan comida sin morir.",
	"Para subir de [b]era[/b] necesitas recursos y ciertos edificios. Selecciona tu Centro para ver qué te falta.",
	"Las [b]mesetas[/b] solo tienen dos rampas: son buenos lugares para defenderse.",
	"Pierdes si te quedas sin [b]Centros[/b]. Construir un segundo Centro te da una reserva.",
	"El [b]mercado[/b] cambia los recursos que te sobran por oro, y el oro por lo que te falta.",
	"Los [b]arqueros[/b] atacan de lejos; ponlos detrás de tus guerreros.",
	"El [b]monasterio[/b] cura poco a poco a tus unidades cercanas y entrena santos.",
	"Construye una [b]maravilla[/b] y lleva 3 reliquias con tus santos: si aguanta la cuenta atrás, ganas.",
	"Los [b]arqueros[/b] pueden meterse en una torre de guardia y disparar desde arriba.",
	"Con [b]Ctrl + número[/b] guardas un grupo de unidades; con el número lo vuelves a elegir (en PC).",
	"En el celular, deja el dedo sobre un aldeano y arrástralo hasta un árbol, mina o enemigo: al soltar, va y lo hace.",
	"En el celular, deja el dedo sobre el botón [b]Aldeano[/b]: la barra se llena y compra uno tras otro.",
	"Explora pronto: no sabes dónde está tu rival hasta que lo encuentras.",
	"Cada civilización gana en algo y pierde en otra cosa. ¡Juega con su ventaja!",
]

var bar: ProgressBar
var status: Label
var ui: CanvasLayer
var game: Game


func _ready() -> void:
	# Esta escena se queda como base de la partida: no debe quedarse con los toques.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui = CanvasLayer.new()
	ui.layer = 50
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.07, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var img := TextureRect.new()
	img.texture = Art.tex(["ui/portada.jpg", "ui/fondo.jpg"][randi() % 2])
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	root.add_child(img)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -300
	shade.color = Color(0.08, 0.05, 0.03, 0.82)
	root.add_child(shade)
	var font: Font = load("res://assets/ui/fuentes/LilitaOne-Regular.ttf")
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -270
	box.offset_bottom = -30
	box.offset_left = 80
	box.offset_right = -80
	box.add_theme_constant_override("separation", 12)
	root.add_child(box)
	var tt := Label.new()
	tt.text = Lang.t("Consejo")
	tt.add_theme_font_override("font", font)
	tt.add_theme_font_size_override("font_size", 30)
	tt.add_theme_color_override("font_color", Color(0.96, 0.76, 0.30))
	box.add_child(tt)
	var tip := RichTextLabel.new()
	tip.bbcode_enabled = true
	tip.fit_content = true
	tip.text = Lang.t(TIPS[randi() % TIPS.size()])
	tip.add_theme_font_size_override("normal_font_size", 26)
	tip.add_theme_font_size_override("bold_font_size", 26)
	tip.add_theme_color_override("default_color", Color(0.98, 0.93, 0.80))
	box.add_child(tip)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sp)
	status = Label.new()
	status.add_theme_font_override("font", font)
	status.add_theme_font_size_override("font_size", 22)
	status.add_theme_color_override("font_color", Color(0.98, 0.93, 0.80))
	status.text = Lang.t("Preparando la partida…")
	box.add_child(status)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 26)
	bar.max_value = 1.0
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.08, 0.05, 0.03, 0.9)
	bgs.border_color = Color(0.54, 0.42, 0.22)
	bgs.set_border_width_all(3)
	bgs.set_corner_radius_all(13)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.96, 0.76, 0.30)
	fill.set_corner_radius_all(11)
	bar.add_theme_stylebox_override("background", bgs)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	# Dejar que se dibuje la pantalla antes de crear el mapa.
	for k in 3:
		await get_tree().process_frame
	Setup.loading = true
	game = load("res://scenes/game.tscn").instantiate()
	game.loading.connect(_on_progress)
	game.loaded.connect(_on_loaded)
	add_child(game)
	move_child(game, 0)


func _on_progress(p: float, text: String) -> void:
	bar.value = p
	status.text = text
	# Desarrollo: --shot-carga=archivo.png toma la foto a media carga.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-carga=") and p >= 0.45 and p < 0.5:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.get_slice("=", 1))


func _on_loaded() -> void:
	Setup.loading = false
	bar.value = 1.0
	status.text = Lang.t("¡Listo!")
	var root: Control = ui.get_child(0)
	# Mientras se desvanece ya se puede tocar el mapa.
	root.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(root, "modulate:a", 0.0, 0.45)
	tw.tween_callback(ui.queue_free)


## Ir a una partida pasando por esta pantalla.
static func go(tree: SceneTree) -> void:
	tree.change_scene_to_file("res://scenes/carga.tscn")
