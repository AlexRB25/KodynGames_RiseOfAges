# Monedas, gemas, Game Pass y Tienda

## Cómo funciona

- **Monedas**: se ganan jugando y en el Game Pass. Sirven en la Tienda.
- **Gemas (diamantes)**: se compran con dinero (paquetes) y unas cuantas salen en el pase.
  Sirven para el **Game Pass Premium** y para artículos especiales de la Tienda.
- **Experiencia de temporada (xp)**: se gana en cada partida y **va aparte de los puntos de
  rango**. Cada 500 xp subes un nivel del pase (50 niveles por temporada de 8 semanas).
  - Con rango: +200 al ganar, +80 al perder (la da el servidor; quien abandona no gana nada).
  - Contra bots: +100 al ganar, +40 al perder. Solo partidas de 5 min o más, máximo 8 al día
    y no una enseguida de otra (para que no se pueda inflar).
  - Monedas por partida: con rango 60/20, contra bots 25/10.
  - Se cambia en `roa_match_prize`, `roa_bot_daily` y `roa_bot_minutes` (supabase/temporadas.sql).
- **Game Pass**: la línea de la temporada con dos filas:
  - **Gratis** (todos): niveles pares: monedas, gemas (25 en 10/20/30/40), títulos,
    imágenes de aldeano maya y estandartes.
  - **Premium**: todos los niveles: más monedas, 400 gemas en total, imágenes de humano y
    orco, estandartes épicos, títulos y el aldeano maya legendario en el 50.
- **Game Pass Premium**: cuesta **500 gemas** (≈ el paquete de 4.99 USD) y da la fila
  premium + **20 % más de xp** el resto de la temporada. Lo ya alcanzado se reclama enseguida.
- **Jugar en línea es gratis** para todos; no hace falta el pase. (Anuncios: por decidir.)
- **Tienda**: estandartes, títulos e imágenes con monedas o con gemas, y los paquetes de gemas.
- **Perfil** (tocar tu tarjeta en el menú): imagen de perfil, estandarte (fondo de la
  tarjeta) y título. Se ve en el menú; en las partidas se agregará después.
- **Civilizaciones de temporada**: si en `roa_items` hay una `civ` que no es `free`, solo la
  puede usar quien la tiene (el menú la muestra con candado y el servidor la revisa en el rango).

Todo lo decide Supabase: el juego solo muestra (`roa_status`) y pide acciones. Nadie puede
darse monedas, gemas, xp ni el pase desde el juego.

## Paquetes de gemas (dinero real)

| Paquete | Gemas | USD | MXN | EUR | BRL | COP |
|---|---|---|---|---|---|---|
| gemas_100 | 100 | 0.99 | 19 | 0.99 | 4.90 | 3,900 |
| gemas_500 | 500 + 50 | 4.99 | 99 | 4.99 | 24.90 | 19,900 |
| gemas_1000 | 1000 + 200 | 9.99 | 199 | 9.99 | 49.90 | 39,900 |
| gemas_2000 | 2000 + 600 | 19.99 | 399 | 19.99 | 99.90 | 79,900 |

La moneda sale del país del idioma del jugador; si no está en `roa_gem_prices`, se cobra en
USD. Los precios se cambian en esa tabla (Table Editor de Supabase).

Cobro: el juego llama al servidor de Render (`POST /api/checkout`), que crea el pago en
**Stripe Checkout** con el precio de la tabla. Al pagar, Stripe avisa a `POST /api/stripe`;
el servidor revisa la firma y entrega las gemas (`roa_grant_gems`, una sola vez por pago,
queda en `kodyn_purchases` con `game = 'rise_of_ages'`). En la web el pago abre en la misma
pestaña y regresa al juego (`?pago=ok`); en PC se abre el navegador y las gemas aparecen solas.

## Para activarlo (una vez)

1. **Supabase → SQL Editor**: pega `supabase/temporadas.sql` → Run (después de
   `esquema.sql`). Crea la temporada 1 empezando ese día. Se puede volver a correr.
2. **Stripe** (la misma cuenta de Zombie War) → Developers → Webhooks → **Add endpoint**:
   - URL: `https://conquista-srzq.onrender.com/api/stripe`
   - Eventos: `checkout.session.completed` y `checkout.session.async_payment_succeeded`
   - Copia el **Signing secret** (`whsec_…`).
3. **Render → servicio conquista → Environment**:
   - `STRIPE_SECRET_KEY` = la clave secreta de Stripe (`sk_live_…`, o `sk_test_…` para probar)
   - `STRIPE_WEBHOOK_SECRET` = el `whsec_…` del paso 2
4. Probar con la clave de prueba y la tarjeta `4242 4242 4242 4242`.

Mientras no se corra el SQL, el juego dice "La tienda y el Game Pass se están preparando".
Sin las claves de Stripe, la pestaña Gemas dice "La tienda aún no está lista".

## Nueva temporada

```sql
insert into roa_seasons (id, name, starts_at, ends_at)
values ('t2', 'Temporada 2: …', '2027-01-01', '2027-02-26');
```

Después sus premios en `roa_season_rewards` (copia los `insert … select` de la temporada 1
cambiando 't1' por 't2'). Lo nuevo (imágenes, estandartes, títulos, civilizaciones,
vestimentas) se agrega primero a `roa_items`.

## Agregar cosas

- **Imagen de perfil**: el PNG en `assets/…` y en `roa_items` con `kind = 'imagen'`,
  `detail = {"file": "ruta/dentro/de/assets.png"}`.
- **Estandarte**: `kind = 'estandarte'`, `detail = {"bg": "#…", "edge": "#…", "mark": "#…"}`.
- **Título**: `kind = 'titulo'` (el nombre es el título).
- **Civilización**: `kind = 'civ'`, `detail = {"civ": "inca"}` (el id de `data/civs/`).
- **Vestimenta (skin)**: `kind = 'skin'`, `detail = {"civ": "maya", "unit": "aldeano"}`.
  El juego todavía no las dibuja: falta el arte.
- Para venderlo: una fila en `roa_shop` con `price_coins` **o** `price_gems`.
- Los nombres se traducen: agrégalos a `data/idiomas/en.json` y `pt.json`.

## Pruebas y desarrollo

- `--demo-tienda`: datos de ejemplo sin internet (las acciones se simulan).
- `--abrir=pase|tienda|gemas|perfil`: abre esa página al iniciar. `--moneda=USD` fuerza la moneda.
- En una partida: `--rendirse` muestra la pantalla final (con el premio).
- El SQL se probó con PGlite (compras, premios, topes y permisos); `server/pagos.js` con
  Stripe simulado (firma, pago duplicado, pagos de otros juegos).
