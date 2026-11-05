class_name Look
extends RefCounted
## Aspecto por era (1..5). Era 1: gente con taparrabo y chozas de paja.
## Era 5: túnicas finas, oro y penachos grandes; edificios de estuco con adornos.

const SKIN := Color(0.62, 0.42, 0.28)
const HAIR := Color(0.10, 0.08, 0.07)
const GOLD := Color(0.95, 0.78, 0.25)
const JADE := Color(0.20, 0.62, 0.50)
const FEATHERS := [Color(0.15, 0.62, 0.38), Color(0.10, 0.45, 0.75), Color(0.85, 0.20, 0.18), Color(0.95, 0.78, 0.25)]


## Colores de construcción: muro, techo, adorno, piedra.
static func palette(age: int) -> Dictionary:
	match age:
		1:
			return {"wall": Color(0.60, 0.48, 0.34), "roof": Color(0.66, 0.54, 0.30), "trim": Color(0.45, 0.33, 0.20), "stone": Color(0.58, 0.55, 0.50)}
		2:
			return {"wall": Color(0.78, 0.66, 0.48), "roof": Color(0.80, 0.66, 0.36), "trim": Color(0.55, 0.38, 0.22), "stone": Color(0.64, 0.61, 0.56)}
		3:
			return {"wall": Color(0.72, 0.68, 0.61), "roof": Color(0.62, 0.30, 0.20), "trim": Color(0.55, 0.25, 0.18), "stone": Color(0.68, 0.65, 0.59)}
		4:
			return {"wall": Color(0.90, 0.87, 0.80), "roof": Color(0.70, 0.25, 0.18), "trim": Color(0.75, 0.20, 0.15), "stone": Color(0.74, 0.71, 0.65)}
		_:
			return {"wall": Color(0.95, 0.92, 0.84), "roof": Color(0.66, 0.22, 0.16), "trim": GOLD, "stone": Color(0.80, 0.77, 0.70)}


## Penacho en abanico detrás de la cabeza (plumas en bloques, estilo voxel).
static func penacho(parent: Node3D, head_y: float, n: int, length: float, colors: Array) -> void:
	for i in n:
		var a := (float(i) / maxf(n - 1, 1) - 0.5) * 1.9 if n > 1 else 0.0
		var f := Node3D.new()
		f.position = Vector3(-0.1, head_y, 0)
		f.rotation = Vector3(a, 0, 0.45)
		parent.add_child(f)
		Mat.box(f, Vector3(0.05, length, 0.09), Vector3(0, length * 0.5, 0), colors[i % colors.size()])
		Mat.box(f, Vector3(0.055, length * 0.25, 0.095), Vector3(0, length * 0.9, 0), colors[i % colors.size()].lightened(0.25))


