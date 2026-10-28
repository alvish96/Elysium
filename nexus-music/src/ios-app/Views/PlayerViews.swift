import SwiftUI

struct MiniPlayerView: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var showFullModal = false

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 0.12, green: 0.16, blue: 0.26))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 50)
            .onTapGesture {
                showFullModal = true
            }
            .sheet(isPresented: $showFullModal) {
                FullPlayerView()
            }
        }
    }
}

struct FullPlayerView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(APIClient.self) private var apiClient

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.09, blue: 0.16).ignoresSafeArea()

            VStack(spacing: 28) {
                Capsule()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top)

                Spacer()

                // Album Artwork
                AsyncImage(url: apiClient.getCoverArtURL(coverId: player.currentTrack?.coverArt)) { img in
                    img.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 20)

                // Track Metadata
                VStack(spacing: 6) {
                    Text(player.currentTrack?.title ?? "Unknown Title")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(player.currentTrack?.artist ?? "Unknown Artist")
                        .font(.headline)
                        .foregroundStyle(.gray)
                }

                // Scrubber
                Slider(value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ), in: 0...max(player.duration, 1.0))
                .tint(.emerald)
                .padding(.horizontal)

                // Controls
                HStack(spacing: 50) {
                    Button {} label: {
                        Image(systemName: "backward.fill").font(.title)
                    }
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    Button {} label: {
                        Image(systemName: "forward.fill").font(.title)
                    }
                }
                .foregroundStyle(.white)

                Spacer()
            }
            .padding()
        }
    }
}
