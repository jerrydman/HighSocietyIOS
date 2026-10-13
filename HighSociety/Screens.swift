import SwiftUI

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            content
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
            if let t = store.toastText {
                Text(t)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.bg)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.fg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 60)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $store.sheet) { s in
            SheetHost(kind: s).environmentObject(store)
        }
        .onAppear { store.runCpuIfNeeded() }
        .onOpenURL { store.handleURL($0) }
        .overlay(alignment: .bottom) {
            if store.connectionProblem && store.online != nil {
                Text("Reconnecting…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.accentFg)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.bad)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.online != nil && store.game == nil {
            LobbyView()
        } else if store.online == nil && (store.showHome || store.game == nil) {
            HomeView()
        } else if let g = store.game {
            switch g.screen {
            case .handoff: HandoffView(g: g)
            case .roundEnd: RoundEndView(g: g)
            case .final: FinalView(g: g)
            case .turn: TurnView(g: g)
            }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("High Society")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.fg)
                    Text("Contract rummy in eleven rounds. Pass the phone around, play the computer, or play friends online.")
                        .foregroundColor(Theme.muted)
                }
                .padding(.top, 12)

                if let g = store.game, g.screen != .final {
                    Button("Resume game · round \(g.round + 1) of 11") { store.resume() }
                        .buttonStyle(PrimaryButton())
                }

                playersPanel
                rulesPanel
                OnlinePanel()

                Button("Deal round 1") { store.start() }
                    .buttonStyle(PrimaryButton())

                Button("Contracts, points and rules") { store.sheet = .rules }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
    }

    private var playersPanel: some View {
        Panel {
            Text("Players").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Theme.fg)
            ForEach($store.setup.players) { $p in
                HStack(spacing: 8) {
                    TextField("Name", text: $p.name)
                        .textFieldStyle(.roundedBorder)
                    Picker("Type", selection: $p.cpu) {
                        Text("Person").tag(false)
                        Text("CPU").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    if store.setup.players.count > 2 {
                        Button {
                            store.removePlayer(p.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                        }
                        .accessibilityLabel("Remove player")
                    }
                }
            }
            if store.setup.players.count < 6 {
                Button("Add player") { store.addPlayer() }
                    .buttonStyle(PrimaryButton(ghost: true))
            }
            let decks = max(2, store.setup.players.count)
            Text("\(store.setup.players.count) players use \(decks) decks (\(decks * 54) cards, with jokers).")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
        }
    }

    private var rulesPanel: some View {
        Panel {
            Text("House rules").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Theme.fg)
            HStack {
                Text("Cards dealt").foregroundColor(Theme.fg)
                Spacer()
                Picker("Cards dealt", selection: $store.setup.handSize) {
                    Text("10").tag(10)
                    Text("13").tag(13)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            Toggle(isOn: $store.setup.wildLimit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wilds can't outnumber naturals").foregroundColor(Theme.fg)
                    Text("In any set or run, 2s and jokers stay in the minority")
                        .font(.system(size: 13)).foregroundColor(Theme.muted)
                }
            }
            Toggle(isOn: $store.setup.hints) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-fill hint").foregroundColor(Theme.fg)
                    Text("Lets the lay-down screen suggest melds")
                        .font(.system(size: 13)).foregroundColor(Theme.muted)
                }
            }
        }
    }
}

// MARK: - Turn screen

struct TurnView: View {
    let g: GameState

    var body: some View {
        VStack(spacing: 10) {
            TopBar(g: g)
            PlayersStrip(g: g)
            DeckRow(g: g)
            MeldsView(g: g)
            HandPanel(g: g)
        }
        .padding(.vertical, 8)
    }
}

