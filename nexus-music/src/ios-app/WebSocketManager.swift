import Foundation
import Observation
import Combine

@Observable
public final class WebSocketManager: @unchecked Sendable {
    public static let shared = WebSocketManager()

    // MARK: - Observable UI State

    public var isConnected: Bool = false
    public var lastEvent: WSEvent? = nil
    public var isReconnecting: Bool = false

    // MARK: - Combine & Stream Emitter

    public let eventSubject = PassthroughSubject<WSEvent, Never>()

    // MARK: - Internal Engine Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var currentToken: String = ""
    private var retryCount: Int = 0
    private var isIntentionallyClosed: Bool = false

    private let lock = NSLock()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection Management

    public func connect(token: String) {
        lock.lock()
        defer { lock.unlock() }

        guard !token.isEmpty else { return }

        self.currentToken = token
        self.isIntentionallyClosed = false
        self.retryCount = 0

        cancelTimersAndTask()
        initiateSocketTask(token: token)
    }

    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        self.isIntentionallyClosed = true
        self.currentToken = ""
        self.retryCount = 0

        cancelTimersAndTask()

        DispatchQueue.main.async {
            self.isConnected = false
            self.isReconnecting = false
        }
    }

    // MARK: - Socket Lifecycle

    private func initiateSocketTask(token: String) {
        let syncBase = APIClient.shared.syncBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        let wsScheme: String
        if syncBase.lowercased().hasPrefix("https://") {
            wsScheme = "wss://"
        } else {
            wsScheme = "ws://"
        }

        let rawHost = syncBase
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)

        guard let socketURL = URL(string: "\(wsScheme)\(rawHost)/api/v1/ws?token=\(token)") else {
            return
        }

        let task = session.webSocketTask(with: socketURL)
        self.webSocketTask = task
        task.resume()

        listenForMessages()
        scheduleKeepaliveTimer()

        DispatchQueue.main.async {
            self.isConnected = true
            self.isReconnecting = false
        }
    }

    private func cancelTimersAndTask() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        pingTimer?.invalidate()
        pingTimer = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Listen & Dispatch Pipeline

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseAndEmit(text: text)
                case .data(let data):
                    if let string = String(data: data, encoding: .utf8) {
                        self.parseAndEmit(text: string)
                    }
                @unknown default:
                    break
                }
                self.listenForMessages()

            case .failure:
                self.handleSocketFailure()
            }
        }
    }

    private func parseAndEmit(text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "pong" {
            return
        }

        guard let data = text.data(using: .utf8) else { return }

        do {
            let event = try JSONDecoder().decode(WSEvent.self, data: data)
            DispatchQueue.main.async {
                self.lastEvent = event
                self.eventSubject.send(event)
            }
        } catch {
            // Silently drop non-matching control messages
        }
    }

    // MARK: - Keepalive Heartbeat

    private func scheduleKeepaliveTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
                self?.sendKeepalive()
            }
        }
    }

    private func sendKeepalive() {
        guard let task = webSocketTask, isConnected else { return }

        task.sendPing { [weak self] error in
            if error != nil {
                self?.handleSocketFailure()
            }
        }

        let pingMessage = URLSessionWebSocketTask.Message.string("ping")
        task.send(pingMessage) { _ in }
    }

    // MARK: - Reconnection & Resilience

    private func handleSocketFailure() {
        lock.lock()
        guard !isIntentionallyClosed else {
            lock.unlock()
            return
        }

        cancelTimersAndTask()

        DispatchQueue.main.async {
            self.isConnected = false
            self.isReconnecting = true
        }

        let backoffDelay = min(30.0, pow(2.0, Double(min(retryCount, 5))))
        retryCount += 1
        let tokenToReuse = self.currentToken

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            defer self.lock.unlock()

            guard !self.isIntentionallyClosed, !tokenToReuse.isEmpty else { return }
            self.initiateSocketTask(token: tokenToReuse)
        }

        self.reconnectWorkItem = workItem
        lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + backoffDelay, execute: workItem)
    }
}

