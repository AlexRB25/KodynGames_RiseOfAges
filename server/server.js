// Servidor de Conquista: landing + juego web (archivos estáticos) y salas en línea (WebSocket /ws).
// Modelo lockstep: cada 100 ms se manda un "turno" con las órdenes de todos los jugadores.
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const PUBLIC = path.join(__dirname, 'public');
const PROTOCOL = 2;
const TURN_MS = 100;
const MAX_PLAYERS = 8;
const MAP_TYPES = ['azar', 'valle', 'costa', 'mesetas', 'lagos', 'selva', 'desierto', 'mar_interior'];

// Cuentas y puntos (mismo Supabase que Zombie War). Sin estas variables el servidor
// funciona en "modo prueba": los puntos viven en memoria y se pierden al reiniciar.
const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY || '';
const ACCOUNTS = !!(SUPABASE_URL && SUPABASE_KEY);

// ---------------- archivos estáticos ----------------
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
  '.webp': 'image/webp', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8',
};
const gzCache = new Map(); // archivo -> {mtime, buf}

function serveStatic(req, res) {
  let url = decodeURIComponent((req.url || '/').split('?')[0]);
  if (url.endsWith('/')) url += 'index.html';
  const file = path.normalize(path.join(PUBLIC, url));
  if (!file.startsWith(PUBLIC)) { res.writeHead(403); return res.end(); }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      // /jugar -> /jugar/
      if (!path.extname(url)) { res.writeHead(301, { Location: url + '/' }); return res.end(); }
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('No encontrado');
    }
    const ext = path.extname(file).toLowerCase();
    const headers = {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=3600',
    };
    const gzipOk = /\bgzip\b/.test(req.headers['accept-encoding'] || '') &&
      ['.wasm', '.pck', '.js', '.html', '.css', '.json', '.svg'].includes(ext);
    if (!gzipOk) {
      headers['Content-Length'] = st.size;
      res.writeHead(200, headers);
      return fs.createReadStream(file).pipe(res);
    }
    let c = gzCache.get(file);
    if (!c || c.mtime !== st.mtimeMs) {
      c = { mtime: st.mtimeMs, buf: zlib.gzipSync(fs.readFileSync(file), { level: 6 }) };
      gzCache.set(file, c);
    }
    headers['Content-Encoding'] = 'gzip';
    headers['Content-Length'] = c.buf.length;
    headers['Vary'] = 'Accept-Encoding';
    res.writeHead(200, headers);
    res.end(c.buf);
  });
}

const server = http.createServer((req, res) => {
  if (req.url === '/salud') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, salas: rooms.size, cuentas: ACCOUNTS,
      en_cola: Object.values(queues).reduce((s, q) => s + q.length, 0) }));
  }
  serveStatic(req, res);
});

// ---------------- salas ----------------
const rooms = new Map(); // código -> sala

function newCode() {
  const L = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  for (;;) {
    let c = '';
    for (let i = 0; i < 4; i++) c += L[crypto.randomInt(L.length)];
    if (!rooms.has(c)) return c;
  }
}

function send(ws, m) {
  if (ws.readyState === 1) ws.send(JSON.stringify(m));
}

function clean(s, n) {
  return String(s == null ? '' : s).replace(/[\u0000-\u001f]/g, '').trim().slice(0, n);
}

function roomState(room) {
  return {
    code: room.code, host: room.host, map: room.map, type: room.type || 'azar', bots: room.bots,
    players: room.players.map(p => ({ id: p.id, name: p.name, civ: p.civ, team: p.team, color: p.color })),
  };
}

function broadcastRoom(room) {
  const st = roomState(room);
  for (const p of room.players) send(p.ws, Object.assign({ t: 'room', you: p.id }, st));
}

function freeColor(room) {
  const used = new Set(room.players.map(p => p.color));
  for (let c = 0; c < 8; c++) if (!used.has(c)) return c;
  return 0;
}

