import Foundation

// MARK: - Cards and contracts

enum Kind: String, Codable {
    case set
    case run
}

struct Card: Codable, Identifiable, Hashable {
    let id: Int
    let r: Int   // 0 = joker, 1 = ace ... 13 = king
    let s: Int   // 0...3 = spades, hearts, diamonds, clubs; -1 = joker

    var isWild: Bool { r == 0 || r == 2 }
    var points: Int {
        if r == 0 || r == 2 { return 50 }
        if r == 1 { return 15 }
        if r >= 11 { return 10 }
        return 5
    }
    var isRed: Bool { s == 1 || s == 2 }
    var rankLabel: String { rankText(r) }
    var suitSymbol: String { s < 0 ? "★" : ["♠", "♥", "♦", "♣"][s] }
    var name: String { r == 0 ? "Joker" : rankLabel + suitSymbol }
}

func rankText(_ r: Int) -> String {
    switch r {
    case 0: return "JKR"
    case 1: return "A"
    case 11: return "J"
    case 12: return "Q"
    case 13: return "K"
    default: return String(r)
    }
}

struct Req {
    let kind: Kind
    let minLen: Int
}

struct Contract {
    let label: String
    let short: String
    let reqs: [Req]
}

private func S(_ n: Int) -> Req { Req(kind: .set, minLen: n) }
private func R(_ n: Int) -> Req { Req(kind: .run, minLen: n) }

let contracts: [Contract] = [
    Contract(label: "2 sets of 3", short: "2S3", reqs: [S(3), S(3)]),
    Contract(label: "2 runs of 3", short: "2R3", reqs: [R(3), R(3)]),
    Contract(label: "1 set of 3 + 1 run of 4", short: "1S3 1R4", reqs: [S(3), R(4)]),
    Contract(label: "2 sets of 4", short: "2S4", reqs: [S(4), S(4)]),
    Contract(label: "2 runs of 4", short: "2R4", reqs: [R(4), R(4)]),
    Contract(label: "3 sets of 3", short: "3S3", reqs: [S(3), S(3), S(3)]),
    Contract(label: "1 run of 7", short: "1R7", reqs: [R(7)]),
    Contract(label: "2 sets of 5", short: "2S5", reqs: [S(5), S(5)]),
    Contract(label: "2 runs of 5", short: "2R5", reqs: [R(5), R(5)]),
    Contract(label: "1 set of 4 + 1 run of 5", short: "1S4 1R5", reqs: [S(4), R(5)]),
    Contract(label: "1 run of 9", short: "1R9", reqs: [R(9)]),
]

func buildDeck(_ n: Int) -> [Card] {
    var id = 0
    var d: [Card] = []
    for _ in 0..<n {
        for s in 0..<4 {
            for r in 1...13 {
                d.append(Card(id: id, r: r, s: s))
                id += 1
            }
        }
        d.append(Card(id: id, r: 0, s: -1)); id += 1
        d.append(Card(id: id, r: 0, s: -1)); id += 1
    }
    return d
}

// MARK: - Meld validation

struct Slot: Identifiable {
    let card: Card
    let asRank: Int
    var id: Int { card.id }
}

/// Returns ordered slots if the cards form a valid set or run, otherwise nil.
/// 2s and jokers are always wild. Aces are low or high in runs, with no wrapping.
func describe(_ cards: [Card], _ kind: Kind, _ wl: Bool) -> [Slot]? {
    let n = cards.count
    if n < 3 { return nil }
    let nat = cards.filter { !$0.isWild }
    let wilds = cards.filter { $0.isWild }
    if nat.isEmpty { return nil }
    if wl && wilds.count > nat.count { return nil }

    if kind == .set {
        let rank = nat[0].r
        if nat.contains(where: { $0.r != rank }) { return nil }
        return nat.map { Slot(card: $0, asRank: rank) } + wilds.map { Slot(card: $0, asRank: rank) }
    }

    let suit = nat[0].s
    if nat.contains(where: { $0.s != suit }) { return nil }
    if n > 14 { return nil }

    var st = 1
    while st + n - 1 <= 14 {
        let en = st + n - 1
        var at: [Int: Card] = [:]
        var aces: [Card] = []
        var ok = true
        for c in nat {
            if c.r == 1 {
                aces.append(c)
                continue
            }
            if c.r < st || c.r > en || at[c.r] != nil {
                ok = false
                break
            }
            at[c.r] = c
        }
        if ok {
            var ap: [Int] = []
            if st == 1 { ap.append(1) }
            if en == 14 { ap.append(14) }
            if aces.count <= ap.count {
                var pos = at
                for (i, a) in aces.enumerated() {
                    pos[ap[i]] = a
                }
                var out: [Slot] = []
                var wq = wilds
                for p in st...en {
                    let rank = (p == 14) ? 1 : p
                    if let c = pos[p] {
                        out.append(Slot(card: c, asRank: rank))
                    } else if !wq.isEmpty {
                        out.append(Slot(card: wq.removeFirst(), asRank: rank))
                    }
                }
                return out
            }
        }
        st += 1
    }
    return nil
}

