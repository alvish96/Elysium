import Foundation
import AVFoundation
import MediaPlayer
import Observation

@Observable
final class AudioPlayerManager: NSObject {
    static let shared = AudioPlayerManager()

    var currentTrack: SubsonicTrack?
    var isPlaying = false
    var currentTime: Double = 0.0
    var duration: Double = 1.0

    private var player: AVPlayer?
    private var timeObserverToken: Any?

    // Local Storage for Offline Tracks
    private let offlineDir: URL

    override private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.offlineDir = docs.appendingPathComponent("offline_tracks", isDirectory: true)
        super.init()

        try? FileManager.default.createDirectory(at: offlineDir, withIntermediateDirectories: true)
        setupAudioSession()
        setupRemoteCommands()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }

    func playTrack(_ track: SubsonicTrack) {
        self.currentTrack = track
        
        let playURL: URL
        let localFile = offlineDir.appendingPathComponent("\(track.id).mp3")
        
        if FileManager.default.fileExists(atPath: localFile.path) {
            playURL = localFile
        } else {
            playURL = APIClient.shared.getStreamURL(trackId: track.id)
        }

        let playerItem = AVPlayerItem(url: playURL)
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }

        player?.play()
        self.isPlaying = true

        setupTimeObserver()
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackState()
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    // MARK: - Lock Screen & CarPlay Remote Commands
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.isPlaying = true
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: posEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist ?? "Nexus Music",
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(track.duration ?? 180),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime().seconds ?? 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let coverUrl = APIClient.shared.getCoverArtURL(coverId: track.coverArt) {
            URLSession.shared.dataTask(with: coverUrl) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }.resume()
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds ?? 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }

    private func setupTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            if let dur = self.player?.currentItem?.duration.seconds, !dur.isNaN {
                self.duration = dur
            }
        }
    }

    // MARK: - 1-Tap Offline Caching
    func isTrackCached(trackId: String) -> Bool {
        let localFile = offlineDir.appendingPathComponent("\(trackId).mp3")
        return FileManager.default.fileExists(atPath: localFile.path)
    }

    func downloadForOffline(track: SubsonicTrack) async throws {
        let streamURL = APIClient.shared.getStreamURL(trackId: track.id)
        let (data, _) = try await URLSession.shared.data(from: streamURL)
        let destination = offlineDir.appendingPathComponent("\(track.id).mp3")
        try data.write(to: destination)
    }
}