function addPlayer(room, ws, name) {
  const id = room.nextId++;
  const p = { id, ws, name: clean(name, 16) || 'Jugador', civ: 'mexica', team: room.players.length + 1 > 4 ? 1 : room.players.length + 1, color: freeColor(room) };
  room.players.push(p);
  ws.room = room;
  ws.pid = id;
  return p;
}

function leave(ws) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  const p = room.players.find(x => x.id === ws.pid);
  room.players = room.players.filter(x => x.id !== ws.pid);
  if (room.players.length === 0) {
    if (room.timer) clearInterval(room.timer);
    rooms.delete(room.code);
    if (room.ranked && room.started && !room.rated && p) {
      room.left.push(p);
      checkForfeit(room);
    }
    return;
  }
  if (room.host === ws.pid) room.host = room.players[0].id;
  if (room.started) {
    for (const o of room.players) send(o.ws, { t: 'left', name: p ? p.name : '' });
    if (room.ranked && p && !room.rated) {
      room.left.push(p);
      checkForfeit(room);
    }
  } else {
    broadcastRoom(room);
  }
}

function startGame(room) {
  // Jugadores humanos primero, luego bots. "slot" = índice en la partida.
  const list = [];
  for (const p of room.players) {
    p.slot = list.length;
    list.push({ name: p.name, civ: p.civ, team: p.team, color: p.color, bot: false, difficulty: 'normal',
      level: p.level || 0 });
  }
  const used = new Set(list.map(x => x.color));
  for (const b of room.bots) {
    let c = 0;
    while (used.has(c) && c < 7) c++;
    used.add(c);
    list.push({ name: 'Bot ' + (list.length + 1), civ: b.civ, team: b.team, color: c, bot: true, difficulty: b.difficulty });
  }
  const teams = new Set(list.map(x => x.team));
  if (teams.size < 2) return 'Debe haber al menos dos equipos distintos.';
  room.started = true;
  room.turn = -1;
  room.pending = [];
  room.hashes = new Map();
  const seed = crypto.randomInt(1, 2 ** 31 - 1);
  for (const p of room.players) {
    send(p.ws, { t: 'start', players: list, you: p.slot, map: room.map, type: room.type || 'azar', seed, ranked: !!room.ranked, mode: room.mode || '' });
  }
  room.timer = setInterval(() => tickRoom(room), TURN_MS);
  return '';
}

function tickRoom(room) {
  room.turn++;
  const msg = JSON.stringify({ t: 'turn', n: room.turn, cmds: room.pending });
  room.pending = [];
  for (const p of room.players) if (p.ws.readyState === 1) p.ws.send(msg);
}

function onHash(room, p, n, h) {
  let m = room.hashes.get(n);
  if (!m) { m = new Map(); room.hashes.set(n, m); }
  m.set(p.slot, h);
  if (m.size >= room.players.length) {
    const vals = new Set(m.values());
    if (vals.size > 1) {
      console.log(`[${room.code}] desincronización en turno ${n}`, [...m.entries()]);
      for (const o of room.players) send(o.ws, { t: 'desync', n });
    }
    room.hashes.delete(n);
  }
  // no guardar basura vieja
  if (room.hashes.size > 20) room.hashes.delete(room.hashes.keys().next().value);
}

const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 64 * 1024 });

