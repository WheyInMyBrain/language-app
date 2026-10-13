import Foundation

public struct CICandidateItem: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { "\(date)_\(url)" }
    public let date: String
    public let url: String

    public init(date: String, url: String) {
        self.date = date
        self.url = url
    }
}

public struct CICandidateData: Sendable, Equatable {
    public let candidates: [CICandidateItem]
    public let groupedByDate: [String: [CICandidateItem]]
    public let sortedDates: [String]

    public init(
        candidates: [CICandidateItem] = [],
        groupedByDate: [String: [CICandidateItem]] = [:],
        sortedDates: [String] = []
    ) {
        self.candidates = candidates
        self.groupedByDate = groupedByDate
        self.sortedDates = sortedDates
    }
}

public enum CICandidateService {
    public static func getUnprocessedCICandidates(
        listeningEntries: [ListeningEntry],
        ciLinks: [String]
    ) -> CICandidateData {
        // 1. Processed canonical set
        var processedSet = Set<String>()
        for raw in ciLinks {
            let clean = MediaResolver.canonicalize(raw: raw)
            if !clean.isEmpty {
                processedSet.insert(clean)
            }
        }

        // 2. Filter unhandled candidates
        var candidates: [CICandidateItem] = []
        var seenInSession = Set<String>()

        for entry in listeningEntries {
            guard !entry.link.isEmpty else { continue }
            let cleanUrl = MediaResolver.canonicalize(raw: entry.link)
            guard !cleanUrl.isEmpty, !processedSet.contains(cleanUrl) else { continue }

            let d = entry.date.isEmpty ? "Undated" : entry.date
            let uniqueKey = "\(d)_\(cleanUrl)"
            guard !seenInSession.contains(uniqueKey) else { continue }
            seenInSession.insert(uniqueKey)

            candidates.append(CICandidateItem(date: d, url: cleanUrl))
        }

        // 3. Group by date
        var groupedByDate: [String: [CICandidateItem]] = [:]
        for item in candidates {
            groupedByDate[item.date, default: []].append(item)
        }

        // 4. Sort dates descending (latest first)
        let sortedDates = groupedByDate.keys.sorted(by: >)

        return CICandidateData(
            candidates: candidates,
            groupedByDate: groupedByDate,
            sortedDates: sortedDates
        )
    }
}