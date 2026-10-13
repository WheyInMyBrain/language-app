import Foundation
import Observation
import YSwift

@Observable
public final class SRSStore {
    public static let shared = SRSStore()

    public var cards: [String: SRSCard] = [:]
    public var isLoaded: Bool = false
    public var activeRoom: String?

    private var session: YDocSession?

    private init() {}

    public func connect(langCode: String) {
        let room = "\(langCode):srs"
        guard activeRoom != room else { return }

        cards = [:]
        isLoaded = false
        activeRoom = room

        self.session = YDocSession(roomName: room) { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncFromDoc()
            }
        }
    }

    @MainActor
    private func syncFromDoc() {
        guard let doc = session?.doc else { return }
        let queueMap: YMap<SRSCard> = doc.getOrCreateMap(named: "queue")

        var parsed: [String: SRSCard] = [:]
        doc.transactSync(origin: nil) { txn in
            parsed = queueMap.toMap(transaction: txn)
        }

        for (key, _) in parsed {
            parsed[key]?.key = key
        }

        self.cards = parsed
        self.isLoaded = true
    }

    public func getDueItems(todayStr: String, cardType: String? = nil) -> [SRSCard] {
        cards.values.filter { card in
            guard let due = card.due_date, due <= todayStr else { return true }
            if let cardType { return card.card_type == cardType }
            return true
        }
    }

    public func rateCard(langCode: String, cardKey: String, grade: SRSGrade) async {
        guard var card = cards[cardKey] else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let next = SRSEngine.calculateNextState(
            currentRev: card.reps,
            currentInterval: card.interval,
            currentEase: card.ease,
            grade: grade,
            todayStr: today
        )

        card.interval = next.interval
        card.ease = next.ease
        card.due_date = next.dueDate
        card.reps = (grade == .again) ? 0 : card.reps + 1
        card.lapses = (grade == .again) ? card.lapses + 1 : card.lapses
        card.last_reviewed = today

        cards[cardKey] = card

        await session?.commitMapUpdate(mapName: "queue", key: cardKey, value: card)

        MetadataStore.shared.recordReview(
            langCode: langCode,
            date: today,
            type: "srs",
            subType: card.card_type ?? "visual"
        )
    }
}