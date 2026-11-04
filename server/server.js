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
const PROTOCOL = 1;
const TURN_MS = 100;
const MAX_PLAYERS = 8;

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
    return res.end(JSON.stringify({ ok: true, salas: rooms.size }));
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
    code: room.code, host: room.host, map: room.map, bots: room.bots,
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
    return;
  }
  if (room.host === ws.pid) room.host = room.players[0].id;
  if (room.started) {
    for (const o of room.players) send(o.ws, { t: 'left', name: p ? p.name : '' });
  } else {
    broadcastRoom(room);
  }
}

function startGame(room) {
  // Jugadores humanos primero, luego bots. "slot" = índice en la partida.
  const list = [];
  for (const p of room.players) {
    p.slot = list.length;
    list.push({ name: p.name, civ: p.civ, team: p.team, color: p.color, bot: false, difficulty: 'normal' });
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
    send(p.ws, { t: 'start', players: list, you: p.slot, map: room.map, seed });
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
      case 'hash': {
        if (!room || !room.started) return;
        const p = room.players.find(x => x.id === ws.pid);
        if (p) onHash(room, p, m.n | 0, m.h);
        break;
      }
    }
  });
  ws.on('close', () => leave(ws));
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

server.listen(PORT, () => console.log(`Conquista escuchando en el puerto ${PORT}`));
