import SwiftUI
import UIKit

public struct TransmitterAndTelemetryView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @Environment(APIClient.self) private var api
    public var onNavigateToTracks: () -> Void

    @State private var urlInput: String = ""
    @State private var visibility: String = "private"
    @State private var isTransmitting: Bool = false
    @State private var isClearingQueue: Bool = false
    @State private var feedbackMessage: String = ""

    public init(onNavigateToTracks: @escaping () -> Void) {
        self.onNavigateToTracks = onNavigateToTracks
    }

    private var detectedProtocolLabel: String {
        let text = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if text.isEmpty { return "AWAITING COORDINATES" }
        if lower.contains("youtube.com/") || lower.contains("youtu.be/") {
            let isRadioMix = lower.contains("list=rd")
            let isPlaylist = lower.contains("/playlist") || (lower.contains("list=") && !isRadioMix)
            return isPlaylist ? "YOUTUBE PLAYLIST" : "YOUTUBE TRACK"
        }
        if lower.contains("/track/") || lower.contains("spotify:track:") {
            return "SPOTIFY TRACK"
        }
        if lower.contains("spotify.link/") || lower.contains("spoti.fi/") || lower.contains("spotify.app.link/") {
            return "SPOTIFY SHORT LINK"
        }
        if lower.contains("/playlist/") || lower.contains("spotify:playlist:") || text.count == 22 {
            return "SPOTIFY PLAYLIST"
        }
        return "COORDINATES READY"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("[ SEC-01 // INGESTION ] // \(detectedProtocolLabel)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("IMPERIAL\nAUDIO ARCHIVE.")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(theme.fgPrimary)
                        .lineSpacing(-4)
                        .minimumScaleFactor(0.8)

                    Text("Direct 320kbps MP3 extraction into the Atlantis master storage pool. Paste any YouTube track, YouTube playlist, Spotify song, or Spotify playlist link below.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.fgMuted)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(theme.accent).frame(width: 3)
                        }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            TextField("PASTE YOUTUBE OR SPOTIFY URL...", text: $urlInput)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.fgPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.send)
                                .onSubmit { triggerTransmission() }

                            if !urlInput.isEmpty {
                                Button {
                                    urlInput = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(theme.fgMuted)
                                }
                            }

                            Button {
                                if let clip = UIPasteboard.general.string {
                                    urlInput = clip
                                }
                            } label: {
                                Text("PASTE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(theme.accent.opacity(0.15))
                                    .foregroundStyle(theme.accent)
                                    .overlay(Rectangle().stroke(theme.accent, lineWidth: 1))
                            }
                        }
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(theme.accent).frame(height: 1.5)
                        }

                        HStack(spacing: 10) {
                            Button {
                                visibility = "private"
                            } label: {
                                Text("🔒 PRIVATE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(visibility == "private" ? theme.accent : Color.clear)
                                    .foregroundStyle(visibility == "private" ? .black : theme.fgMuted)
                                    .overlay(ChamferedRectangle(cut: 6).stroke(theme.hairline, lineWidth: 1))
                                    .clipShape(ChamferedRectangle(cut: 6))
                            }

                            Button {
                                visibility = "public"
                            } label: {
                                Text("🌍 PUBLIC VAULT")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(visibility == "public" ? theme.accent : Color.clear)
                                    .foregroundStyle(visibility == "public" ? .black : theme.fgMuted)
                                    .overlay(ChamferedRectangle(cut: 6).stroke(theme.hairline, lineWidth: 1))
                                    .clipShape(ChamferedRectangle(cut: 6))
                            }
                            Spacer(minLength: 0)
                        }

                        if !feedbackMessage.isEmpty {
                            Text(feedbackMessage)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.accent)
                                .lineLimit(3)
                        }

                        Button {
                            triggerTransmission()
                        } label: {
                            Text(isTransmitting ? "TRANSMITTING SIGNAL..." : "IGNITE TRANSMISSION ↵")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(theme.accent)
                                .foregroundStyle(.black)
                                .clipShape(ChamferedRectangle(cut: 10))
                                .shadow(color: theme.accent.opacity(0.5), radius: 10)
                        }
                        .disabled(isTransmitting)
                    }
                    .padding(16)
                    .background(theme.bgElevated)
                    .overlay(ChamferedRectangle(cut: 16).stroke(theme.accent, lineWidth: 1))
                    .clipShape(ChamferedRectangle(cut: 16))
                }

                LightsaberDividerView(
                    leftLabel: "SECTOR 01 -> 02",
                    centerCode: "ORBITAL TELEMETRY // 320KBPS"
                )

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("[ SEC-02 // TELEMETRY MATRIX ]")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.accent)
                            Text("ORBITAL\nTELEMETRY.")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(theme.fgPrimary)
                                .lineSpacing(-4)
                        }
                        Spacer()
                        Button {
                            onNavigateToTracks()
                        } label: {
                            Text("🎵 ALL TRACKS ↗")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(theme.accent)
                                .foregroundStyle(.black)
                                .clipShape(ChamferedRectangle(cut: 6))
                        }
                    }

                    HStack(spacing: 8) {
                        telemetryCounterCard(
                            value: String(format: "%02d", api.activeStreams.count),
                            label: "ACTIVE"
                        )
                        telemetryCounterCard(
                            value: String(format: "%02d", api.pendingCount),
                            label: "QUEUED"
                        )
                        telemetryCounterCard(
                            value: String(format: "%02d", api.completedHistory.count),
                            label: "ARCHIVED"
                        )
                    }

                    // MARK: Active Transcoding Streams (Overall + Ticker + Per-Song Breakdown)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 7, height: 7)
                                .shadow(color: theme.accent, radius: 5)
                            Text("ACTIVE TRANSCODING STREAM")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.accent)
                            Spacer()
                            Text(api.activeStreams.isEmpty ? "STANDBY" : "LOCKED")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(api.activeStreams.isEmpty ? theme.fgMuted : theme.accent)
                        }

                        if api.activeStreams.isEmpty {
                            HStack {
                                Text("[ NO ACTIVE STREAMS // STANDBY ]")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.fgMuted)
                                    .lineLimit(1)
                                Spacer()
                                Text("READY")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                            .padding(14)
                            .background(theme.bgElevated)
                            .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 3) }
                            .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                        } else {
                            ForEach(api.activeStreams) { stream in
                                activeStreamCard(stream)
                            }
                        }
                    }

                    // MARK: Pending Queue with ✕ CLEAR ALL & Resolved Track Names
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("⏳ PENDING QUEUE (\(api.pendingQueue.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.fgMuted)
                            Spacer()
                            if !api.pendingQueue.isEmpty {
                                Button {
                                    isClearingQueue = true
                                    Task {
                                        _ = await api.clearAllPendingQueue()
                                        await MainActor.run { isClearingQueue = false }
                                    }
                                } label: {
                                    Text(isClearingQueue ? "CLEARING..." : "✕ CLEAR ALL")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.red.opacity(0.14))
                                        .foregroundStyle(.red)
                                        .overlay(Rectangle().stroke(Color.red.opacity(0.7), lineWidth: 1))
                                }
                                .disabled(isClearingQueue)
                            }
                        }

                        if api.pendingQueue.isEmpty {
                            Text("[ QUEUE CLEAR // 0 PENDING ]")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.fgMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(theme.bgElevated)
                                .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                        } else {
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(Array(api.pendingQueue.enumerated()), id: \.offset) { idx, item in
                                        HStack(spacing: 8) {
                                            Text("#\(String(format: "%02d", idx + 1))")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundStyle(theme.accent)
                                            Text(item.displayTitle)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(theme.fgPrimary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Spacer(minLength: 6)
                                            Button {
                                                let key = item.task_id ?? item.playlist_id ?? item.raw_id ?? "idx-\(idx)"
                                                Task { await api.cancelOrRemoveDownload(itemID: key) }
                                            } label: {
                                                Text("✕")
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .foregroundStyle(.red)
                                                    .overlay(Rectangle().stroke(Color.red, lineWidth: 1))
                                            }
                                        }
                                        .padding(11)
                                        .background(theme.bgElevated)
                                        .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }

                    // MARK: Recently Downloaded
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("✓ RECENTLY DOWNLOADED (LATEST 4)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.fgMuted)
                            Spacer()
                            Button("VIEW ALL →") { onNavigateToTracks() }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.accent)
                        }

                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(api.completedHistory.prefix(20)) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("\(item.artist != nil ? item.artist! + " — " : "")\(item.title ?? "Track")")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(theme.fgPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("[\((item.status ?? "DONE").uppercased())]")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundStyle(item.status == "completed" ? theme.accent : .red)
                                        }
                                        Text(item.file ?? "320KBPS MP3")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(theme.fgMuted)
                                            .lineLimit(1)
                                    }
                                    .padding(12)
                                    .background(theme.bgElevated)
                                    .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 3) }
                                    .overlay(Rectangle().stroke(theme.hairline, lineWidth: 1))
                                }
                            }
                        }
                        .frame(height: 250)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await api.refreshAllData()
        }
    }

    @ViewBuilder
    private func activeStreamCard(_ stream: ActiveDownloadStream) -> some View {
        let overallPct = stream.effectiveOverallPercent
        let isPlaylist = stream.isPlaylistStream
        let trackItems = stream.tracks ?? []

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPlaylist ? "PLAYLIST // \(stream.playlist_name ?? stream.title ?? "Sync")" : (stream.title ?? "Resolving stream..."))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.fgPrimary)
                        .lineLimit(1)
                    if isPlaylist {
                        let done = stream.completed_tracks ?? 0
                        let tot = stream.total_tracks ?? trackItems.count
                        Text("OVERALL: \(done) / \(tot) TRACKS • \((stream.artist ?? "SYNC").uppercased())")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.fgMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(Int(round(overallPct)))%")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)

                Button {
                    Task { await api.cancelOrRemoveDownload(itemID: stream.id) }
                } label: {
                    Text("✕ CANCEL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(.red)
                        .overlay(Rectangle().stroke(Color.red, lineWidth: 1))
                }
            }

            // Overall Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.hairline).frame(height: 7)
                    Rectangle()
                        .fill(LinearGradient(colors: [theme.accent, .white], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(overallPct / 100.0), height: 7)
                        .shadow(color: theme.accent, radius: 6)
                }
            }
            .frame(height: 7)

            // Single-Line Live Scrolling Ticker
            SingleLineScrollingTickerView(
                text: stream.effectiveLogLine,
                accent: theme.accent,
                textColor: theme.fgPrimary.opacity(0.9)
            )

            // Current Song Spotlight + Scrollable Per-Song Breakdown (Playlists)
            if isPlaylist && !trackItems.isEmpty {
                let curIdx = stream.current_index ?? 1
                let curTrack = stream.current_track ?? trackItems.first?.name ?? ""
                let curPct = max(0.0, min(100.0, stream.track_percent ?? 0.0))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("NOW [\(curIdx)/\(trackItems.count)]: \(curTrack)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.fgPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int(round(curPct)))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(theme.hairline).frame(height: 4)
                            Rectangle()
                                .fill(theme.accent)
                                .frame(width: geo.size.width * CGFloat(curPct / 100.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(9)
                .background(theme.accent.opacity(0.08))
                .overlay(Rectangle().stroke(theme.accent.opacity(0.3), lineWidth: 1))

                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(trackItems) { track in
                            playlistTrackRow(track)
                        }
                    }
                }
                .frame(maxHeight: 165)
            }

            HStack {
                Text("RATE: \(stream.speed ?? "--") // ETA: \(stream.eta ?? "--")")
                Spacer()
                Text("CMD // \((stream.owner ?? api.currentUsername).uppercased())")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(theme.fgMuted)
            .lineLimit(1)
        }
        .padding(14)
        .background(theme.bgElevated)
        .overlay(ChamferedRectangle(cut: 10).stroke(theme.accent, lineWidth: 1.5))
        .clipShape(ChamferedRectangle(cut: 10))
    }

    private func playlistTrackRow(_ track: PlaylistTrackProgress) -> some View {
        let isDownloading = track.status == "downloading"
        let isDone = track.status == "done" || track.status == "cached"
        let isFailed = track.status == "failed"

        let statusText: String = {
            switch track.status {
            case "done": return "100% ✓"
            case "cached": return "POOL ✓"
            case "failed": return "ERR ✕"
            case "downloading": return "\(Int(round(track.percent)))%"
            default: return "QUEUE"
            }
        }()

        let statusColor: Color = {
            if isFailed { return .red }
            if isDownloading || isDone { return theme.accent }
            return theme.fgMuted
        }()

        return HStack(spacing: 8) {
            Text(String(format: "%02d", track.index))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.fgMuted)
                .frame(width: 18, alignment: .leading)

            Text(track.name)
                .font(.system(size: 10.5, weight: isDownloading ? .semibold : .regular))
                .foregroundStyle(isFailed ? .red : theme.fgPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 4)
                    Capsule()
                        .fill(isFailed ? Color.red : theme.accent)
                        .frame(width: geo.size.width * CGFloat(max(0, min(100, track.percent)) / 100.0), height: 4)
                }
            }
            .frame(width: 48, height: 4)

            Text(statusText)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isDownloading ? theme.accent.opacity(0.14) : Color.white.opacity(0.03))
        .overlay(
            Rectangle().stroke(isDownloading ? theme.accent.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .opacity(isDone ? 0.8 : 1.0)
    }

    private func telemetryCounterCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.accent)
                .shadow(color: theme.accent.opacity(0.5), radius: 6)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.fgMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.bgElevated)
        .overlay(alignment: .leading) { Rectangle().fill(theme.accent).frame(width: 3) }
        .overlay(ChamferedRectangle(cut: 8).stroke(theme.hairline, lineWidth: 1))
        .clipShape(ChamferedRectangle(cut: 8))
    }

    private func triggerTransmission() {
        let target = urlInput
        guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            feedbackMessage = "[ ERROR: INPUT COORDINATES REQUIRED ]"
            return
        }
        isTransmitting = true
        feedbackMessage = "[ LOCKING HYPERDRIVE SIGNAL... ]"
        Task {
            do {
                let msg = try await api.transmitCoordinates(urlOrId: target, visibility: visibility)
                await MainActor.run {
                    feedbackMessage = "[ ✓ \(msg) ]"
                    urlInput = ""
                    isTransmitting = false
                    theme.triggerScreenTransitionFX()
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = "[ FAILED: \(error.localizedDescription.uppercased()) ]"
                    isTransmitting = false
                }
            }
        }
    }
}

