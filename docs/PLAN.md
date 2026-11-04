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
  Mercado, Templo (cura), Castillo.
- Granjas: la siembra se compra en el Centro (se pueden guardar varias); colocar una granja gasta
  1 siembra; el granjero siembra y luego cosecha 250; al agotarse se resiembra sola si hay siembras.
- Población: empiezas con 5 y tope 5; cada casa +5 (máx. 200). Los aldeanos se compran en el Centro.
- 5 eras (Aldea, Señorío, Ciudad-Estado, Reino, Imperio): cuestan recursos y piden edificios.
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
