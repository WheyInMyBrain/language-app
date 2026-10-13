import Foundation
import OSLog

private let logger = Logger(subsystem: "com.personal.LanguageApp", category: "SyncClient")

public actor MultiplexedSyncClient {
    public static let shared = MultiplexedSyncClient()

    private let MSG_SUBSCRIBE: UInt8 = 0x01
    private let MSG_UNSUBSCRIBE: UInt8 = 0x02
    private let MSG_PAYLOAD: UInt8 = 0x03

    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected: Bool = false
    private var pendingOutbox: [Data] = []
    private var subscribers: [String: [UUID: AsyncStream<Data>.Continuation]] = [:]

    private init() {}

    public func connect() {
        guard webSocketTask == nil else { return }
        
        let request = URLRequest(url: AppConfig.wsBaseURL)
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()
        
        // Mark connected and flush outbox
        self.isConnected = true
        flushPendingOutbox()
        listenForMessages()
    }

    public func subscribe(room: String) -> AsyncStream<Data> {
        if webSocketTask == nil {
            connect()
        }

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let id = UUID()

        var current = subscribers[room] ?? [:]
        let isFirst = current.isEmpty
        current[id] = continuation
        subscribers[room] = current

        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.unsubscribe(room: room, id: id)
            }
        }

        if isFirst {
            sendSubscribe(room: room)
        }

        return stream
    }

    private func unsubscribe(room: String, id: UUID) {
        guard var current = subscribers[room] else { return }
        current.removeValue(forKey: id)
        if current.isEmpty {
            subscribers.removeValue(forKey: room)
            sendUnsubscribe(room: room)
        } else {
            subscribers[room] = current
        }
    }

    public func sendPayload(room: String, payload: Data) {
        let frame = encodeFrame(flag: MSG_PAYLOAD, room: room, payload: payload)
        send(frame: frame)
    }

    private func sendSubscribe(room: String) {
        let frame = encodeFrame(flag: MSG_SUBSCRIBE, room: room, payload: Data())
        send(frame: frame)
    }

    private func sendUnsubscribe(room: String) {
        let frame = encodeFrame(flag: MSG_UNSUBSCRIBE, room: room, payload: Data())
        send(frame: frame)
    }

    private func encodeFrame(flag: UInt8, room: String, payload: Data) -> Data {
        let nameBytes = Data(room.utf8)
        let nameLen = UInt16(nameBytes.count)

        var frame = Data()
        frame.append(flag)
        frame.append(UInt8((nameLen >> 8) & 0xFF))
        frame.append(UInt8(nameLen & 0xFF))
        frame.append(nameBytes)
        frame.append(payload)
        return frame
    }

    private func send(frame: Data) {
        guard let task = webSocketTask, isConnected else {
            pendingOutbox.append(frame)
            return
        }

        task.send(.data(frame)) { error in
            if let error {
                logger.error("Failed to send frame: \(error.localizedDescription)")
            }
        }
    }

    private func flushPendingOutbox() {
        guard let task = webSocketTask, isConnected else { return }
        while !pendingOutbox.isEmpty {
            let frame = pendingOutbox.removeFirst()
            task.send(.data(frame)) { error in
                if let error {
                    logger.error("Outbox send error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func listenForMessages() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            guard let self else { return }
            Task {
                switch result {
                case .success(let message):
                    if case .data(let data) = message {
                        await self.handleIncomingFrame(data)
                    }
                    await self.listenForMessages()

                case .failure(let error):
                    logger.warning("WebSocket stream ended: \(error.localizedDescription)")
                    await self.resetSocketTask()
                }
            }
        }
    }

    private func resetSocketTask() {
        self.webSocketTask = nil
        self.isConnected = false
    }

    private func handleIncomingFrame(_ buf: Data) {
        guard buf.count >= 3 else { return }
        let flag = buf[0]
        let nameLen = Int(UInt16(buf[1]) << 8 | UInt16(buf[2]))
        guard buf.count >= 3 + nameLen else { return }

        let nameData = buf.subdata(in: 3..<(3 + nameLen))
        guard let roomName = String(data: nameData, encoding: .utf8) else { return }
        let payload = buf.subdata(in: (3 + nameLen)..<buf.count)

        if flag == MSG_PAYLOAD && !payload.isEmpty {
            if let listeners = subscribers[roomName] {
                for continuation in listeners.values {
                    continuation.yield(payload)
                }
            }
        }
    }
}