import SwiftUI

enum Sheet: String, Identifiable {
    case scores, rules, menu, lay, join
    var id: String { rawValue }
}

struct LayDraft {
    var slots: [[Int]]
    var sel: Set<Int>
}

struct PendingJoin {
    var code: String
    var base: String
}

@MainActor
final class GameStore: ObservableObject {
    // Local (pass-and-play / computer) game
    @Published var setup: GameSetup {
        didSet { saveSetup() }
    }
    @Published var game: GameState? {
        didSet {
            saveGame()
            runCpuIfNeeded()
        }
    }
    @Published var showHome = true
    @Published var selected = Set<Int>()
    @Published var sheet: Sheet?
    @Published var lay: LayDraft?
    @Published var freshID: Int?
    @Published var toastText: String?
    @Published var histRound: Int?
    @Published var confirmNew = false

    // Online game
    @Published var online: OnlineSession?
    @Published var lobby: OnlineView?
    @Published var connectionProblem = false
    @Published var busy = false
    @Published var pendingJoin: PendingJoin?
    @Published var onlineSeats = 2
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: GameStore.serverKey) }
    }
    @Published var onlineName: String {
        didSet { UserDefaults.standard.set(onlineName, forKey: GameStore.nameKey) }
    }

    private var cpuTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var latestVersion = 0
    private var handOrder: [Int] = []

    private static let gameKey = "eh-game-v1"
    private static let setupKey = "eh-setup-v1"
    private static let serverKey = "eh-server-v1"
    private static let nameKey = "eh-name-v1"
    private static let onlineKey = "eh-online-v1"

    init() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: GameStore.setupKey),
           let s = try? JSONDecoder().decode(GameSetup.self, from: d), s.players.count >= 2 {
            setup = s
        } else {
            setup = GameSetup.standard
        }
        serverURL = ud.string(forKey: GameStore.serverKey) ?? ""
        onlineName = ud.string(forKey: GameStore.nameKey) ?? ""
        if let d = ud.data(forKey: GameStore.onlineKey),
           let s = try? JSONDecoder().decode(OnlineSession.self, from: d) {
            online = s
            showHome = false
        } else if let d = ud.data(forKey: GameStore.gameKey),
                  let g = try? JSONDecoder().decode(GameState.self, from: d) {
            game = g
        }
        if online != nil { startPolling() }
    }

    // MARK: Persistence

    private func saveSetup() {
        if let d = try? JSONEncoder().encode(setup) {
            UserDefaults.standard.set(d, forKey: GameStore.setupKey)
        }
    }

    private func saveGame() {
        // Online games live on the server; never overwrite the saved local game with one.
        if online != nil { return }
        if let g = game, let d = try? JSONEncoder().encode(g) {
            UserDefaults.standard.set(d, forKey: GameStore.gameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: GameStore.gameKey)
        }
    }

    private func loadLocalGame() -> GameState? {
        guard let d = UserDefaults.standard.data(forKey: GameStore.gameKey) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: d)
    }

    // MARK: Helpers

    func showToast(_ t: String) {
        toastText = t
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self.toastText == t { self.toastText = nil }
        }
    }

    /// Seat whose hand this device shows.
    func viewer(_ g: GameState) -> Int {
        online?.seat ?? g.turn
    }

    /// True when this device may act right now.
    func myTurn(_ g: GameState) -> Bool {
        if let s = online { return g.screen == .turn && g.turn == s.seat }
        return g.screen == .turn && !g.players[g.turn].cpu && !showHome
    }

    private func resetTransient() {
        selected = []
        freshID = nil
        sheet = nil
        lay = nil
    }

    // MARK: Local setup actions

    func addPlayer() {
        if setup.players.count < 6 {
            setup.players.append(SetupPlayer(name: "Player \(setup.players.count + 1)", cpu: true))
        }
    }

    func removePlayer(_ id: UUID) {
        if setup.players.count > 2 {
            setup.players.removeAll { $0.id == id }
        }
    }

    func start() {
        for i in setup.players.indices {
            let n = setup.players[i].name.trimmingCharacters(in: .whitespaces)
            setup.players[i].name = n.isEmpty ? "Player \(i + 1)" : n
        }
        game = GameState.new(setup)
        showHome = false
        resetTransient()
    }

    func playAgain() {
        game = GameState.new(setup)
        resetTransient()
    }

    func resume() {
        showHome = false
        resetTransient()
        runCpuIfNeeded()
    }

    /// Abandon the current game (online: leave it).
    func abandon() {
        if online != nil {
            leaveOnline()
            return
        }
        game = nil
        showHome = true
        confirmNew = false
        resetTransient()
    }

    func goHome() {
        showHome = true
        sheet = nil
    }

    // MARK: Turn actions (local game, or sent to the server in an online game)

    func handoffGo() {
        guard var g = game else { return }
        g.screen = .turn
        game = g
        selected = []
        freshID = nil
    }

    private func myHandIDs() -> Set<Int> {
        guard let g = game else { return [] }
        return Set(g.players[viewer(g)].hand.map { $0.id })
    }

    func drawFromStock() {
        guard var g = game, myTurn(g), g.phase == .draw else { return }
        if online != nil {
            send(["type": "draw", "from": "stock"], markFresh: true)
            return
        }
        if let c = g.drawStock() {
            freshID = c.id
        } else {
            showToast("No cards left to draw")
        }
        game = g
    }

    func takeTopDiscard() {
        guard var g = game, myTurn(g), g.phase == .draw else { return }
        if online != nil {
            send(["type": "draw", "from": "discard"], markFresh: true)
            return
        }
        if let c = g.takeDiscard() { freshID = c.id }
        game = g
    }

    func toggleCard(_ id: Int) {
        guard let g = game, myTurn(g), g.phase == .play else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func sortedHand(_ hand: [Card], by: String) -> [Card] {
        func key(_ c: Card) -> [Int] {
            if c.isWild { return [9, c.r, 0] }
            if by == "rank" { return [0, c.r, c.s] }
            return [0, c.s * 20 + c.r, 0]
        }
        return hand.sorted { a, b in
            let x = key(a)
            let y = key(b)
            if x[0] != y[0] { return x[0] < y[0] }
            if x[1] != y[1] { return x[1] < y[1] }
            return x[2] < y[2]
        }
    }

    func sortHand(by: String) {
        guard var g = game else { return }
        if let s = online {
            let h = sortedHand(g.players[s.seat].hand, by: by)
            handOrder = h.map { $0.id }
            g.players[s.seat].hand = h
            game = g
            return
        }
        guard myTurn(g) else { return }
        g.players[g.turn].hand = sortedHand(g.players[g.turn].hand, by: by)
        game = g
    }

    func discardSelected() {
        guard var g = game, myTurn(g), g.phase == .play else { return }
        guard selected.count == 1, let id = selected.first else {
            showToast("Select one card to discard")
            return
        }
        if online != nil {
            send(["type": "discard", "card": id])
            resetTransient()
            return
        }
        g.discardCard(id)
        game = g
        resetTransient()
    }

    func hit(_ meldIndex: Int) {
        guard var g = game, myTurn(g), g.phase == .play else { return }
        let me = g.players[viewer(g)]
        if !me.down {
            showToast("Go down before adding to melds")
            return
        }
        if selected.isEmpty {
            showToast("Select the cards to add first")
            return
        }
        let cards = me.hand.filter { selected.contains($0.id) }
        if online != nil {
            // Quick local check so a bad tap gives instant feedback; the server still decides.
            guard meldIndex < g.melds.count,
                  describe(g.melds[meldIndex].cards + cards, g.melds[meldIndex].kind, g.wl) != nil else {
                showToast("That doesn't fit this meld")
                return
            }
            send(["type": "hit", "meld": meldIndex, "cards": cards.map { $0.id }])
            selected = []
            return
        }
        if g.tryHit(meldIndex, cards) {
            game = g
            selected = []
            if g.screen != .turn { resetTransient() }
        } else {
            showToast("That doesn't fit this meld")
        }
    }

    func nextRound() {
        guard var g = game else { return }
        if online != nil {
            send(["type": "next", "round": g.round])
            resetTransient()
            return
        }
        g.nextRound()
        game = g
        resetTransient()
    }

    // MARK: Lay down

    func openLay() {
        guard let g = game, myTurn(g), g.phase == .play, !g.players[viewer(g)].down else { return }
        lay = LayDraft(slots: g.contract.reqs.map { _ in [Int]() }, sel: selected)
        sheet = .lay
    }

    func layToggle(_ id: Int) {
        guard var L = lay else { return }
        if L.sel.contains(id) { L.sel.remove(id) } else { L.sel.insert(id) }
        lay = L
    }

    func slotAdd(_ i: Int) {
        guard var L = lay else { return }
        L.slots[i].append(contentsOf: Array(L.sel))
        L.sel = []
        lay = L
    }

    func slotRemove(_ i: Int, _ id: Int) {
        guard var L = lay else { return }
        L.slots[i].removeAll { $0 == id }
        lay = L
    }

    func layClear() {
        guard var L = lay else { return }
        L.slots = L.slots.map { _ in [Int]() }
        L.sel = []
        lay = L
    }

    func layAutoFill() {
        guard let g = game, var L = lay else { return }
        let hand = g.players[viewer(g)].hand
        if let sol = findMelds(hand, g.contract.reqs, g.wl) {
            L.slots = sol.map { grp in grp.map { $0.id } }
            L.sel = []
            lay = L
        } else {
            showToast("No complete contract in this hand yet")
        }
    }

    func layGo() {
        guard var g = game, let L = lay else { return }
        let seat = viewer(g)
        let hand = g.players[seat].hand
        let groups: [[Card]] = L.slots.map { ids in
            ids.compactMap { id in hand.first(where: { $0.id == id }) }
        }
        let reqs = g.contract.reqs
        var valid = groups.count == reqs.count
        if valid {
            for (i, grp) in groups.enumerated() where grp.count < reqs[i].minLen || describe(grp, reqs[i].kind, g.wl) == nil {
                valid = false
            }
        }
        if !valid {
            showToast("Those cards do not complete the contract")
            return
        }
        if online != nil {
            send(["type": "laydown", "groups": L.slots])
            sheet = nil
            lay = nil
            selected = []
            return
        }
        if g.layDown(g.turn, groups) {
            game = g
            sheet = nil
            lay = nil
            selected = []
            if g.screen != .turn {
                resetTransient()
            } else {
                showToast("You are down. Add to melds or discard.")
            }
        } else {
            showToast("Those cards do not complete the contract")
        }
    }

    // MARK: Computer player (local games only)

    func runCpuIfNeeded() {
        guard online == nil, let g = game, !showHome, g.screen == .turn, g.players[g.turn].cpu, cpuTask == nil else { return }
        cpuTask = Task { [weak self] in
            await self?.cpuLoop()
            self?.cpuTask = nil
        }
    }

    private func cpuIsLive(turn t: Int) -> Bool {
        guard let g = game else { return false }
        return !showHome && g.screen == .turn && g.turn == t
    }

    private func nap(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    private func cpuLoop() async {
        while let g0 = game, !showHome, g0.screen == .turn, g0.players[g0.turn].cpu {
            let t = g0.turn
            await nap(900)
            if !cpuIsLive(turn: t) { break }

            if game?.phase == .draw {
                guard var g = game else { break }
                let c = g.cpuDraw()
                if c == nil { g.nextTurn() }
                game = g
                if c == nil { continue }
                await nap(900)
                if !cpuIsLive(turn: t) { break }
            }

            if var g = game {
                if g.cpuLay() {
                    game = g
                    await nap(1100)
                    if !cpuIsLive(turn: t) { break }
                }
            }

            while cpuIsLive(turn: t) {
                guard var g = game else { break }
                if !g.cpuHit() { break }
                game = g
                await nap(800)
            }
            if !cpuIsLive(turn: t) { break }

            if var g = game {
                g.cpuDiscard()
                game = g
            }
            selected = []
        }
    }

    // MARK: Online play

    var inviteURL: URL? {
        guard let s = online else { return nil }
        return URL(string: s.baseURL + "/join/" + s.code)
    }

    func normalizedServer(_ raw: String? = nil) -> String? {
        var t = (raw ?? serverURL).trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }

    private func cleanedName() -> String {
        let n = onlineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Player" : n
    }

    private func report(_ e: Error) {
        if let a = e as? APIError {
            showToast(a.message)
        } else {
            showToast("Can't reach the server. Check the address and your connection.")
        }
    }

    func hostOnline() {
        guard let base = normalizedServer() else {
            showToast("Enter your server address first")
            return
        }
        let body: [String: Any] = [
            "name": cleanedName(),
            "maxSeats": onlineSeats,
            "handSize": setup.handSize,
            "wildLimit": setup.wildLimit,
        ]
        busy = true
        Task {
            defer { busy = false }
            do {
                let r: JoinResponse = try await OnlineClient(base: base).request("POST", "/api/games", body: body)
                beginSession(OnlineSession(baseURL: base, code: r.code, token: r.token, seat: r.seat))
            } catch {
                report(error)
            }
        }
    }

    func joinWithCode(_ raw: String) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 5 else {
            showToast("Game codes are 5 characters")
            return
        }
        guard let base = normalizedServer() else {
            showToast("Enter the server address first")
            return
        }
        joinOnline(code: code, base: base, name: cleanedName())
    }

    func joinOnline(code: String, base: String, name: String) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let r: JoinResponse = try await OnlineClient(base: base).request(
                    "POST", "/api/games/\(code)/join", body: ["name": name])
                serverURL = base
                onlineName = name
                pendingJoin = nil
                beginSession(OnlineSession(baseURL: base, code: r.code, token: r.token, seat: r.seat))
            } catch {
                report(error)
            }
        }
    }

    /// Handles highsociety://join/CODE?server=... and https://server/join/CODE
    func handleURL(_ url: URL) {
        var code: String?
        var base: String?
        if url.scheme == "highsociety" {
            code = url.pathComponents.filter { $0 != "/" }.last
            if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                base = items.first(where: { $0.name == "server" })?.value
            }
        } else if url.scheme == "https" || url.scheme == "http" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2 && parts[0] == "join" {
                code = parts[1]
                if let host = url.host {
                    base = (url.scheme ?? "https") + "://" + host + (url.port.map { ":\($0)" } ?? "")
                }
            }
        }
        guard let c = code, c.count == 5, let b = normalizedServer(base ?? serverURL) else { return }
        pendingJoin = PendingJoin(code: c.uppercased(), base: b)
        if online == nil {
            sheet = .join
        } else {
            showToast("Leave your current online game before joining another")
        }
    }

    func startOnlineGame() {
        send(["type": "start"])
    }

    func leaveOnline(message: String? = nil) {
        pollTask?.cancel()
        pollTask = nil
        UserDefaults.standard.removeObject(forKey: GameStore.onlineKey)
        online = nil
        lobby = nil
        latestVersion = 0
        handOrder = []
        connectionProblem = false
        confirmNew = false
        resetTransient()
        game = loadLocalGame()
        showHome = true
        if let m = message { showToast(m) }
    }

    private func beginSession(_ s: OnlineSession) {
        online = s              // set first, so the saved local game is left alone
        game = nil
        lobby = nil
        latestVersion = 0
        handOrder = []
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: GameStore.onlineKey)
        }
        showHome = false
        resetTransient()
        startPolling()
    }

    private func apply(_ v: OnlineView) {
        if v.version < latestVersion { return }
        latestVersion = v.version
        lobby = v
        if v.ended == true {
            leaveOnline(message: "The host ended the game")
            return
        }
        guard var g = v.toGameState(), v.seat < g.players.count else {
            game = nil
            return
        }
        g.players[v.seat].hand = orderHand(g.players[v.seat].hand)
        let ids = Set(g.players[v.seat].hand.map { $0.id })
        selected = selected.intersection(ids)
        game = g
    }

    private func orderHand(_ hand: [Card]) -> [Card] {
        var byID: [Int: Card] = [:]
        for c in hand { byID[c.id] = c }
        var out: [Card] = []
        for id in handOrder {
            if let c = byID[id] { out.append(c) }
        }
        let have = Set(out.map { $0.id })
        for c in hand where !have.contains(c.id) { out.append(c) }
        handOrder = out.map { $0.id }
        return out
    }

    private func send(_ body: [String: Any], markFresh: Bool = false) {
        guard let s = online else { return }
        let before = myHandIDs()
        Task {
            do {
                let resp: PollResponse = try await OnlineClient(base: s.baseURL).request(
                    "POST", "/api/games/\(s.code)/action", body: body, token: s.token)
                if let v = resp.view { apply(v) }
                if markFresh, let g = game {
                    let now = g.players[viewer(g)].hand.map { $0.id }
                    freshID = now.first(where: { !before.contains($0) })
                }
            } catch let e as APIError {
                if case .server(let status, let msg) = e {
                    // 409: the game moved on without us. The next poll refreshes the screen.
                    if status != 409 { showToast(msg) }
                } else {
                    showToast(e.message)
                }
            } catch {
                showToast("Can't reach the server")
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func pollLoop() async {
        while let s = online, !Task.isCancelled {
            do {
                let resp: PollResponse = try await OnlineClient(base: s.baseURL).request(
                    "GET", "/api/games/\(s.code)/state?since=\(latestVersion)", token: s.token, timeout: 40)
                connectionProblem = false
                if let v = resp.view { apply(v) }
            } catch let e as APIError {
                if case .server(let status, _) = e, status == 401 || status == 404 || status == 410 {
                    leaveOnline(message: "That game is no longer available")
                    return
                }
                connectionProblem = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                if Task.isCancelled { return }
                connectionProblem = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
