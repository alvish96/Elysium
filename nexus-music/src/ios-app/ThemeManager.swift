import SwiftUI
import Observation
import PhotosUI
import UIKit

// MARK: - Canvas Background Presets

public struct CanvasPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let hex: String
    public let isLight: Bool

    public init(id: String, name: String, hex: String, isLight: Bool = false) {
        self.id = id
        self.name = name
        self.hex = hex
        self.isLight = isLight
    }

    public static let allPresets: [CanvasPreset] = [
        CanvasPreset(id: "dark_slate", name: "Dark Slate", hex: "#0F172A", isLight: false),
        CanvasPreset(id: "oled_black", name: "OLED Black", hex: "#000000", isLight: false),
        CanvasPreset(id: "midnight", name: "Midnight", hex: "#081026", isLight: false),
        CanvasPreset(id: "emerald", name: "Emerald", hex: "#041F18", isLight: false),
        CanvasPreset(id: "amethyst", name: "Amethyst", hex: "#1E1028", isLight: false),
        CanvasPreset(id: "crimson", name: "Crimson", hex: "#240C12", isLight: false),
        CanvasPreset(id: "cyan_deep", name: "Cyan Deep", hex: "#051B2C", isLight: false),
        CanvasPreset(id: "rose_quartz", name: "Rose Quartz", hex: "#23121D", isLight: false),
        CanvasPreset(id: "cloud_white", name: "Cloud White", hex: "#F8FAFC", isLight: true),
        CanvasPreset(id: "alabaster", name: "Alabaster", hex: "#FDFBF7", isLight: true),
        CanvasPreset(id: "soft_sage", name: "Soft Sage", hex: "#F1F5F3", isLight: true),
        CanvasPreset(id: "lavender", name: "Lavender", hex: "#F7F3F9", isLight: true)
    ]

    public static var defaultDark: CanvasPreset { allPresets[0] }
    public static var defaultLight: CanvasPreset { allPresets[8] }
}

public enum WallpaperSourceType: String, Codable, Sendable {
    case preset
    case remoteURL
    case localPhoto
}

// MARK: - Theme Manager Observable

@Observable
public final class ThemeManager: @unchecked Sendable {
    public static let shared = ThemeManager()

    private enum StorageKeys {
        static let isLightMode = "nexus_music_is_light_mode"
        static let activePresetId = "nexus_music_active_preset_id"
        static let wallpaperSource = "nexus_music_wallpaper_source"
        static let remoteWallpaperURL = "nexus_music_remote_wallpaper_url"
    }

    // MARK: - Observable States

    public var isLightMode: Bool {
        didSet {
            UserDefaults.standard.set(isLightMode, forKey: StorageKeys.isLightMode)
            updatePresetForModeTransition()
        }
    }

    public var activePreset: CanvasPreset {
        didSet {
            UserDefaults.standard.set(activePreset.id, forKey: StorageKeys.activePresetId)
        }
    }

    public var wallpaperSource: WallpaperSourceType {
        didSet {
            UserDefaults.standard.set(wallpaperSource.rawValue, forKey: StorageKeys.wallpaperSource)
        }
    }

    public var remoteWallpaperURLString: String {
        didSet {
            UserDefaults.standard.set(remoteWallpaperURLString, forKey: StorageKeys.remoteWallpaperURL)
        }
    }

    public var localWallpaperImage: UIImage?

    // MARK: - File Paths

