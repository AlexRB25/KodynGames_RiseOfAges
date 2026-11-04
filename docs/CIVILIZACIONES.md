# Civilizaciones

Cada civilización es un archivo `data/civs/<id>.json`. Para agregar una nueva (españoles,
incas, orcos...) basta con crear otro archivo: el menú y el juego la toman sola.

```json
{
 "id": "inca", "order": 10, "name": "Incas", "season": "andes",
 "desc": "Texto que ve el jugador con sus ventajas y desventajas.",
 "mods": { ... },
 "look": {"skin": [r, g, b], "style": "mesoamerica"}
}
```

Todas juegan con las mismas reglas, edificios y recursos. Solo cambian los modificadores:

| mod | qué hace | ejemplo | puntos |
|---|---|---|---|
| gather | multiplica la recolección de cada recurso | {"oro": 1.2} | +2 por cada +20 % |
| mil_train | tiempo de entrenamiento militar | 0.8 | +2 (20 % más rápido) |
| mil_atk | ataque extra de militares | 1 | +1.5 por punto |
| mil_hp | vida de militares | 0.9 | -1 |
| bld_hp | vida de edificios | 1.15 | +0.9 |
| build_speed | velocidad de construcción | 0.85 | -1.2 |
| villager_speed | velocidad de aldeanos | 0.95 | -0.4 |
| archer_range | alcance extra de arqueros | 1 | +1.5 |
| tower_atk | ataque extra de torres | 2 | +1 |
| cost_mult | multiplica costos de unidades/edificios | {"casa": 0.83} | +0.06 por cada 1 % en casa |
| start | recursos extra al empezar | {"madera": 50} | +0.5 por cada 100 |

**Balance:** la suma de puntos (`Defs.civ_score`) de cada civilización debe quedar entre -1 y +1:
lo que gana en algo lo pierde en otra cosa. `tests/sim_check` falla si alguna se sale.

`look.style` decide el vestuario y los edificios (por ahora solo "mesoamerica"; después
"europa", "andes", "orco"...). `season` agrupa las civilizaciones por temporada.