struct TopBar: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ROUND \(g.round + 1) OF \(contracts.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.ink.opacity(0.7))
                Text(g.contract.label)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent, lineWidth: 3))

            smallButton("Scores") { store.histRound = nil; store.sheet = .scores }
            smallButton("Menu") { store.confirmNew = false; store.sheet = .menu }
        }
        .frame(height: 50)
    }

    private func smallButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.fg)
                .frame(width: 52)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct PlayersStrip: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(g.players) { p in
                    Button {
                        store.histRound = nil
                        store.sheet = .scores
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name + (p.cpu ? " (CPU)" : "") + (store.online?.seat == p.id ? " (you)" : ""))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.fg)
                                .lineLimit(1)
                            HStack(spacing: 3) {
                                Text("\(p.hand.count) cards · \(p.total) pts")
                                    .foregroundColor(Theme.muted)
                                if p.down {
                                    Text("· down").foregroundColor(Theme.good).fontWeight(.semibold)
                                }
                            }
                            .font(.system(size: 12))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .frame(minWidth: 84, alignment: .leading)
                        .background(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(p.id == g.turn ? Theme.accent : Theme.line, lineWidth: p.id == g.turn ? 2 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct DeckRow: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        let canDraw = store.myTurn(g) && g.phase == .draw
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Button { store.drawFromStock() } label: {
                    DeckBack(count: g.stock.count, ready: canDraw)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Draw from deck")
                Text("Deck").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            VStack(spacing: 4) {
                if let top = g.discardPile.last {
                    Button { store.takeTopDiscard() } label: {
                        CardView(card: top, width: 58)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(canDraw ? Theme.accent : Color.clear, lineWidth: 3)
                                    .padding(-5)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .frame(width: 58, height: 81)
                }
                Text("Discard").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(g.log.suffix(3).reversed().enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.system(size: 12.5))
                        .foregroundColor(item.offset == 0 ? Theme.fg : Theme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }
}

func meldLabel(_ m: Meld, _ slots: [Slot]) -> String {
    guard let nat = slots.first(where: { !$0.card.isWild }), let first = slots.first, let last = slots.last else { return "" }
    if m.kind == .set { return "Set of \(rankText(nat.card.r))s" }
    return "Run \(nat.card.suitSymbol) \(rankText(first.asRank)) to \(rankText(last.asRank))"
}

struct MeldsView: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        let tapOK = store.myTurn(g) && g.phase == .play && g.players[store.viewer(g)].down && !store.selected.isEmpty
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if g.melds.isEmpty {
                    Text("No melds on the table yet. The first player to complete \(g.contract.label) goes down.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                ForEach(g.players) { owner in
                    let mine = g.melds.enumerated().filter { $0.element.owner == owner.id }
                    if !mine.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(owner.name.uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.muted)
                            ForEach(mine, id: \.offset) { item in
                                meldRow(index: item.offset, meld: item.element, tapOK: tapOK)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func meldRow(index: Int, meld: Meld, tapOK: Bool) -> some View {
        let slots = describe(meld.cards, meld.kind, g.wl) ?? meld.cards.map { Slot(card: $0, asRank: 0) }
        return Button {
            store.hit(index)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(meldLabel(meld, slots))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(slots) { s in
                        MiniCard(card: s.card, asRank: s.asRank)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tapOK ? Theme.accent : Theme.line, style: StrokeStyle(lineWidth: 1, dash: tapOK ? [4] : []))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct HandPanel: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        let p = g.players[store.viewer(g)]
        VStack(spacing: 6) {
            Divider()
            if store.online == nil && p.cpu {
                VStack(spacing: 2) {
                    Text("\(p.name) is playing")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.fg)
                    Text("\(p.hand.count) cards in hand").foregroundColor(Theme.muted)
                }
                .padding(.vertical, 16)
            } else {
                humanPanel(p)
            }
        }
    }

    private func hintText(_ p: Player) -> String {
        if g.phase == .draw { return "Draw first: tap the deck or the top of the discard pile." }
        if !p.down {
            return store.selected.isEmpty
                ? "Lay down your contract when it is complete, then discard one card."
                : "\(store.selected.count) selected. Discard needs exactly one."
        }
        return store.selected.isEmpty
            ? "Select cards to add to melds on the table, then discard one."
            : "Tap a meld to add the selected cards, or discard one."
    }

    @ViewBuilder
    private func humanPanel(_ p: Player) -> some View {
        let w = handCardWidth()
        let mine = store.myTurn(g)
        HStack {
            Text("\(store.online != nil ? "Your hand" : p.name) · \(p.hand.count) cards")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.fg)
            Spacer()
            sortButton("Rank", "rank")
            sortButton("Suit", "suit")
        }
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: 5), count: 7), spacing: 6) {
            ForEach(p.hand) { c in
                Button { store.toggleCard(c.id) } label: {
                    CardView(card: c, width: w, selected: store.selected.contains(c.id), fresh: store.freshID == c.id)
                }
                .buttonStyle(.plain)
                .disabled(!mine)
            }
        }
        .padding(.top, 10)
        Text(mine ? hintText(p) : "Waiting for \(g.current.name)…")
            .font(.system(size: 13))
            .foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        if mine && g.phase == .play {
            HStack(spacing: 8) {
                if !p.down {
                    Button("Lay down") { store.openLay() }
                        .buttonStyle(PrimaryButton(ghost: true))
                }
                Button("Discard") { store.discardSelected() }
                    .buttonStyle(PrimaryButton())
                    .disabled(store.selected.count != 1)
            }
        }
    }

    private func sortButton(_ title: String, _ by: String) -> some View {
        Button(title) { store.sortHand(by: by) }
            .font(.system(size: 12))
            .foregroundColor(Theme.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}

// MARK: - Hand-off, round end, final

struct HandoffView: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        let p = g.current
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Round \(g.round + 1) · \(g.contract.label)")
                    .foregroundColor(Theme.muted)
                    .padding(.top, 40)
                Text("Pass the phone to \(p.name)")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.fg)
                if !g.lastTurn.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SINCE YOUR LAST TURN")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.muted)
                        ForEach(Array(g.lastTurn.enumerated()), id: \.offset) { item in
                            Text(item.element).font(.system(size: 14)).foregroundColor(Theme.fg)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button("I am \(p.name). Show my hand") { store.handoffGo() }
                    .buttonStyle(PrimaryButton())
                Button("View scores") { store.histRound = nil; store.sheet = .scores }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct RoundEndView: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        let r = g.results[g.results.count - 1]
        let last = g.round >= contracts.count - 1
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Round \(g.round + 1) of \(contracts.count) · \(g.contract.label)")
                    .foregroundColor(Theme.muted)
                    .padding(.top, 16)
                Text("\(g.players[r.out].name) went out")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.fg)
                ForEach(g.players) { p in
                    resultRow(p, r)
                }
                Button("Play-by-play of this round") {
                    store.histRound = g.round
                    store.sheet = .scores
                }
                .buttonStyle(PrimaryButton(ghost: true))
                Button(last ? "See final standings" : "Deal round \(g.round + 2): \(contracts[min(g.round + 1, contracts.count - 1)].label)") {
                    store.nextRound()
                }
                .buttonStyle(PrimaryButton())
            }
            .padding(.bottom, 24)
        }
    }

    private func resultRow(_ p: Player, _ r: RoundResult) -> some View {
        let isOut = p.id == r.out
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.fg)
                Spacer()
                Text(isOut ? "0" : "+\(r.scores[p.id])")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.fg)
            }
            Text((isOut ? "Went out" : "\(p.hand.count) cards left") + " · total \(p.total)")
                .font(.system(size: 13, weight: isOut ? .semibold : .regular))
                .foregroundColor(isOut ? Theme.good : Theme.muted)
            if !isOut {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(p.hand) { c in
                        MiniCard(card: c, showTag: false)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isOut ? Theme.good : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct FinalView: View {
    @EnvironmentObject var store: GameStore
    let g: GameState

    var body: some View {
        let order = g.players.sorted { $0.total < $1.total }
        let best = order[0].total
        let winners = order.filter { $0.total == best }.map { $0.name }.joined(separator: " and ")
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("After all 11 rounds")
                    .foregroundColor(Theme.muted)
                    .padding(.top, 16)
                Text("\(winners) won")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.fg)
                ForEach(Array(order.enumerated()), id: \.offset) { item in
                    HStack(spacing: 12) {
                        Text("\(item.offset + 1)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.muted)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.element.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.fg)
                                Spacer()
                                Text("\(item.element.total)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.fg)
                            }
                            Text(item.element.total == best ? "Lowest score wins" : "+\(item.element.total - best) behind")
                                .font(.system(size: 13))
                                .foregroundColor(item.element.total == best ? Theme.good : Theme.muted)
                        }
                    }
                    .padding(12)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(item.element.total == best ? Theme.good : Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if store.online == nil {
                    Button("Play again with the same players") { store.playAgain() }
                        .buttonStyle(PrimaryButton())
                }
                Button("Round by round scores") { store.histRound = nil; store.sheet = .scores }
                    .buttonStyle(PrimaryButton(ghost: true))
                Button(store.online != nil ? "Leave game" : "Back to setup") {
                    if store.online != nil { store.leaveOnline() } else { store.goHome() }
                }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Sheets

struct SheetHost: View {
    @EnvironmentObject var store: GameStore
    let kind: Sheet

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch kind {
                    case .scores: ScoresSheet()
                    case .rules: RulesSheet()
                    case .menu: MenuSheet()
                    case .lay: LaySheet()
                    case .join: JoinSheet()
                    }
                }
                .padding(16)
            }
        }
    }
}

struct SheetHeader: View {
    @EnvironmentObject var store: GameStore
    let title: String
    var cancel = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.fg)
            Spacer()
            Button(cancel ? "Cancel" : "Close") {
                store.sheet = nil
                store.lay = nil
                store.confirmNew = false
            }
            .font(.system(size: 15, weight: .semibold))
        }
    }
}

