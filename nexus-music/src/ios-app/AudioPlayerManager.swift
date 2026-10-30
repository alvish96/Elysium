import Foundation
import AVFoundation
import MediaPlayer
import Observation

public enum PlaybackRepeatMode: String, CaseIterable, Sendable {
    case off = "Off"
    case all = "All"
    case one = "One"

    public var iconName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

public struct OfflineIndexMetadata: Codable, Sendable {
    public var tracks: [String: SubsonicTrack]

    public init(tracks: [String: SubsonicTrack] = [:]) {
        self.tracks = tracks
    }
}

@Observable
public final class AudioPlayerManager: NSObject, @unchecked Sendable {
    public static let shared = AudioPlayerManager()

    // MARK: - Published State

    public var currentTrack: SubsonicTrack?
    public var queue: [SubsonicTrack] = []
    public var originalQueue: [SubsonicTrack] = []
    public var currentIndex: Int = 0

    public var isPlaying: Bool = false
    public var isBuffering: Bool = false
    public var currentTime: Double = 0.0
    public var duration: Double = 1.0

    public var isShuffleEnabled: Bool = false {
        didSet {
            handleShuffleToggled()
        }
    }

    public var repeatMode: PlaybackRepeatMode = .off

    public var cachedTrackIds: Set<String> = []
    public var inFlightDownloads: [String: Double] = [:]

    // MARK: - Audio Engine Core

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private let offlineDir: URL
    private let offlineIndexFile: URL
    private let lock = NSLock()

    // MARK: - Lifecycle

    override private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.offlineDir = docs.appendingPathComponent("OfflineTracks", isDirectory: true)
        self.offlineIndexFile = offlineDir.appendingPathComponent("index.json")

        super.init()

        createOfflineDirectoryIfNeeded()
        refreshCachedTrackIds()
        setupAudioSession()
        setupRemoteCommands()
        registerNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("Failed to activate playback AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func registerNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    // MARK: - Queue & Playback Controls

    public func playPlaylist(tracks: [SubsonicTrack], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        self.originalQueue = tracks

        if isShuffleEnabled {
            var shuffled = tracks
            let target = (index >= 0 && index < tracks.count) ? tracks[index] : tracks[0]
            shuffled.shuffle()
            if let targetIdx = shuffled.firstIndex(of: target) {
                shuffled.remove(at: targetIdx)
                shuffled.insert(target, at: 0)
            }
            self.queue = shuffled
            self.currentIndex = 0
        } else {
            self.queue = tracks
            self.currentIndex = max(0, min(index, tracks.count - 1))
        }

        playCurrentQueueItem()
    }

    public func playTrack(_ track: SubsonicTrack) {
        if let existingIndex = queue.firstIndex(where: { $0.id == track.id }) {
            self.currentIndex = existingIndex
            playCurrentQueueItem()
        } else {
            self.originalQueue = [track]
            self.queue = [track]
            self.currentIndex = 0
            playCurrentQueueItem()
        }
    }

    public func togglePlayPause() {
        guard let p = player else {
            if !queue.isEmpty {
                playCurrentQueueItem()
            }
            return
        }

        if isPlaying {
            p.pause()
            self.isPlaying = false
        } else {
            p.play()
            self.isPlaying = true
        }
        updateNowPlayingPlaybackState()
    }

    public func nextTrack() {
        guard !queue.isEmpty else { return }

        if currentIndex + 1 < queue.count {
            currentIndex += 1
            playCurrentQueueItem()
        } else if repeatMode == .all {
            currentIndex = 0
            playCurrentQueueItem()
        } else {
            player?.pause()
            self.isPlaying = false
            updateNowPlayingPlaybackState()
        }
    }

    public func previousTrack() {
        guard !queue.isEmpty else { return }

        if currentTime > 3.0 {
            seek(to: 0.0)
            return
        }

        if currentIndex - 1 >= 0 {
            currentIndex -= 1
            playCurrentQueueItem()
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            playCurrentQueueItem()
        } else {
            seek(to: 0.0)
        }
    }

    public func seek(to seconds: Double) {
        let clamped = max(0.0, min(seconds, duration))
        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            if completed {
                self?.currentTime = clamped
                self?.updateNowPlayingPlaybackState()
            }
        }
    }

