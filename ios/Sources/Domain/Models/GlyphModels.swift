import Foundation
import CoreGraphics

public struct GlyphDecomposition: Codable, Sendable, Equatable {
    public let character: String
    public let phonetic: String?
    public let definition: String?
    public let pinyin: String?
    public let transliteration: String?
    public let component1: String?
    public let component2: String?
    public let decomposition: String?
    public let etymology_hint: String?
    public let mnemonic: String?
    public let root: String?
    public let strokes: [String]?
    public let medians: [[[Double]]]?

    public init(
        character: String,
        phonetic: String? = nil,
        definition: String? = nil,
        pinyin: String? = nil,
        transliteration: String? = nil,
        component1: String? = nil,
        component2: String? = nil,
        decomposition: String? = nil,
        etymology_hint: String? = nil,
        mnemonic: String? = nil,
        root: String? = nil,
        strokes: [String]? = nil,
        medians: [[[Double]]]? = nil
    ) {
        self.character = character
        self.phonetic = phonetic
        self.definition = definition
        self.pinyin = pinyin
        self.transliteration = transliteration
        self.component1 = component1
        self.component2 = component2
        self.decomposition = decomposition
        self.etymology_hint = etymology_hint
        self.mnemonic = mnemonic
        self.root = root
        self.strokes = strokes
        self.medians = medians
    }
}

public struct MorphDecompositionInfo: Sendable, Equatable {
    public let operatorChar: String?
    public let parts: [String]

    public init(operatorChar: String? = nil, parts: [String] = []) {
        self.operatorChar = operatorChar
        self.parts = parts
    }
}