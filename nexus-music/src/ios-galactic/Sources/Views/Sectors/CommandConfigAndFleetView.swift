import SwiftUI
import UIKit

public struct CommandConfigAndFleetView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(APIClient.self) private var api
    @Environment(\.openURL) private var openURL

    @State private var syncURLField: String = ""
    @State private var navidromeURLField: String = ""
    @State private var appLaunchFeedback: String = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("[ SEC-04 // CONFIGURATION & iOS APPS ]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)

                Text("COMMAND\n& FLEET.")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(theme.fgPrimary)
                    .lineSpacing(-4)

                // =========================================================
                // NATIVE iOS SUBSONIC PLAYERS (AMPERFY & SUBSONIFY)
                // =========================================================
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("[ NATIVE iOS SUBSONIC PLAYERS ]")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.accent)
                        Spacer()
                        if !appLaunchFeedback.isEmpty {
                            Text(appLaunchFeedback)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.accent)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        nativeAppLauncherCard(
                            badge: "iOS APP // 01",
                            title: "AMPERFY",
                            subtitle: "Launch native Amperfy player",
                            icon: "Waveform.circle.fill",
                            schemes: ["amperfy://", "amperfy://x-callback-url"],
                            fallbackWebURL: "https://apps.apple.com/app/amperfy-music/id1530145038"
                        )

                        nativeAppLauncherCard(
                            badge: "iOS APP // 02",
                            title: "SUBSONIFY",
                            subtitle: "Launch SubSonify CarPlay & iOS",
                            icon: "music.quarternote.3",
                            schemes: ["subsonify://", "subsonify://open"],
                            fallbackWebURL: "https://subsonify.app"
                        )

                        nativeAppLauncherCard(
                            badge: "QUICK ACTION",
                            title: "AMPERFY SHUFFLE",
                            subtitle: "Play random songs in Amperfy",
                            icon: "shuffle",
                            schemes: ["amperfy://x-callback-url/playRandomSongs?onlyCached=0", "amperfy://"],
                            fallbackWebURL: "https://apps.apple.com/app/amperfy-music/id1530145038"
                        )

                        nativeAppLauncherCard(
                            badge: "SERVER CORE",
                            title: "NAVIDROME",
                            subtitle: "Open Subsonic server console",
                            icon: "server.rack",
                            schemes: [],
                            fallbackWebURL: api.navidromeBaseURL
                        )
                    }
                }

                // =========================================================
                // CARD 01: KYBER CRYSTAL ACCENTS, TRANSITION FX & POLARITY
                // =========================================================
                VStack(alignment: .leading, spacing: 14) {
                    Text("[ 01 // KYBER CRYSTAL & VISUAL FX ]")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)

                    Text("Select lightsaber plasma accent color, transition FX, and space vs. hangar polarity.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.fgMuted)

                    HStack(spacing: 12) {
                        ForEach(GalacticThemeManager.kyberPresets) { crystal in
                            Button {
                                theme.selectedCrystal = crystal
                                theme.triggerScreenTransitionFX()
                            } label: {
                                Rectangle()
                                    .fill(crystal.color)
                                    .frame(width: 20, height: 20)
                                    .rotationEffect(.degrees(45))
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.white, lineWidth: theme.selectedCrystal.id == crystal.id ? 2 : 1)
                                            .rotationEffect(.degrees(45))
                                    )
                                    .shadow(color: crystal.color, radius: theme.selectedCrystal.id == crystal.id ? 8 : 0)
                                    .scaleEffect(theme.selectedCrystal.id == crystal.id ? 1.2 : 1.0)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)

                    HStack(spacing: 10) {
                        Button {
                            theme.cycleFXMode()
                        } label: {
                            Text("FX // \(theme.fxMode.rawValue)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .foregroundStyle(theme.accent)
                                .overlay(ChamferedRectangle(cut: 6).stroke(theme.accent, lineWidth: 1))
                        }

                        Button {
                            theme.isHangarLightPolarity.toggle()
                        } label: {
                            Text(theme.isHangarLightPolarity ? "☀ HANGAR LANDED" : "◐ SPACE MODE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .foregroundStyle(theme.fgPrimary)
                                .overlay(ChamferedRectangle(cut: 6).stroke(theme.hairline, lineWidth: 1))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgElevated)
                .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 4) }
                .overlay(ChamferedRectangle(cut: 14).stroke(theme.hairline, lineWidth: 1))
                .clipShape(ChamferedRectangle(cut: 14))

                // =========================================================
                // CARD 02: SPOTIFY OAUTH RELAY & RESTORE HIDDEN PLAYLISTS
                // =========================================================
                VStack(alignment: .leading, spacing: 12) {
                    Text("[ 02 // SPOTIFY OAUTH RELAY ]")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)

                    Text(api.spotifyStatus.connected
                         ? "CONNECTED // ID: \(api.spotifyStatus.spotify_id ?? "ACTIVE")"
                         : "NOT LINKED // CONNECT OAUTH")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(api.spotifyStatus.connected ? theme.accent : theme.fgPrimary)
                        .lineLimit(1)

                    VStack(spacing: 8) {
                        Button {
                            Task {
                                if let url = await api.fetchSpotifyOAuthURL() {
                                    openURL(url)
                                }
                            }
                        } label: {
                            Text("🔗 CONNECT / SWITCH SPOTIFY ACCOUNT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(theme.accent)
                                .overlay(ChamferedRectangle(cut: 6).stroke(theme.accent, lineWidth: 1))
                        }

                        HStack(spacing: 8) {
                            if api.spotifyStatus.connected {
                                Button {
                                    Task { await api.disconnectSpotify() }
                                } label: {
                                    Text("✕ UNLINK SPOTIFY")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .foregroundStyle(.red)
                                        .overlay(ChamferedRectangle(cut: 6).stroke(Color.red, lineWidth: 1))
                                }
                            }

                            Button {
                                Task { await api.restoreHiddenPlaylists() }
                            } label: {
                                Text("↺ RESTORE HIDDEN")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(theme.fgPrimary)
                                    .overlay(ChamferedRectangle(cut: 6).stroke(theme.hairline, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgElevated)
                .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 4) }
                .overlay(ChamferedRectangle(cut: 14).stroke(theme.hairline, lineWidth: 1))
                .clipShape(ChamferedRectangle(cut: 14))

                // =========================================================
                // CARD 03: COMMANDER SESSION & TAILSCALE / LAN ENDPOINTS
                // =========================================================
                VStack(alignment: .leading, spacing: 12) {
                    Text("[ 03 // COMMANDER SESSION & ENDPOINTS ]")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)

                    Text("ACTIVE CALLSIGN: CMD // \(api.currentUsername.uppercased())")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.fgPrimary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SYNC API URL (LAN OR TAILSCALE):")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.fgMuted)
                        TextField("http://sync.nexus.link", text: $syncURLField)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.fgPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))

                        Text("NAVIDROME SUBSONIC URL:")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.fgMuted)
                        TextField("http://navidrome.nexus.link", text: $navidromeURLField)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.fgPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                    }

                    HStack(spacing: 10) {
                        Button {
                            api.syncBaseURL = syncURLField
                            api.navidromeBaseURL = navidromeURLField
                            Task { await api.refreshAllData() }
                        } label: {
                            Text("SAVE ENDPOINTS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(theme.accent)
                                .foregroundStyle(.black)
                                .clipShape(ChamferedRectangle(cut: 6))
                        }

                        Button {
                            api.logout()
                        } label: {
                            Text("🚪 LOGOUT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .foregroundStyle(.red)
                                .overlay(ChamferedRectangle(cut: 6).stroke(Color.red, lineWidth: 1))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgElevated)
                .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 4) }
                .overlay(ChamferedRectangle(cut: 14).stroke(theme.hairline, lineWidth: 1))
                .clipShape(ChamferedRectangle(cut: 14))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            syncURLField = api.syncBaseURL
            navidromeURLField = api.navidromeBaseURL
        }
    }

    private func nativeAppLauncherCard(
        badge: String,
        title: String,
        subtitle: String,
        icon: String,
        schemes: [String],
        fallbackWebURL: String
    ) -> some View {
        Button {
            launchNativeAppOrFallback(title: title, schemes: schemes, fallbackWebURL: fallbackWebURL)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accent)
                }
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.fgPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.fgMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(theme.bgElevated)
            .overlay(alignment: .top) { Rectangle().fill(theme.accent).frame(height: 2.5) }
            .overlay(ChamferedRectangle(cut: 10).stroke(theme.hairline, lineWidth: 1))
            .clipShape(ChamferedRectangle(cut: 10))
        }
    }

    private func launchNativeAppOrFallback(title: String, schemes: [String], fallbackWebURL: String) {
        func tryScheme(index: Int) {
            if index >= schemes.count {
                if let webURL = URL(string: fallbackWebURL) {
                    appLaunchFeedback = "OPENING \(title)..."
                    openURL(webURL)
                }
                return
            }
            guard let url = URL(string: schemes[index]) else {
                tryScheme(index: index + 1)
                return
            }
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    appLaunchFeedback = "LAUNCHED \(title)"
                } else {
                    tryScheme(index: index + 1)
                }
            }
        }
        tryScheme(index: 0)
    }
}
