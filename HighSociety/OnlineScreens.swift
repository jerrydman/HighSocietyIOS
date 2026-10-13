import SwiftUI

// MARK: - Home: host or join an online game

struct OnlinePanel: View {
    @EnvironmentObject var store: GameStore
    @State private var code = ""

    var body: some View {
        Panel {
            Text("Play online").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Theme.fg)
            Text("Each player uses their own phone. Hands stay private on the server.")
                .font(.system(size: 13)).foregroundColor(Theme.muted)

            TextField("Your name", text: $store.onlineName)
                .textFieldStyle(.roundedBorder)
            TextField("Server address (https://…)", text: $store.serverURL)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            HStack {
                Text("Players").foregroundColor(Theme.fg)
                Spacer()
                Picker("Players", selection: $store.onlineSeats) {
                    ForEach(2...6, id: \.self) { n in Text("\(n)").tag(n) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            Button(store.busy ? "Connecting…" : "Host a game") { store.hostOnline() }
                .buttonStyle(PrimaryButton())
                .disabled(store.busy)

            Divider()
            HStack(spacing: 8) {
                TextField("Game code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join") { store.joinWithCode(code) }
                    .buttonStyle(PrimaryButton(ghost: true))
                    .frame(width: 90)
                    .disabled(store.busy)
            }
        }
    }
}

// MARK: - Join sheet (opened from an invite link)

struct JoinSheet: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        SheetHeader(title: "Join game")
        if let p = store.pendingJoin {
            Text("You were invited to game \(p.code).")
                .foregroundColor(Theme.fg)
            TextField("Your name", text: $store.onlineName)
                .textFieldStyle(.roundedBorder)
            Button(store.busy ? "Joining…" : "Join game \(p.code)") {
                let n = store.onlineName.trimmingCharacters(in: .whitespacesAndNewlines)
                store.joinOnline(code: p.code, base: p.base, name: n.isEmpty ? "Player" : n)
            }
            .buttonStyle(PrimaryButton())
            .disabled(store.busy)
        } else {
            Text("This invite link isn't valid.").foregroundColor(Theme.muted)
        }
    }
}

// MARK: - Lobby (waiting for the host to start)

struct LobbyView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        let v = store.lobby
        let names = v?.lobby ?? []
        let isHost = (store.online?.seat ?? -1) == 0
        let seats = v?.maxSeats ?? 2
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Game lobby")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.fg)
                    .padding(.top, 24)

                Panel {
                    Text("GAME CODE").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.muted)
                    Text(store.online?.code ?? "")
                        .font(.system(size: 44, weight: .heavy, design: .monospaced))
                        .foregroundColor(Theme.fg)
                    if let url = store.inviteURL {
                        ShareLink(
                            item: url,
                            message: Text("Join my High Society game! Code \(store.online?.code ?? "")")
                        ) {
                            Label("Send invite by text", systemImage: "message.fill")
                        }
                        .buttonStyle(PrimaryButton())
                    }
                }

                Panel {
                    Text("Players (\(names.count) of \(seats))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.fg)
                    ForEach(Array(names.enumerated()), id: \.offset) { item in
                        HStack {
                            Text(item.element).foregroundColor(Theme.fg)
                            if item.offset == store.online?.seat {
                                Text("(you)").foregroundColor(Theme.muted)
                            }
                            Spacer()
                            if item.offset == 0 {
                                Text("Host").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.muted)
                            }
                        }
                    }
                    if names.count < seats {
                        Text("Waiting for \(seats - names.count) more…")
                            .font(.system(size: 13)).foregroundColor(Theme.muted)
                    }
                }

                if isHost {
                    Button("Start game") { store.startOnlineGame() }
                        .buttonStyle(PrimaryButton())
                        .disabled(names.count < 2)
                } else {
                    Text("Waiting for the host to start…")
                        .foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity)
                }

                Button("Leave game") { store.leaveOnline() }
                    .buttonStyle(PrimaryButton(ghost: true))
            }
            .padding(.bottom, 24)
        }
    }
}
