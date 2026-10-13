import Foundation
import Observation
import YSwift

@Observable
public final class MetadataStore {
    public static let shared = MetadataStore()

    public var connectionStatus: String = "connecting"
    public var languages: [String: LanguageConfig] = [:]
    public var calendarIndex: [String: CalendarEntry] = [:]
    public var activeLanguage: String = "zh-CN"

    private var session: YDocSession?

    private init() {
        startSession()
    }

    private func startSession() {
        self.session = YDocSession(roomName: "global:metadata") { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncFromDoc()
            }
        }
    }

    @MainActor
    private func syncFromDoc() {
        guard let doc = session?.doc else { return }
        let langsMap: YMap<LanguageConfig> = doc.getOrCreateMap(named: "languages")
        let calMap: YMap<CalendarEntry> = doc.getOrCreateMap(named: "calendar_index")

        var parsedLangs: [String: LanguageConfig] = [:]
        var parsedCal: [String: CalendarEntry] = [:]

        doc.transactSync(origin: nil) { txn in
            parsedLangs = langsMap.toMap(transaction: txn)
            parsedCal = calMap.toMap(transaction: txn)
        }

        self.languages = parsedLangs
        self.calendarIndex = parsedCal

        if !parsedLangs.keys.contains(activeLanguage), let first = parsedLangs.keys.first {
            self.activeLanguage = first
        }
    }

    public func recordReview(langCode: String, date: String, type: String, subType: String = "visual") {
        let key = "\(langCode):\(date)"
        var entry = calendarIndex[key] ?? CalendarEntry(date: date)

        if type == "srs" {
            if subType == "listening" || subType == "audio" {
                entry.reviews_completed.srs_listen += 1
            } else if subType == "writing" {
                entry.reviews_completed.srs_write += 1
            } else {
                entry.reviews_completed.srs_vision += 1
            }
        } else if type == "day_revision" {
            entry.reviews_completed.day_revisions += 1
        }

        calendarIndex[key] = entry

        Task {
            await session?.commitMapUpdate(mapName: "calendar_index", key: key, value: entry)
        }
    }
}