struct ScoresSheet: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let g = store.game {
            let keys = Array(0..<g.hist.count).filter { !g.hist[$0].isEmpty }
            let sel: Int? = {
                if let h = store.histRound, keys.contains(h) { return h }
                return keys.last
            }()
            SheetHeader(title: "Scores")
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Round").gridColumnAlignment(.leading)
                        ForEach(g.players) { p in Text(p.name) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.muted)
                    ForEach(0..<contracts.count, id: \.self) { i in
                        GridRow {
                            Text("\(i + 1) · \(contracts[i].short)").gridColumnAlignment(.leading)
                            ForEach(g.players) { p in
                                if let r = g.results.first(where: { $0.round == i }) {
                                    Text("\(r.scores[p.id])")
                                } else {
                                    Text("")
                                }
                            }
                        }
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Theme.fg)
                    }
                    GridRow {
                        Text("Total").gridColumnAlignment(.leading)
                        ForEach(g.players) { p in Text("\(p.total)") }
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.fg)
                }
            }
            if let s = sel {
                Text("Play-by-play").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(Theme.fg)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(keys, id: \.self) { k in
                            Button("\(k + 1)") { store.histRound = k }
                                .font(.system(size: 14, weight: .semibold))
                                .frame(minWidth: 36, minHeight: 34)
                                .foregroundColor(k == s ? Theme.accentFg : Theme.fg)
                                .background(k == s ? Theme.accent : Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Text("Round \(s + 1) · \(contracts[s].label)")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(g.hist[s].enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 13.5))
                            .foregroundColor(Theme.fg)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
            }
        }
    }
}

