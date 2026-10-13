import Foundation
import Observation
import YSwift

@Observable
@MainActor
public final class DaySessionStore {
    public static let shared = DaySessionStore()

    public private(set) var activeRoom: String? = nil
    public private(set) var words: [WordItem] = []
    public private(set) var activities: [ActivityItem] = []
    public private(set) var session: DaySessionMeta = DaySessionMeta()
    public private(set) var isLoaded: Bool = false

    private var sessionDoc: YDocSession?

    private init() {}

    public func connect(langCode: String, dateStr: String) {
        let room = "\(langCode):\(dateStr)"
        guard activeRoom != room else { return }

        self.activeRoom = room
        self.isLoaded = false
        self.words = []
        self.activities = []
        self.session = DaySessionMeta(due_date: dateStr)

        self.sessionDoc = YDocSession(roomName: room) { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncFromDoc()
            }
        }
        
        // Initial parse after loading local disk cache
        syncFromDoc()
    }

    private func syncFromDoc() {
        guard let doc = sessionDoc?.doc else { return }

        var parsedWords: [WordItem] = []
        var parsedActivities: [ActivityItem] = []
        var parsedMeta: DaySessionMeta? = nil

        doc.transactSync(origin: nil) { txn in
            let wordsArray: YArray<WordItem> = doc.getOrCreateArray(named: "words")
            let activitiesArray: YArray<ActivityItem> = doc.getOrCreateArray(named: "activities")
            let metaMap: YMap<DaySessionMeta> = doc.getOrCreateMap(named: "meta")

            parsedWords = wordsArray.toArray(transaction: txn)
            parsedActivities = activitiesArray.toArray(transaction: txn)
            
            // Only query "session" if the map actually contains entries,
            // preventing the Rust map.rs:128 panic on an unpopulated map
            if metaMap.length(transaction: txn) > 0 {
                parsedMeta = metaMap.get(key: "session", transaction: txn)
            }
        }

        self.words = parsedWords
        self.activities = parsedActivities
        if let meta = parsedMeta {
            self.session = meta
        }
        self.isLoaded = true
    }

    // MARK: - Mutations

    public func addWord(_ item: WordItem) async {
        guard let sessionDoc else { return }
        words.append(item)
        await sessionDoc.commitArrayAppend(arrayName: "words", values: [item])
    }

    public func addActivity(_ item: ActivityItem) async {
        guard let sessionDoc else { return }
        activities.append(item)
        await sessionDoc.commitArrayAppend(arrayName: "activities", values: [item])
    }

    public func updateSessionSRS(grade: SRSGrade, dateStr: String) async {
        guard let sessionDoc else { return }

        let next = SRSEngine.calculateNextState(
            currentRev: session.revision,
            currentInterval: session.interval,
            currentEase: session.ease,
            grade: grade,
            todayStr: dateStr
        )

        session.revision += 1
        session.interval = next.interval
        session.ease = next.ease
        session.due_date = next.dueDate

        await sessionDoc.commitMapUpdate(mapName: "meta", key: "session", value: session)
    }
}