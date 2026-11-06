class_name Defs
extends RefCounted
## Datos del juego: recursos, unidades, edificios, civilizaciones y dificultad.
## Cambiar números aquí ajusta el balance sin tocar la lógica.

const TICK := 0.05                     # la simulación avanza en pasos fijos de 50 ms
const RES := ["comida", "madera", "oro", "piedra"]
const RES_NAMES := {"comida": "Alimento", "madera": "Madera", "oro": "Oro", "piedra": "Piedra"}
const RES_COLORS := {
	"comida": Color(0.86, 0.32, 0.26), "madera": Color(0.55, 0.36, 0.18),
	"oro": Color(0.96, 0.80, 0.20), "piedra": Color(0.62, 0.62, 0.64),
}
const CARRY := 10.0                    # lo que carga un aldeano antes de volver
const START_RES := {"comida": 200, "madera": 200, "oro": 100, "piedra": 150}
const START_VILLAGERS := 5
const POP_MAX := 200
const SEARCH_RADIUS := 14.0            # radio para buscar el siguiente recurso igual
const CAMP_RADIUS := 9.0               # radio de efecto de los campamentos
const CAMP_SPEED := 1.25               # +25 % más rápido cerca de su campamento
const CAMP_YIELD := 1.15               # +15 % de producto al dejarlo en su campamento

const PLAYER_COLORS := [
	Color(0.20, 0.45, 0.95), Color(0.90, 0.18, 0.15), Color(0.20, 0.75, 0.25), Color(0.95, 0.80, 0.10),
	Color(0.10, 0.80, 0.85), Color(0.75, 0.25, 0.85), Color(0.55, 0.55, 0.55), Color(0.98, 0.50, 0.10),
]
const COLOR_NAMES := ["Azul", "Rojo", "Verde", "Amarillo", "Turquesa", "Morado", "Gris", "Naranja"]

## Recursos fijos del mapa. "group" decide qué buscar al terminar uno.
const NODES := {
	"arbol": {"name": "Árbol", "res": "madera", "amount": 100, "rate": 0.55, "group": "arbol"},
	"piedra": {"name": "Mina de piedra", "res": "piedra", "amount": 350, "rate": 0.40, "group": "piedra"},
	"oro": {"name": "Mina de oro", "res": "oro", "amount": 400, "rate": 0.40, "group": "oro"},
	"arbusto": {"name": "Arbusto de bayas", "res": "comida", "amount": 125, "rate": 0.45, "group": "arbusto"},
	"pesca": {"name": "Banco de peces", "res": "comida", "amount": 200, "rate": 0.50, "group": "pesca"},
}

const ANIMALS := {
	"cabra": {"name": "Cabra", "hp": 8.0, "food": 100.0, "speed": 0.9, "flee": 1.5, "color": Color(0.93, 0.91, 0.86), "tame": true},
	"venado": {"name": "Venado", "hp": 6.0, "food": 140.0, "speed": 1.3, "flee": 2.4, "color": Color(0.62, 0.43, 0.25)},
	"guajolote": {"name": "Guajolote", "hp": 4.0, "food": 70.0, "speed": 0.8, "flee": 1.3, "color": Color(0.30, 0.22, 0.18), "tame": true},
}
# Pastoreo: un aldeano pastorea una cabra o guajolote 10 segundos seguidos y se vuelve
# de su pueblo (también si era de otro jugador: así se roban). En un Corral pastan: dan
# alimento sin morir y engordan (más carne si después se sacrifican).
const HERD_TIME := 10.0
const HERD_REACH := 1.5
const GRAZE_RATE := 0.2        # alimento por segundo por animal en el corral
const CORRAL_CAP := 6          # animales que pastan por corral
const CORRAL_RADIUS := 4.5     # distancia al corral para contar como "pastando"
const FATTEN_RATE := 0.15      # comida que gana el animal por segundo pastando
const FATTEN_MAX := 1.6        # hasta 1.6 veces su carne normal
const MEAT_RATE := 0.70
const FARM_RATE := 0.42
const SEED_COST := {"madera": 60}   # 1 siembra = 1 granja
const SOW_TIME := 10.0              # segundos de trabajo para sembrar

