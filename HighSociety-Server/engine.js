'use strict';
/* ===== High Society: rules engine (no DOM) ===== */
const SUITS = ['♠', '♥', '♦', '♣'];
const CONTRACTS = [
  { label: '2 sets of 3', short: '2S3', reqs: [['set', 3], ['set', 3]] },
  { label: '2 runs of 3', short: '2R3', reqs: [['run', 3], ['run', 3]] },
  { label: '1 set of 3 + 1 run of 4', short: '1S3 1R4', reqs: [['set', 3], ['run', 4]] },
  { label: '2 sets of 4', short: '2S4', reqs: [['set', 4], ['set', 4]] },
  { label: '2 runs of 4', short: '2R4', reqs: [['run', 4], ['run', 4]] },
  { label: '3 sets of 3', short: '3S3', reqs: [['set', 3], ['set', 3], ['set', 3]] },
  { label: '1 run of 7', short: '1R7', reqs: [['run', 7]] },
  { label: '2 sets of 5', short: '2S5', reqs: [['set', 5], ['set', 5]] },
  { label: '2 runs of 5', short: '2R5', reqs: [['run', 5], ['run', 5]] },
  { label: '1 set of 4 + 1 run of 5', short: '1S4 1R5', reqs: [['set', 4], ['run', 5]] },
  { label: '1 run of 9', short: '1R9', reqs: [['run', 9]] },
];

let G = null;
let persist = () => {};
function setPersist(f) { persist = f; }
function setG(g) { G = g; }
function getG() { return G; }

const isWild = (c) => c.r === 0 || c.r === 2;
const pts = (c) => (c.r === 0 || c.r === 2 ? 50 : c.r === 1 ? 15 : c.r >= 11 ? 10 : 5);
const RL = { 1: 'A', 11: 'J', 12: 'Q', 13: 'K' };
const lbl = (r) => (r === 0 ? 'JKR' : RL[r] || String(r));
const cardName = (c) => (c.r === 0 ? 'Joker' : lbl(c.r) + SUITS[c.s]);
const cur = () => G.players[G.turn];
const humanCount = () => G.players.filter((p) => !p.cpu).length;

function buildDeck(n) {
  let id = 0;
  const d = [];
  for (let k = 0; k < n; k++) {
    for (let s = 0; s < 4; s++) for (let r = 1; r <= 13; r++) d.push({ id: id++, r, s });
    d.push({ id: id++, r: 0, s: -1 });
    d.push({ id: id++, r: 0, s: -1 });
  }
  return d;
}
function shuffle(a) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/* Returns ordered slots [{card, as}] if cards form a valid set/run, else null.
   2s and jokers are always wild. Aces are low or high in runs (no wrap). */
function describe(cards, kind, wl) {
  const n = cards.length;
  if (n < 3) return null;
  const nat = cards.filter((c) => !isWild(c));
  const wilds = cards.filter(isWild);
  if (!nat.length) return null;
  if (wl && wilds.length > nat.length) return null;
  if (kind === 'set') {
    const r = nat[0].r;
    if (nat.some((c) => c.r !== r)) return null;
    return nat.map((c) => ({ card: c, as: r })).concat(wilds.map((c) => ({ card: c, as: r })));
  }
  const s = nat[0].s;
  if (nat.some((c) => c.s !== s)) return null;
  if (n > 14) return null;
  for (let st = 1; st + n - 1 <= 14; st++) {
    const en = st + n - 1;
    const at = {};
    const aces = [];
    let ok = true;
    for (const c of nat) {
      if (c.r === 1) { aces.push(c); continue; }
      if (c.r < st || c.r > en || at[c.r]) { ok = false; break; }
      at[c.r] = c;
    }
    if (!ok) continue;
    const ap = [];
    if (st === 1) ap.push(1);
    if (en === 14) ap.push(14);
    if (aces.length > ap.length) continue;
    const assigns = aces.length === 0 ? [[]] : aces.length === 1 ? ap.map((p) => [p]) : [ap.slice()];
    const as = assigns[0];
    const pos = Object.assign({}, at);
    aces.forEach((a, i) => { pos[as[i]] = a; });
    const out = [];
    const wq = wilds.slice();
    for (let p = st; p <= en; p++) {
      out.push({ card: pos[p] || wq.shift(), as: p === 14 ? 1 : p });
    }
    return out;
  }
  return null;
}

