import Foundation
import Observation
import YSwift

@Observable
@MainActor
public final class CIIndexStore {
    public static let shared = CIIndexStore()

    public var links: [String] = []
    public var isLoaded: Bool = false
    public var activeRoom: String?

    private var session: YDocSession?

    private init() {}

    public func connect(langCode: String) {
        let room = "\(langCode):ci_index"
        guard activeRoom != room else { return }

        links = []
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
        let linksArray: YArray<String> = doc.getOrCreateArray(named: "links")

        var parsed: [String] = []
        doc.transactSync(origin: nil) { txn in
            parsed = linksArray.toArray(transaction: txn)
        }

        self.links = parsed
        self.isLoaded = true
    }

    public func isDuplicate(rawUrl: String) -> Bool {
        guard !rawUrl.isEmpty else { return false }
        let canonical = MediaResolver.canonicalize(raw: rawUrl)
        return links.contains { MediaResolver.canonicalize(raw: $0) == canonical }
    }
}