import SwiftUI
import Observation

public struct KyberCrystalPreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let hex: String
    public let color: Color
}

public enum TransitionFXMode: String, CaseIterable {
    case flyby = "FLYBY"
    case saber = "SABER"
    case lightning = "LIGHTNING"
}

@Observable
public final class GalacticThemeManager {
    public static let shared = GalacticThemeManager()

    public static let kyberPresets: [KyberCrystalPreset] = [
        KyberCrystalPreset(id: "red", name: "Sith Crimson", hex: "#FF1E1E", color: Color(red: 1.0, green: 0.12, blue: 0.12)),
        KyberCrystalPreset(id: "green", name: "Consular Green", hex: "#2BFF4F", color: Color(red: 0.17, green: 1.0, blue: 0.31)),
        KyberCrystalPreset(id: "teal", name: "Guardian Teal", hex: "#00FFCC", color: Color(red: 0.0, green: 1.0, blue: 0.80)),
        KyberCrystalPreset(id: "cyan", name: "Skywalker Cyan", hex: "#00E5FF", color: Color(red: 0.0, green: 0.90, blue: 1.0)),
        KyberCrystalPreset(id: "orange", name: "Cal Kestis Orange", hex: "#FF7700", color: Color(red: 1.0, green: 0.47, blue: 0.0)),
        KyberCrystalPreset(id: "gold", name: "Temple Guard Gold", hex: "#FFD000", color: Color(red: 1.0, green: 0.82, blue: 0.0)),
        KyberCrystalPreset(id: "violet", name: "Mace Windu Violet", hex: "#B829FF", color: Color(red: 0.72, green: 0.16, blue: 1.0)),
        KyberCrystalPreset(id: "white", name: "Darksaber White", hex: "#FFFFFF", color: Color.white)
    ]

    public var selectedCrystal: KyberCrystalPreset {
        didSet { UserDefaults.standard.set(selectedCrystal.id, forKey: "nexus_kyber_id") }
    }

    public var isHangarLightPolarity: Bool {
        didSet { UserDefaults.standard.set(isHangarLightPolarity, forKey: "nexus_hangar_polarity") }
    }

    public var fxMode: TransitionFXMode {
        didSet { UserDefaults.standard.set(fxMode.rawValue, forKey: "nexus_fx_mode") }
    }

    public var activeFXTriggerID: UUID? = nil

    private init() {
        let savedID = UserDefaults.standard.string(forKey: "nexus_kyber_id") ?? "teal"
        self.selectedCrystal = Self.kyberPresets.first(where: { $0.id == savedID }) ?? Self.kyberPresets[2]
        self.isHangarLightPolarity = UserDefaults.standard.bool(forKey: "nexus_hangar_polarity")
        let savedFX = UserDefaults.standard.string(forKey: "nexus_fx_mode") ?? TransitionFXMode.flyby.rawValue
        self.fxMode = TransitionFXMode(rawValue: savedFX) ?? .flyby
    }

    // MARK: - Semantic Galactic Palette

    public var accent: Color { selectedCrystal.color }
    public var bgCanvas: Color { isHangarLightPolarity ? Color(red: 0.965, green: 0.969, blue: 0.976) : Color.black }
    public var bgElevated: Color { isHangarLightPolarity ? Color.white.opacity(0.88) : Color(red: 0.04, green: 0.05, blue: 0.07).opacity(0.84) }
    public var fgPrimary: Color { isHangarLightPolarity ? Color(red: 0.02, green: 0.02, blue: 0.02) : Color.white }
    public var fgMuted: Color { isHangarLightPolarity ? Color.black.opacity(0.62) : Color.white.opacity(0.62) }
    public var hairline: Color { isHangarLightPolarity ? Color.black.opacity(0.18) : Color.white.opacity(0.16) }

    public func cycleFXMode() {
        let all = TransitionFXMode.allCases
        if let idx = all.firstIndex(of: fxMode) {
            fxMode = all[(idx + 1) % all.count]
        }
        triggerScreenTransitionFX()
    }

    public func triggerScreenTransitionFX() {
        activeFXTriggerID = UUID()
    }
}

// MARK: - Diagonal Sci-Fi Chamfered Clip Shape

public struct ChamferedRectangle: Shape {
    public var cut: CGFloat = 14

    public init(cut: CGFloat = 14) {
        self.cut = cut
    }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width - cut, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: cut))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: cut, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height - cut))
        p.closeSubpath()
        return p
    }
}
