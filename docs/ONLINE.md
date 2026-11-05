# En línea y Render

## Cómo funciona

- `server/server.js` (Node + `ws`) hace dos cosas en el mismo puerto:
  - Sirve `server/public/`: la landing (`index.html`) y el juego web (`jugar/`, exportado por Godot).
  - Salas en línea por WebSocket en `/ws`.
- Modelo **lockstep**: cada 100 ms el servidor manda un "turno" con las órdenes de todos.
  Cada jugador simula lo mismo (pasos fijos de 50 ms, sin azar no sembrado). Cada 50 turnos los
  clientes mandan una suma de control; si no coincide, el servidor avisa "desincronización".
- Mejor jugar todos en la versión web (mismo motor = mismos cálculos). Mezclar .exe y web podría
  desincronizarse por diferencias mínimas de decimales.

## Actualizar el juego web

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" server/public/jugar/index.html
```
Después: commit + push; Render vuelve a desplegar solo.

## Probar en la PC

```
cd server && npm install && node server.js      # http://localhost:8080
```
Prueba automática de red (2 clientes sin pantalla, con el servidor corriendo):
```
godot --headless --path . res://tests/net_check.tscn -- --server=ws://127.0.0.1:8080/ws --role=host --dir=CARPETA
godot --headless --path . res://tests/net_check.tscn -- --server=ws://127.0.0.1:8080/ws --role=guest --dir=CARPETA
```
Los dos deben imprimir el mismo `hash` en el paso 600.

## Render (primera vez)

1. En render.com: New → Blueprint → conectar el repositorio de GitHub. Toma `render.yaml`.
2. Plan free: el servicio se duerme tras 15 min sin visitas; la primera visita tarda ~1 min en despertar.
3. La URL queda tipo `https://conquista.onrender.com` (si el nombre está libre). Si cambia, actualizar
   `DEFAULT_SERVER` en `scripts/net/net.gd` (solo lo usa la versión .exe; la web usa su propia dirección).

## Partidas con rango (emparejar por nivel)

- Menú → **Jugar con rango (en línea)** → nombre, civilización y **Buscar 1 vs 1 / 2 vs 2 / 4 vs 4**.
- El servidor (`server/server.js`, sección "partidas con rango") revisa la cola cada 2 s. Toma al que lleva más tiempo esperando y le junta a los más cercanos en puntos. Si solo hay jugadores de otro nivel, se juega igual. Los equipos se arman parejos (serpiente A B B A).
- **Puntos:** ganar = +20, más o menos hasta 10 según la diferencia con el rival (ganarle a alguien más fuerte da más). Perder = −15, más o menos hasta 8. Abandonar = derrota y −5 extra. Nunca baja de 0. **Nivel = 1 + puntos / 100.**
- **Fin de partida:** cada cliente avisa qué equipo ganó (`over`). Todos simulan lo mismo, así que deben coincidir; si no coinciden, la partida no cuenta. Si alguien se sale y los que quedan son de un solo equipo, ese equipo gana por abandono. En el juego también existe **Rendirse** (menú de pausa).
- Prueba: con el servidor corriendo, en dos terminales:
  `godot --headless --path . res://tests/ranked_check.tscn -- --server=ws://127.0.0.1:8080/ws --role=a --name=Ana`
  `godot --headless --path . res://tests/ranked_check.tscn -- --server=ws://127.0.0.1:8080/ws --role=b --name=Beto`

### Cuentas: el mismo Supabase que Zombie War (Kodyn Games)

Mismo login, misma tabla común `kodyn_profiles` (nombre). Todo lo de este juego lleva el prefijo `roa_` y **sus puntos no se mezclan** con los de Zombie War (`zm_`). `roa_played_zombie_war(id)` ya dice si esa cuenta jugó Zombie War, para la recompensa del ecosistema (por definir).

Sin configurar nada funciona en **modo prueba**: el servidor guarda los puntos en memoria por nombre y se borran al reiniciar.

Para activarlo de verdad:
1. Supabase → SQL Editor → pega `supabase/esquema.sql` → Run. Se puede volver a correr y no toca nada de Zombie War.
2. `data/online.json`: `supabase_url` y `supabase_anon_key` (la clave pública **anon**, la misma de Zombie War). Volver a exportar la Web.
3. Render → servicio → Environment: `SUPABASE_URL` y `SUPABASE_SERVICE_KEY` (la clave **service_role**; solo va en el servidor, nunca en el juego).

Los jugadores entran como invitados automáticamente. En la pantalla de rango pueden guardar su progreso con correo, o entrar con su cuenta de Kodyn Games.
