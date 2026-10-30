import SwiftUI
import AVKit
import MediaPlayer
import Observation

// MARK: - AirPlay Route Picker Representable

public struct AirPlayRoutePicker: UIViewRepresentable {
    public var tintColor: UIColor

    public init(tintColor: UIColor = .white) {
        self.tintColor = tintColor
    }

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tintColor
        picker.activeTintColor = UIColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 1.0)
        picker.backgroundColor = .clear
        picker.prioritizesVideoDevices = false
        return picker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}

// MARK: - Floating Glassmorphic MiniPlayer View

public struct MiniPlayerView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AudioPlayerManager.self) private var player
    @Environment(APIClient.self) private var apiClient

    @State private var showFullPlayer: Bool = false

    public init() {}

    public var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                // Top Mini Progress Line
                GeometryReader { geo in
                    let fraction = player.duration > 0 ? (player.currentTime / player.duration) : 0.0
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(theme.cardBorder.opacity(0.3))
                            .frame(height: 2.5)

                        Rectangle()
                            .fill(theme.accentEmerald)
                            .frame(width: max(0, geo.size.width * CGFloat(fraction)), height: 2.5)
                    }
                }
                .frame(height: 2.5)

                HStack(spacing: 12) {
                    // Thumbnail Cover Art
                    AsyncImage(url: apiClient.getCoverArtURL(coverId: track.coverArt)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            ZStack {
                                Rectangle().fill(theme.cardBorder.opacity(0.4))
                                Image(systemName: "music.note")
                                    .font(.caption)
                                    .foregroundStyle(theme.mutedText)
                            }
                        @unknown default:
                            Rectangle().fill(theme.cardBorder.opacity(0.4))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                    )

                    // Track & Artist
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(track.artist ?? "Nexus Audio")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Controls: Play/Pause & Next
                    HStack(spacing: 14) {
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(theme.primaryText)
                        }
                        .buttonStyle(.plain)

                        Button {
                            player.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .glassCard(cornerRadius: 16, padding: nil)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                showFullPlayer = true
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Apple Music-Inspired FullScreen Now Playing Modal

public struct FullPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AudioPlayerManager.self) private var player
    @Environment(APIClient.self) private var apiClient

    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0.0

    public init() {}

    public var body: some View {
        ZStack {
            AppCanvasBackgroundView()

            VStack(spacing: 0) {
                // Top Dismiss Handle & AirPlay Picker
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.secondaryText)
                            .padding(10)
                            .background(theme.pillBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 1) {
                        Text("PLAYING FROM SERVER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.mutedText)

                        Text(player.currentTrack?.album ?? "Nexus Music Library")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    AirPlayRoutePicker(tintColor: theme.isLightMode ? .black : .white)
                        .frame(width: 38, height: 38)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                Spacer()

                // Large Shadowed Artwork
                AsyncImage(url: apiClient.getCoverArtURL(coverId: player.currentTrack?.coverArt)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure, .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(theme.cardBackground)
                            Image(systemName: "music.note")
                                .font(.system(size: 72))
                                .foregroundStyle(theme.mutedText)
                        }
                    @unknown default:
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(theme.cardBackground)
                    }
                }
                .frame(maxWidth: 320, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaleEffect(player.isPlaying ? 1.0 : 0.92)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)
                .shadow(color: Color.black.opacity(theme.isLightMode ? 0.2 : 0.55), radius: 25, x: 0, y: 15)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: 1.0)
                )
                .padding(.horizontal, 28)

                Spacer()

                // Track Meta & Offline Badge
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentTrack?.title ?? "No Audio Playing")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)

                            Text(player.currentTrack?.artist ?? "Select a track to stream")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let track = player.currentTrack {
                            Button {
                                if player.isTrackCached(track.id) {
                                    player.removeOfflineTrack(track.id)
                                } else {
                                    Task { try? await player.downloadTrackForOffline(track) }
                                }
                            } label: {
                                Image(systemName: player.isTrackCached(track.id) ? "arrow.down.circle.fill" : "arrow.down.circle")
                                    .font(.title3)
                                    .foregroundStyle(player.isTrackCached(track.id) ? theme.accentEmerald : theme.mutedText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 28)

                // Interactive Scrubber Slider
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubValue : player.currentTime },
                            set: { scrubValue = $0 }
                        ),
                        in: 0...max(player.duration, 1.0),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                player.seek(to: scrubValue)
                            }
                        }
                    )
                    .tint(theme.accentEmerald)

                    HStack {
                        Text(formatTime(isScrubbing ? scrubValue : player.currentTime))
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.mutedText)

                        Spacer()

                        Text(formatTime(player.duration))
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.mutedText)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)

                // Playback Control Buttons
                HStack(spacing: 36) {
                    // Shuffle
                    Button {
                        player.isShuffleEnabled.toggle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundStyle(player.isShuffleEnabled ? theme.accentEmerald : theme.mutedText)
                    }
                    .buttonStyle(.plain)

                    // Previous
                    Button {
                        player.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                            .foregroundStyle(theme.primaryText)
                    }
                    .buttonStyle(.plain)

                    // Play/Pause Big Button
                    Button {
                        player.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(theme.primaryText)
                                .frame(width: 72, height: 72)
                                .shadow(color: theme.accentEmeraldGlow, radius: 10)

                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundStyle(theme.isLightMode ? Color.white : Color.black)
                                .offset(x: player.isPlaying ? 0 : 2)
                        }
                    }
                    .buttonStyle(.plain)

                    // Next
                    Button {
                        player.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundStyle(theme.primaryText)
                    }
                    .buttonStyle(.plain)

                    // Repeat Mode Toggle
                    Button {
                        cycleRepeatMode()
                    } label: {
                        Image(systemName: player.repeatMode.iconName)
                            .font(.title3)
                            .foregroundStyle(player.repeatMode != .off ? theme.accentEmerald : theme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
    }

    private func cycleRepeatMode() {
        switch player.repeatMode {
        case .off:
            player.repeatMode = .all
        case .all:
            player.repeatMode = .one
        case .one:
            player.repeatMode = .off
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
