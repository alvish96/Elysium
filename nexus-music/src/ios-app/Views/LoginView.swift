import SwiftUI
import Observation

public struct LoginView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient

    @State private var usernameInput: String = "alvish"
    @State private var passwordInput: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    // Editable Server Endpoints for LAN vs Tailscale
    @State private var isEndpointsExpanded: Bool = false
    @State private var editSyncURL: String = ""
    @State private var editNavidromeURL: String = ""

    public init() {}

    public var body: some View {
        ZStack {
            AppCanvasBackgroundView()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Brand Hero Icon & Header
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [theme.accentEmerald, Color(hex: "#34D399")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: theme.accentEmerald.opacity(0.4), radius: 14, x: 0, y: 6)

                            Image(systemName: "music.note.house.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(Color.black)
                        }

                        Text("Nexus Music")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(theme.primaryText)

                        Text("Elysium K3s Audio Controller & OpenSubsonic Player")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Login Credentials Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("NAVIDROME CREDENTIALS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.mutedText)

                        // Username Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(theme.secondaryText)

                            HStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(theme.mutedText)

                                TextField("alvish, vikas, jhansi, or admin", text: $usernameInput)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.primaryText)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            .padding(12)
                            .background(theme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(theme.cardBorder, lineWidth: 1)
                            )
                        }

                        // Password Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(theme.secondaryText)

                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(theme.mutedText)

                                SecureField("Subsonic Password", text: $passwordInput)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.primaryText)
                            }
                            .padding(12)
                            .background(theme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(theme.cardBorder, lineWidth: 1)
                            )
                        }

                        // Error Banner
                        if let error = errorMessage {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(Color(hex: "#F43F5E"))
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: "#F43F5E"))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#F43F5E").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Submit Button
                        Button {
                            performLogin()
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.subheadline)
                                    Text("Authenticate & Connect")
                                        .font(.subheadline.weight(.bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(theme.accentEmerald)
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: theme.accentEmerald.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || usernameInput.isEmpty || passwordInput.isEmpty)
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 20, padding: nil)

                    // Expandable Server Endpoints Disclosure Group
                    DisclosureGroup(
                        isExpanded: $isEndpointsExpanded,
                        content: {
                            VStack(alignment: .leading, spacing: 12) {
                                // Presets Buttons
                                HStack(spacing: 8) {
                                    Button("Home Wi-Fi (Split-DNS)") {
                                        editSyncURL = "http://sync.nexus.link"
                                        editNavidromeURL = "http://navidrome.nexus.link"
                                    }
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(theme.pillBackground)
                                    .foregroundStyle(theme.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button("Tailscale VPN") {
                                        editSyncURL = "http://100.110.100.1:80"
                                        editNavidromeURL = "http://100.110.100.1:30545"
                                    }
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(theme.pillBackground)
                                    .foregroundStyle(theme.accentEmerald)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("SYNC ENGINE URL")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(theme.mutedText)

                                    TextField("http://sync.nexus.link", text: $editSyncURL)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(theme.primaryText)
                                        .padding(8)
                                        .background(theme.inputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NAVIDROME BASE URL")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(theme.mutedText)

                                    TextField("http://navidrome.nexus.link", text: $editNavidromeURL)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(theme.primaryText)
                                        .padding(8)
                                        .background(theme.inputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            HStack(spacing: 6) {
                                Image(systemName: "network")
                                    .font(.caption)
                                    .foregroundStyle(theme.accentEmerald)
                                Text("Configure Server Endpoints & Tailscale")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                    )
                    .padding(14)
                    .glassCard(cornerRadius: 16, padding: nil)

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
        }
        .onAppear {
            editSyncURL = apiClient.syncBaseURL
            editNavidromeURL = apiClient.navidromeBaseURL
        }
    }

    private func performLogin() {
        let trimmedUser = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !passwordInput.isEmpty else { return }

        // Apply updated endpoints if configured
        if !editSyncURL.isEmpty {
            apiClient.syncBaseURL = editSyncURL
        }
        if !editNavidromeURL.isEmpty {
            apiClient.navidromeBaseURL = editNavidromeURL
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await apiClient.login(username: trimmedUser, pass: passwordInput)
                await MainActor.run {
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
