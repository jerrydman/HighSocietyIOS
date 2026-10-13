'use strict';
/* High Society game server. No dependencies. The server owns the deck and every hand;
   each player is only ever sent their own cards. Updates use HTTP long polling. */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const E = require('./engine.js');

const PORT = parseInt(process.env.PORT || '8080', 10);
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const MAX_AGE_MS = 7 * 24 * 3600 * 1000;
const POLL_MS = parseInt(process.env.POLL_MS || '25000', 10);
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const games = new Map();   // code -> game
const waiters = new Map(); // code -> Set of { seat, res, timer }

/* ---------- persistence ---------- */
const FILE = path.join(DATA_DIR, 'games.json');
let saveTimer = null;
function load() {
  try {
    const arr = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    const now = Date.now();
    for (const g of arr) if (now - g.updated < MAX_AGE_MS) games.set(g.code, g);
  } catch (e) { /* first run */ }
}
function scheduleSave() {
  if (saveTimer || process.env.NO_PERSIST) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    try {
      fs.mkdirSync(DATA_DIR, { recursive: true });
      const tmp = FILE + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify([...games.values()]));
      fs.renameSync(tmp, FILE);
    } catch (e) { console.error('save failed', e.message); }
  }, 500);
}

/* ---------- helpers ---------- */
class HttpError extends Error {
  constructor(status, msg) { super(msg); this.status = status; }
}
const bad = (msg, status = 400) => new HttpError(status, msg);
const newToken = () => crypto.randomBytes(18).toString('hex');
function newCode() {
  for (;;) {
    let c = '';
    for (let i = 0; i < 5; i++) c += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
    if (!games.has(c)) return c;
  }
}
function cleanName(s, fallback) {
  const n = String(s == null ? '' : s).replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, 14);
  return n || fallback;
}
function uniqueName(game, name) {
  let n = name, k = 2;
  while (game.seats.some((s) => s.name === n)) n = name + ' ' + k++;
  return n;
}
function sendJSON(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}
function sendHTML(res, status, html) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(html);
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > 65536) { reject(bad('Request too large', 413)); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch (e) { reject(bad('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}
function origin(req) {
  const proto = req.headers['x-forwarded-proto'] || 'http';
  return proto.split(',')[0] + '://' + (req.headers['x-forwarded-host'] || req.headers.host);
}

/* ---------- views: what one seat is allowed to see ---------- */
function viewFor(game, seat) {
  const base = {
    code: game.code,
    version: game.version,
    started: game.started,
    ended: !!game.ended,
    host: 0,
    seat,
    maxSeats: game.maxSeats,
    lobby: game.seats.map((s) => s.name),
    settings: game.settings,
  };
  if (!game.started) return base;
  const G = game.G;
  const reveal = G.screen === 'roundEnd' || G.screen === 'final';
  const hist = [];
  for (let r = 0; r <= G.round; r++) hist.push((G.hist && G.hist[r]) || []);
  return Object.assign(base, {
    wl: G.wl,
    handSize: G.handSize,
    players: G.players.map((p, i) => ({
      id: i, name: p.name, down: p.down, total: p.total, handCount: p.hand.length,
      hand: (i === seat || reveal) ? p.hand : null,
    })),
    round: G.round,
    turn: G.turn,
    phase: G.phase,
    stockCount: G.stock.length,
    discardCount: G.discard.length,
    discardTop: G.discard.length ? G.discard[G.discard.length - 1] : null,
    melds: G.melds.map((m, i) => ({ id: i, owner: m.owner, kind: m.kind, cards: m.cards })),
    screen: G.screen,
    log: G.log,
    lastTurn: G.lastTurn,
    results: G.results,
    hist,
  });
}

/* ---------- game actions ---------- */
function ints(a) {
  if (!Array.isArray(a) || a.length > 60 || a.some((x) => !Number.isInteger(x))) throw bad('Bad card list');
  return a;
}
function act(game, seat, body) {
  const t = body.type;
  if (t === 'start') {
    if (seat !== 0) throw bad('Only the host can start the game', 403);
    if (game.started) throw bad('Already started');
    if (game.seats.length < 2) throw bad('Need at least 2 players');
    E.newGame({
      players: game.seats.map((s) => ({ name: s.name, cpu: false })),
      handSize: game.settings.handSize,
      wildLimit: game.settings.wildLimit,
      hints: false,
    });
    game.G = E.getG();
    game.G.screen = 'turn';
    game.started = true;
    return;
  }
  if (t === 'end') {
    if (seat !== 0) throw bad('Only the host can end the game', 403);
    game.ended = true;
    return;
  }
  if (!game.started) throw bad('The game has not started');
  if (game.ended) throw bad('This game has ended', 410);
  E.setG(game.G);
  const G = E.getG();

  if (t === 'next') {
    if (G.screen === 'roundEnd' && G.round === body.round) {
      E.nextRound();
      if (G.screen === 'handoff') G.screen = 'turn';
    } else {
      throw bad('Round already advanced', 409);
    }
    return;
  }

  if (G.screen !== 'turn' || G.turn !== seat) throw bad('It is not your turn', 409);
  const p = G.players[seat];

  if (t === 'draw') {
    if (G.phase !== 'draw') throw bad('You already drew this turn');
    const c = body.from === 'discard' ? E.takeDiscard() : E.drawStock();
    if (!c) throw bad('No card available to draw');
  } else if (t === 'laydown') {
    if (G.phase !== 'play') throw bad('Draw first');
    if (p.down) throw bad('You are already down');
    if (!Array.isArray(body.groups)) throw bad('Bad groups');
    const groups = body.groups.map((ids) => ints(ids).map((id) => p.hand.find((c) => c.id === id)));
    if (groups.some((g) => g.some((c) => !c))) throw bad('Card not in your hand');
    if (!E.layDown(seat, groups)) throw bad('Those cards do not complete the contract');
  } else if (t === 'hit') {
    if (G.phase !== 'play') throw bad('Draw first');
    if (!p.down) throw bad('Go down before adding to melds');
    const cards = ints(body.cards).map((id) => p.hand.find((c) => c.id === id));
    if (!cards.length || cards.some((c) => !c)) throw bad('Card not in your hand');
    if (!Number.isInteger(body.meld) || !E.tryHit(body.meld, cards)) throw bad("That doesn't fit this meld");
  } else if (t === 'discard') {
    if (G.phase !== 'play') throw bad('Draw first');
    if (!Number.isInteger(body.card) || !E.discardCard(body.card)) throw bad('Card not in your hand');
  } else {
    throw bad('Unknown action');
  }
  if (G.screen === 'handoff') G.screen = 'turn';
}

/* ---------- long polling ---------- */
function removeWaiter(code, w) {
  const set = waiters.get(code);
  if (set) { set.delete(w); if (!set.size) waiters.delete(code); }
}
function poll(game, seat, since, res) {
  if (game.version > since) return sendJSON(res, 200, { version: game.version, view: viewFor(game, seat) });
  const w = { seat, res, timer: null };
  w.timer = setTimeout(() => {
    removeWaiter(game.code, w);
    sendJSON(res, 200, { version: game.version, unchanged: true });
  }, POLL_MS);
  if (!waiters.has(game.code)) waiters.set(game.code, new Set());
  waiters.get(game.code).add(w);
  res.on('close', () => { clearTimeout(w.timer); removeWaiter(game.code, w); });
}
function bump(game) {
  game.version++;
  game.updated = Date.now();
  const set = waiters.get(game.code);
  if (set) {
    for (const w of [...set]) {
      clearTimeout(w.timer);
      removeWaiter(game.code, w);
      sendJSON(w.res, 200, { version: game.version, view: viewFor(game, w.seat) });
    }
  }
  scheduleSave();
}

/* ---------- pages ---------- */
function landing(req, code) {
  const base = origin(req);
  const app = 'highsociety://join/' + code + '?server=' + encodeURIComponent(base);
  const tf = process.env.TESTFLIGHT_URL ? '<p><a href="' + process.env.TESTFLIGHT_URL + '">Get the app on TestFlight</a></p>' : '';
  return '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>High Society</title>' +
    '<style>body{font:17px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:32px 20px;max-width:440px;margin-inline:auto;color:#14212b;background:#e8edf1}' +
    'h1{font-size:34px;margin:0 0 8px}.code{font:700 38px ui-monospace,Menlo,monospace;letter-spacing:.12em;background:#fffef9;border:3px solid #1769b3;padding:10px 16px;display:inline-block;margin:12px 0}' +
    'a.b{display:block;background:#1769b3;color:#fff;text-decoration:none;text-align:center;padding:14px;border-radius:10px;font-weight:600;margin:16px 0}' +
    '@media(prefers-color-scheme:dark){body{background:#0d161d;color:#e7eef3}.code{color:#14212b}}</style></head><body>' +
    '<h1>High Society</h1><p>You have been invited to a game.</p><div class="code">' + code + '</div>' +
    '<a class="b" href="' + app + '">Open in the High Society app</a>' + tf +
    '<p style="opacity:.7;font-size:15px">If the button does nothing, open the app, tap Join with a code, and enter the code above.</p></body></html>';
}

/* ---------- routing ---------- */
async function handle(req, res) {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;
  const m = req.method;

  if (p === '/healthz') return sendJSON(res, 200, { ok: true, games: games.size });
  if (p === '/' && m === 'GET') return sendHTML(res, 200, '<!doctype html><title>High Society</title><p style="font:17px system-ui;padding:32px">High Society game server is running.</p>');
  if (p === '/.well-known/apple-app-site-association' && process.env.APPLE_APP_ID) {
    return sendJSON(res, 200, { applinks: { details: [{ appIDs: [process.env.APPLE_APP_ID], components: [{ '/': '/join/*' }] }] } });
  }
  let mm = p.match(/^\/join\/([A-Za-z0-9]{5})$/);
  if (mm && m === 'GET') return sendHTML(res, 200, landing(req, mm[1].toUpperCase()));

  if (p === '/api/games' && m === 'POST') {
    const body = await readBody(req);
    const code = newCode();
    const maxSeats = Math.min(6, Math.max(2, parseInt(body.maxSeats, 10) || 2));
    const handSize = body.handSize === 10 ? 10 : 13;
    const token = newToken();
    const game = {
      code, created: Date.now(), updated: Date.now(), version: 1, started: false, ended: false, maxSeats,
      settings: { handSize, wildLimit: !!body.wildLimit },
      seats: [{ name: cleanName(body.name, 'Player 1'), token }], G: null,
    };
    games.set(code, game);
    scheduleSave();
    return sendJSON(res, 200, { code, seat: 0, token, version: game.version });
  }

  mm = p.match(/^\/api\/games\/([A-Za-z0-9]{5})(?:\/(join|state|action))?$/);
  if (!mm) return sendJSON(res, 404, { error: 'Not found' });
  const code = mm[1].toUpperCase();
  const game = games.get(code);
  if (!game) return sendJSON(res, 404, { error: 'No game with that code' });
  const sub = mm[2];

  if (!sub && m === 'GET') {
    return sendJSON(res, 200, { code, started: game.started, ended: !!game.ended, names: game.seats.map((s) => s.name), maxSeats: game.maxSeats });
  }
  if (sub === 'join' && m === 'POST') {
    const body = await readBody(req);
    if (game.started) throw bad('That game has already started', 409);
    if (game.seats.length >= game.maxSeats) throw bad('That game is full', 409);
    const token = newToken();
    const name = uniqueName(game, cleanName(body.name, 'Player ' + (game.seats.length + 1)));
    game.seats.push({ name, token });
    bump(game);
    return sendJSON(res, 200, { code, seat: game.seats.length - 1, token, version: game.version });
  }

  const auth = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const seat = game.seats.findIndex((s) => s.token === auth);
  if (!auth || seat < 0) throw bad('Not signed in to this game', 401);

  if (sub === 'state' && m === 'GET') {
    const since = parseInt(url.searchParams.get('since') || '0', 10) || 0;
    return poll(game, seat, since, res);
  }
  if (sub === 'action' && m === 'POST') {
    const body = await readBody(req);
    act(game, seat, body);
    bump(game);
    return sendJSON(res, 200, { version: game.version, view: viewFor(game, seat) });
  }
  return sendJSON(res, 405, { error: 'Method not allowed' });
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((e) => {
    if (res.headersSent) return;
    if (e instanceof HttpError) return sendJSON(res, e.status, { error: e.message });
    console.error(e);
    sendJSON(res, 500, { error: 'Server error' });
  });
});

function start(port) {
  load();
  setInterval(() => {
    const now = Date.now();
    for (const [c, g] of games) if (now - g.updated > MAX_AGE_MS) games.delete(c);
  }, 3600 * 1000).unref();
  return new Promise((resolve) => server.listen(port, () => resolve(server)));
}

if (require.main === module) {
  start(PORT).then(() => console.log('High Society server listening on ' + PORT));
}
module.exports = { start, server, games };
