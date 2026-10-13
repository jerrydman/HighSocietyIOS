process.env.NO_PERSIST = '1';
process.env.POLL_MS = '600';
const S = require('./server.js');
const E = require('./engine.js');
let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } };
let base;
async function api(method, path, body, token) {
  const r = await fetch(base + path, { method, headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}), body: body ? JSON.stringify(body) : undefined });
  let j = null; try { j = await r.json(); } catch (e) {}
  return { status: r.status, body: j };
}
const view = async (code, tok, since = 0) => (await api('GET', `/api/games/${code}/state?since=${since}`, null, tok)).body;
const rank = (c) => c.r;
const cname = (c) => c.r + '/' + c.s;

function usefulness(card, hand, reqs) {
  if (E.isWild(card)) return 100;
  const wS = reqs.some((r) => r[0] === 'set') ? 1 : 0.25, wR = reqs.some((r) => r[0] === 'run') ? 1 : 0.25;
  let u = 0;
  for (const c of hand) {
    if (c.id === card.id || E.isWild(c)) continue;
    if (c.r === card.r) u += 3 * wS;
    if (c.s === card.s) { let d = Math.abs(c.r - card.r); if (card.r === 1) d = Math.min(d, Math.abs(14 - c.r)); if (c.r === 1) d = Math.min(d, Math.abs(14 - card.r)); if (d === 1) u += 3 * wR; else if (d === 2) u += 1.5 * wR; }
  }
  return u;
}

async function botTurn(code, tok, v) {
  const me = v.players[v.seat];
  const reqs = E.CONTRACTS[v.round].reqs;
  let r;
  if (v.phase === 'draw') {
    let from = 'stock';
    const top = v.discardTop;
    if (top && !me.down && (E.isWild(top) || usefulness(top, me.hand.concat([top]), reqs) >= 3)) from = 'discard';
    if (me.down && top && v.melds.some((m) => E.describe(m.cards.concat([top]), m.kind, v.wl))) from = 'discard';
    r = await api('POST', `/api/games/${code}/action`, { type: 'draw', from }, tok);
    ok(r.status === 200, 'draw failed ' + JSON.stringify(r.body));
    v = r.body.view;
  }
  let hand = v.players[v.seat].hand;
  if (!v.players[v.seat].down) {
    const sol = E.findMelds(hand, reqs, v.wl);
    if (sol) {
      r = await api('POST', `/api/games/${code}/action`, { type: 'laydown', groups: sol.map((g) => g.map((c) => c.id)) }, tok);
      ok(r.status === 200, 'laydown failed ' + JSON.stringify(r.body));
      v = r.body.view;
      if (v.screen !== 'turn') return v;
    }
  }
  if (v.players[v.seat].down) {
    let did = true;
    while (did) {
      did = false;
      hand = v.players[v.seat].hand;
      outer: for (const c of hand) {
        for (const m of v.melds) {
          if (E.describe(m.cards.concat([c]), m.kind, v.wl)) {
            r = await api('POST', `/api/games/${code}/action`, { type: 'hit', meld: m.id, cards: [c.id] }, tok);
            ok(r.status === 200, 'hit failed ' + JSON.stringify(r.body));
            v = r.body.view; did = true;
            if (v.screen !== 'turn') return v;
            break outer;
          }
        }
      }
    }
  }
  hand = v.players[v.seat].hand;
  let best = hand[0], bu = Infinity, bp = 0;
  for (const c of hand) {
    const u = v.players[v.seat].down ? (E.isWild(c) ? 1000 : 0) : usefulness(c, hand, reqs);
    const pp = -E.pts(c);
    if (u < bu || (u === bu && pp < bp)) { best = c; bu = u; bp = pp; }
  }
  r = await api('POST', `/api/games/${code}/action`, { type: 'discard', card: best.id }, tok);
  ok(r.status === 200, 'discard failed ' + JSON.stringify(r.body));
  return r.body.view;
}

