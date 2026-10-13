import Foundation

// MARK: - Day Session Meta

public struct DaySessionMeta: Codable, Equatable, Sendable {
    public var revision: Int
    public var interval: Double
    public var ease: Double
    public var due_date: String

    public init(revision: Int = 0, interval: Double = 0, ease: Double = 2.5, due_date: String = "") {
        self.revision = revision
        self.interval = interval
        self.ease = ease
        self.due_date = due_date
    }
}

// MARK: - Word Item

public struct WordItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(word_index)" }
    public var word_index: Int
    public var native_script: String
    public var pronunciation: String?
    public var translation: String?
    public var mnemonic: String?
    public var link: String?
    public var audio_url: String?
    public var is_voiced: Bool

    public init(
        word_index: Int,
        native_script: String,
        pronunciation: String? = nil,
        translation: String? = nil,
        mnemonic: String? = nil,
        link: String? = nil,
        audio_url: String? = nil,
        is_voiced: Bool = false
    ) {
        self.word_index = word_index
        self.native_script = native_script
        self.pronunciation = pronunciation
        self.translation = translation
        self.mnemonic = mnemonic
        self.link = link
        self.audio_url = audio_url
        self.is_voiced = is_voiced
    }
}

// MARK: - Activity Item (CI, Listening, Grammar)

public enum ActivityType: String, Codable, Sendable, CaseIterable {
    case ci
    case listening
    case grammar
}

public struct ActivityItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(activity_type.rawValue):\(item_index)" }
    public var item_index: Int
    public var activity_type: ActivityType
    public var title: String
    public var detail: String?
    public var duration_sec: Double
    public var link: String?

    public init(
        item_index: Int,
        activity_type: ActivityType,
        title: String,
        detail: String? = nil,
        duration_sec: Double = 0,
        link: String? = nil
    ) {
        self.item_index = item_index
        self.activity_type = activity_type
        self.title = title
        self.detail = detail
        self.duration_sec = duration_sec
        self.link = link
    }
}