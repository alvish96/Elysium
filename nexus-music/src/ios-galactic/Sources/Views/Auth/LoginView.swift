import SwiftUI

public struct LoginView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(APIClient.self) private var api

    @State private var username: String = "alvish"
    @State private var password: String = ""
    @State private var syncEndpoint: String = ""
    @State private var showEndpoints: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""

    public init() {}

    public var body: some View {
        ZStack {
            GalacticBackdropView(activeSector: 0)

            VStack(alignment: .leading, spacing: 20) {
                Text("[ SECURITY CLEARANCE REQUIRED ]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .tracking(2)

                Text("NEXUS //\nGALACTIC OS.")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(theme.fgPrimary)
                    .lineSpacing(-6)

                VStack(alignment: .leading, spacing: 16) {
                    TextField("CALLSIGN (e.g. alvish)", text: $username)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(theme.fgPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))

                    SecureField("ACCESS CODE", text: $password)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(theme.fgPrimary)
                        .padding(12)
                        .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))

                    DisclosureGroup("SERVER ENDPOINTS (LAN / TAILSCALE)", isExpanded: $showEndpoints) {
                        TextField("http://sync.nexus.link", text: $syncEndpoint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.fgPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                            .padding(.top, 8)
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.fgMuted)

                    if !errorMessage.isEmpty {
                        Text("[ \(errorMessage.uppercased()) ]")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                    }

                    Button {
                        performAuth()
                    } label: {
                        HStack {
                            Spacer()
                            Text(isLoading ? "VERIFYING..." : "VERIFY CLEARANCE ↵")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(theme.accent)
                        .foregroundStyle(.black)
                        .clipShape(ChamferedRectangle(cut: 10))
                    }
                    .disabled(isLoading)
                }
                .padding(24)
                .background(theme.bgElevated)
                .overlay(ChamferedRectangle(cut: 18).stroke(theme.accent, lineWidth: 1))
                .clipShape(ChamferedRectangle(cut: 18))
            }
            .padding(24)
        }
        .onAppear {
            syncEndpoint = api.syncBaseURL
        }
    }

    private func performAuth() {
        isLoading = true
        errorMessage = ""
        if !syncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            api.syncBaseURL = syncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        Task {
            do {
                try await api.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), pass: password)
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