## Unidades. "from" = edificio que la entrena.
## naval: va por el agua. fisher: barco que pesca y pone trampas. civil: no pelea.
## siege: máquina de asedio. only_buildings: solo ataca edificios. splash: daño en área.
const UNITS := {
	"aldeano": {"name": "Aldeano", "hp": 25.0, "atk": 3.0, "armor": 0.0, "range": 0.0, "cd": 1.5,
		"speed": 2.0, "sight": 7, "cost": {"comida": 50}, "time": 12.0, "from": "centro", "villager": true,
		"desc": "Recolecta, caza, pesca, siembra y construye."},
	"guerrero": {"name": "Guerrero", "hp": 60.0, "atk": 8.0, "armor": 1.0, "range": 0.0, "cd": 1.4,
		"speed": 2.1, "sight": 7, "cost": {"comida": 60, "oro": 20}, "time": 18.0, "from": "cuartel", "age": 1,
		"desc": "Infantería con macuahuitl. Buena contra arqueros."},
	"lancero": {"name": "Lancero", "hp": 45.0, "atk": 5.0, "armor": 0.0, "range": 0.0, "cd": 1.5,
		"speed": 2.2, "sight": 7, "cost": {"comida": 35, "madera": 25}, "time": 15.0, "from": "cuartel",
		"bonus_vs": {"jinete": 12.0}, "desc": "Barato. Mucho daño contra jinetes."},
	"arquero": {"name": "Arquero", "hp": 32.0, "atk": 5.0, "armor": 0.0, "range": 6.0, "cd": 1.8,
		"speed": 2.0, "sight": 8, "cost": {"madera": 40, "oro": 30}, "time": 20.0, "from": "arqueria", "age": 2,
		"desc": "Ataca a distancia. Puede meterse en una torre de guardia y disparar desde ahí."},
	"jinete": {"name": "Jinete", "hp": 110.0, "atk": 9.0, "armor": 1.0, "range": 0.0, "cd": 1.6,
		"speed": 3.2, "sight": 8, "cost": {"comida": 80, "oro": 60}, "time": 26.0, "from": "establo", "age": 2,
		"desc": "Rápido y resistente. Débil contra lanceros."},
	"santo": {"name": "Santo", "hp": 30.0, "atk": 0.0, "armor": 0.0, "range": 0.0, "cd": 1.0,
		"speed": 1.8, "sight": 9, "cost": {"oro": 100}, "time": 30.0, "from": "monasterio", "age": 3, "civil": true,
		"heal": 1.0, "desc": "Cura a tus unidades cercanas. Crea reliquias en el monasterio y las lleva a la maravilla."},
	"ariete": {"name": "Ariete", "hp": 200.0, "atk": 28.0, "armor": 3.0, "range": 0.0, "cd": 3.0,
		"speed": 1.2, "sight": 5, "cost": {"madera": 160, "oro": 75}, "time": 35.0, "from": "taller", "age": 4,
		"siege": true, "only_buildings": true, "desc": "Tumba puertas, muros y edificios. No ataca a las unidades."},
	"catapulta": {"name": "Catapulta", "hp": 70.0, "atk": 26.0, "armor": 0.0, "range": 10.0, "cd": 5.0,
		"speed": 1.0, "sight": 10, "cost": {"madera": 200, "oro": 120}, "time": 40.0, "from": "taller", "age": 4,
		"siege": true, "splash": 1.4, "min_range": 3.0, "desc": "Lanza piedras muy lejos: daña en área y destroza edificios. No dispara de cerca."},
	"barco_pesca": {"name": "Barco pesquero", "hp": 60.0, "atk": 0.0, "armor": 0.0, "range": 0.0, "cd": 1.0,
		"speed": 2.4, "sight": 7, "cost": {"madera": 75}, "time": 20.0, "from": "muelle", "naval": true,
		"fisher": true, "civil": true, "desc": "Pesca en el mar y en las trampas para peces. Lleva el pescado al muelle y construye las trampas."},
	"barco_guerra": {"name": "Barco de guerra", "hp": 130.0, "atk": 6.0, "armor": 1.0, "range": 7.0, "cd": 2.0,
		"speed": 2.6, "sight": 9, "cost": {"madera": 110, "oro": 40}, "time": 28.0, "from": "muelle", "age": 2,
		"naval": true, "desc": "Dispara a barcos, unidades y edificios cerca del agua."},
}