(async () => {
  const srv = await S.start(0);
  base = 'http://127.0.0.1:' + srv.address().port;

  // lobby
  let r = await api('POST', '/api/games', { name: 'Alice', maxSeats: 2, handSize: 13, wildLimit: false });
  ok(r.status === 200 && r.body.code && r.body.token, 'create');
  const code = r.body.code, aTok = r.body.token;
  ok(/^[A-HJKMNP-Z2-9]{5}$/.test(code), 'code format ' + code);
  r = await api('GET', `/api/games/${code}`);
  ok(r.body.names.length === 1 && !r.body.started, 'public info');
  r = await api('GET', '/api/games/ZZZZZ');
  ok(r.status === 404, 'unknown code');
  r = await api('POST', `/api/games/${code}/action`, { type: 'start' }, 'nope');
  ok(r.status === 401, 'bad token rejected');
  r = await api('POST', `/api/games/${code}/action`, { type: 'start' }, aTok);
  ok(r.status === 400, 'cannot start alone');

  // long poll wakes on join
  const pending = view(code, aTok, 1);
  const t0 = Date.now();
  r = await api('POST', `/api/games/${code}/join`, { name: 'Alice' });
  ok(r.status === 200 && r.body.seat === 1, 'join');
  const bTok = r.body.token;
  const pv = await pending;
  ok(pv.view && pv.view.lobby.length === 2 && Date.now() - t0 < 400, 'long poll woke on join');
  ok(pv.view.lobby[1] === 'Alice 2', 'duplicate names made unique: ' + pv.view.lobby[1]);
  r = await api('POST', `/api/games/${code}/join`, { name: 'Carl' });
  ok(r.status === 409, 'full game refuses third');

  r = await api('POST', `/api/games/${code}/action`, { type: 'start' }, bTok);
  ok(r.status === 403, 'only host starts');
  r = await api('POST', `/api/games/${code}/action`, { type: 'start' }, aTok);
  ok(r.status === 200 && r.body.view.started, 'start');

  // privacy
  let va = await view(code, aTok), vb = await view(code, bTok);
  ok(va.view.players[0].hand.length === 13 && va.view.players[1].hand === null, 'A sees only own hand');
  ok(vb.view.players[1].hand.length === 13 && vb.view.players[0].hand === null, 'B sees only own hand');
  ok(va.view.players[1].handCount === 13, 'hand counts public');
  const raw = JSON.stringify(vb.view);
  ok(!raw.includes('"stock"'), 'stock order not sent');
  ok(typeof va.view.stockCount === 'number', 'stock count sent');

  // illegal actions
  const turn = va.view.turn;
  const wrongTok = turn === 0 ? bTok : aTok, rightTok = turn === 0 ? aTok : bTok;
  r = await api('POST', `/api/games/${code}/action`, { type: 'draw' }, wrongTok);
  ok(r.status === 409, 'draw out of turn rejected');
  r = await api('POST', `/api/games/${code}/action`, { type: 'discard', card: 1 }, rightTok);
  ok(r.status === 400, 'discard before drawing rejected');
  r = await api('POST', `/api/games/${code}/action`, { type: 'draw', from: 'stock' }, rightTok);
  ok(r.status === 200, 'draw ok');
  r = await api('POST', `/api/games/${code}/action`, { type: 'draw', from: 'stock' }, rightTok);
  ok(r.status === 400, 'double draw rejected');
  r = await api('POST', `/api/games/${code}/action`, { type: 'laydown', groups: [[9999], [9998]] }, rightTok);
  ok(r.status === 400, 'laydown with foreign cards rejected');
  const oppCard = (await view(code, wrongTok)).view.players[turn === 0 ? 1 : 0].hand[0];
  r = await api('POST', `/api/games/${code}/action`, { type: 'discard', card: oppCard.id }, rightTok);
  ok(r.status === 400, "cannot discard opponent's card");

  // long poll resolves on action; and times out unchanged
  let cur = await view(code, wrongTok);
  const waitP = view(code, wrongTok, cur.version);
  const t1 = Date.now();
  const myHand = (await view(code, rightTok)).view.players[turn].hand;
  r = await api('POST', `/api/games/${code}/action`, { type: 'discard', card: myHand[0].id }, rightTok);
  ok(r.status === 200, 'discard');
  const w = await waitP;
  ok(w.view && w.view.turn !== turn && Date.now() - t1 < 400, 'long poll woke on action');
  const t2 = Date.now();
  const un = await view(code, wrongTok, w.version);
  ok(un.unchanged && Date.now() - t2 >= 500, 'long poll times out unchanged');

  // play full game with two bots
  let rounds = 0, turns = 0, guard = 0;
  while (guard++ < 20000) {
    const a = await view(code, aTok);
    const v = a.view;
    if (v.screen === 'final') break;
    if (v.screen === 'roundEnd') {
      rounds++;
      // revealed hands at round end
      ok(v.players.every((p) => Array.isArray(p.hand)), 'hands revealed at round end');
      const rr = await api('POST', `/api/games/${code}/action`, { type: 'next', round: v.round }, bTok);
      ok(rr.status === 200, 'next round');
      const dup = await api('POST', `/api/games/${code}/action`, { type: 'next', round: v.round }, aTok);
      ok(dup.status === 409, 'duplicate next ignored');
      continue;
    }
    const tok = v.turn === 0 ? aTok : bTok;
    const mine = v.turn === 0 ? v : (await view(code, bTok)).view;
    await botTurn(code, tok, mine);
    turns++;
  }
  const fin = (await view(code, aTok)).view;
  ok(fin.screen === 'final', 'game reached final, guard=' + guard);
  ok(fin.results.length === 11, 'eleven results ' + fin.results.length);
  const tot = fin.players.map((p) => p.total);
  const re = fin.players.map((_, i) => fin.results.reduce((s, x) => s + x.scores[i], 0));
  ok(JSON.stringify(tot) === JSON.stringify(re), 'totals match results');
  ok(fin.hist.length === 11 && fin.hist.every((h) => h.length > 2), 'play-by-play recorded');
  ok(fin.players.every((p) => Array.isArray(p.hand)), 'hands visible at final');
  console.log('rounds', rounds + 1, 'turns', turns, 'totals', tot.join(','));

  r = await api('POST', `/api/games/${code}/action`, { type: 'end' }, bTok);
  ok(r.status === 403, 'non-host cannot end');
  r = await api('POST', `/api/games/${code}/action`, { type: 'end' }, aTok);
  ok(r.status === 200, 'host ends');

  // landing page
  const lp = await fetch(base + `/join/${code}`);
  const html = await lp.text();
  ok(lp.status === 200 && html.includes('highsociety://join/' + code), 'landing page deep link');

  console.log(fails ? fails + ' FAILURES' : 'ALL PASSED');
  srv.close();
  process.exit(fails ? 1 : 0);
})();
