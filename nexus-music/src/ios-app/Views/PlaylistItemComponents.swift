import SwiftUI

// MARK: - Column Visibility Configuration for Table Views

public struct TableColumnConfig: Sendable, Equatable {
    public var showCover: Bool
    public var showOwner: Bool
    public var showTracks: Bool
    public var showStatus: Bool
    public var showVisibility: Bool
    public var showSlug: Bool
    public var showActions: Bool

    public init(
        showCover: Bool = true,
        showOwner: Bool = true,
        showTracks: Bool = true,
        showStatus: Bool = true,
        showVisibility: Bool = true,
        showSlug: Bool = true,
        showActions: Bool = true
    ) {
        self.showCover = showCover
        self.showOwner = showOwner
        self.showTracks = showTracks
        self.showStatus = showStatus
        self.showVisibility = showVisibility
        self.showSlug = showSlug
        self.showActions = showActions
    }

    public static let `default` = TableColumnConfig()
}

// MARK: - Status Badge View

public struct SyncStatusBadgeView: View {
    public let status: String
    @Environment(ThemeManager.self) private var theme

    @State private var isSpinning: Bool = false

    public init(status: String) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 5) {
            switch status.lowercased() {
            case "syncing":
                Circle()
                    .fill(Color(hex: "#F59E0B"))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isSpinning ? 1.25 : 0.8)
                    .opacity(isSpinning ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isSpinning)
                    .onAppear { isSpinning = true }

                Text("Syncing")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: "#F59E0B"))

            case "completed":
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.accentEmerald)

                Text("Synced")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.accentEmerald)

            case "queued":
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "#3B82F6"))

                Text("Queued")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: "#3B82F6"))

            case "failed":
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "#F43F5E"))

                Text("Failed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: "#F43F5E"))

            default:
                Circle()
                    .fill(theme.mutedText)
                    .frame(width: 6, height: 6)

                Text("Idle")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.mutedText)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(theme.pillBackground.opacity(0.8))
        .clipShape(Capsule())
    }
}

// MARK: - Playlist Grid Card View

public struct PlaylistGridCardView: View {
    public let playlist: PlaylistItem
    public var showDeleteButton: Bool = false

    public var onToggleSync: ((Bool) -> Void)?
    public var onChangeVisibility: ((String) -> Void)?
    public var onSyncNow: (() -> Void)?
    public var onDelete: (() -> Void)?
    public var onTapCard: (() -> Void)?

    @Environment(ThemeManager.self) private var theme
    @State private var isSyncingTriggered: Bool = false

    public init(
        playlist: PlaylistItem,
        showDeleteButton: Bool = false,
        onToggleSync: ((Bool) -> Void)? = nil,
        onChangeVisibility: ((String) -> Void)? = nil,
        onSyncNow: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onTapCard: (() -> Void)? = nil
    ) {
        self.playlist = playlist
        self.showDeleteButton = showDeleteButton
        self.onToggleSync = onToggleSync
        self.onChangeVisibility = onChangeVisibility
        self.onSyncNow = onSyncNow
        self.onDelete = onDelete
        self.onTapCard = onTapCard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Cover Art + Info + Delete Button
            HStack(alignment: .top, spacing: 12) {
                // Cover Art
                AsyncImage(url: URL(string: playlist.cover_url ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        ZStack {
                            Rectangle().fill(theme.cardBorder.opacity(0.3))
                            Image(systemName: "music.note.list")
                                .font(.title3)
                                .foregroundStyle(theme.mutedText)
                        }
                    @unknown default:
                        Rectangle().fill(theme.cardBorder.opacity(0.3))
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                )

                // Info Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(playlist.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Spacer()

                        if showDeleteButton {
                            Button {
                                onDelete?()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: "#F43F5E").opacity(0.85))
                                    .padding(6)
                                    .background(theme.pillBackground)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Folder Slug
                    Text("/playlists/\(playlist.effectiveFolderSlug)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentEmerald)
                        .lineLimit(1)

                    // Badges: Owner + Visibility
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 10))
                            Text(playlist.effectiveOwner)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.pillBackground)
                        .clipShape(Capsule())

                        HStack(spacing: 3) {
                            Image(systemName: playlist.isPublic ? "globe" : "lock.fill")
                                .font(.system(size: 9))
                            Text(playlist.isPublic ? "Public" : "Private")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(playlist.isPublic ? theme.accentEmerald : theme.mutedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(playlist.isPublic ? theme.accentEmeraldGlow : theme.pillBackground)
                        .clipShape(Capsule())
                    }
                }
            }

            // Live Progress Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SyncStatusBadgeView(status: playlist.effectiveStatus)

                    Spacer()

