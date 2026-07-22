import Foundation
import Observation
import PokerCore

enum TableQuickMessage: String, CaseIterable, Codable, Equatable, Identifiable {
    case hello
    case niceHand
    case thinking
    case goodGame

    var id: String { rawValue }

    var text: String {
        switch self {
        case .hello: "大家好"
        case .niceHand: "好牌！"
        case .thinking: "让我想想"
        case .goodGame: "打得不错"
        }
    }
}

enum TableReaction: String, CaseIterable, Codable, Equatable, Identifiable {
    case smile
    case applause
    case surprise
    case thanks

    var id: String { rawValue }

    var text: String {
        switch self {
        case .smile: "😊"
        case .applause: "👏"
        case .surprise: "😮"
        case .thanks: "🙏"
        }
    }
}

enum TableSocialContent: Equatable {
    case message(TableQuickMessage)
    case reaction(TableReaction)

    var text: String {
        switch self {
        case let .message(message): message.text
        case let .reaction(reaction): reaction.text
        }
    }
}

struct TableBubble: Identifiable, Equatable {
    let id: UUID
    let seat: SeatID
    let text: String
    let isHuman: Bool
}

@MainActor @Observable
final class TableSocialInteractionModel {
    private(set) var visibleBubbles: [TableBubble] = []

    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let randomUnit: () -> Double
    @ObservationIgnored private let responseDelay: Duration
    @ObservationIgnored private let bubbleDuration: Duration
    @ObservationIgnored private let cooldown: TimeInterval
    @ObservationIgnored private var expirationTasks: [UUID: Task<Void, Never>] = [:]
    private var lastHumanMessageTime: TimeInterval?

    init(
        now: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        randomUnit: @escaping () -> Double = { Double.random(in: 0...1) },
        responseDelay: Duration = .milliseconds(320),
        bubbleDuration: Duration = .seconds(3),
        cooldown: TimeInterval = 1.5
    ) {
        self.now = now
        self.randomUnit = randomUnit
        self.responseDelay = responseDelay
        self.bubbleDuration = bubbleDuration
        self.cooldown = cooldown
    }

    @discardableResult
    func send(
        _ content: TableSocialContent,
        humanSeat: SeatID,
        eligibleBots: [SeatID]
    ) async -> Bool {
        let sentAt = now()
        if let lastHumanMessageTime,
           sentAt - lastHumanMessageTime < cooldown {
            return false
        }
        lastHumanMessageTime = sentAt
        showBubble(seat: humanSeat, text: content.text, isHuman: true)

        guard !eligibleBots.isEmpty, randomUnit() < 0.42 else { return true }
        if responseDelay > .zero {
            try? await Task.sleep(for: responseDelay)
        }
        guard !Task.isCancelled else { return true }
        let unit = min(max(randomUnit(), 0), 0.999_999)
        let index = min(Int(unit * Double(eligibleBots.count)), eligibleBots.count - 1)
        showBubble(
            seat: eligibleBots[index],
            text: botReply(to: content),
            isHuman: false
        )
        return true
    }

    func clear() {
        expirationTasks.values.forEach { $0.cancel() }
        expirationTasks.removeAll()
        visibleBubbles.removeAll()
    }

    private func showBubble(seat: SeatID, text: String, isHuman: Bool) {
        visibleBubbles.removeAll { $0.seat == seat }
        let bubble = TableBubble(
            id: UUID(),
            seat: seat,
            text: text,
            isHuman: isHuman
        )
        visibleBubbles.append(bubble)
        expirationTasks[bubble.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.bubbleDuration ?? .zero)
            guard !Task.isCancelled else { return }
            self?.visibleBubbles.removeAll { $0.id == bubble.id }
            self?.expirationTasks[bubble.id] = nil
        }
    }

    private func botReply(to content: TableSocialContent) -> String {
        switch content {
        case .message(.hello): "你好，祝你好运"
        case .message(.niceHand): "谢谢，你也打得好"
        case .message(.thinking): "慢慢来"
        case .message(.goodGame): "精彩的一局"
        case .reaction(.smile): "😊"
        case .reaction(.applause): "👏"
        case .reaction(.surprise): "😄"
        case .reaction(.thanks): "不客气"
        }
    }
}