## Edificios. size = lado en casillas. drop = recursos que acepta.
## Torre, muralla y puerta suben de nivel con mejoras (ver LEVELS).
const BUILDINGS := {
	"centro": {"name": "Centro urbano", "age": 3, "size": 4, "hp": 1500.0, "cost": {"madera": 275, "piedra": 100}, "time": 120.0,
		"sight": 10, "drop": ["comida", "madera", "oro", "piedra"], "pop": 5, "trains": ["aldeano"],
		"atk": 5.0, "range": 7.0, "cd": 2.0, "desc": "Edificio principal: recibe todos los recursos, entrena aldeanos, investiga mejoras y avanza de era. Da 5 de población. Un segundo centro se puede construir desde el nivel 3. Si te quedas sin centros, pierdes."},
	"casa": {"name": "Casa", "size": 2, "hp": 400.0, "cost": {"madera": 30}, "time": 20.0, "sight": 4, "pop": 5,
		"desc": "+5 de población máxima."},
	"maderero": {"name": "Campamento maderero", "size": 2, "hp": 500.0, "cost": {"madera": 100}, "time": 25.0,
		"sight": 5, "drop": ["madera"], "desc": "Recibe madera. Cerca de él se corta 25 % más rápido y rinde 15 % más."},
	"minero": {"name": "Campamento minero", "size": 2, "hp": 500.0, "cost": {"madera": 100}, "time": 25.0,
		"sight": 5, "drop": ["oro", "piedra"], "desc": "Recibe oro y piedra. Cerca de él se pica 25 % más rápido y rinde 15 % más."},
	"molino": {"name": "Molino", "size": 2, "hp": 500.0, "cost": {"madera": 100}, "time": 30.0,
		"sight": 5, "drop": ["comida"], "desc": "Recibe alimento. Permite granjas. Bayas y granjas cercanas rinden más."},
	"corral": {"name": "Corral", "size": 3, "hp": 350.0, "cost": {"madera": 80}, "time": 20.0, "sight": 3,
		"walkable": true,
		"desc": "Lleva aquí tus cabras y guajolotes (selecciónalos y clic derecho en el corral). Pastan y te dan alimento sin morir, hasta 6 por corral, y además engordan."},
	"granja": {"name": "Granja", "size": 2, "hp": 300.0, "cost": {}, "time": 8.0, "sight": 2,
		"walkable": true, "food": 250.0, "seed": true,
		"desc": "Ocupa 4 cuadros y gasta 1 siembra (se compra en el Centro). El granjero siembra, luego cosecha 250 de alimento. Si tienes siembras guardadas, se resiembra sola."},
	"muelle": {"name": "Muelle", "size": 3, "hp": 1000.0, "cost": {"madera": 150}, "time": 35.0, "sight": 6,
		"dock": true, "drop": ["comida"], "trains": ["barco_pesca", "barco_guerra"],
		"desc": "Se construye en la orilla. Entrena barcos pesqueros y de guerra, recibe el pescado y desde aquí se ponen las trampas para peces."},
	"trampa": {"name": "Trampa para peces", "size": 2, "hp": 250.0, "cost": {"madera": 90}, "time": 15.0, "sight": 2,
		"walkable": true, "water": true, "food": 450.0, "needs": "muelle", "builder": "barco_pesca", "hidden": true,
		"desc": "Va en el agua. Un barco pesquero la construye y la pesca: da 450 de alimento."},
	"cuartel": {"name": "Cuartel", "size": 3, "hp": 1200.0, "cost": {"madera": 150}, "time": 40.0, "sight": 6,
		"trains": ["guerrero", "lancero"], "desc": "Entrena guerreros y lanceros."},
	"arqueria": {"name": "Galería de tiro con arco", "age": 2, "size": 3, "hp": 1200.0, "cost": {"madera": 150}, "time": 40.0, "sight": 6,
		"trains": ["arquero"], "needs": "cuartel", "desc": "Entrena arqueros."},
	"establo": {"name": "Establo", "age": 2, "size": 3, "hp": 1200.0, "cost": {"madera": 150}, "time": 40.0, "sight": 6,
		"trains": ["jinete"], "needs": "cuartel", "desc": "Entrena jinetes."},
	"torre": {"name": "Puesto de avanzada", "size": 2, "hp": 500.0, "cost": {"madera": 25, "piedra": 25}, "time": 30.0,
		"sight": 11, "atk": 3.0, "range": 6.0, "cd": 2.5, "levels": "torre",
		"desc": "Vigía: ve muy lejos y lanza flechas débiles. Sube a torre de guardia con mejoras."},
	"muralla": {"name": "Empalizada", "size": 1, "hp": 300.0, "cost": {"madera": 4}, "time": 4.0, "sight": 2,
		"wall": true, "levels": "muralla", "desc": "Arrastra para trazar una línea de muro. Sube a muro de piedra con mejoras."},
	"puerta": {"name": "Portón de madera", "size": 1, "hp": 350.0, "cost": {"madera": 10}, "time": 6.0, "sight": 2,
		"wall": true, "gate": true, "levels": "puerta",
		"desc": "Va dentro del muro: tus unidades y las de tu equipo pasan, las enemigas no. Arrastra para poner varias."},
	"mercado": {"name": "Mercado", "age": 2, "size": 3, "hp": 1200.0, "cost": {"madera": 175}, "time": 50.0, "sight": 6,
		"market": true, "desc": "Compra y vende alimento, madera y piedra a cambio de oro. Los precios cambian con cada trato."},
	"herreria": {"name": "Herrería", "age": 2, "size": 3, "hp": 1200.0, "cost": {"madera": 150}, "time": 40.0, "sight": 6,
		"desc": "Investiga mejoras de ataque y armadura para tu ejército."},
	"monasterio": {"name": "Monasterio", "age": 3, "size": 3, "hp": 1500.0, "cost": {"piedra": 175, "oro": 50}, "time": 60.0,
		"sight": 7, "heal": 1.5, "trains": ["santo"],
		"desc": "Cura poco a poco a tus unidades cercanas. Entrena santos y, con un santo a su lado, crea reliquias."},
	"universidad": {"name": "Universidad", "age": 3, "size": 3, "hp": 1300.0, "cost": {"madera": 200, "piedra": 100}, "time": 60.0,
		"sight": 6, "desc": "Investiga mejoras de muros, torres y edificios."},
	"castillo": {"name": "Castillo", "age": 4, "size": 4, "hp": 4000.0, "cost": {"piedra": 650}, "time": 150.0,
		"sight": 11, "atk": 10.0, "range": 8.0, "cd": 1.2, "pop": 10,
		"desc": "Fortaleza de piedra: dispara a los enemigos y da 10 de población."},
	"taller": {"name": "Taller de maquinaria de asedio", "age": 4, "size": 3, "hp": 1300.0, "cost": {"madera": 200, "oro": 50}, "time": 50.0,
		"sight": 6, "trains": ["ariete", "catapulta"], "desc": "Construye arietes y catapultas."},
	"maravilla": {"name": "Maravilla", "age": 5, "size": 6, "hp": 6000.0, "cost": {"madera": 1000, "piedra": 1000, "oro": 1000}, "time": 400.0,
		"sight": 10, "wonder": true,
		"desc": "Lleva aquí 3 reliquias con tus santos. Con las 3 dentro empieza una cuenta atrás: si sigue en pie al terminar, ganas la partida."},
}