private struct SingleLineScrollingTickerView: View {
    let text: String
    let accent: Color
    let textColor: Color

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offsetX: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: accent, radius: 4)
                Text("LIVE //")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }
            .fixedSize()

            GeometryReader { geo in
                let viewportW = geo.size.width
                ZStack(alignment: .leading) {
                    Text(text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            GeometryReader { tGeo in
                                Color.clear
                                    .onAppear {
                                        textWidth = tGeo.size.width
                                        restartScroll()
                                    }
                                    .onChange(of: tGeo.size.width) { _, newW in
                                        textWidth = newW
                                        restartScroll()
                                    }
                            }
                        )
                        .offset(x: offsetX)
                }
                .frame(width: viewportW, height: geo.size.height, alignment: .leading)
                .clipped()
                .onAppear {
                    containerWidth = viewportW
                    restartScroll()
                }
                .onChange(of: viewportW) { _, newW in
                    containerWidth = newW
                    restartScroll()
                }
                .onChange(of: text) { _, _ in
                    restartScroll()
                }
            }
            .frame(height: 15)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.45))
        .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func restartScroll() {
        var resetTx = Transaction()
        resetTx.disablesAnimations = true
        withTransaction(resetTx) {
            offsetX = 0
        }
        let overflow = textWidth - containerWidth
        guard overflow > 6, containerWidth > 0 else { return }
        let distance = overflow + 18
        let duration = max(3.5, Double(distance) / 36.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: true)) {
                offsetX = -distance
            }
        }
    }
}