function whyNot(cards, kind, min, wl) {
  if (!cards.length) return 'Empty';
  if (cards.length < min) return 'Needs ' + (min - cards.length) + ' more';
  const nat = cards.filter((c) => !isWild(c));
  if (!nat.length) return 'Needs a natural card';
  if (wl && cards.length - nat.length > nat.length) return 'Too many wilds';
  if (kind === 'set') {
    if (nat.some((c) => c.r !== nat[0].r)) return 'Set cards must match in rank';
  } else if (nat.some((c) => c.s !== nat[0].s)) return 'Run cards must share a suit';
  return describe(cards, kind, wl) ? '' : kind === 'set' ? 'Not a set' : 'Duplicate rank or gap too big';
}

/* Backtracking search: can this hand complete the contract? Returns groups of cards or null. */
function findMelds(hand, reqs, wl) {
  const wilds = hand.filter(isWild);
  const nats = hand.filter((c) => !isWild(c));
  const used = new Set();
  function candidates(kind, len) {
    const out = [];
    const freeW = wilds.filter((c) => !used.has(c.id));
    if (kind === 'set') {
      for (let r = 1; r <= 13; r++) {
        if (r === 2) continue;
        const N = nats.filter((c) => c.r === r && !used.has(c.id));
        for (let m = Math.min(len, N.length); m >= 1; m--) {
          const w = len - m;
          if (w > freeW.length) continue;
          if (wl && w > m) continue;
          out.push(N.slice(0, m).concat(freeW.slice(0, w)));
        }
      }
    } else {
      for (let s = 0; s < 4; s++) {
        const S = nats.filter((c) => c.s === s && !used.has(c.id));
        for (let st = 1; st + len - 1 <= 14; st++) {
          const cards = [];
          const local = new Set();
          let w = 0;
          for (let p = st; p < st + len; p++) {
            const rank = p === 14 ? 1 : p;
            const c = rank === 2 ? null : S.find((x) => x.r === rank && !local.has(x.id));
            if (c) { cards.push(c); local.add(c.id); } else w++;
          }
          const m = cards.length;
          if (m === 0 || w > freeW.length) continue;
          if (wl && w > m) continue;
          out.push(cards.concat(freeW.slice(0, w)));
        }
      }
    }
    return out;
  }
  function rec(i, acc) {
    if (i === reqs.length) return acc;
    const [kind, len] = reqs[i];
    for (const cand of candidates(kind, len)) {
      cand.forEach((c) => used.add(c.id));
      const r = rec(i + 1, acc.concat([cand]));
      if (r) return r;
      cand.forEach((c) => used.delete(c.id));
    }
    return null;
  }
  return rec(0, []);
}

/* ===== game flow ===== */
function addLog(t) {
  G.log.push(t);
  if (G.log.length > 40) G.log.shift();
  if (!G.hist) G.hist = {};
  (G.hist[G.round] = G.hist[G.round] || []).push(t);
  G.turnLog.push(t);
}
function needHandoff() { return !cur().cpu && humanCount() > 1; }

function newGame(setup) {
  G = {
    wl: !!setup.wildLimit,
    hints: !!setup.hints,
    handSize: setup.handSize || 13,
    players: setup.players.map((p) => ({ name: p.name, cpu: !!p.cpu, hand: [], down: false, total: 0 })),
    round: -1, turn: 0, phase: 'draw', stock: [], discard: [], melds: [],
    screen: 'turn', log: [], turnLog: [], lastTurn: [], results: [], outBy: null,
  };
  dealRound();
  return G;
}