## Niveles de torre, muralla y puerta. El nivel lo dan las mejoras investigadas (tech).
## Cada nivel cambia nombre y números; lo que no dice, se toma del edificio.
const LEVELS := {
	"torre": [
		{"name": "Puesto de avanzada"},
		{"tech": "torre_guardia", "name": "Torre de guardia", "hp": 900.0, "atk": 6.0, "range": 7.0, "cd": 2.0, "garrison": 3, "sight": 10},
		{"tech": "torre_mejorada", "name": "Torre de guardia mejorada", "hp": 1400.0, "atk": 7.0, "range": 8.0, "cd": 1.8, "garrison": 6, "sight": 10},
		{"tech": "torre_bombarda", "name": "Torre bombarda", "hp": 1800.0, "atk": 20.0, "range": 9.0, "cd": 3.0, "garrison": 6, "splash": 1.5, "sight": 10},
	],
	"muralla": [
		{"name": "Empalizada"},
		{"tech": "muro_piedra", "name": "Muro de piedra", "hp": 900.0, "cost": {"piedra": 5}, "time": 6.0},
		{"tech": "muro_fortificado", "name": "Muro fortificado", "hp": 1600.0, "cost": {"piedra": 5}, "time": 6.0},
		{"tech": "muro_puas", "name": "Muro de púas", "hp": 1800.0, "cost": {"piedra": 6}, "time": 7.0, "thorns": 2.5},
	],
	"puerta": [
		{"name": "Portón de madera"},
		{"tech": "muro_piedra", "name": "Puerta de piedra", "hp": 1000.0, "cost": {"piedra": 10}, "time": 8.0},
		{"tech": "muro_fortificado", "name": "Puerta fortificada", "hp": 1700.0, "cost": {"piedra": 10}, "time": 8.0},
		{"tech": "muro_puas", "name": "Puerta de púas", "hp": 1900.0, "cost": {"piedra": 12}, "time": 9.0, "thorns": 2.5},
	],
}

