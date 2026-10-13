import Foundation
import YSwift
import OSLog

private let logger = Logger(subsystem: "com.personal.LanguageApp", category: "YDocSession")

/// Manages a single synchronized Yjs document room with local disk persistence (equivalent to y-indexeddb)
/// and bidirectional multiplexed WebSocket sync matching y-protocols.
public final class YDocSession: @unchecked Sendable {
    public let roomName: String
    public let doc: YDocument
    
    /// A valid empty Yjs V1 StateVector (0 entries, encoded as a single byte 0x00 in lib0 varuint)
    private static let emptyStateVector: [UInt8] = [0]
    
    // y-protocols sync sub-types
    private static let YJS_SYNC_STEP_1: UInt8 = 0
    private static let YJS_SYNC_STEP_2: UInt8 = 1
    private static let YJS_UPDATE: UInt8 = 2

    private var syncTask: Task<Void, Never>?
    private var onUpdateHandler: (@Sendable () -> Void)?

    // MARK: - Local Disk Storage Path
    private static var storageDirectory: URL = {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("YjsStorage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var storageFileURL: URL {
        let safeName = roomName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return Self.storageDirectory.appendingPathComponent("\(safeName).ydoc")
    }

    public init(roomName: String, onUpdate: (@Sendable () -> Void)? = nil) {
        self.roomName = roomName
        self.doc = YDocument()
        self.onUpdateHandler = onUpdate
        
        // 1. Instant local offline restore (equivalent to y-indexeddb on web)
        loadFromDisk()

        // 2. Start multiplexed network sync
        startSync()
    }

    deinit {
        syncTask?.cancel()
    }

    // MARK: - Local Persistence (IndexedDB Equivalent)

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageFileURL)
            // Discard legacy or corrupt empty 2-byte files
            guard data.count > 2 else { return }

            doc.transactSync(origin: nil) { txn in
                try? txn.transactionApplyUpdate(update: [UInt8](data))
            }
            logger.info("Loaded \(data.count) bytes from local storage for room: \(self.roomName, privacy: .public)")
            onUpdateHandler?()
        } catch {
            logger.error("Failed to load offline storage for \(self.roomName, privacy: .public): \(error.localizedDescription)")
        }
    }

    public func saveToDisk() {
        let snapshot: [UInt8] = doc.transactSync(origin: nil) { txn in
            return self.doc.diff(txn: txn, from: Self.emptyStateVector)
        }
        
        // Yjs diff of an empty doc is 2 bytes ([0, 0]). Never persist empty dummy diffs!
        guard snapshot.count > 2 else { return }

        do {
            try Data(snapshot).write(to: storageFileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist offline storage for \(self.roomName, privacy: .public): \(error.localizedDescription)")
        }
    }

    // MARK: - Bidirectional Sync Pipeline

    private func startSync() {
        syncTask = Task { [weak self] in
            guard let self else { return }
            let stream = await MultiplexedSyncClient.shared.subscribe(room: self.roomName)

            // Step 1: Send local State Vector to request remote diff
            let sv: [UInt8] = self.doc.transactSync(origin: nil) { txn in
                txn.transactionStateVector()
            }
            var step1Payload = Data([Self.YJS_SYNC_STEP_1])
            Lib0Encoder.writeVarUInt8Array(Data(sv), into: &step1Payload)
            await MultiplexedSyncClient.shared.sendPayload(room: self.roomName, payload: step1Payload)

            // Ingest incoming remote binary frames
            for await frame in stream {
                guard !Task.isCancelled else { break }
                guard !frame.isEmpty else { continue }
                
                let syncType = frame[0]
                var offset = 1

                guard let payloadBytes = Lib0Decoder.readVarUInt8Array(from: frame, offset: &offset) else {
                    continue
                }

                switch syncType {
                case Self.YJS_SYNC_STEP_1:
                    // Server sent its State Vector -> compute local diff and reply with SyncStep2
                    let diffBytes: [UInt8] = self.doc.transactSync(origin: nil) { txn in
                        return self.doc.diff(txn: txn, from: [UInt8](payloadBytes))
                    }
                    var step2Payload = Data([Self.YJS_SYNC_STEP_2])
                    Lib0Encoder.writeVarUInt8Array(Data(diffBytes), into: &step2Payload)
                    await MultiplexedSyncClient.shared.sendPayload(room: self.roomName, payload: step2Payload)

                case Self.YJS_SYNC_STEP_2, Self.YJS_UPDATE:
                    // Server sent an update (or diff) -> apply to local doc, save to disk, and notify
                    self.doc.transactSync(origin: nil) { txn in
                        try? txn.transactionApplyUpdate(update: [UInt8](payloadBytes))
                    }
                    self.saveToDisk()
                    self.onUpdateHandler?()

                default:
                    logger.debug("Unhandled sync sub-type: \(syncType)")
                }
            }
        }
    }

    // MARK: - Local-First Mutations

    /// Commits an update to a YMap safely
    public func commitMapUpdate<T: Codable>(mapName: String, key: String, value: T) async {
        guard !mapName.isEmpty, !key.isEmpty else { return }
        
        let updateData: [UInt8]? = doc.transactSync(origin: nil) { txn in
            let map: YMap<T> = self.doc.getOrCreateMap(named: mapName)
            map.updateValue(value, forKey: key, transaction: txn)
            return self.doc.diff(txn: txn, from: Self.emptyStateVector)
        }

        guard let updateData, !updateData.isEmpty else { return }

        saveToDisk()

        var updatePayload = Data([Self.YJS_UPDATE])
        Lib0Encoder.writeVarUInt8Array(Data(updateData), into: &updatePayload)
        await MultiplexedSyncClient.shared.sendPayload(room: roomName, payload: updatePayload)
    }

    /// Commits an update to a YArray, persists to disk immediately, and broadcasts diff to backend
    public func commitArrayAppend<T: Codable>(arrayName: String, values: [T]) async {
        let array: YArray<T> = doc.getOrCreateArray(named: arrayName)
        let updateData: [UInt8] = doc.transactSync(origin: nil) { txn in
            for item in values {
                array.append(item, transaction: txn)
            }
            return self.doc.diff(txn: txn, from: Self.emptyStateVector)
        }

        // 1. Immediately persist offline locally
        saveToDisk()

        // 2. Broadcast out to backend
        var updatePayload = Data([Self.YJS_UPDATE])
        Lib0Encoder.writeVarUInt8Array(Data(updateData), into: &updatePayload)
        await MultiplexedSyncClient.shared.sendPayload(room: roomName, payload: updatePayload)
    }
}