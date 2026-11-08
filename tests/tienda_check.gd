extends Node
## Acciones nuevas de la tienda y el pase en modo demostración (sin internet):
## godot --headless --path . res://tests/tienda_check.tscn -- --demo-tienda

var fails := 0


func check(c: bool, msg: String) -> void:
	print(("OK   " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _ready() -> void:
	check(Economy.demo, "modo demostración")
	var c0 := Economy.coins()
	check(Economy.gift_ready() and await Economy.claim_gift() == "", "se reclama el regalo del día")
	check(Economy.coins() == c0 + Economy.gift_coins(), "el regalo suma %d monedas" % Economy.gift_coins())
	check(await Economy.claim_gift() != "", "el regalo no se reclama dos veces")
	var g0 := Economy.gems()
	c0 = Economy.coins()
	check(await Economy.buy_coins("monedas_1000") == "", "se cambian gemas por monedas")
	check(Economy.gems() == g0 - 60 and Economy.coins() == c0 + 1000, "60 gemas -> 1000 monedas")
	check(await Economy.buy_coins("monedas_100000") != "", "sin gemas suficientes no se cambia")
	var t0 := Economy.tier()
	g0 = Economy.gems()
	check(await Economy.skip_tier() == "", "se salta un nivel del pase")
	check(Economy.tier() == t0 + 1 and Economy.gems() == g0 - Economy.skip_gems(), "nivel %d -> %d por %d gemas" % [t0, Economy.tier(), Economy.skip_gems()])
	g0 = Economy.gems()
	check(await Economy.buy_item("est_jaguar") == "" and Economy.owns("est_jaguar"), "se compra una oferta del día")
	check(Economy.gems() == g0 - 225, "con el precio de oferta (225 en vez de 300)")
	print("RESULTADO: %s (%d fallos)" % ["BIEN" if fails == 0 else "MAL", fails])
	get_tree().quit(1 if fails > 0 else 0)
