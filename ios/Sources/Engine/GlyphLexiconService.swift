import Foundation

@MainActor
public final class GlyphLexiconService {
    public static let shared = GlyphLexiconService()

    private let memoryCache = NSCache<NSString, NSData>()
    private let cacheDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("GlyphLexicon", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryCache.countLimit = 300
    }

    public func fetchGlyph(lang: String, character: String) async -> GlyphDecomposition? {
        guard let cleanChar = character.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return nil
        }
        let charString = String(cleanChar)
        let cacheKey = "\(lang):\(charString)"

        // 1. RAM Cache (0 ms latency)
        if let cachedData = memoryCache.object(forKey: cacheKey as NSString) {
            if let decoded = try? JSONDecoder().decode(GlyphDecomposition.self, from: cachedData as Data) {
                return decoded
            }
        }

        // 2. Disk Cache (Offline Support)
        let fileURL = cacheDirectory.appendingPathComponent("\(lang)_\(charString).json")
        if let diskData = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(GlyphDecomposition.self, from: diskData) {
            memoryCache.setObject(diskData as NSData, forKey: cacheKey as NSString)
            return decoded
        }

        // 3. Network Fetch
        guard let encodedLang = lang.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedChar = charString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        let endpoint = AppConfig.httpBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("glyph")
            .appendingPathComponent(encodedLang)
            .appendingPathComponent(encodedChar)

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            let decoded = try JSONDecoder().decode(GlyphDecomposition.self, from: data)

            // Cache in memory and on disk atomically
            memoryCache.setObject(data as NSData, forKey: cacheKey as NSString)
            try? data.write(to: fileURL, options: .atomic)

            return decoded
        } catch {
            return nil
        }
    }
}