wss.on('connection', ws => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', data => {
    let m;
    try { m = JSON.parse(String(data)); } catch { return; }
    if (!m || typeof m !== 'object') return;
    const room = ws.room;
    switch (m.t) {
      case 'create': {
        if (m.v !== PROTOCOL) return send(ws, { t: 'error', msg: 'Versión distinta: recarga la página para actualizar el juego.' });
        leave(ws);
        const r = { code: newCode(), players: [], bots: [], map: 'mediano', host: 0, nextId: 0, started: false };
        rooms.set(r.code, r);
        const p = addPlayer(r, ws, m.name);
        r.host = p.id;
        broadcastRoom(r);
        break;
      }
      case 'join': {
        if (m.v !== PROTOCOL) return send(ws, { t: 'error', msg: 'Versión distinta: recarga la página para actualizar el juego.' });
        const r = rooms.get(clean(m.code, 4).toUpperCase());
        if (!r) return send(ws, { t: 'error', msg: 'No existe una sala con ese código.' });
        if (r.started) return send(ws, { t: 'error', msg: 'Esa partida ya empezó.' });
        if (r.players.length + r.bots.length >= MAX_PLAYERS) return send(ws, { t: 'error', msg: 'La sala está llena.' });
        leave(ws);
        addPlayer(r, ws, m.name);
        broadcastRoom(r);
        break;
      }
      case 'set': {
        if (!room || room.started) return;
        const p = room.players.find(x => x.id === ws.pid);
        if (!p) return;
        p.civ = clean(m.civ, 24) || p.civ;
        p.team = Math.min(4, Math.max(1, m.team | 0));
        p.color = Math.min(7, Math.max(0, m.color | 0));
        broadcastRoom(room);
        break;
      }
      case 'config': {
        if (!room || room.started || room.host !== ws.pid) return;
        if (['pequeno', 'mediano', 'grande'].includes(m.map)) room.map = m.map;
        if (MAP_TYPES.includes(m.type)) room.type = m.type;
        if (Array.isArray(m.bots)) {
          const max = MAX_PLAYERS - room.players.length;
          room.bots = m.bots.slice(0, max).map(b => ({
            civ: clean(b && b.civ, 24) || 'maya',
            team: Math.min(4, Math.max(1, (b && b.team) | 0)),
            difficulty: ['facil', 'normal', 'dificil', 'experto'].includes(b && b.difficulty) ? b.difficulty : 'normal',
          }));
        }
        broadcastRoom(room);
        break;
      }
      case 'start': {
        if (!room || room.started || room.host !== ws.pid) return;
        const err = startGame(room);
        if (err) send(ws, { t: 'error', msg: err });
        break;
      }
      case 'cmd': {
        if (!room || !room.started || !m.c || typeof m.c !== 'object') return;
        const p = room.players.find(x => x.id === ws.pid);
        if (!p) return;
        if (room.pending.length < 400) room.pending.push([p.slot, m.c]);
        break;
      }
      case 'queue': {
        if (m.v !== PROTOCOL) return send(ws, { t: 'error', msg: 'Versión distinta: recarga la página para actualizar el juego.' });
        leave(ws);
        enqueue(ws, m).catch(e => {
          console.log('cola:', e.message);
          send(ws, { t: 'error', msg: 'No se pudo entrar a la cola: ' + e.message });
        });
        break;
      }
      case 'unqueue': {
        dequeue(ws);
        send(ws, { t: 'unqueued' });
        break;
      }
      case 'over': {
        if (!room || !room.started || !room.ranked) return;
        const p = room.players.find(x => x.id === ws.pid);
        if (p) onOver(room, p, m.winner | 0);
        break;
      }
      case 'hash': {
        if (!room || !room.started) return;
        const p = room.players.find(x => x.id === ws.pid);
        if (p) onHash(room, p, m.n | 0, m.h);
        break;
      }
    }
  });
  ws.on('close', () => { dequeue(ws); leave(ws); });
  ws.on('error', () => {});
});

// Cerrar conexiones muertas (y mantener vivas las de Render).
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch {}
  }
}, 25000);

// ---------------- partidas con rango: cola, emparejar por puntos y repartir puntos ----------------
const MODES = { '1v1': { size: 2, map: 'pequeno' }, '2v2': { size: 4, map: 'mediano' }, '4v4': { size: 8, map: 'grande' } };
const queues = { '1v1': [], '2v2': [], '4v4': [] };
const devPoints = new Map(); // modo prueba: nombre -> {points, wins, losses, games}

function level(points) { return 1 + Math.floor(Math.max(0, points) / 100); }

async function supa(pathname, opts = {}, token = SUPABASE_KEY) {
  const r = await fetch(SUPABASE_URL + pathname, Object.assign({}, opts, {
    headers: Object.assign({ apikey: SUPABASE_KEY, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, opts.headers || {}),
  }));
  const text = await r.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!r.ok) throw new Error((data && (data.message || data.msg)) || ('HTTP ' + r.status));
  return data;
}

