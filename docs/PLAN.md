# Conquista: plan y estado

Estrategia en tiempo real en 3D "plano" (cámara a 3/4, figuras sencillas), en Godot 4.7
(GDScript, renderizador Compatibility), para PC/Steam (.exe), Web y celular/tablet.
El nombre "Conquista" es provisional.

## Cómo probar

- Abrir `project.godot` con Godot 4.7 y dar Play (F5).
- Pruebas sin pantalla: `Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_check.tscn`
- Opciones de desarrollo (después de `--`): `--reveal` (sin niebla), `--fast=300` (adelanta 300 s),
  `--look=1` (cámara en el centro del jugador 1), `--shot=archivo.png` (captura y sale).

## Fase 1: hecha

- Mapa por cuadros (1 cuadro = 1 casilla): pradera, selva, desierto, lagos, río con vados entre
  dos equipos, bosques, minas de oro/piedra, bayas, peces, cabras/venados/guajolotes.
- Niebla de guerra: negro sin explorar, oscuro explorado, normal a la vista. El enemigo solo se ve
  dentro de la visión de tu equipo.
- Cámara: WASD/bordes, Q/E o botón central para girar, rueda para acercar; 2 dedos en táctil.
- Aldeanos: recolectan hasta 10, lo llevan al edificio más cercano que lo acepte y regresan.
  Si se acaba, buscan el siguiente igual en un radio de 14; si no hay, se quedan quietos con "!"
  y avisan. Caza: la cabra se mueve y huye, muere (animación), queda el cuerpo y se achica al
  recolectar. Los árboles caen al empezar a talarlos.
- Recursos: Alimento, Madera, Oro, Piedra.
- Edificios por cuadros con vista previa verde/roja y andamio mientras se construyen:
  Centro 4×4, Casa 2×2 (+5 población), Campamento maderero y minero (+25 % velocidad y +15 % de
  producto en su radio), Molino, Granja 2×2, Cuartel, Arquería, Establo, Torre, Muralla (arrastrar),
  Mercado, Monasterio (cura; antes Templo), Castillo. Lista completa por fase abajo.
- Granjas: la siembra se compra en el Centro (se pueden guardar varias); colocar una granja gasta
  1 siembra; el granjero siembra y luego cosecha 250; al agotarse se resiembra sola si hay siembras.
- Población: empiezas con 5 y tope 5; cada casa +5 (máx. 200). Los aldeanos se compran en el Centro.
- 5 eras o niveles (I Aldea Primitiva, II Era Tribal, III Era de Piedra, IV Era de los Metales, V Era Imperial): cuestan recursos y piden edificios.
  Cambian el vestuario (taparrabo → túnica → penachos → oro) y los edificios (paja → adobe →
  piedra → estuco).
- Combate: vida, ataque, armadura, alcance, flechas; torres/centro/castillo disparan.
- Victoria: pierde quien se queda sin Centros. Si cae el principal, otro centro toma su lugar.
- Contra bots: hasta 8 jugadores (1v1, 2v2, 3v3, 4v4, 1v3, todos contra todos), 4 dificultades.
- 5 civilizaciones en `data/civs/*.json` con ventajas y desventajas balanceadas
  (ver `docs/CIVILIZACIONES.md`).
- Minimapa en rombo abajo a la derecha; en táctil, botón "Mapa" a pantalla completa.

## Fase 2: siguiente

- Barcos: muelle, barco de pesca, de transporte y de guerra; mares (mapa costero), lagunas.
- Puertas en murallas (solo pasan tus unidades) y castillos con unidad única por civilización.
- Controles táctiles completos (tocar = orden, mantener = menú), interfaz más grande en celular.
- Más arte: modelos 3D propios (low-poly), iconos de botones, sonidos y música.
- Exportar: Windows (.exe, después Steam), Web y Android.

## Fase 3: en línea

- 1v1, 2v2 y 4v4 en línea. La simulación ya avanza en pasos fijos de 50 ms y todas las órdenes
  pasan por `Game.command_units` / `train` / `place_building`, lo que permite el modelo
  "lockstep" (cada jugador manda solo sus órdenes).

## Temporadas de civilizaciones

- Españoles, incas, etc., y después temporadas de fantasía (orcos...). Todas con las mismas reglas;
  cambian modificadores, aspecto (`look.style`) y unidad única. Ver `docs/CIVILIZACIONES.md`.

## Terreno y tipos de mapa (2026-11-04)
- Terreno en bloques con altura (MapData.height, LEVEL_H = 2.2): mesetas con barrancos (suelo CLIFF, no se camina) y 2 rampas cada una; mar en esquinas con playa ancha; acantilados donde una meseta toca el agua; agua animada (TerrainView, turquesa en la orilla, azul hondo, espuma).
- Las figuras se paran a la altura del suelo (MapData.ground_y); un edificio solo se pone si todas sus casillas están a la misma altura.
- Tipos (Defs.MAP_TYPES): Al azar (por defecto), Valle, Costa, Mesetas, Tierra de lagos, Selva, Desierto, Mar interior. El terreno siempre se genera al azar con la semilla de la partida; el tipo cambia el carácter. En línea el anfitrión elige el tipo; con rango siempre "Al azar".
- Desarrollo: `-- --seed=N --tipo=costa --mapinfo --at=x,y,dist --reveal --shot=archivo.png`.
- Pendiente: barcos (pesca, guerra, transporte) para aprovechar el mar.

