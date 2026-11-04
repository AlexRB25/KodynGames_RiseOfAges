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


## Penacho en abanico sobre la cabeza.
static func penacho(parent: Node3D, head_y: float, n: int, length: float, colors: Array) -> void:
	for i in n:
		var a := (float(i) / maxf(n - 1, 1) - 0.5) * 1.6 if n > 1 else 0.0
		var f := Node3D.new()
		f.position = Vector3(-0.05, head_y + 0.06, 0)
		f.rotation = Vector3(a, 0, 0.35)
		parent.add_child(f)
		Mat.box(f, Vector3(0.03, length, 0.07), Vector3(0, length * 0.5, 0), colors[i % colors.size()])


## Cuerpo de una persona según la era. Devuelve {arm, legs, y0}.
static var SKIN_NOW := SKIN


static func person(body: Node3D, kind: String, age: int, team: Color, y0: float, skin: Color = SKIN) -> Dictionary:
	var SKIN := skin
	var legs: Array[Node3D] = []
	if kind != "jinete":
		for lz in [-0.07, 0.07]:
			legs.append(Mat.box(body, Vector3(0.08, 0.34, 0.08), Vector3(0, 0.17, lz), SKIN))
		if age >= 3:
			for lz in [-0.07, 0.07]:
				Mat.box(body, Vector3(0.1, 0.04, 0.1), Vector3(0.01, 0.02, lz), Color(0.45, 0.32, 0.2))
	var villager := kind == "aldeano"
	var torso: Color
	var cloth: Color
	if villager:
		torso = [SKIN, Color(0.82, 0.78, 0.66), Color(0.92, 0.89, 0.80), Color(0.94, 0.92, 0.84), team.lightened(0.35)][age - 1]
		cloth = [Color(0.50, 0.40, 0.28), team.darkened(0.2), team, team, GOLD][age - 1]
	else:
		torso = [SKIN, Color(0.93, 0.90, 0.82), team, team, team][age - 1]
		cloth = [team.darkened(0.15), team, Color(0.93, 0.90, 0.82), GOLD.darkened(0.1), GOLD][age - 1]
	# torso y taparrabo / faja
	Mat.box(body, Vector3(0.2, 0.36, 0.3), Vector3(0, y0 + 0.52, 0), torso)
	Mat.box(body, Vector3(0.21, 0.08 + (0.06 if age == 1 else 0.0), 0.31), Vector3(0, y0 + 0.38, 0), cloth)
	if age >= 2 and kind != "jinete":
		# falda de la túnica
		Mat.box(body, Vector3(0.22, 0.12, 0.32), Vector3(0, y0 + 0.30, 0), torso.darkened(0.06))
	if age >= 3 and not villager:
		# capa
		Mat.box(body, Vector3(0.04, 0.42, 0.3), Vector3(-0.12, y0 + 0.45, 0), team.darkened(0.25))
	if age >= 5:
		# collar de oro / jade
		Mat.box(body, Vector3(0.22, 0.05, 0.32), Vector3(0, y0 + 0.68, 0), GOLD if not villager else JADE)
	# cabeza
	Mat.ball(body, 0.12, Vector3(0, y0 + 0.82, 0), SKIN, 6)
	Mat.box(body, Vector3(0.2, 0.08, 0.22), Vector3(-0.02, y0 + 0.9, 0), HAIR)
	if villager:
		if age >= 4:
			Mat.box(body, Vector3(0.21, 0.04, 0.23), Vector3(0, y0 + 0.88, 0), team)
			penacho(body, y0 + 0.82, 1 if age == 4 else 2, 0.22, FEATHERS)
		if age >= 5:
			Mat.ball(body, 0.025, Vector3(0, y0 + 0.78, 0.12), GOLD, 4)
			Mat.ball(body, 0.025, Vector3(0, y0 + 0.78, -0.12), GOLD, 4)
	else:
		match age:
			1:
				Mat.box(body, Vector3(0.21, 0.04, 0.23), Vector3(0, y0 + 0.88, 0), team.darkened(0.2))
			2:
				Mat.box(body, Vector3(0.21, 0.05, 0.23), Vector3(0, y0 + 0.88, 0), team)
				penacho(body, y0 + 0.82, 1, 0.22, [FEATHERS[0]])
			3:
				Mat.box(body, Vector3(0.23, 0.06, 0.25), Vector3(0, y0 + 0.9, 0), team)
				penacho(body, y0 + 0.82, 3, 0.28, FEATHERS)
			4:
				# casco de jaguar/águila
				Mat.box(body, Vector3(0.26, 0.14, 0.27), Vector3(0.02, y0 + 0.92, 0), Color(0.85, 0.65, 0.2))
				Mat.box(body, Vector3(0.1, 0.06, 0.2), Vector3(0.14, y0 + 0.9, 0), Color(0.95, 0.85, 0.5))
				penacho(body, y0 + 0.86, 5, 0.34, FEATHERS)
			_:
				Mat.box(body, Vector3(0.27, 0.15, 0.28), Vector3(0.02, y0 + 0.92, 0), GOLD)
				penacho(body, y0 + 0.88, 7, 0.46, FEATHERS)
	var arm := Node3D.new()
	arm.position = Vector3(0, y0 + 0.66, 0.2)
	body.add_child(arm)
	Mat.box(arm, Vector3(0.07, 0.28, 0.07), Vector3(0, -0.12, 0), torso if age >= 2 and villager else SKIN)
	if age >= 4:
		Mat.box(arm, Vector3(0.08, 0.04, 0.08), Vector3(0, -0.2, 0), GOLD if age >= 5 else JADE)
	return {"arm": arm, "legs": legs}