function rpc(fn, args) {
  return supa('/rest/v1/rpc/' + fn, { method: 'POST', body: JSON.stringify(args) });
}

// Quién es y cuántos puntos tiene. Con Supabase se verifica la sesión del jugador.
async function identify(m) {
  const name = clean(m.name, 16) || 'Jugador';
  if (!ACCOUNTS) {
    const d = devPoints.get(name) || { points: 0 };
    return { uid: 'dev:' + name, name, points: d.points };
  }
  if (!m.token) throw new Error('inicia sesión primero');
  const user = await supa('/auth/v1/user', {}, String(m.token));
  if (!user || !user.id) throw new Error('sesión no válida');
  const prof = await rpc('roa_server_profile', { p_user: user.id });
  return { uid: user.id, name: (prof && prof.name) || name, points: (prof && prof.points) | 0 };
}

async function enqueue(ws, m) {
  const mode = MODES[m.mode] ? m.mode : '1v1';
  dequeue(ws);
  const who = await identify(m);
  if (ws.readyState !== 1) return;
  // La misma cuenta no puede estar dos veces en la cola.
  for (const k in queues) {
    for (const e of queues[k].filter(e => e.uid === who.uid)) {
      e.ws.queued = null;
      send(e.ws, { t: 'unqueued', msg: 'Entraste a la cola desde otro lugar.' });
    }
    queues[k] = queues[k].filter(e => e.uid !== who.uid);
  }
  const entry = { ws, uid: who.uid, name: who.name, points: who.points, civ: clean(m.civ, 24) || 'mexica', since: Date.now() };
  queues[mode].push(entry);
  ws.queued = mode;
  send(ws, { t: 'queued', mode, points: who.points, level: level(who.points), name: who.name,
    waiting: queues[mode].length, need: MODES[mode].size });
  matchmake();
}

function dequeue(ws) {
  const mode = ws.queued;
  if (!mode) return;
  ws.queued = null;
  queues[mode] = queues[mode].filter(e => e.ws !== ws);
}

// Empareja con los más cercanos en puntos al que lleva más tiempo esperando.
// Si no hay nadie de tu nivel, se juega con quien esté en la cola.
function matchmake() {
  for (const mode in queues) {
    const q = queues[mode] = queues[mode].filter(e => e.ws.readyState === 1);
    const need = MODES[mode].size;
    while (q.length >= need) {
      q.sort((a, b) => a.since - b.since);
      const anchor = q[0];
      const rest = q.slice(1).sort((a, b) => Math.abs(a.points - anchor.points) - Math.abs(b.points - anchor.points));
      const group = [anchor].concat(rest.slice(0, need - 1));
      for (const g of group) {
        q.splice(q.indexOf(g), 1);
        g.ws.queued = null;
      }
      startRanked(mode, group);
    }
    for (const e of q) send(e.ws, { t: 'queue', mode, waiting: q.length, need });
  }
}

function startRanked(mode, group) {
  // Equipos parejos: del más fuerte al más débil, en serpiente (A B B A A B B A).
  group.sort((a, b) => b.points - a.points);
  const r = { code: newCode(), players: [], bots: [], map: MODES[mode].map, host: 0, nextId: 0, started: false,
    ranked: true, mode, left: [], reports: new Map(), rated: false };
  rooms.set(r.code, r);
  group.forEach((g, i) => {
    const p = addPlayer(r, g.ws, g.name);
    p.civ = g.civ;
    p.uid = g.uid;
    p.points = g.points;
    p.level = level(g.points);
    p.team = [1, 2, 2, 1][i % 4];
    p.color = i;
  });
  r.host = r.players[0].id;
  r.all = r.players.slice();
  console.log(`[${r.code}] con rango ${mode}:`, r.players.map(p => `${p.name}(${p.points})`).join(' vs '));
  startGame(r);
}