## Pastoreo (2026-11-04, reglas del usuario)
- Solo un aldeano puede apropiarse de una cabra o guajolote (Defs.ANIMALS "tame"): clic derecho = pastorear (cursor de cayado), 10 s seguidos (Defs.HERD_TIME) junto al animal, que se queda quieto. Si se aleja, recibe otra orden o lo atacan, vuelve a empezar. Acercarse no basta.
- Un aldeano enemigo te lo roba igual (10 s seguidos). Si dos pueblos lo pastorean a la vez, nadie avanza.
- Corral (3x3, 80 de madera, pestaña Recursos): hasta 6 animales pastan, dan 0.2 de alimento/s cada uno sin morir y engordan hasta 1.6x su carne. Al apropiarte de uno, si tienes corral cerca se va solo. Con un aldeano, clic derecho en tu animal = sacrificarlo.
- Bots: construyen corral si hay animales cerca, mandan un aldeano a pastorear (uno a la vez) y llevan sus animales al corral.

## Edificios por fase, mejoras, barcos y maravilla (2026-11-05, reglas del usuario)

Pestañas de construcción: **Recursos** (siembra, granja, molino, corral, campamentos, muelle),
**Pueblo** (casa, centro urbano, mercado, herrería, universidad, monasterio, maravilla) y
**Guerra** (cuartel, galería de tiro con arco, establo, taller de asedio, castillo, torre, muro, puerta).

| Fase | Se puede construir / pasa |
|---|---|
| 1 Aldea Primitiva | Centro urbano (solo el inicial), casa, cuartel, muelle, puesto de avanzada, empalizada, portón de madera, campamentos, molino, granja, corral |
| 2 Era Tribal | Galería de tiro con arco, establo, mercado, herrería, trampa para peces (desde el muelle). Mejoras en el Centro: muro de piedra (empalizada → muro, portón → puerta de piedra) y torre de guardia (puesto → torre, caben 3 arqueros) |
| 3 Era de Piedra | Segundo centro urbano, monasterio (antes templo), universidad. Mejoras en la universidad: muro fortificado, torre de guardia mejorada (más vida, 6 arqueros), albañilería |
| 4 Era de los Metales | Castillo, taller de asedio (ariete y catapulta) |
| 5 Era Imperial | Maravilla. Mejoras en la universidad: muro de púas (daña a los pegados) y torre bombarda (daño en área) |

- Torre, muralla y puerta son un solo edificio con niveles (`Defs.LEVELS`): las mejoras
  (`Defs.TECHS`, investigadas una vez, en `PlayerState.techs`) suben de nivel a los que ya existen
  y a los nuevos (nombre, vida, ataque, costo). Las casas no cambian con mejoras.
- Herrería: forja, arcos reforzados, escudos (nivel 2) y su segunda versión (nivel 3).
- Puertas: `MapData.gate_team` + una rejilla de caminos por equipo (`team_grids`); solo pasa el
  equipo dueño. Las unidades buscan caminos con `Unit.nav()`.
- Agua: rejilla aparte (`MapData.water`, `WATER_NAV`). El muelle va en la orilla (3+ casillas de
  agua junto). Barco pesquero: pesca bancos de peces y trampas, lleva el pescado al muelle y construye
  las trampas (450 de alimento, se acaban). Barco de guerra: dispara (alcance 7). Por tierra cuerpo a
  cuerpo no se le puede pegar a un barco.
- Arqueros en torres: clic derecho en tu torre de guardia; cada uno dispara una flecha más.
  "Sacar arqueros" en la torre. Si la torre cae, salen.
- Asedio: ariete (solo edificios, incluso muros y puertas), catapulta (alcance 10, no dispara de
  cerca, daño en área).
- Reliquias y maravilla: el santo (monasterio, nivel 3) crea una reliquia en el monasterio (200 de
  oro, 60 s, el santo junto al monasterio). Aparece en un lugar al azar del mapa (igual en todos los
  equipos en línea: `Game.sim_rng`). Cualquier santo la recoge; si muere, cae al suelo. Llevada a la
  maravilla (una por jugador) queda guardada; si la maravilla cae, las reliquias caen alrededor.
  Con 3 reliquias empieza una cuenta atrás de 6 min (`Defs.WONDER_TIME`) que ven todos; al terminar
  gana ese equipo.
- Bots: herrería, universidad, monasterio, taller y mejoras de la herrería y torres; todavía no usan
  barcos, muros ni maravilla.
- Pruebas: `tests/rasgos_check.tscn` (puertas, torres, mejoras, barcos, asedio, reliquias, maravilla,
  bots largos). Desarrollo: `--era=5 --techs=a,b --edificio=maravilla --unidad=catapulta --reliquia`.
