import SwiftUI

/// Width of a card in the 7-column hand grid.
func handCardWidth() -> CGFloat {
    let usable = min(UIScreen.main.bounds.width, 520) - 32
    return floor((usable - 5 * 6) / 7)
}

struct CardView: View {
    let card: Card
    let width: CGFloat
    var selected = false
    var fresh = false

    var body: some View {
        let rankSize: CGFloat = card.r == 0 ? width * 0.28 : width * 0.44
        ZStack(alignment: .topLeading) {
            Theme.paper
            if card.isWild {
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle().fill(Theme.accent).frame(height: 4)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(card.rankLabel)
                    .font(.system(size: rankSize, weight: .bold, design: .rounded))
                if card.r != 0 {
                    Text(card.suitSymbol)
                        .font(.system(size: width * 0.30, weight: .bold))
                }
            }
            .padding(.leading, 3)
            .padding(.top, 2)
            Text(card.suitSymbol)
                .font(.system(size: width * 0.5, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 3)
                .padding(.bottom, 5)
        }
        .foregroundColor(card.isRed ? Theme.red : Theme.ink)
        .frame(width: width, height: width * 1.4)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Theme.accent : Color.black.opacity(0.25), lineWidth: selected ? 3 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if fresh {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                    .offset(x: 4, y: -4)
            }
        }
        .offset(y: selected ? -9 : 0)
        .accessibilityLabel(card.name)
    }
}

struct MiniCard: View {
    let card: Card
    var asRank: Int? = nil
    var showTag = true

    var body: some View {
        VStack(spacing: 2) {
            VStack(spacing: 0) {
                Text(card.rankLabel)
                    .font(.system(size: card.r == 0 ? 10 : 19, weight: .bold, design: .rounded))
                Text(card.suitSymbol)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(card.isRed ? Theme.red : Theme.ink)
            .frame(width: 34, height: 46)
            .background(Theme.paper)
            .overlay(alignment: .bottom) {
                if card.isWild {
                    Rectangle().fill(Theme.accent).frame(height: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.25), lineWidth: 1))
            if showTag {
                Text(tagText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.accent)
                    .frame(height: 13)
            }
        }
        .accessibilityLabel(card.name)
    }

    private var tagText: String {
        if card.isWild, let a = asRank, a > 0 { return "=" + rankText(a) }
        return " "
    }
}

struct DeckBack: View {
    let count: Int
    var ready = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Theme.accent)
            RoundedRectangle(cornerRadius: 7).stroke(Theme.paper, lineWidth: 3)
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.accentFg)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: 58, height: 81)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(ready ? Theme.accent : Color.clear, lineWidth: 3)
                .padding(-5)
        )
    }
}
