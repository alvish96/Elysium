import SwiftUI

struct LoginView: View {
    @Environment(APIClient.self) private var apiClient

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.09, blue: 0.16).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo Header
                VStack(spacing: 12) {
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.linearGradient(colors: [.emerald, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))

                    Text("Nexus Music")
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    Text("Sign in with your Navidrome credentials")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }

                // Inputs
                VStack(spacing: 16) {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(red: 0.1, green: 0.14, blue: 0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)

                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(red: 0.1, green: 0.14, blue: 0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.rose)
                }

                // Login Button
                Button {
                    Task {
                        isLoading = true
                        errorMessage = nil
                        do {
                            try await apiClient.login(username: username, pass: password)
                        } catch {
                            errorMessage = "Invalid credentials or server offline"
                        }
                        isLoading = false
                    }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text("Authenticate & Connect")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.emerald)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoading || username.isEmpty || password.isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
    }
}

extension Color {
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let rose = Color(red: 244/255, green: 63/255, blue: 94/255)
}