function dealRound() {
  G.round++;
  const n = G.players.length;
  const deck = shuffle(buildDeck(Math.max(2, n)));
  G.players.forEach((p) => { p.hand = []; p.down = false; });
  for (let k = 0; k < G.handSize; k++) G.players.forEach((p) => p.hand.push(deck.pop()));
  G.discard = [deck.pop()];
  G.stock = deck;
  G.melds = [];
  G.turn = G.round % n;
  G.phase = 'draw';
  G.turnLog = [];
  G.lastTurn = [];
  G.log = [];
  if (!G.hist) G.hist = {};
  G.hist[G.round] = ['Round ' + (G.round + 1) + ': ' + CONTRACTS[G.round].label + '. ' + cur().name + ' goes first.'];
  G.outBy = null;
  G.screen = needHandoff() ? 'handoff' : 'turn';
  persist();
}

function refill() {
  if (G.stock.length === 0 && G.discard.length > 1) {
    const top = G.discard.pop();
    G.stock = shuffle(G.discard);
    G.discard = [top];
  }
}
function drawStock() {
  refill();
  if (!G.stock.length) return null;
  const c = G.stock.pop();
  cur().hand.push(c);
  G.phase = 'play';
  addLog(cur().name + ' drew from the deck');
  persist();
  return c;
}
function takeDiscard() {
  if (!G.discard.length) return null;
  const c = G.discard.pop();
  cur().hand.push(c);
  G.phase = 'play';
  addLog(cur().name + ' took the ' + cardName(c));
  persist();
  return c;
}

function layDown(idx, groups) {
  const p = G.players[idx];
  const reqs = CONTRACTS[G.round].reqs;
  if (p.down || groups.length !== reqs.length) return false;
  const ids = new Set();
  for (let i = 0; i < reqs.length; i++) {
    const g = groups[i];
    if (g.length < reqs[i][1] || !describe(g, reqs[i][0], G.wl)) return false;
    for (const c of g) {
      if (ids.has(c.id) || !p.hand.some((h) => h.id === c.id)) return false;
      ids.add(c.id);
    }
  }
  p.hand = p.hand.filter((c) => !ids.has(c.id));
  groups.forEach((g, i) => G.melds.push({ owner: idx, kind: reqs[i][0], cards: g.slice() }));
  p.down = true;
  addLog(p.name + ' went down (' + CONTRACTS[G.round].label + ')');
  if (!p.hand.length) goOut(idx); else persist();
  return true;
}

function tryHit(mi, cards) {
  const p = cur();
  const m = G.melds[mi];
  if (!p.down || !m || !cards.length) return false;
  const arr = m.cards.concat(cards);
  if (!describe(arr, m.kind, G.wl)) return false;
  const ids = new Set(cards.map((c) => c.id));
  if (!cards.every((c) => p.hand.some((h) => h.id === c.id))) return false;
  m.cards = arr;
  p.hand = p.hand.filter((c) => !ids.has(c.id));
  addLog(p.name + ' added ' + cards.map(cardName).join(' ') + ' to ' + G.players[m.owner].name + "'s " + m.kind);
  if (!p.hand.length) goOut(G.turn); else persist();
  return true;
}

function discardCard(id) {
  const p = cur();
  const i = p.hand.findIndex((c) => c.id === id);
  if (i < 0 || G.phase !== 'play') return false;
  const [c] = p.hand.splice(i, 1);
  G.discard.push(c);
  addLog(p.name + ' discarded ' + cardName(c));
  if (!p.hand.length) goOut(G.turn); else nextTurn();
  return true;
}

function nextTurn() {
  G.lastTurn = G.turnLog;
  G.turnLog = [];
  G.turn = (G.turn + 1) % G.players.length;
  G.phase = 'draw';
  G.screen = needHandoff() ? 'handoff' : 'turn';
  persist();
}

