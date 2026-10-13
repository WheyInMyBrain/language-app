import Foundation

public struct VocabItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(date):\(index)" }
    public let date: String
    public let index: Int
    public let native_script: String
    public let pronunciation: String?
    public let translation: String?
    public let link: String?

    // Normalized search tokens pre-computed at ingestion
    public let _normPrimary: String
    public let _normSecondary: String
    public let _searchSyllables: [String]

    enum CodingKeys: String, CodingKey {
        case date, index, native_script, pronunciation, translation, link
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try container.decode(String.self, forKey: .date)
        self.index = try container.decode(Int.self, forKey: .index)
        self.native_script = try container.decode(String.self, forKey: .native_script)
        self.pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation)
        self.translation = try container.decodeIfPresent(String.self, forKey: .translation)
        self.link = try container.decodeIfPresent(String.self, forKey: .link)

        let primary = self.native_script.lowercased()
        let secondary = PhoneticsFormatter.stripDiacritics(self.pronunciation ?? "")
        self._normPrimary = primary
        self._normSecondary = secondary
        self._searchSyllables = secondary
            .components(separatedBy: CharacterSet(charactersIn: " '-"))
            .filter { !$0.isEmpty }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(index, forKey: .index)
        try container.encode(native_script, forKey: .native_script)
        try container.encodeIfPresent(pronunciation, forKey: .pronunciation)
        try container.encodeIfPresent(translation, forKey: .translation)
        try container.encodeIfPresent(link, forKey: .link)
    }
}