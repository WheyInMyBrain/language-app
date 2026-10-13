import Foundation
import Network
import Observation

public struct AudioSyncItem: Identifiable, Sendable, Codable, Equatable {
    public var id: String { "\(lang):\(date):\(category):\(index)" }
    public let lang: String
    public let date: String
    public let category: String
    public let index: String
    public let duration: Double
    public let localFileName: String
    public let timestamp: Date
}

@Observable
@MainActor
public final class AudioSyncEngine {
    public static let shared = AudioSyncEngine()

    public private(set) var pendingCount: Int = 0
    public private(set) var isSyncing: Bool = false
    public private(set) var isOnline: Bool = true

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.languageapp.networkmonitor")
    private let outboxDirectory: URL
    private let manifestURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.outboxDirectory = caches.appendingPathComponent("AudioOutbox", isDirectory: true)
        self.manifestURL = outboxDirectory.appendingPathComponent("outbox_manifest.json")
        try? FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)

        startNetworkMonitor()
        refreshPendingCount()
    }

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let online = path.status == .satisfied
                self.isOnline = online
                if online {
                    await self.syncPendingAudios()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Outbox Management

    private func readManifest() -> [AudioSyncItem] {
        guard let data = try? Data(contentsOf: manifestURL),
              let items = try? JSONDecoder().decode([AudioSyncItem].self, from: data) else {
            return []
        }
        return items
    }

    private func saveManifest(_ items: [AudioSyncItem]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: manifestURL, options: .atomic)
        }
        self.pendingCount = items.count
    }

    public func refreshPendingCount() {
        self.pendingCount = readManifest().count
    }

    // MARK: - Source Resolution

    public func resolveAudioSource(
        lang: String,
        date: String,
        category: String,
        index: Int,
        hasDuration: Double
    ) -> (url: URL?, isPendingSync: Bool) {
        let cleanIndex = "\(index)"
        let targetId = "\(lang):\(date):\(category):\(cleanIndex)"
        let manifest = readManifest()

        // 1. If currently waiting in the offline outbox, play from local cache
        if let pending = manifest.first(where: { $0.id == targetId }) {
            let localURL = outboxDirectory.appendingPathComponent(pending.localFileName)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return (localURL, true)
            }
        }

        // 2. If duration exists on server, load from remote server endpoint
        if hasDuration > 0 {
            let remoteURL = AppConfig.httpBaseURL
                .appendingPathComponent("audio")
                .appendingPathComponent(lang)
                .appendingPathComponent(date)
                .appendingPathComponent(category)
                .appendingPathComponent("\(cleanIndex).m4a")
            return (remoteURL, false)
        }

        return (nil, false)
    }

    // MARK: - Recording Ingestion & Dispatch

    public func saveAudioRecord(
        lang: String,
        date: String,
        category: String,
        index: Int,
        sourceFileURL: URL,
        duration: Double
    ) async {
        let cleanIndex = "\(index)"
        let localFileName = "\(lang)_\(date)_\(category)_\(cleanIndex).m4a"
        let outboxURL = outboxDirectory.appendingPathComponent(localFileName)

        // Move/copy recorded audio into the outbox
        try? FileManager.default.removeItem(at: outboxURL)
        do {
            try FileManager.default.copyItem(at: sourceFileURL, to: outboxURL)
            try? FileManager.default.removeItem(at: sourceFileURL)
        } catch {
            print("[AudioSyncEngine] Failed to cache recording into outbox: \(error)")
            return
        }

        let item = AudioSyncItem(
            lang: lang,
            date: date,
            category: category,
            index: cleanIndex,
            duration: duration,
            localFileName: localFileName,
            timestamp: Date()
        )

        var manifest = readManifest()
        manifest.removeAll { $0.id == item.id }
        manifest.append(item)
        saveManifest(manifest)

        // Upload immediately if online
        if isOnline {
            await syncPendingAudios()
        }
    }

    // MARK: - Upload Worker

    public func syncPendingAudios() async {
        guard !isSyncing, isOnline else { return }
        isSyncing = true
        defer { isSyncing = false }

        let manifest = readManifest()
        var completedIDs = Set<String>()

        for item in manifest {
            let fileURL = outboxDirectory.appendingPathComponent(item.localFileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                completedIDs.insert(item.id)
                continue
            }

            let success = await uploadSingleItem(item, fileURL: fileURL)
            if success {
                // Delete file from device disk immediately
                try? FileManager.default.removeItem(at: fileURL)
                completedIDs.insert(item.id)
            } else {
                // Server unreachable or failure: stop draining to prevent hammering the network
                break
            }
        }

        let remaining = manifest.filter { !completedIDs.contains($0.id) }
        saveManifest(remaining)
    }

    private func uploadSingleItem(_ item: AudioSyncItem, fileURL: URL) async -> Bool {
        let endpoint = AppConfig.httpBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("audio")
            .appendingPathComponent(item.lang)
            .appendingPathComponent(item.date)
            .appendingPathComponent(item.category)
            .appendingPathComponent(item.index)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
            if let httpResponse = response as? HTTPURLResponse, (200...204).contains(httpResponse.statusCode) {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}