## Persona chibi voxel (como el arte del juego): cabeza cúbica grande, pelo en
## bloque con fleco, ojos cuadrados y cuerpo corto. Mira hacia +X.
## La ropa cambia por era. Devuelve {arm, legs}.
static func person(body: Node3D, kind: String, age: int, team: Color, y0: float, skin: Color = SKIN) -> Dictionary:
	var legs: Array[Node3D] = []
	var villager := kind == "aldeano"
	var white := Color(0.93, 0.90, 0.80)
	var red := Color(0.78, 0.18, 0.14)
	var cloth_dark := white.darkened(0.15)
	# piernas
	if kind != "jinete":
		for lz in [-0.065, 0.065]:
			var leg := Mat.box(body, Vector3(0.09, 0.2, 0.1), Vector3(0, 0.1, lz), skin)
			legs.append(leg)
			Mat.box(leg, Vector3(0.11, 0.04, 0.11), Vector3(0.01, -0.08, 0), skin.darkened(0.25) if age < 3 else Color(0.45, 0.32, 0.2))
	# torso
	var torso := skin
	if villager and age >= 4:
		torso = white
	elif not villager and age >= 2:
		torso = [skin, white, team, team, team][age - 1]
	Mat.box(body, Vector3(0.18, 0.22, 0.26), Vector3(0, y0 + 0.37, 0), torso)
	# taparrabo / falda
	Mat.box(body, Vector3(0.2, 0.09, 0.28), Vector3(0, y0 + 0.24, 0), white if villager else (team.darkened(0.2) if age < 3 else white))
	var flap := white
	if villager and age >= 3:
		flap = red
	elif not villager:
		flap = team
	Mat.box(body, Vector3(0.03, 0.13, 0.1), Vector3(0.1, y0 + 0.2, 0), flap)
	if villager and age == 2:
		# banda blanca cruzada sobre el pecho
		Mat.box(body, Vector3(0.19, 0.06, 0.06), Vector3(0.005, y0 + 0.4, 0), white, Vector3(0.8, 0, 0))
	if villager and age >= 4:
		Mat.box(body, Vector3(0.185, 0.04, 0.265), Vector3(0, y0 + 0.28, 0), red)   # orilla roja de la túnica
	if age >= 3:
		# collar de jade (oro en era 5)
		Mat.box(body, Vector3(0.2, 0.045, 0.28), Vector3(0, y0 + 0.47, 0), GOLD if age >= 5 else JADE)
	if age >= 5:
		Mat.box(body, Vector3(0.21, 0.05, 0.29), Vector3(0, y0 + 0.29, 0), GOLD)   # cinturón
		Mat.box(body, Vector3(0.04, 0.34, 0.3), Vector3(-0.12, y0 + 0.36, 0), red if villager else team.darkened(0.2))  # capa
	elif not villager and age >= 3:
		Mat.box(body, Vector3(0.04, 0.32, 0.28), Vector3(-0.11, y0 + 0.36, 0), team.darkened(0.25))
	if villager and age == 4:
		# canasta en la espalda
		Mat.box(body, Vector3(0.12, 0.2, 0.22), Vector3(-0.16, y0 + 0.4, 0), Color(0.62, 0.45, 0.22))
		Mat.box(body, Vector3(0.13, 0.03, 0.23), Vector3(-0.16, y0 + 0.47, 0), Color(0.5, 0.35, 0.16))
	# cabeza grande
	var hy := y0 + 0.64
	Mat.box(body, Vector3(0.3, 0.29, 0.3), Vector3(0, hy, 0), skin)
	# ojos y boca
	for ez in [-0.065, 0.065]:
		Mat.box(body, Vector3(0.02, 0.07, 0.045), Vector3(0.151, hy - 0.01, ez), Color(0.08, 0.06, 0.05))
	Mat.box(body, Vector3(0.015, 0.02, 0.06), Vector3(0.151, hy - 0.09, 0), skin.darkened(0.3))
	# pelo: casco, nuca y fleco
	Mat.box(body, Vector3(0.32, 0.09, 0.32), Vector3(-0.005, hy + 0.15, 0), HAIR)
	Mat.box(body, Vector3(0.12, 0.25, 0.32), Vector3(-0.105, hy + 0.02, 0), HAIR)
	Mat.box(body, Vector3(0.04, 0.06, 0.3), Vector3(0.14, hy + 0.1, 0.0), HAIR)
	for sz in [-0.15, 0.15]:
		Mat.box(body, Vector3(0.18, 0.14, 0.03), Vector3(-0.04, hy + 0.06, sz), HAIR)
	if villager:
		match age:
			2:
				Mat.box(body, Vector3(0.315, 0.05, 0.315), Vector3(0, hy + 0.09, 0), white)
				Mat.box(body, Vector3(0.317, 0.018, 0.317), Vector3(0, hy + 0.09, 0), red)
			3:
				Mat.box(body, Vector3(0.1, 0.1, 0.1), Vector3(-0.08, hy + 0.23, 0), HAIR)   # chongo
				Mat.box(body, Vector3(0.11, 0.03, 0.11), Vector3(-0.08, hy + 0.2, 0), red)
				for ez in [-0.155, 0.155]:
					Mat.box(body, Vector3(0.05, 0.05, 0.02), Vector3(0.0, hy - 0.04, ez), JADE)
			4:
				Mat.box(body, Vector3(0.32, 0.07, 0.32), Vector3(0, hy + 0.12, 0), GOLD)    # diadema
				Mat.box(body, Vector3(0.03, 0.08, 0.08), Vector3(0.165, hy + 0.12, 0), JADE)
				for ez in [-0.16, 0.16]:
					Mat.box(body, Vector3(0.06, 0.06, 0.03), Vector3(0.0, hy - 0.04, ez), JADE)
			5:
				Mat.box(body, Vector3(0.33, 0.1, 0.33), Vector3(0, hy + 0.14, 0), GOLD)
				Mat.box(body, Vector3(0.04, 0.12, 0.12), Vector3(0.17, hy + 0.16, 0), JADE)
				for ez in [-0.165, 0.165]:
					Mat.box(body, Vector3(0.07, 0.07, 0.03), Vector3(0.0, hy - 0.04, ez), GOLD)
				penacho(body, hy + 0.14, 7, 0.34, [Color(0.10, 0.62, 0.45), Color(0.12, 0.55, 0.40), Color(0.15, 0.70, 0.52)])
	else:
		match age:
			1:
				Mat.box(body, Vector3(0.315, 0.04, 0.315), Vector3(0, hy + 0.09, 0), team.darkened(0.2))
			2:
				Mat.box(body, Vector3(0.315, 0.05, 0.315), Vector3(0, hy + 0.1, 0), team)
				penacho(body, hy + 0.14, 1, 0.24, [FEATHERS[0]])
			3:
				Mat.box(body, Vector3(0.33, 0.07, 0.33), Vector3(0, hy + 0.12, 0), team)
				penacho(body, hy + 0.14, 3, 0.28, FEATHERS)
			4:
				# casco de jaguar/águila
				Mat.box(body, Vector3(0.34, 0.16, 0.34), Vector3(0.0, hy + 0.12, 0), Color(0.85, 0.65, 0.2))
				Mat.box(body, Vector3(0.12, 0.06, 0.26), Vector3(0.17, hy + 0.11, 0), Color(0.95, 0.85, 0.5))
				penacho(body, hy + 0.16, 5, 0.34, FEATHERS)
			_:
				Mat.box(body, Vector3(0.35, 0.17, 0.35), Vector3(0.0, hy + 0.13, 0), GOLD)
				penacho(body, hy + 0.18, 7, 0.44, FEATHERS)
	# brazos (uno se mueve al trabajar/atacar; el otro queda quieto)
	var sleeve := torso if (villager and age >= 4) or (not villager and age >= 2) else skin
	Mat.box(body, Vector3(0.07, 0.22, 0.07), Vector3(0, y0 + 0.37, -0.165), sleeve)
	var arm := Node3D.new()
	arm.position = Vector3(0, y0 + 0.47, 0.165)
	body.add_child(arm)
	Mat.box(arm, Vector3(0.07, 0.22, 0.07), Vector3(0, -0.1, 0), sleeve)
	Mat.box(arm, Vector3(0.075, 0.06, 0.075), Vector3(0, -0.2, 0), skin)
	if age >= 3:
		Mat.box(arm, Vector3(0.08, 0.035, 0.08), Vector3(0, -0.05, 0), GOLD if age >= 4 else JADE)
	return {"arm": arm, "legs": legs}