## Mejoras que se investigan en un edificio ("at"). Una vez cada una.
## melee/ranged/armor/bld_hp: lo que suman. Las de torre y muro cambian el nivel (LEVELS).
const TECHS := {
	"muro_piedra": {"name": "Muro de piedra", "at": "centro", "age": 2, "cost": {"piedra": 150, "madera": 100}, "time": 40.0,
		"desc": "La empalizada pasa a muro de piedra y el portón a puerta de piedra (los que ya tienes también)."},
	"torre_guardia": {"name": "Torre de guardia", "at": "centro", "age": 2, "cost": {"madera": 100, "piedra": 100}, "time": 40.0,
		"desc": "Los puestos de avanzada pasan a torres de guardia: más vida y daño, y les caben 3 arqueros que disparan desde arriba."},
	"forja": {"name": "Forja", "at": "herreria", "age": 2, "cost": {"comida": 150, "oro": 50}, "time": 40.0, "melee": 1.0,
		"desc": "+1 de ataque a guerreros, lanceros y jinetes."},
	"arcos": {"name": "Arcos reforzados", "at": "herreria", "age": 2, "cost": {"comida": 100, "madera": 50}, "time": 40.0, "ranged": 1.0,
		"desc": "+1 de ataque a arqueros, torres y barcos de guerra."},
	"escudos": {"name": "Escudos de cuero", "at": "herreria", "age": 2, "cost": {"comida": 100, "oro": 40}, "time": 40.0, "armor": 1.0,
		"desc": "+1 de armadura a tu ejército."},
	"forja2": {"name": "Armas de obsidiana", "at": "herreria", "age": 3, "cost": {"comida": 220, "oro": 120}, "time": 55.0, "melee": 1.0, "needs": "forja",
		"desc": "+1 más de ataque cuerpo a cuerpo."},
	"arcos2": {"name": "Flechas de obsidiana", "at": "herreria", "age": 3, "cost": {"comida": 200, "oro": 100}, "time": 55.0, "ranged": 1.0, "needs": "arcos",
		"desc": "+1 más de ataque a distancia."},
	"escudos2": {"name": "Armadura de algodón", "at": "herreria", "age": 3, "cost": {"comida": 200, "oro": 100}, "time": 55.0, "armor": 1.0, "needs": "escudos",
		"desc": "+1 más de armadura a tu ejército."},
	"muro_fortificado": {"name": "Muro fortificado", "at": "universidad", "age": 3, "cost": {"piedra": 250, "oro": 100}, "time": 60.0, "needs": "muro_piedra",
		"desc": "Muros y puertas de piedra pasan a fortificados: casi el doble de vida."},
	"torre_mejorada": {"name": "Torre de guardia mejorada", "at": "universidad", "age": 3, "cost": {"piedra": 200, "oro": 100}, "time": 60.0, "needs": "torre_guardia",
		"desc": "Las torres de guardia duran más, disparan más lejos y les caben 6 arqueros."},
	"albanileria": {"name": "Albañilería", "at": "universidad", "age": 3, "cost": {"madera": 150, "piedra": 150}, "time": 50.0, "bld_hp": 0.15,
		"desc": "+15 % de vida a todos tus edificios."},
	"muro_puas": {"name": "Muro de púas", "at": "universidad", "age": 5, "cost": {"piedra": 400, "oro": 200}, "time": 70.0, "needs": "muro_fortificado",
		"desc": "Muros y puertas lastiman poco a poco a los enemigos que se les pegan."},
	"torre_bombarda": {"name": "Torre bombarda", "at": "universidad", "age": 5, "cost": {"piedra": 300, "oro": 300}, "time": 70.0, "needs": "torre_mejorada",
		"desc": "Las torres dejan las flechas: lanzan bombas que dañan en área (los arqueros de adentro siguen disparando)."},
}

