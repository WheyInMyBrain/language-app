import Foundation

public enum MediaType: Equatable, Sendable {
    case empty
    case youtube(id: String, url: URL)
    case directVideo(url: URL)
    case image(url: URL)
}

public enum MediaResolver {
    private static let ytRegex = try? NSRegularExpression(
        pattern: #"(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=|shorts\/))([a-zA-Z0-9_-]{11})"#,
        options: .caseInsensitive
    )

    private static let videoExtensions: Set<String> = ["mp4", "webm", "mov", "m4v"]

    /// Extracts the 11-character YouTube ID from various URL formats
    public static func extractYouTubeId(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let regex = ytRegex else { return nil }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              let idRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        return String(trimmed[idRange])
    }

    /// Strips Obsidian wiki-links (![[test.mp4]]), tracking parameters, and standardizes media URLs
    public static func canonicalize(raw: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }

        // Strip Obsidian wiki-link brackets: ![[filename.mp4]] -> filename.mp4
        if clean.hasPrefix("![[") && clean.hasSuffix("]]") {
            clean = String(clean.dropFirst(3).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if clean.hasPrefix("[[") && clean.hasSuffix("]]") {
            clean = String(clean.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !clean.isEmpty else { return "" }

        // Canonicalize YouTube
        if let ytId = extractYouTubeId(from: clean) {
            return "https://www.youtube.com/watch?v=\(ytId)"
        }

        return clean
    }

    /// Analyzes a raw string and resolves its renderable media payload
    public static func resolveMedia(raw: String) -> MediaType {
        let canonical = canonicalize(raw: raw)
        guard !canonical.isEmpty else { return .empty }

        // 1. YouTube
        if let ytId = extractYouTubeId(from: canonical), let url = URL(string: canonical) {
            return .youtube(id: ytId, url: url)
        }

        // 2. Direct Web URLs & Data URIs
        if canonical.hasPrefix("http://") || canonical.hasPrefix("https://") || canonical.hasPrefix("data:") {
            guard let url = URL(string: canonical) else { return .empty }
            let ext = url.pathExtension.lowercased()
            if videoExtensions.contains(ext) {
                return .directVideo(url: url)
            }
            return .image(url: url)
        }

        // 3. Backend-hosted static media asset fallback
        let endpoint = AppConfig.httpBaseURL.appendingPathComponent("media").appendingPathComponent(canonical)
        let ext = endpoint.pathExtension.lowercased()
        if videoExtensions.contains(ext) {
            return .directVideo(url: endpoint)
        }
        return .image(url: endpoint)
    }
}