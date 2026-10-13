import Foundation
import Observation
import YSwift

public struct ListeningEntry: Codable, Sendable, Equatable, Hashable {
    public var date: String
    public var link: String

    public init(date: String, link: String) {
        self.date = date
        self.link = link
    }
}

@Observable
@MainActor
public final class ListeningIndexStore {
    public static let shared = ListeningIndexStore()

    public var entries: [ListeningEntry] = []
    public var isLoaded: Bool = false
    public var activeRoom: String?

    private var session: YDocSession?

    private init() {}

    public func connect(langCode: String) {
        let room = "\(langCode):listening_index"
        guard activeRoom != room else { return }

        entries = []
        isLoaded = false
        activeRoom = room

        self.session = YDocSession(roomName: room) { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncFromDoc()
            }
        }
    }

    private func syncFromDoc() {
        guard let doc = session?.doc else { return }
        let entriesArray: YArray<ListeningEntry> = doc.getOrCreateArray(named: "entries")

        var parsed: [ListeningEntry] = []
        doc.transactSync(origin: nil) { txn in
            parsed = entriesArray.toArray(transaction: txn)
        }

        self.entries = parsed
        self.isLoaded = true
    }

    public func findMatches(rawUrl: String, excludeDate: String? = nil) -> [ListeningEntry] {
        guard !rawUrl.isEmpty else { return [] }
        let canonical = MediaResolver.canonicalize(raw: rawUrl)
        return entries.filter { entry in
            MediaResolver.canonicalize(raw: entry.link) == canonical &&
            (excludeDate == nil || entry.date != excludeDate)
        }
    }
}