## Reliquias y maravilla.
const RELIC_COST := {"oro": 200}
const RELIC_TIME := 60.0          # segundos que tarda el santo en crearla
const WONDER_RELICS := 3          # reliquias dentro para empezar la cuenta atrás
const WONDER_TIME := 360.0        # segundos de cuenta atrás para ganar

## Eras (5). Para avanzar: pagar en el Centro y cumplir los requisitos de edificios.
## req: Array de [lista de edificios aceptados, cantidad, texto]
## Al avanzar cambian el vestuario de las unidades y el aspecto de los edificios.
const AGES := [
	{"name": "Aldea Primitiva"},
	{"name": "Era Tribal", "cost": {"comida": 500}, "time": 60.0,
		"req": [[["casa"], 2, "2 casas"], [["maderero", "minero", "molino"], 2, "2 campamentos o molinos"]]},
	{"name": "Era de Piedra", "cost": {"comida": 800, "oro": 200}, "time": 90.0,
		"req": [[["cuartel", "arqueria", "establo"], 2, "2 edificios militares"], [["mercado"], 1, "1 mercado"], [["granja"], 4, "4 granjas"]]},
	{"name": "Era de los Metales", "cost": {"comida": 1000, "oro": 600}, "time": 110.0,
		"req": [[["monasterio"], 1, "1 monasterio"], [["torre"], 2, "2 torres"], [["centro"], 2, "2 centros"]]},
	{"name": "Era Imperial", "cost": {"comida": 1500, "oro": 1000, "piedra": 300}, "time": 140.0,
		"req": [[["castillo"], 1, "1 castillo"], [["casa"], 12, "12 casas"], [["monasterio"], 2, "2 monasterios"]]},
]
const AGE_HP := 0.2   # +20 % de vida a los edificios por cada era


## Nivel de torre/muralla/puerta de un jugador (0 = el básico).
static func level_of(kind: String, techs: Dictionary) -> int:
	var lv: String = BUILDINGS.get(kind, {}).get("levels", "")
	if lv == "":
		return 0
	var n := 0
	var list: Array = LEVELS[lv]
	for i in range(1, list.size()):
		if techs.has(list[i]["tech"]):
			n = i
	return n


## Dato de un edificio según el nivel del jugador (si el nivel no lo cambia, el del edificio).
static func bstat(kind: String, techs: Dictionary, key: String, default_v = null):
	var d: Dictionary = BUILDINGS[kind]
	var lv: String = d.get("levels", "")
	if lv != "":
		var l: Dictionary = LEVELS[lv][level_of(kind, techs)]
		if l.has(key):
			return l[key]
	return d.get(key, default_v)


## Suma de un efecto de las mejoras investigadas (melee, ranged, armor, bld_hp).
static func tech_sum(techs: Dictionary, key: String) -> float:
	var s := 0.0
	for t in techs:
		s += float(TECHS.get(t, {}).get(key, 0.0))
	return s

## Civilizaciones: se cargan de data/civs/*.json (ver docs/CIVILIZACIONES.md).
static var CIVS: Dictionary = _load_civs()
static var CIV_ORDER: Array = _civ_order()


static func _load_civs() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://data/civs")
	if dir == null:
		return out
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")
		if not fname.ends_with(".json"):
			continue
		var txt := FileAccess.get_file_as_string("res://data/civs/" + fname)
		var d = JSON.parse_string(txt)
		if d is Dictionary:
			out[d["id"]] = d
	return out


static func _civ_order() -> Array:
	var ids := CIVS.keys()
	ids.sort_custom(func(a, b) -> bool: return CIVS[a].get("order", 99) < CIVS[b].get("order", 99))
	return ids


static func civ_mod(civ: String, key: String, default_v):
	if not CIVS.has(civ):
		return default_v
	return CIVS[civ].get("mods", {}).get(key, default_v)