function goOut(idx) {
  const scores = G.players.map((p, i) => (idx !== null && i === idx ? 0 : p.hand.reduce((s, c) => s + pts(c), 0)));
  G.players.forEach((p, i) => { p.total += scores[i]; });
  G.results.push({ round: G.round, out: idx, scores });
  G.outBy = idx;
  G.screen = 'roundEnd';
  if (idx !== null) addLog(G.players[idx].name + ' went out!');
  G.players.forEach((p, i) => {
    if (i !== idx) addLog(p.name + ' counted ' + scores[i] + ' (' + (p.hand.map(cardName).join(' ') || 'no cards') + ')');
  });
  persist();
}

function nextRound() {
  if (G.round >= CONTRACTS.length - 1) { G.screen = 'final'; persist(); } else dealRound();
}

/* ===== computer player ===== */
function usefulness(card, hand) {
  if (isWild(card)) return 100;
  const reqs = CONTRACTS[G.round].reqs;
  const wS = reqs.some((r) => r[0] === 'set') ? 1 : 0.25;
  const wR = reqs.some((r) => r[0] === 'run') ? 1 : 0.25;
  let u = 0;
  for (const c of hand) {
    if (c.id === card.id || isWild(c)) continue;
    if (c.r === card.r) u += 3 * wS;
    if (c.s === card.s) {
      let d = Math.abs(c.r - card.r);
      if (card.r === 1) d = Math.min(d, Math.abs(14 - c.r));
      if (c.r === 1) d = Math.min(d, Math.abs(14 - card.r));
      if (d === 1) u += 3 * wR; else if (d === 2) u += 1.5 * wR;
    }
  }
  return u;
}
function cpuDraw() {
  const p = cur();
  const top = G.discard[G.discard.length - 1];
  let take = false;
  if (top) {
    const withTop = p.hand.concat([top]);
    if (p.down) {
      take = G.melds.some((_, mi) => describe(G.melds[mi].cards.concat([top]), G.melds[mi].kind, G.wl));
    } else if (isWild(top)) take = true;
    else if (findMelds(withTop, CONTRACTS[G.round].reqs, G.wl)) take = true;
    else if (usefulness(top, withTop) >= 3 && chooseDiscard(withTop, false).id !== top.id) take = true;
  }
  return take ? takeDiscard() : drawStock();
}
function cpuLay() {
  const p = cur();
  if (p.down) return false;
  const sol = findMelds(p.hand, CONTRACTS[G.round].reqs, G.wl);
  return sol ? layDown(G.turn, sol) : false;
}
function cpuHit() {
  const p = cur();
  if (!p.down) return false;
  for (const c of p.hand.slice()) {
    for (let mi = 0; mi < G.melds.length; mi++) {
      if (tryHit(mi, [c])) return true;
    }
  }
  return false;
}
function chooseDiscard(hand, down) {
  let best = null;
  let bestKey = null;
  for (const c of hand) {
    const u = down ? (isWild(c) ? 1000 : 0) : usefulness(c, hand);
    const key = [u, -pts(c)];
    if (!best || key[0] < bestKey[0] || (key[0] === bestKey[0] && key[1] < bestKey[1])) { best = c; bestKey = key; }
  }
  return best;
}
function cpuDiscard() {
  const p = cur();
  if (!p.hand.length) return false;
  return discardCard(chooseDiscard(p.hand, p.down).id);
}
/* Whole turn at once (used for tests and fast-forward). */
function cpuTurnSync() {
  const t = G.turn;
  const live = () => G.screen !== 'roundEnd' && G.screen !== 'final' && G.turn === t;
  if (G.phase === 'draw') { if (!cpuDraw()) { nextTurn(); return; } }
  if (!live()) return;
  cpuLay();
  if (!live()) return;
  while (live() && cpuHit()) { /* keep adding */ }
  if (!live()) return;
  cpuDiscard();
}

if (typeof module !== 'undefined') {
  module.exports = { CONTRACTS, SUITS, isWild, pts, lbl, describe, whyNot, findMelds, buildDeck, shuffle, newGame, cur, drawStock, takeDiscard, layDown, tryHit, discardCard, nextRound, cpuTurnSync, getG, setG, goOut, dealRound };
}