                    let pct = Int(playlist.progressFraction * 100.0)
                    Text("\(playlist.effectiveDownloadedTracks)/\(playlist.effectiveTotalTracks) (\(pct)%)")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.inputBackground)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [theme.accentEmerald, Color(hex: "#34D399")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * CGFloat(playlist.progressFraction)), height: 6)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: playlist.progressFraction)
                    }
                }
                .frame(height: 6)
            }
            .padding(9)
            .background(theme.inputBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()
                .background(theme.cardBorder)

            // Bottom Action Controls
            HStack(spacing: 8) {
                // Sync Toggle
                Toggle(isOn: Binding(
                    get: { playlist.isSyncedBool },
                    set: { onToggleSync?($0) }
                )) {
                    Text("Sync")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(playlist.isSyncedBool ? theme.primaryText : theme.mutedText)
                }
                .toggleStyle(SwitchToggleStyle(tint: theme.accentEmerald))
                .labelsHidden()

                Text("Sync")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(playlist.isSyncedBool ? theme.primaryText : theme.mutedText)

                Spacer()

                // Visibility Selector Pill
                HStack(spacing: 0) {
                    Button {
                        onChangeVisibility?("private")
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text("Private")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(!playlist.isPublic ? theme.cardBackground : Color.clear)
                        .foregroundStyle(!playlist.isPublic ? theme.primaryText : theme.mutedText)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onChangeVisibility?("public")
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                                .font(.system(size: 9))
                            Text("Public")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(playlist.isPublic ? theme.accentEmerald : Color.clear)
                        .foregroundStyle(playlist.isPublic ? Color.white : theme.mutedText)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(theme.pillBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Force Sync Now Bolt Button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isSyncingTriggered = true
                    }
                    onSyncNow?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isSyncingTriggered = false
                    }
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(playlist.isSyncedBool ? Color(hex: "#F59E0B") : theme.mutedText.opacity(0.4))
                        .rotationEffect(.degrees(isSyncingTriggered ? 360 : 0))
                        .padding(7)
                        .background(theme.pillBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!playlist.isSyncedBool)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18, padding: nil)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapCard?()
        }
    }
}

// MARK: - Playlist Table Row View

public struct PlaylistTableRowView: View {
    public let playlist: PlaylistItem
    public var columns: TableColumnConfig = .default
    public var showDeleteButton: Bool = false

    public var onToggleSync: ((Bool) -> Void)?
    public var onChangeVisibility: ((String) -> Void)?
    public var onSyncNow: (() -> Void)?
    public var onDelete: (() -> Void)?
    public var onTapRow: (() -> Void)?

    @Environment(ThemeManager.self) private var theme
    @State private var isSyncingTriggered: Bool = false

    public init(
        playlist: PlaylistItem,
        columns: TableColumnConfig = .default,
        showDeleteButton: Bool = false,
        onToggleSync: ((Bool) -> Void)? = nil,
        onChangeVisibility: ((String) -> Void)? = nil,
        onSyncNow: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onTapRow: (() -> Void)? = nil
    ) {
        self.playlist = playlist
        self.columns = columns
        self.showDeleteButton = showDeleteButton
        self.onToggleSync = onToggleSync
        self.onChangeVisibility = onChangeVisibility
        self.onSyncNow = onSyncNow
        self.onDelete = onDelete
        self.onTapRow = onTapRow
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Cover Column
            if columns.showCover {
                AsyncImage(url: URL(string: playlist.cover_url ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        ZStack {
                            Rectangle().fill(theme.cardBorder.opacity(0.3))
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundStyle(theme.mutedText)
                        }
                    @unknown default:
                        Rectangle().fill(theme.cardBorder.opacity(0.3))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: 0.8)
                )
            }

            // Title & Path
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                if columns.showSlug {
                    Text(playlist.effectiveFolderSlug)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentEmerald)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 110, alignment: .leading)

            Spacer()

            // Owner Column
            if columns.showOwner {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                    Text(playlist.effectiveOwner)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.pillBackground)
                .clipShape(Capsule())
                .frame(width: 80, alignment: .center)
            }

            // Track Count Column
            if columns.showTracks {
                Text("\(playlist.effectiveTotalTracks) tracks")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 65, alignment: .trailing)
            }

            // Status & Progress Mini Column
            if columns.showStatus {
                VStack(alignment: .trailing, spacing: 2) {
                    SyncStatusBadgeView(status: playlist.effectiveStatus)

                    let pct = Int(playlist.progressFraction * 100.0)
                    Text("\(playlist.effectiveDownloadedTracks)/\(playlist.effectiveTotalTracks) (\(pct)%)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.mutedText)
                }
                .frame(width: 100, alignment: .trailing)
            }

            // Visibility Column
            if columns.showVisibility {
                HStack(spacing: 0) {
                    Button {
                        onChangeVisibility?("private")
                    } label: {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(!playlist.isPublic ? theme.cardBackground : Color.clear)
                            .foregroundStyle(!playlist.isPublic ? theme.primaryText : theme.mutedText)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onChangeVisibility?("public")
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(playlist.isPublic ? theme.accentEmerald : Color.clear)
                            .foregroundStyle(playlist.isPublic ? Color.white : theme.mutedText)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(1.5)
                .background(theme.pillBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Action Buttons: Sync Toggle + Bolt + Delete
            if columns.showActions {
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { playlist.isSyncedBool },
                        set: { onToggleSync?($0) }
                    )) {
                        EmptyView()
                    }
                    .toggleStyle(SwitchToggleStyle(tint: theme.accentEmerald))
                    .labelsHidden()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isSyncingTriggered = true
                        }
                        onSyncNow?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            isSyncingTriggered = false
                        }
                    } label: {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(playlist.isSyncedBool ? Color(hex: "#F59E0B") : theme.mutedText.opacity(0.4))
                            .rotationEffect(.degrees(isSyncingTriggered ? 360 : 0))
                            .padding(6)
                            .background(theme.pillBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!playlist.isSyncedBool)

                    if showDeleteButton {
                        Button {
                            onDelete?()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#F43F5E"))
                                .padding(6)
                                .background(theme.pillBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 12, padding: nil)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapRow?()
        }
    }
}
