import SwiftUI
import AVKit

// MARK: - Floating Galactic MiniPlayer & Full-Screen Now Playing Sheet

public struct GalacticMiniPlayerView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(AudioPlayerManager.self) private var player
    @State private var showFullPlayer: Bool = false
    @State private var dragOffsetY: CGFloat = 0

    public init() {}

    public var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: theme.accent, radius: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.fgPrimary)
                            .lineLimit(1)
                        Text(track.artist ?? "Atlantis Master Pool")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture { showFullPlayer = true }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    player.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.fgPrimary)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        player.stopAndClose()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.fgMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Player")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.bgElevated)
            .overlay(alignment: .top) { Rectangle().fill(theme.accent).frame(height: 2) }
            .overlay(ChamferedRectangle(cut: 10).stroke(theme.hairline, lineWidth: 1))
            .clipShape(ChamferedRectangle(cut: 10))
            .padding(.horizontal, 12)
            .offset(y: max(0, dragOffsetY))
            .opacity(max(0.25, 1.0 - Double(max(0, dragOffsetY)) / 120.0))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffsetY = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 48 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                player.stopAndClose()
                                dragOffsetY = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                dragOffsetY = 0
                            }
                        }
                    }
            )
            .sheet(isPresented: $showFullPlayer) {
                GalacticFullPlayerSheet()
            }
        }
    }
}

public struct GalacticFullPlayerSheet: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        ZStack {
            GalacticBackdropView(activeSector: 1)

            VStack(spacing: 28) {
                HStack(spacing: 12) {
                    Text("[ IMPERIAL AUDIO DECK // 320KBPS ]")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        player.stopAndClose()
                        dismiss()
                    } label: {
                        Text("■ STOP")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                    }

                    Button("▾ HIDE") { dismiss() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.fgMuted)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .frame(width: 220, height: 220)
                    Circle()
                        .stroke(theme.fgPrimary, lineWidth: 1.5)
                        .frame(width: 180, height: 180)
                    Image(systemName: "waveform")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .shadow(color: theme.accent, radius: 14)
                }

                VStack(spacing: 6) {
                    Text(player.currentTrack?.title ?? "NO SIGNAL")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.fgPrimary)
                        .multilineTextAlignment(.center)
                    Text((player.currentTrack?.artist ?? "ATLANTIS ARCHIVE").uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }

                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(1, player.duration)
                    )
                    .tint(theme.accent)

                    HStack {
                        Text(formatTime(player.currentTime))
                        Spacer()
                        Text(formatTime(player.duration))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.fgMuted)
                }

                HStack(spacing: 42) {
                    Button { player.previousTrack() } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(theme.fgPrimary)
                    }

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(theme.accent)
                            .shadow(color: theme.accent.opacity(0.6), radius: 14)
                    }

                    Button { player.nextTrack() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(theme.fgPrimary)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private func formatTime(_ sec: Double) -> String {
        guard sec.isFinite, sec > 0 else { return "00:00" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