## Puntos de ventaja (+) y desventaja (-). Debe quedar cerca de 0.
static func civ_score(civ: String) -> float:
	var m: Dictionary = CIVS[civ].get("mods", {})
	var s := 0.0
	for r in m.get("gather", {}):
		s += (float(m["gather"][r]) - 1.0) * 10.0
	s += (1.0 - float(m.get("mil_train", 1.0))) * 10.0
	s += float(m.get("mil_atk", 0.0)) * 1.5
	s += (float(m.get("mil_hp", 1.0)) - 1.0) * 10.0
	s += (float(m.get("bld_hp", 1.0)) - 1.0) * 6.0
	s += (float(m.get("build_speed", 1.0)) - 1.0) * 8.0
	s += (float(m.get("villager_speed", 1.0)) - 1.0) * 8.0
	s += float(m.get("archer_range", 0.0)) * 1.5
	s += float(m.get("tower_atk", 0.0)) * 0.5
	for k in m.get("cost_mult", {}):
		s += (1.0 - float(m["cost_mult"][k])) * (3.0 if k == "casa" else 6.0)
	for r in m.get("start", {}):
		s += float(m["start"][r]) / 100.0 * 0.5
	return s


const DIFFICULTY := {
	"facil": {"name": "Fácil", "gather": 0.75, "villagers": 14, "attack_at": 720.0, "army": 6, "think": 2.0},
	"normal": {"name": "Normal", "gather": 1.0, "villagers": 24, "attack_at": 480.0, "army": 10, "think": 1.2},
	"dificil": {"name": "Difícil", "gather": 1.15, "villagers": 34, "attack_at": 390.0, "army": 14, "think": 0.8},
	"experto": {"name": "Experto", "gather": 1.3, "villagers": 45, "attack_at": 330.0, "army": 18, "think": 0.5},
}
const DIFF_ORDER := ["facil", "normal", "dificil", "experto"]

const MAP_SIZES := {"pequeno": 120, "mediano": 160, "grande": 220}

## Tipos de mapa. Todos se generan al azar en cada partida (nunca sale el mismo);
## el tipo cambia el carácter: cuánto mar, mesetas, lagos, selva o desierto.
## seas: esquinas con mar (-1 = según el tamaño); plateaus/lakes: multiplicador;
## bias: -1 más selva … +1 más desierto.
const MAP_TYPES := {
	"azar": {"name": "Al azar", "desc": "Cada partida, un tipo de mapa distinto."},
	"valle": {"name": "Valle", "desc": "Equilibrado: un poco de todo.",
		"seas": -1, "sea_r": 0.27, "plateaus": 1.0, "lakes": 1.0, "bias": 0.0},
	"costa": {"name": "Costa", "desc": "Mucho mar en las orillas, playas y acantilados.",
		"seas": 3, "sea_r": 0.31, "plateaus": 0.7, "lakes": 0.5, "bias": 0.0},
	"mesetas": {"name": "Mesetas", "desc": "Muchas mesetas con barrancos y pocas subidas.",
		"seas": 0, "plateaus": 2.6, "lakes": 0.6, "bias": 0.1},
	"lagos": {"name": "Tierra de lagos", "desc": "Lagos por todas partes y un río.",
		"seas": 0, "plateaus": 0.6, "lakes": 3.0, "bias": -0.1},
	"selva": {"name": "Selva", "desc": "Selva espesa: mucha madera y caminos angostos.",
		"seas": 1, "sea_r": 0.25, "plateaus": 0.8, "lakes": 1.0, "bias": -0.45},
	"desierto": {"name": "Desierto", "desc": "Poca madera, oasis y mesetas de roca.",
		"seas": 0, "plateaus": 1.5, "lakes": 0.7, "bias": 0.5},
	"mar_interior": {"name": "Mar interior", "desc": "Un mar en el centro: se pelea por las orillas.",
		"seas": 0, "plateaus": 0.8, "lakes": 0.4, "bias": 0.0, "inner_sea": true, "river": false},
}
const MAP_TYPE_ORDER := ["azar", "valle", "costa", "mesetas", "lagos", "selva", "desierto", "mar_interior"]


static func cost_of(kind: String, civ: String) -> Dictionary:
	var c: Dictionary
	if UNITS.has(kind):
		c = UNITS[kind]["cost"].duplicate()
	elif TECHS.has(kind):
		return TECHS[kind]["cost"].duplicate()
	else:
		c = BUILDINGS[kind]["cost"].duplicate()
	var mult: Dictionary = civ_mod(civ, "cost_mult", {})
	if mult.has(kind):
		for r in c:
			c[r] = roundi(c[r] * float(mult[kind]))
	return c


static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RES:
		if cost.has(r):
			parts.append("%d %s" % [cost[r], Lang.t(RES_NAMES[r]).to_lower()])
	return ", ".join(parts)