    private var localWallpaperFileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("custom_wallpaper.jpg")
    }

    // MARK: - Initialization

    private init() {
        let savedLightMode = UserDefaults.standard.bool(forKey: StorageKeys.isLightMode)
        self.isLightMode = savedLightMode

        let savedPresetId = UserDefaults.standard.string(forKey: StorageKeys.activePresetId)
        if let found = CanvasPreset.allPresets.first(where: { $0.id == savedPresetId }) {
            self.activePreset = found
        } else {
            self.activePreset = savedLightMode ? CanvasPreset.defaultLight : CanvasPreset.defaultDark
        }

        let rawSource = UserDefaults.standard.string(forKey: StorageKeys.wallpaperSource) ?? WallpaperSourceType.preset.rawValue
        self.wallpaperSource = WallpaperSourceType(rawValue: rawSource) ?? .preset
        self.remoteWallpaperURLString = UserDefaults.standard.string(forKey: StorageKeys.remoteWallpaperURL) ?? ""

        loadLocalWallpaperFromDisk()
    }

    // MARK: - High-Contrast Semantic Colors

    public var primaryText: Color {
        isLightMode ? Color(hex: "#0F172A") : Color(hex: "#F8FAFC")
    }

    public var secondaryText: Color {
        isLightMode ? Color(hex: "#475569") : Color(hex: "#94A3B8")
    }

    public var mutedText: Color {
        isLightMode ? Color(hex: "#64748B") : Color(hex: "#64748B")
    }

    public var cardBackground: Color {
        if isLightMode {
            return Color(hex: "#FFFFFF").opacity(0.90)
        } else {
            return Color(hex: "#141B2D").opacity(0.78)
        }
    }

    public var cardBorder: Color {
        if isLightMode {
            return Color(hex: "#CBD5E1").opacity(0.85)
        } else {
            return Color.white.opacity(0.09)
        }
    }

    public var sidebarBackground: Color {
        if isLightMode {
            return Color.white.opacity(0.96)
        } else {
            return Color(hex: "#0D1321").opacity(0.92)
        }
    }

    public var inputBackground: Color {
        if isLightMode {
            return Color(hex: "#F1F5F9").opacity(0.95)
        } else {
            return Color(hex: "#0B0F19").opacity(0.85)
        }
    }

    public var pillBackground: Color {
        if isLightMode {
            return Color(hex: "#E2E8F0").opacity(0.95)
        } else {
            return Color(hex: "#0F172A").opacity(0.95)
        }
    }

    public var accentEmerald: Color {
        isLightMode ? Color(hex: "#059669") : Color(hex: "#10B981")
    }

    public var accentEmeraldGlow: Color {
        isLightMode ? Color(hex: "#059669").opacity(0.20) : Color(hex: "#10B981").opacity(0.25)
    }

    public var canvasColor: Color {
        Color(hex: activePreset.hex)
    }

    // MARK: - Background Customizer Methods

    public func setPreset(_ preset: CanvasPreset) {
        self.activePreset = preset
        self.wallpaperSource = .preset
        if preset.isLight && !isLightMode {
            self.isLightMode = true
        } else if !preset.isLight && isLightMode {
            self.isLightMode = false
        }
    }

    public func setRemoteWallpaper(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.remoteWallpaperURLString = trimmed
        self.wallpaperSource = .remoteURL
    }

    public func setLocalWallpaper(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: localWallpaperFileURL, options: .atomic)
            self.localWallpaperImage = image
            self.wallpaperSource = .localPhoto
        } catch {
            print("Failed to save wallpaper image: \(error.localizedDescription)")
        }
    }

    public func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.setLocalWallpaper(image: image)
                }
            }
        } catch {
            print("Failed to load photo picker item: \(error.localizedDescription)")
        }
    }

    public func resetBackground() {
        try? FileManager.default.removeItem(at: localWallpaperFileURL)
        self.localWallpaperImage = nil
        self.remoteWallpaperURLString = ""
        self.wallpaperSource = .preset
        self.activePreset = isLightMode ? CanvasPreset.defaultLight : CanvasPreset.defaultDark
        UserDefaults.standard.removeObject(forKey: StorageKeys.remoteWallpaperURL)
    }

    private func loadLocalWallpaperFromDisk() {
        if FileManager.default.fileExists(atPath: localWallpaperFileURL.path) {
            if let data = try? Data(contentsOf: localWallpaperFileURL),
               let image = UIImage(data: data) {
                self.localWallpaperImage = image
            }
        }
    }

    private func updatePresetForModeTransition() {
        if isLightMode && !activePreset.isLight {
            self.activePreset = CanvasPreset.defaultLight
        } else if !isLightMode && activePreset.isLight {
            self.activePreset = CanvasPreset.defaultDark
        }
    }
}

// MARK: - Color Hex Initializer

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 11, 15, 25)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

// MARK: - Reusable Glass Card Modifier

public struct GlassCardModifier: ViewModifier {
    @Environment(ThemeManager.self) private var theme
    public var cornerRadius: CGFloat
    public var paddingAmount: CGFloat?

    public init(cornerRadius: CGFloat = 16, paddingAmount: CGFloat? = 14) {
        self.cornerRadius = cornerRadius
        self.paddingAmount = paddingAmount
    }

    public func body(content: Content) -> some View {
        content
            .ifLet(paddingAmount) { view, padding in
                view.padding(padding)
            }
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(theme.cardBackground)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(theme.isLightMode ? 0.35 : 0.20))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: 1.0)
            }
            .shadow(color: Color.black.opacity(theme.isLightMode ? 0.05 : 0.25), radius: 10, x: 0, y: 4)
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = 16, padding: CGFloat? = 14) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, paddingAmount: padding))
    }

    @ViewBuilder
    func ifLet<V, Transform: View>(_ value: V?, transform: (Self, V) -> Transform) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - App Canvas Background View

public struct AppCanvasBackgroundView: View {
    @Environment(ThemeManager.self) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            switch theme.wallpaperSource {
            case .preset:
                theme.canvasColor
                    .ignoresSafeArea()

            case .remoteURL:
                if let url = URL(string: theme.remoteWallpaperURLString), !theme.remoteWallpaperURLString.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .ignoresSafeArea()
                        case .failure, .empty:
                            theme.canvasColor
                                .ignoresSafeArea()
                        @unknown default:
                            theme.canvasColor
                                .ignoresSafeArea()
                        }
                    }
                } else {
                    theme.canvasColor
                        .ignoresSafeArea()
                }

            case .localPhoto:
                if let image = theme.localWallpaperImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                } else {
                    theme.canvasColor
                        .ignoresSafeArea()
                }
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(theme.wallpaperSource == .preset ? 0.08 : (theme.isLightMode ? 0.65 : 0.55))
                .ignoresSafeArea()

            Rectangle()
                .fill(theme.isLightMode ? Color.white.opacity(0.15) : Color.black.opacity(0.25))
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.35), value: theme.activePreset)
        .animation(.easeInOut(duration: 0.35), value: theme.wallpaperSource)
        .animation(.easeInOut(duration: 0.35), value: theme.isLightMode)
    }
}
