import Foundation

// MARK: - Wire types (match server/server.js)

struct OnlinePlayer: Codable {
    let id: Int
    let name: String
    let down: Bool
    let total: Int
    let handCount: Int
    let hand: [Card]?
}

struct OnlineMeld: Codable {
    let id: Int
    let owner: Int
    let kind: Kind
    let cards: [Card]
}

struct OnlineSettings: Codable {
    let handSize: Int
    let wildLimit: Bool
}

struct OnlineView: Codable {
    let code: String
    let version: Int
    let started: Bool
    let ended: Bool?
    let seat: Int
    let maxSeats: Int
    let lobby: [String]
    let settings: OnlineSettings
    // The rest is present once the host has started the game.
    let wl: Bool?
    let handSize: Int?
    let players: [OnlinePlayer]?
    let round: Int?
    let turn: Int?
    let phase: Phase?
    let stockCount: Int?
    let discardCount: Int?
    let discardTop: Card?
    let melds: [OnlineMeld]?
    let screen: Screen?
    let log: [String]?
    let lastTurn: [String]?
    let results: [RoundResult]?
    let hist: [[String]]?
}

struct PollResponse: Codable {
    let version: Int
    let unchanged: Bool?
    let view: OnlineView?
}

struct JoinResponse: Codable {
    let code: String
    let seat: Int
    let token: String
    let version: Int
}

struct OnlineSession: Codable {
    var baseURL: String
    var code: String
    var token: String
    var seat: Int
}

private struct APIErrorBody: Codable {
    let error: String
}

enum APIError: Error {
    case server(Int, String)
    case badURL
    case network

    var message: String {
        switch self {
        case .server(_, let m): return m
        case .badURL: return "That server address doesn't look right."
        case .network: return "Can't reach the server."
        }
    }
}

// MARK: - Client

struct OnlineClient {
    let base: String

    func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil,
                               token: String? = nil, timeout: TimeInterval = 15) async throws -> T {
        guard let url = URL(string: base + path) else { throw APIError.badURL }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        if let token = token {
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.network }
        if http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error ?? "Error \(http.statusCode)"
            throw APIError.server(http.statusCode, msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Server view -> GameState (so the existing screens can draw it)

extension OnlineView {
    func toGameState() -> GameState? {
        guard started, let ps = players, let round = round, let turn = turn,
              let phase = phase, let screen = screen else { return nil }
        let placeholder = Card(id: -1, r: 0, s: -1)
        let built: [Player] = ps.map { p in
            let h: [Card] = p.hand ?? Array(repeating: placeholder, count: p.handCount)
            return Player(id: p.id, name: p.name, cpu: false, hand: h, down: p.down, total: p.total)
        }
        var g = GameState(wl: wl ?? false, hints: false, handSize: handSize ?? 13, players: built)
        g.round = round
        g.turn = turn
        g.phase = phase
        g.screen = screen
        g.stock = Array(repeating: placeholder, count: stockCount ?? 0)
        var pile: [Card] = Array(repeating: placeholder, count: max(0, (discardCount ?? 0) - 1))
        if let top = discardTop { pile.append(top) }
        g.discardPile = pile
        g.melds = (melds ?? []).map { Meld(id: $0.id, owner: $0.owner, kind: $0.kind, cards: $0.cards) }
        g.log = log ?? []
        g.lastTurn = lastTurn ?? []
        g.results = results ?? []
        g.hist = hist ?? []
        return g
    }
}