func whyNot(_ cards: [Card], _ kind: Kind, _ minLen: Int, _ wl: Bool) -> String {
    if cards.isEmpty { return "Empty" }
    if cards.count < minLen { return "Needs \(minLen - cards.count) more" }
    let nat = cards.filter { !$0.isWild }
    if nat.isEmpty { return "Needs a natural card" }
    if wl && cards.count - nat.count > nat.count { return "Too many wilds" }
    if kind == .set {
        if nat.contains(where: { $0.r != nat[0].r }) { return "Set cards must match in rank" }
    } else {
        if nat.contains(where: { $0.s != nat[0].s }) { return "Run cards must share a suit" }
    }
    if describe(cards, kind, wl) != nil { return "" }
    return kind == .set ? "Not a set" : "Duplicate rank or gap too big"
}

/// Backtracking search: can this hand complete the contract? Returns groups of cards or nil.
func findMelds(_ hand: [Card], _ reqs: [Req], _ wl: Bool) -> [[Card]]? {
    let wilds = hand.filter { $0.isWild }
    let nats = hand.filter { !$0.isWild }
    var used = Set<Int>()

    func candidates(_ kind: Kind, _ len: Int) -> [[Card]] {
        var out: [[Card]] = []
        let freeW = wilds.filter { !used.contains($0.id) }
        if kind == .set {
            for r in 1...13 where r != 2 {
                let group = nats.filter { $0.r == r && !used.contains($0.id) }
                var m = min(len, group.count)
                while m >= 1 {
                    let w = len - m
                    if w <= freeW.count && !(wl && w > m) {
                        out.append(Array(group.prefix(m)) + Array(freeW.prefix(w)))
                    }
                    m -= 1
                }
            }
        } else {
            for suit in 0..<4 {
                let ofSuit = nats.filter { $0.s == suit && !used.contains($0.id) }
                var st = 1
                while st + len - 1 <= 14 {
                    var cards: [Card] = []
                    var local = Set<Int>()
                    var w = 0
                    for p in st..<(st + len) {
                        let rank = (p == 14) ? 1 : p
                        if rank != 2, let c = ofSuit.first(where: { $0.r == rank && !local.contains($0.id) }) {
                            cards.append(c)
                            local.insert(c.id)
                        } else {
                            w += 1
                        }
                    }
                    let m = cards.count
                    if m > 0 && w <= freeW.count && !(wl && w > m) {
                        out.append(cards + Array(freeW.prefix(w)))
                    }
                    st += 1
                }
            }
        }
        return out
    }

    func rec(_ i: Int, _ acc: [[Card]]) -> [[Card]]? {
        if i == reqs.count { return acc }
        let req = reqs[i]
        for cand in candidates(req.kind, req.minLen) {
            for c in cand { used.insert(c.id) }
            if let r = rec(i + 1, acc + [cand]) { return r }
            for c in cand { used.remove(c.id) }
        }
        return nil
    }

    return rec(0, [])
}

// MARK: - Game state

struct SetupPlayer: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var cpu: Bool
}

struct GameSetup: Codable {
    var players: [SetupPlayer]
    var handSize: Int
    var wildLimit: Bool
    var hints: Bool

    static let standard = GameSetup(
        players: [SetupPlayer(name: "Player 1", cpu: false), SetupPlayer(name: "Player 2", cpu: true)],
        handSize: 13, wildLimit: false, hints: false)
}

struct Player: Codable, Identifiable {
    var id: Int
    var name: String
    var cpu: Bool
    var hand: [Card] = []
    var down: Bool = false
    var total: Int = 0
}

struct Meld: Codable, Identifiable {
    var id: Int
    var owner: Int
    var kind: Kind
    var cards: [Card]
}

