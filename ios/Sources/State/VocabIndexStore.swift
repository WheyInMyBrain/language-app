import Foundation
import Observation
import YSwift

@Observable
public final class VocabIndexStore {
    public static let shared = VocabIndexStore()

    public var entries: [VocabItem] = []
    public var isLoaded: Bool = false
    public var activeRoom: String?

    private var session: YDocSession?

    private init() {}

    public func connect(langCode: String) {
        let room = "\(langCode):vocab_index"
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

    @MainActor
    private func syncFromDoc() {
        guard let doc = session?.doc else { return }
        let entriesArray: YArray<VocabItem> = doc.getOrCreateArray(named: "entries")

        var parsed: [VocabItem] = []
        doc.transactSync(origin: nil) { txn in
            parsed = entriesArray.toArray(transaction: txn)
        }

        self.entries = parsed
        self.isLoaded = true
    }

    public func search(query: String) -> [VocabItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }

        let cleanQuery = PhoneticsFormatter.stripDiacritics(trimmed)
        let lowerQuery = trimmed.lowercased()

        return entries.filter { entry in
            if entry._normPrimary.contains(lowerQuery) { return true }
            if entry._normSecondary.starts(with: cleanQuery) { return true }
            return entry._searchSyllables.contains { $0.starts(with: cleanQuery) }
        }
    }
}