struct RulesSheet: View {
    var body: some View {
        SheetHeader(title: "Rules")
        Text("Card points").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.fg)
        VStack(spacing: 3) {
            pointRow("Jokers", "50")
            pointRow("2s", "50")
            pointRow("Aces", "15")
            pointRow("Jack, Queen, King", "10")
            pointRow("All other cards", "5")
        }
        Text("The 11 contracts").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.fg)
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<contracts.count, id: \.self) { i in
                Text("\(i + 1).  \(contracts[i].label)").foregroundColor(Theme.fg)
            }
        }
        Text("How a turn works").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.fg)
        VStack(alignment: .leading, spacing: 6) {
            bullet("Draw first, from the deck or the top of the discard pile.")
            bullet("You can only go down when the whole contract is complete, and you lay it all down at once.")
            bullet("Sets are 3 or more of one rank. Runs are 3 or more in a row of one suit; aces are high or low, with no wrapping.")
            bullet("Jokers and 2s are wild. Every meld needs at least one natural card.")
            bullet("Once you are down, you can add cards to any meld on the table.")
            bullet("End your turn with a discard. First player with no cards left wins the round with 0 points.")
            bullet("Everyone else adds up the cards in hand. After round 11, the lowest total wins.")
        }
    }

    private func pointRow(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).foregroundColor(Theme.fg)
            Spacer()
            Text(b).fontWeight(.bold).foregroundColor(Theme.fg)
        }
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(t)
        }
        .font(.system(size: 14))
        .foregroundColor(Theme.fg)
    }
}

