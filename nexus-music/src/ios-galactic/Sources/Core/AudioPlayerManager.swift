import Foundation
import AVFoundation
import MediaPlayer
import Observation

@Observable
public final class AudioPlayerManager: @unchecked Sendable {
    public static let shared = AudioPlayerManager()

    public var currentTrack: SubsonicTrack?
    public var queue: [SubsonicTrack] = []
    public var currentIndex: Int = 0
    public var isPlaying: Bool = false
    public var currentTime: Double = 0
    public var duration: Double = 1
    public var cachedTrackIDs: Set<String> = []

    private var player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private let offlineDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.offlineDir = docs.appendingPathComponent("OfflineTracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: offlineDir, withIntermediateDirectories: true)
        refreshCachedTrackList()
        configureAudioSession()
        setupRemoteTransportControls()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession error: \(error)")
        }
    }

    public func refreshCachedTrackList() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: offlineDir.path) else { return }
        cachedTrackIDs = Set(files.filter { $0.hasSuffix(".mp3") }.map { $0.replacingOccurrences(of: ".mp3", with: "") })
    }

    public func isTrackCached(_ id: String) -> Bool {
        cachedTrackIDs.contains(id)
    }

    @MainActor
    public func playDownloadedFile(_ file: DownloadedTrackFile) {
        guard let streamURL = APIClient.shared.directDownloadedTrackStreamURL(filename: file.filename) else { return }
        let track = SubsonicTrack(
            id: file.filename,
            title: file.title,
            artist: file.artist,
            album: "Atlantis Master Pool",
            duration: nil,
            coverArt: nil,
            suffix: "mp3",
            directStreamURL: streamURL
        )
        playPlaylist(tracks: [track], startingAt: 0)
    }

    @MainActor
    public func playPlaylist(tracks: [SubsonicTrack], startingAt index: Int = 0) {
        guard !tracks.isEmpty, tracks.indices.contains(index) else { return }
        self.queue = tracks
        self.currentIndex = index
        loadAndPlay(tracks[index])
    }

    @MainActor
    private func loadAndPlay(_ track: SubsonicTrack) {
        self.currentTrack = track
        let localFile = offlineDir.appendingPathComponent("\(track.id).mp3")
        let playURL: URL?

        if FileManager.default.fileExists(atPath: localFile.path) {
            playURL = localFile
        } else if let direct = track.directStreamURL {
            playURL = direct
        } else {
            playURL = APIClient.shared.getSubsonicStreamURL(trackId: track.id)
        }

        guard let url = playURL else { return }
        removePlaybackObservers()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        currentTime = 0

        if let dur = track.duration, dur > 0 {
            self.duration = Double(dur)
        } else {
            self.duration = 1
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            if let itemDur = self.player.currentItem?.duration.seconds, itemDur.isFinite, itemDur > 0 {
                self.duration = itemDur
            }
            self.updateNowPlayingCenter()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.nextTrack() }
        }
        updateNowPlayingCenter()
    }

    @MainActor
    public func stopAndClose() {
        player.pause()
        removePlaybackObservers()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTrack = nil
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func removePlaybackObservers() {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        if let endObs = endObserver {
            NotificationCenter.default.removeObserver(endObs)
            endObserver = nil
        }
    }

    @MainActor
    public func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingCenter()
    }

    @MainActor
    public func nextTrack() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queue.count
        loadAndPlay(queue[currentIndex])
    }

    @MainActor
    public func previousTrack() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        loadAndPlay(queue[currentIndex])
    }

    public func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    public func cacheTrackForOffline(_ track: SubsonicTrack) async {
        let url = track.directStreamURL ?? APIClient.shared.getSubsonicStreamURL(trackId: track.id)
        guard let streamURL = url,
              let (data, _) = try? await URLSession.shared.data(from: streamURL) else { return }
        let dest = offlineDir.appendingPathComponent("\(track.id).mp3")
        try? data.write(to: dest, options: .atomic)
        await MainActor.run {
            cachedTrackIDs.insert(track.id)
        }
    }

    private func setupRemoteTransportControls() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextTrack() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousTrack() }
            return .success
        }
    }

    private func updateNowPlayingCenter() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist ?? "Nexus Galactic",
            MPMediaItemPropertyAlbumTitle: track.album ?? "Holocron Archive",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
