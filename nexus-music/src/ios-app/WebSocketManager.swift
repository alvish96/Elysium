import Foundation
import Observation

@Observable
final class WebSocketManager {
    static let shared = WebSocketManager()

    var isConnected = false
    var lastEvent: WSEvent?

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?

    private init() {}

    func connect(token: String) {
        disconnect()

        guard let url = URL(string: "ws://sync.nexus.link/api/v1/ws?token=\(token)") else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        self.isConnected = true

        receiveMessage()
        startPingTimer()
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let event = try? JSONDecoder().decode(WSEvent.self, data: data) {
                        DispatchQueue.main.async {
                            self.lastEvent = event
                        }
                    }
                default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                print("WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }

    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    print("WebSocket ping failure: \(error)")
                }
            }
        }
    }
}
