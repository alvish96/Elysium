import SwiftUI
import UIKit

public struct ImportPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(APIClient.self) private var apiClient

    public var onImportSuccess: ((String) -> Void)?

    @State private var inputUrlOrId: String = ""
    @State private var selectedVisibility: String = "private" // "private" or "public"
    @State private var isSubmittingOnly: Bool = false
    @State private var isSubmittingSync: Bool = false
    @State private var errorMessage: String? = nil

    public init(onImportSuccess: ((String) -> Void)? = nil) {
        self.onImportSuccess = onImportSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header Banner
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "link.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(theme.accentEmerald)

                                Text("Import Spotify Playlist")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(theme.primaryText)
                            }

                            Text("Import any public or unlisted Spotify playlist URL or 22-character ID. Works for all users with zero OAuth whitelist restrictions.")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                                .lineSpacing(3)
                        }
                        .padding(.top, 4)

                        // Input Field Card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SPOTIFY PLAYLIST URL OR ID")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.mutedText)

                            HStack(spacing: 8) {
                                Image(systemName: "music.note")
                                    .font(.caption)
                                    .foregroundStyle(theme.mutedText)

                                TextField("e.g. 37i9dQZF1DXcBWIGoYBM5M", text: $inputUrlOrId)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.primaryText)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)

                                if !inputUrlOrId.isEmpty {
                                    Button {
                                        inputUrlOrId = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(theme.mutedText)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    pasteFromClipboard()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.caption2)
                                        Text("Paste")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(theme.pillBackground)
                                    .foregroundStyle(theme.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(theme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(theme.cardBorder, lineWidth: 1.0)
                            )
                        }
                        .glassCard(cornerRadius: 16)

                        // Visibility Picker Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INITIAL VISIBILITY")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.mutedText)

                            HStack(spacing: 12) {
                                // Private Option
                                Button {
                                    selectedVisibility = "private"
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: selectedVisibility == "private" ? "checkmark.circle.fill" : "circle")
                                            .font(.subheadline)
                                            .foregroundStyle(selectedVisibility == "private" ? theme.accentEmerald : theme.mutedText)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("🔒 Private")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(theme.primaryText)

                                            Text("Only visible to your personal account")
                                                .font(.caption2)
                                                .foregroundStyle(theme.mutedText)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(selectedVisibility == "private" ? theme.accentEmeraldGlow : theme.inputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(selectedVisibility == "private" ? theme.accentEmerald : theme.cardBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)

                                // Public Option
                                Button {
                                    selectedVisibility = "public"
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: selectedVisibility == "public" ? "checkmark.circle.fill" : "circle")
                                            .font(.subheadline)
                                            .foregroundStyle(selectedVisibility == "public" ? theme.accentEmerald : theme.mutedText)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("🌍 Public")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(theme.primaryText)

                                            Text("Visible to everyone on the server")
                                                .font(.caption2)
                                                .foregroundStyle(theme.mutedText)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(selectedVisibility == "public" ? theme.accentEmeraldGlow : theme.inputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(selectedVisibility == "public" ? theme.accentEmerald : theme.cardBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .glassCard(cornerRadius: 16)

                        // Error Banner
                        if let error = errorMessage {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(Color(hex: "#F43F5E"))
                                    .font(.subheadline)

                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: "#F43F5E"))
                                    .lineSpacing(2)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#F43F5E").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(hex: "#F43F5E").opacity(0.3), lineWidth: 1)
                            )
                        }

                        // Dual Action Buttons
                        VStack(spacing: 12) {
                            // Button 1: Import & Sync
                            Button {
                                executeImport(autoSync: true)
                            } label: {
                                HStack(spacing: 8) {
                                    if isSubmittingSync {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.subheadline)
                                        Text("Import & Sync Now")
                                            .font(.subheadline.weight(.bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(theme.accentEmerald)
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: theme.accentEmerald.opacity(0.3), radius: 8, y: 3)
                            }
                            .disabled(isSubmittingSync || isSubmittingOnly || inputUrlOrId.trimmingCharacters(in: .whitespaces).isEmpty)

                            // Button 2: Import Only
                            Button {
                                executeImport(autoSync: false)
                            } label: {
                                HStack(spacing: 8) {
                                    if isSubmittingOnly {
                                        ProgressView()
                                            .tint(theme.primaryText)
                                    } else {
                                        Image(systemName: "bookmark.fill")
                                            .font(.subheadline)
                                        Text("Import Only (No Download)")
                                            .font(.subheadline.weight(.bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(theme.pillBackground)
                                .foregroundStyle(theme.primaryText)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(theme.cardBorder, lineWidth: 1)
                                Dino)
                            }
                            .disabled(isSubmittingSync || isSubmittingOnly || inputUrlOrId.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func pasteFromClipboard() {
        if let pasteboardString = UIPasteboard.general.string {
            inputUrlOrId = pasteboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func executeImport(autoSync: Bool) {
        let cleanedInput = inputUrlOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedInput.isEmpty else { return }

        errorMessage = nil
        if autoSync {
            isSubmittingSync = true
        } else {
            isSubmittingOnly = true
        }

        Task {
            do {
                let response = try await apiClient.importPlaylist(
                    urlOrId: cleanedInput,
                    visibility: selectedVisibility,
                    autoSync: autoSync
                )

                await MainActor.run {
                    isSubmittingSync = false
                    isSubmittingOnly = false
                    onImportSuccess?(response.playlist_id ?? cleanedInput)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmittingSync = false
                    isSubmittingOnly = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