struct RoundResult: Codable {
    var round: Int
    var out: Int
    var scores: [Int]
}

enum Screen: String, Codable {
    case turn, handoff, roundEnd, final
}

enum Phase: String, Codable {
    case draw, play
}

struct GameState: Codable {
    var wl: Bool
    var hints: Bool
    var handSize: Int
    var players: [Player]
    var round: Int = -1
    var turn: Int = 0
    var phase: Phase = .draw
    var stock: [Card] = []
    var discardPile: [Card] = []
    var melds: [Meld] = []
    var screen: Screen = .turn
    var log: [String] = []
    var turnLog: [String] = []
    var lastTurn: [String] = []
    var results: [RoundResult] = []
    var hist: [[String]] = []

    static func new(_ s: GameSetup) -> GameState {
        let ps = s.players.enumerated().map { Player(id: $0.offset, name: $0.element.name, cpu: $0.element.cpu) }
        var g = GameState(wl: s.wildLimit, hints: s.hints, handSize: s.handSize, players: ps)
        g.dealRound()
        return g
    }

    var current: Player { players[turn] }
    var humanCount: Int { players.filter { !$0.cpu }.count }
    var needHandoff: Bool { !players[turn].cpu && humanCount > 1 }
    var contract: Contract { contracts[round] }

    mutating func addLog(_ t: String) {
        log.append(t)
        if log.count > 40 { log.removeFirst() }
        if round >= 0 && round < hist.count { hist[round].append(t) }
        turnLog.append(t)
    }

    mutating func dealRound() {
        round += 1
        let n = players.count
        var deck = buildDeck(max(2, n)).shuffled()
        for i in players.indices {
            players[i].hand = []
            players[i].down = false
        }
        for _ in 0..<handSize {
            for i in players.indices {
                players[i].hand.append(deck.removeLast())
            }
        }
        discardPile = [deck.removeLast()]
        stock = deck
        melds = []
        turn = round % n
        phase = .draw
        turnLog = []
        lastTurn = []
        log = []
        while hist.count <= round { hist.append([]) }
        hist[round] = ["Round \(round + 1): \(contracts[round].label). \(players[turn].name) goes first."]
        screen = needHandoff ? .handoff : .turn
    }

    private mutating func refill() {
        if stock.isEmpty && discardPile.count > 1 {
            let top = discardPile.removeLast()
            stock = discardPile.shuffled()
            discardPile = [top]
        }
    }

    @discardableResult
    mutating func drawStock() -> Card? {
        refill()
        guard !stock.isEmpty else { return nil }
        let c = stock.removeLast()
        players[turn].hand.append(c)
        phase = .play
        addLog("\(players[turn].name) drew from the deck")
        return c
    }

    @discardableResult
    mutating func takeDiscard() -> Card? {
        guard let c = discardPile.popLast() else { return nil }
        players[turn].hand.append(c)
        phase = .play
        addLog("\(players[turn].name) took the \(c.name)")
        return c
    }

    @discardableResult
    mutating func layDown(_ idx: Int, _ groups: [[Card]]) -> Bool {
        let reqs = contracts[round].reqs
        if players[idx].down || groups.count != reqs.count { return false }
        var ids = Set<Int>()
        for (i, g) in groups.enumerated() {
            if g.count < reqs[i].minLen || describe(g, reqs[i].kind, wl) == nil { return false }
            for c in g {
                if ids.contains(c.id) || !players[idx].hand.contains(where: { $0.id == c.id }) { return false }
                ids.insert(c.id)
            }
        }
        players[idx].hand.removeAll { ids.contains($0.id) }
        for (i, g) in groups.enumerated() {
            melds.append(Meld(id: melds.count, owner: idx, kind: reqs[i].kind, cards: g))
        }
        players[idx].down = true
        addLog("\(players[idx].name) went down (\(contracts[round].label))")
        if players[idx].hand.isEmpty { goOut(idx) }
        return true
    }

    @discardableResult
    mutating func tryHit(_ mi: Int, _ cards: [Card]) -> Bool {
        guard mi >= 0, mi < melds.count, !cards.isEmpty, players[turn].down else { return false }
        let arr = melds[mi].cards + cards
        if describe(arr, melds[mi].kind, wl) == nil { return false }
        let ids = Set(cards.map { $0.id })
        for c in cards {
            if !players[turn].hand.contains(where: { $0.id == c.id }) { return false }
        }
        melds[mi].cards = arr
        players[turn].hand.removeAll { ids.contains($0.id) }
        let ownerName = players[melds[mi].owner].name
        let kindName = melds[mi].kind == .set ? "set" : "run"
        addLog("\(players[turn].name) added \(cards.map { $0.name }.joined(separator: " ")) to \(ownerName)'s \(kindName)")
        if players[turn].hand.isEmpty { goOut(turn) }
        return true
    }