// Cada cliente avisa qué equipo ganó (todos simulan lo mismo, así que deben coincidir).
function onOver(room, p, winner) {
  if (room.rated) return;
  room.reports.set(p.uid, winner);
  const connected = room.players.filter(x => x.ws.readyState === 1);
  if (connected.every(x => room.reports.has(x.uid))) finishRanked(room);
  else if (!room.overTimer) room.overTimer = setTimeout(() => finishRanked(room), 20000);
}

// Si todos los que siguen conectados son de un mismo equipo, ese equipo gana.
function checkForfeit(room) {
  if (room.rated) return;
  const teams = new Set(room.players.filter(x => x.ws.readyState === 1).map(x => x.team));
  if (teams.size <= 1) finishRanked(room, teams.size === 1 ? [...teams][0] : null);
}

async function finishRanked(room, forcedWinner) {
  if (room.rated) return;
  room.rated = true;
  if (room.overTimer) clearTimeout(room.overTimer);
  let winner = forcedWinner;
  if (winner === undefined) {
    const votes = new Set(room.reports.values());
    winner = votes.size === 1 ? [...votes][0] : null;
    if (votes.size > 1) console.log(`[${room.code}] resultados distintos, no cuenta`, [...room.reports.entries()]);
  }
  if (!(winner > 0)) winner = null;
  const leftIds = new Set(room.left.map(x => x.uid));
  const players = room.all.map(x => ({ user_id: x.uid, team: x.team, civ: x.civ, abandoned: leftIds.has(x.uid) }));
  let results = [];
  try {
    results = ACCOUNTS
      ? (await rpc('roa_apply_result', { p_mode: room.mode, p_winner_team: winner, p_players: players })) || []
      : devApply(winner, players);
  } catch (e) {
    console.log(`[${room.code}] no se guardaron los puntos:`, e.message);
  }
  console.log(`[${room.code}] fin con rango: gana equipo ${winner}`,
    results.map(x => `${x.user_id} ${x.delta >= 0 ? '+' : ''}${x.delta}`).join(', '));
  for (const x of room.all) {
    const mine = results.find(rr => rr.user_id === x.uid);
    send(x.ws, {
      t: 'rated', winner, forfeit: forcedWinner !== undefined, you: mine || null,
      results: room.all.map(o => {
        const rr = results.find(z => z.user_id === o.uid) || {};
        return { slot: o.slot, name: o.name, delta: rr.delta | 0, points: rr.points | 0, level: rr.level || level(rr.points | 0) };
      }),
    });
  }
}

// Modo prueba (sin Supabase): misma regla que roa_apply_result en supabase/esquema.sql.
function devApply(winner, players) {
  const pts = uid => (devPoints.get(uid.slice(4)) || { points: 0 }).points;
  const avg = arr => arr.length ? arr.reduce((s, x) => s + pts(x.user_id), 0) / arr.length : 0;
  const out = players.map(pl => {
    const diff = avg(players.filter(x => x.team !== pl.team)) - avg(players.filter(x => x.team === pl.team));
    const won = winner != null && pl.team === winner && !pl.abandoned;
    let delta = 0;
    if (winner != null) {
      delta = won ? 20 + Math.max(-10, Math.min(10, Math.round(diff / 20)))
        : -(15 + Math.max(-8, Math.min(8, Math.round(-diff / 20)))) - (pl.abandoned ? 5 : 0);
    }
    return { pl, won, delta };
  });
  return out.map(({ pl, won, delta }) => {
    const name = pl.user_id.slice(4);
    const d = devPoints.get(name) || { points: 0, wins: 0, losses: 0, games: 0 };
    const before = d.points;
    d.points = Math.max(0, d.points + delta);
    d.games++;
    if (won) d.wins++; else if (winner != null) d.losses++;
    devPoints.set(name, d);
    return { user_id: pl.user_id, delta: d.points - before, points: d.points, level: level(d.points), won };
  });
}

setInterval(matchmake, 2000);

server.listen(PORT, () => console.log(`Conquista escuchando en el puerto ${PORT}`));
