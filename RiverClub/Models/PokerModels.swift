import Foundation

struct PokerTableSummary: Identifiable, Equatable, Sendable {
    let id: UUID; let name: String; let smallBlind: Int; let bigBlind: Int
    let players: Int; let capacity: Int; let averagePot: Int; let isFavorite: Bool
}

struct PokerSeat: Identifiable, Equatable, Sendable {
    let id: UUID; let position: Int; let initials: String; let name: String
    let chips: Int; let isLocalPlayer: Bool; let status: String?
}

struct TournamentSummary: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case beginner, classic, turbo }
    let id: UUID; let kind: Kind; let name: String; let startTime: Date
    let registered: Int; let capacity: Int; let prizePool: Int; let entryChips: Int
}

struct ProfileSummary: Equatable, Sendable {
    let nickname: String; let level: Int; let handsPlayed: Int
    let voluntaryPutInPot: Double; let tournamentAwards: Int
}