struct MenuSheet: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        SheetHeader(title: "Menu")
        Button("Scores") { store.histRound = nil; store.sheet = .scores }
            .buttonStyle(PrimaryButton(ghost: true))
        Button("Contracts, points and rules") { store.sheet = .rules }
            .buttonStyle(PrimaryButton(ghost: true))
        if store.online == nil {
            Button("Back to setup (game is saved)") { store.goHome() }
                .buttonStyle(PrimaryButton(ghost: true))
        }
        if store.confirmNew {
            Button(store.online != nil ? "Yes, leave this game" : "Yes, abandon this game") { store.abandon() }
                .buttonStyle(PrimaryButton(color: Theme.bad))
        } else {
            Button(store.online != nil ? "Leave game" : "Abandon game") { store.confirmNew = true }
                .buttonStyle(PrimaryButton(ghost: true))
        }
    }
}

struct LaySheet: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let g = store.game, let L = store.lay {
            let p = g.players[store.viewer(g)]
            let reqs = g.contract.reqs
            let assigned = Set(L.slots.flatMap { $0 })
            let rest = p.hand.filter { !assigned.contains($0.id) }
            let whys: [String] = reqs.indices.map { i in
                let cards = cardsFor(L.slots[i], p.hand)
                return whyNot(cards, reqs[i].kind, reqs[i].minLen, g.wl)
            }
            let allOK = !whys.contains { !$0.isEmpty }
            let w = handCardWidth()

            SheetHeader(title: "Lay down", cancel: true)
            Text("\(g.contract.label). Lay down everything at once. Tap a laid card to take it back.")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
            ForEach(reqs.indices, id: \.self) { i in
                slotView(i, reqs[i], whys[i], cardsFor(L.slots[i], p.hand), L, g.wl)
            }
            HStack {
                Text("Your hand").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.fg)
                Spacer()
                if g.hints {
                    Button("Auto-fill") { store.layAutoFill() }.font(.system(size: 13))
                }
                Button("Clear") { store.layClear() }.font(.system(size: 13))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: 5), count: 7), spacing: 6) {
                ForEach(rest) { c in
                    Button { store.layToggle(c.id) } label: {
                        CardView(card: c, width: w, selected: L.sel.contains(c.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            Button("Lay down") { store.layGo() }
                .buttonStyle(PrimaryButton())
                .disabled(!allOK)
        }
    }

    private func cardsFor(_ ids: [Int], _ hand: [Card]) -> [Card] {
        ids.compactMap { id in hand.first(where: { $0.id == id }) }
    }

    private func slotView(_ i: Int, _ req: Req, _ why: String, _ cards: [Card], _ L: LayDraft, _ wl: Bool) -> some View {
        let ok = why.isEmpty
        let slots: [Slot] = ok ? (describe(cards, req.kind, wl) ?? []) : cards.map { Slot(card: $0, asRank: 0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((req.kind == .set ? "Set" : "Run") + " of \(req.minLen) or more")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.fg)
                Spacer()
                Button("Add here") { store.slotAdd(i) }
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(L.sel.isEmpty)
            }
            if slots.isEmpty {
                Text("Select cards below, then tap Add here")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                    .frame(minHeight: 46)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(slots) { s in
                        Button { store.slotRemove(i, s.card.id) } label: {
                            MiniCard(card: s.card, asRank: s.asRank, showTag: ok)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(ok ? "Ready" : why)
                .font(.system(size: 12.5, weight: ok ? .semibold : .regular))
                .foregroundColor(ok ? Theme.good : Theme.muted)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ok ? Theme.good : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
