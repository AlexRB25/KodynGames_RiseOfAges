// Compra de gemas con Stripe (lo usa server.js).
//   POST /api/checkout   (Authorization: Bearer <sesión del jugador>, {pack, currency})
//        -> {url} de Stripe Checkout. El precio lo pone el servidor (roa_gem_prices).
//   POST /api/stripe     aviso de Stripe (checkout.session.completed / async_payment_succeeded)
//        -> comprueba la firma y entrega las gemas con roa_grant_gems (una sola vez por pago).
// Variables en Render: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET y, opcional, ROA_PUBLIC_URL.
'use strict';
const crypto = require('crypto');

const GAME = 'rise_of_ages';
const TOLERANCE_SEC = 300;
// Monedas sin decimales en Stripe (el monto va en unidades, no en centavos).
const ZERO_DECIMAL = new Set(['BIF', 'CLP', 'DJF', 'GNF', 'JPY', 'KMF', 'KRW', 'MGA', 'PYG', 'RWF', 'UGX', 'VND',
  'VUV', 'XAF', 'XOF', 'XPF']);

function toMinor(amount, currency) {
  return ZERO_DECIMAL.has(currency.toUpperCase()) ? Math.round(amount) : Math.round(amount * 100);
}

function fromMinor(amount, currency) {
  return ZERO_DECIMAL.has(currency.toUpperCase()) ? amount : amount / 100;
}

// Firma de Stripe: cabecera "t=…,v1=…"; v1 = HMAC-SHA256(secreto, "t.cuerpo").
function validSignature(payload, header, secret, now = Date.now()) {
  const parts = String(header || '').split(',').map(p => p.trim().split('='));
  const t = (parts.find(([k]) => k === 't') || [])[1];
  const sigs = parts.filter(([k]) => k === 'v1').map(([, v]) => v);
  if (!t || !sigs.length) return false;
  if (Math.abs(now / 1000 - Number(t)) > TOLERANCE_SEC) return false;
  const mac = crypto.createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex');
  return sigs.some(s => s.length === mac.length && crypto.timingSafeEqual(Buffer.from(s), Buffer.from(mac)));
}

function readBody(req, limit = 256 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', c => {
      size += c.length;
      if (size > limit) { reject(new Error('demasiado grande')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function reply(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

// deps: {supa(pathname, opts, token), rpc(fn, args), accounts: bool, env, fetch}
function create(deps) {
  const env = deps.env || process.env;
  const fetchFn = deps.fetch || fetch;
  const publicUrl = (env.ROA_PUBLIC_URL || 'https://conquista-srzq.onrender.com').replace(/\/$/, '');

  async function checkout(req, res) {
    if (!deps.accounts || !env.STRIPE_SECRET_KEY) return reply(res, 503, { error: 'La tienda aún no está lista.' });
    const auth = String(req.headers.authorization || '');
    if (!auth.startsWith('Bearer ')) return reply(res, 401, { error: 'Vuelve a entrar a tu cuenta.' });
    let body = {};
    try { body = JSON.parse(await readBody(req, 4096) || '{}'); } catch { return reply(res, 400, { error: 'Pedido no válido.' }); }
    let user;
    try { user = await deps.supa('/auth/v1/user', {}, auth.slice(7)); } catch { user = null; }
    if (!user || !user.id) return reply(res, 401, { error: 'Vuelve a entrar a tu cuenta.' });
    const price = await deps.rpc('roa_pack_price', { p_pack: String(body.pack || ''), p_currency: String(body.currency || '') })
      .catch(() => null);
    if (!price || !price.amount) return reply(res, 400, { error: 'Ese paquete no existe.' });
    const amount = Number(price.amount);
    const currency = String(price.currency);
    // A dónde vuelve: el juego web (o la página que diga el juego, si es de este sitio).
    const back = typeof body.back === 'string' && body.back.startsWith(publicUrl) ? body.back.split('?')[0] : publicUrl + '/jugar/';
    const form = new URLSearchParams({
      mode: 'payment',
      success_url: back + '?pago=ok',
      cancel_url: back + '?pago=cancelado',
      client_reference_id: user.id,
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': currency.toLowerCase(),
      'line_items[0][price_data][unit_amount]': String(toMinor(amount, currency)),
      'line_items[0][price_data][product_data][name]': `${price.gems} gemas · Rise of Ages`,
      'metadata[game]': GAME,
      'metadata[user]': user.id,
      'metadata[pack]': price.pack,
      'payment_intent_data[metadata][game]': GAME,
      'payment_intent_data[metadata][user]': user.id,
    });
    const r = await fetchFn('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + env.STRIPE_SECRET_KEY,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Idempotency-Key': crypto.randomUUID(),
      },
      body: form.toString(),
    });
    const session = await r.json().catch(() => null);
    if (!r.ok || !session || !session.url) {
      console.log('Stripe no creó el pago', r.status, session && session.error ? session.error.message : session);
      return reply(res, 502, { error: 'No se pudo iniciar el pago.' });
    }
    reply(res, 200, { url: session.url, amount, currency, gems: price.gems });
  }

  async function webhook(req, res) {
    const secret = env.STRIPE_WEBHOOK_SECRET;
    if (!secret || !deps.accounts) { res.writeHead(500); return res.end('sin configurar'); }
    let payload;
    try { payload = await readBody(req); } catch { res.writeHead(413); return res.end(); }
    if (!validSignature(payload, req.headers['stripe-signature'], secret)) { res.writeHead(400); return res.end('firma no válida'); }
    let event;
    try { event = JSON.parse(payload); } catch { res.writeHead(400); return res.end(); }
    if (event.type !== 'checkout.session.completed' && event.type !== 'checkout.session.async_payment_succeeded') {
      res.writeHead(200); return res.end('ignorado');
    }
    const s = (event.data && event.data.object) || {};
    const meta = s.metadata || {};
    // La misma cuenta de Stripe cobra otros juegos: solo los de Rise of Ages.
    if (meta.game !== GAME) { res.writeHead(200); return res.end('otro juego'); }
    if (s.payment_status !== 'paid') { res.writeHead(200); return res.end('estado ' + s.payment_status); }
    if (!meta.user || !meta.pack) { console.log('Pago sin datos del juego', s.id); res.writeHead(200); return res.end('sin datos'); }
    const currency = String(s.currency || 'usd').toUpperCase();
    try {
      const out = await deps.rpc('roa_grant_gems', {
        p_user: meta.user, p_pack: meta.pack, p_provider: 'stripe', p_ref: String(s.id),
        p_amount: fromMinor(Number(s.amount_total || 0), currency), p_currency: currency,
      });
      console.log('Gemas entregadas', s.id, JSON.stringify(out));
    } catch (e) {
      console.log('No se entregaron las gemas', s.id, e.message);
      res.writeHead(500); return res.end('error'); // Stripe reintenta
    }
    res.writeHead(200);
    res.end('ok');
  }

  return { checkout, webhook };
}

module.exports = { create, validSignature, toMinor, fromMinor, GAME };
