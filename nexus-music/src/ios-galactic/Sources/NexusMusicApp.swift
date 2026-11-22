import SwiftUI

@main
public struct NexusMusicApp: App {
    @State private var theme = GalacticThemeManager.shared
    @State private var api = APIClient.shared
    @State private var player = AudioPlayerManager.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            Group {
                if api.isAuthenticated {
                    GalacticMainShellView()
                } else {
                    LoginView()
                }
            }
            .environment(theme)
            .environment(api)
            .environment(player)
            .preferredColorScheme(theme.isHangarLightPolarity ? .light : .dark)
        }
    }
}

public struct GalacticMainShellView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(AudioPlayerManager.self) private var player
    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Rectangle()
                        .stroke(theme.accent, lineWidth: 2)
                        .frame(width: 9, height: 9)
                        .rotationEffect(.degrees(45))
                        .shadow(color: theme.accent, radius: 5)
                    Text("NEXUS // GALACTIC")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(theme.fgPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    selectedTab = 2
                    theme.triggerScreenTransitionFX()
                } label: {
                    Text("🎵 TRACKS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .foregroundStyle(theme.accent)
                        .overlay(ChamferedRectangle(cut: 5).stroke(theme.accent, lineWidth: 1))
                }

                Button {
                    selectedTab = 3
                    theme.triggerScreenTransitionFX()
                } label: {
                    Text("⚙ CONFIG")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .foregroundStyle(theme.fgPrimary)
                        .overlay(ChamferedRectangle(cut: 5).stroke(theme.hairline, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(theme.bgElevated)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }

            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    TransmitterAndTelemetryView(onNavigateToTracks: { selectedTab = 2 })
                        .tag(0)

                    HolocronArchivesView()
                        .tag(1)

                    DownloadedTracksAndSubsonicView()
                        .tag(2)

                    CommandConfigAndFleetView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selectedTab) { _, _ in
                    theme.triggerScreenTransitionFX()
                }

                if player.currentTrack != nil {
                    GalacticMiniPlayerView()
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                sectorTabButton(index: 0, code: "01 // TRANSMIT", icon: "bolt.horizontal.fill")
                sectorTabButton(index: 1, code: "02 // HOLOCRON", icon: "square.stack.3d.up.fill")
                sectorTabButton(index: 2, code: "03 // TRACKS", icon: "music.note.list")
                sectorTabButton(index: 3, code: "04 // CONFIG", icon: "slider.horizontal.3")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(theme.bgElevated)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GalacticBackdropView(activeSector: selectedTab)
        }
        .overlay {
            TransitionFXOverlayView()
        }
    }

    private func sectorTabButton(index: Int, code: String, icon: String) -> some View {
        let isActive = selectedTab == index
        return Button {
            selectedTab = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(code)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? theme.accent : theme.fgMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .overlay(alignment: .top) {
                if isActive {
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 2)
                        .shadow(color: theme.accent, radius: 6)
                        .offset(y: -8)
                }
            }
        }
    }
}
