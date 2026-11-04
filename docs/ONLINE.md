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