    @discardableResult
    mutating func discardCard(_ id: Int) -> Bool {
        guard phase == .play, let i = players[turn].hand.firstIndex(where: { $0.id == id }) else { return false }
        let c = players[turn].hand.remove(at: i)
        discardPile.append(c)
        addLog("\(players[turn].name) discarded \(c.name)")
        if players[turn].hand.isEmpty { goOut(turn) } else { nextTurn() }
        return true
    }

    mutating func nextTurn() {
        lastTurn = turnLog
        turnLog = []
        turn = (turn + 1) % players.count
        phase = .draw
        screen = needHandoff ? .handoff : .turn
    }

    mutating func goOut(_ idx: Int) {
        var scores: [Int] = []
        for i in players.indices {
            scores.append(i == idx ? 0 : players[i].hand.reduce(0) { $0 + $1.points })
        }
        for i in players.indices { players[i].total += scores[i] }
        results.append(RoundResult(round: round, out: idx, scores: scores))
        screen = .roundEnd
        addLog("\(players[idx].name) went out!")
        for i in players.indices where i != idx {
            let hs = players[i].hand.map { $0.name }.joined(separator: " ")
            addLog("\(players[i].name) counted \(scores[i]) (\(hs.isEmpty ? "no cards" : hs))")
        }
    }

    mutating func nextRound() {
        if round >= contracts.count - 1 {
            screen = .final
        } else {
            dealRound()
        }
    }

    // MARK: Computer player

    func usefulness(_ card: Card, _ hand: [Card]) -> Double {
        if card.isWild { return 100 }
        let reqs = contracts[round].reqs
        let wS = reqs.contains(where: { $0.kind == .set }) ? 1.0 : 0.25
        let wR = reqs.contains(where: { $0.kind == .run }) ? 1.0 : 0.25
        var u = 0.0
        for c in hand where c.id != card.id && !c.isWild {
            if c.r == card.r { u += 3 * wS }
            if c.s == card.s {
                var d = abs(c.r - card.r)
                if card.r == 1 { d = min(d, abs(14 - c.r)) }
                if c.r == 1 { d = min(d, abs(14 - card.r)) }
                if d == 1 { u += 3 * wR } else if d == 2 { u += 1.5 * wR }
            }
        }
        return u
    }

    func chooseDiscard(_ hand: [Card], down: Bool) -> Card {
        var best = hand[0]
        var bestU = Double.infinity
        var bestP = 0
        for c in hand {
            let u: Double = down ? (c.isWild ? 1000.0 : 0.0) : usefulness(c, hand)
            let p = -c.points
            if u < bestU || (u == bestU && p < bestP) {
                best = c
                bestU = u
                bestP = p
            }
        }
        return best
    }

    @discardableResult
    mutating func cpuDraw() -> Card? {
        let p = players[turn]
        var take = false
        if let top = discardPile.last {
            let withTop = p.hand + [top]
            if p.down {
                take = melds.contains(where: { describe($0.cards + [top], $0.kind, wl) != nil })
            } else if top.isWild {
                take = true
            } else if findMelds(withTop, contracts[round].reqs, wl) != nil {
                take = true
            } else if usefulness(top, withTop) >= 3 && chooseDiscard(withTop, down: false).id != top.id {
                take = true
            }
        }
        return take ? takeDiscard() : drawStock()
    }

    @discardableResult
    mutating func cpuLay() -> Bool {
        let p = players[turn]
        if p.down { return false }
        guard let sol = findMelds(p.hand, contracts[round].reqs, wl) else { return false }
        return layDown(turn, sol)
    }

    @discardableResult
    mutating func cpuHit() -> Bool {
        guard players[turn].down else { return false }
        let hand = players[turn].hand
        for c in hand {
            for mi in melds.indices {
                if tryHit(mi, [c]) { return true }
            }
        }
        return false
    }

    @discardableResult
    mutating func cpuDiscard() -> Bool {
        let p = players[turn]
        if p.hand.isEmpty { return false }
        return discardCard(chooseDiscard(p.hand, down: p.down).id)
    }
}