    private func handleShuffleToggled() {
        guard let current = currentTrack else { return }
        if isShuffleEnabled {
            var shuffled = originalQueue
            shuffled.shuffle()
            if let idx = shuffled.firstIndex(where: { $0.id == current.id }) {
                shuffled.remove(at: idx)
                shuffled.insert(current, at: 0)
            }
            self.queue = shuffled
            self.currentIndex = 0
        } else {
            self.queue = originalQueue
            if let idx = originalQueue.firstIndex(where: { $0.id == current.id }) {
                self.currentIndex = idx
            }
        }
    }

    // MARK: - Internal Player Pipeline

    private func playCurrentQueueItem() {
        guard currentIndex >= 0 && currentIndex < queue.count else { return }
        let track = queue[currentIndex]
        self.currentTrack = track
        self.currentTime = 0.0
        self.duration = Double(track.duration ?? 180)
        self.isBuffering = true

        let resolvedURL: URL
        let localFile = offlineDir.appendingPathComponent("\(track.id).mp3")

        if FileManager.default.fileExists(atPath: localFile.path) {
            resolvedURL = localFile
        } else if let streamURL = APIClient.shared.getStreamURL(trackId: track.id) {
            resolvedURL = streamURL
        } else {
            print("Failed to resolve playable URL for track \(track.id)")
            return
        }

        playerItemStatusObserver?.invalidate()
        let playerItem = AVPlayerItem(url: resolvedURL)

        playerItemStatusObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    self.isBuffering = false
                    let itemDuration = item.duration.seconds
                    if !itemDuration.isNaN && itemDuration > 0 {
                        self.duration = itemDuration
                    }
                    self.updateNowPlayingInfo()
                } else if item.status == .failed {
                    self.isBuffering = false
                    print("Player item failed: \(String(describing: item.error?.localizedDescription))")
                }
            }
        }

        if let existingPlayer = player {
            existingPlayer.replaceCurrentItem(with: playerItem)
        } else {
            player = AVPlayer(playerItem: playerItem)
            player?.automaticallyWaitsToMinimizeStalling = true
        }

        player?.play()
        self.isPlaying = true

        setupTimeObserver()
        updateNowPlayingInfo()
    }

    private func setupTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let secs = time.seconds
            if !secs.isNaN {
                self.currentTime = secs
            }
            if let dur = self.player?.currentItem?.duration.seconds, !dur.isNaN && dur > 0 {
                self.duration = dur
            }
        }
    }

    // MARK: - Lock Screen & Control Center Commands

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if !self.isPlaying {
                self.togglePlayPause()
                return .success
            }
            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.togglePlayPause()
                return .success
            }
            return .commandFailed
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrack()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrack()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: posEvent.positionTime)
            return .success
        }

        commandCenter.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let self = self, let shuffleEvent = event as? MPChangeShuffleModeCommandEvent else {
                return .commandFailed
            }
            self.isShuffleEnabled = (shuffleEvent.shuffleType != .off)
            return .success
        }

        commandCenter.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let self = self, let repEvent = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }
            switch repEvent.repeatType {
            case .one: self.repeatMode = .one
            case .all: self.repeatMode = .all
            default: self.repeatMode = .off
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist ?? "Nexus Music",
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPMediaItemPropertyPlaybackDuration: self.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: self.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if let coverArtURL = APIClient.shared.getCoverArtURL(coverId: track.coverArt) {
            fetchCoverArtImage(from: coverArtURL) { [weak self] image in
                guard let self = self, self.currentTrack?.id == track.id, let image = image else { return }
                DispatchQueue.main.async {
                    var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    currentInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func fetchCoverArtImage(from url: URL, completion: @escaping @Sendable (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            completion(image)
        }.resume()
    }

    // MARK: - Notifications Handlers

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            DispatchQueue.main.async {
                self.isPlaying = false
                self.updateNowPlayingPlaybackState()
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                DispatchQueue.main.async {
                    self.player?.play()
                    self.isPlaying = true
                    self.updateNowPlayingPlaybackState()
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleItemDidPlayToEnd(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch self.repeatMode {
            case .one:
                self.seek(to: 0.0)
                self.player?.play()
                self.isPlaying = true
            case .all:
                self.nextTrack()
            case .off:
                if self.currentIndex + 1 < self.queue.count {
                    self.nextTrack()
                } else {
                    self.seek(to: 0.0)
                    self.isPlaying = false
                    self.player?.pause()
                    self.updateNowPlayingPlaybackState()
                }
            }
        }
    }

    // MARK: - Offline Flight Mode Caching Engine

    public func isTrackCached(_ trackId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedTrackIds.contains(trackId)
    }

    public func downloadTrackForOffline(_ track: SubsonicTrack) async throws {
        guard let streamURL = APIClient.shared.getStreamURL(trackId: track.id) else {
            throw NSError(domain: "link.nexus.music", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid stream URL"])
        }

        await MainActor.run {
            self.inFlightDownloads[track.id] = 0.05
        }

        let destination = offlineDir.appendingPathComponent("\(track.id).mp3")
        let (tempFile, response) = try await URLSession.shared.download(from: streamURL)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            await MainActor.run {
                self.inFlightDownloads.removeValue(forKey: track.id)
            }
            throw NSError(domain: "link.nexus.music", code: 500, userInfo: [NSLocalizedDescriptionKey: "Download failed from server"])
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempFile, to: destination)

        lock.lock()
        var index = readOfflineIndex()
        index.tracks[track.id] = track
        saveOfflineIndex(index)
        self.cachedTrackIds.insert(track.id)
        lock.unlock()

        await MainActor.run {
            self.inFlightDownloads.removeValue(forKey: track.id)
        }
    }

    public func downloadEntirePlaylist(_ tracks: [SubsonicTrack]) async throws {
        for track in tracks {
            if !isTrackCached(track.id) {
                try await downloadTrackForOffline(track)
            }
        }
    }

    public func removeOfflineTrack(_ trackId: String) {
        lock.lock()
        defer { lock.unlock() }

        let file = offlineDir.appendingPathComponent("\(trackId).mp3")
        try? FileManager.default.removeItem(at: file)

        var index = readOfflineIndex()
        index.tracks.removeValue(forKey: trackId)
        saveOfflineIndex(index)
        self.cachedTrackIds.remove(trackId)
    }

    public func clearAllOfflineCache() {
        lock.lock()
        defer { lock.unlock() }

        try? FileManager.default.removeItem(at: offlineDir)
        createOfflineDirectoryIfNeeded()
        self.cachedTrackIds.removeAll()
    }

    public func getCachedTracks() -> [SubsonicTrack] {
        lock.lock()
        defer { lock.unlock() }
        let index = readOfflineIndex()
        return Array(index.tracks.values)
    }

    private func createOfflineDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: offlineDir.path) {
            try? FileManager.default.createDirectory(at: offlineDir, withIntermediateDirectories: true)
        }
    }

    private func refreshCachedTrackIds() {
        let index = readOfflineIndex()
        self.cachedTrackIds = Set(index.tracks.keys)
    }

    private func readOfflineIndex() -> OfflineIndexMetadata {
        guard let data = try? Data(contentsOf: offlineIndexFile),
              let index = try? JSONDecoder().decode(OfflineIndexMetadata.self, data: data) else {
            return OfflineIndexMetadata()
        }
        return index
    }

    private func saveOfflineIndex(_ index: OfflineIndexMetadata) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: offlineIndexFile, options: .atomic)
    }
}
