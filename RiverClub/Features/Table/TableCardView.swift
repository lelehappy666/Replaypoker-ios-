import PokerCoordinator
import PokerCore
import SwiftUI

struct TableCardView: View {
    private let state: TableCardState

    init(cardState: TableCardState) {
        state = cardState
    }

    init(card: Card) {
        state = .faceUp(card)
    }

    var body: some View {
        Group {
            switch state {
            case .faceDown:
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.08, blue: 0.11), .black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(RCTheme.gold.opacity(0.7), lineWidth: 1)
                            .padding(3)
                    }
            case let .faceUp(card):
                VStack(spacing: -2) {
                    Text(rankText(card.rank))
                    Text(suitText(card.suit))
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(isRed(card.suit) ? .red : .black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .aspectRatio(34 / 46, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .faceDown:
            return "牌背"
        case let .faceUp(card):
            return "\(rankText(card.rank))\(suitText(card.suit))"
        }
    }

    private func rankText(_ rank: Rank) -> String {
        switch rank {
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .ten: "10"
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        case .ace: "A"
        }
    }

    private func suitText(_ suit: Suit) -> String {
        switch suit {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }

    private func isRed(_ suit: Suit) -> Bool {
        suit == .diamonds || suit == .hearts
    }
}
