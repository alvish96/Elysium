import SwiftUI
import UIKit

public struct GalacticBackdropView: View {
    @Environment(GalacticThemeManager.self) private var theme
    public let activeSector: Int

    public init(activeSector: Int) {
        self.activeSector = activeSector
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.bgCanvas

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.accent.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 220
                        )
                    )
                    .frame(width: 320, height: 320)
                    .offset(x: geo.size.width * 0.25, y: -geo.size.height * 0.22)
                    .blur(radius: 28)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        for i in 0..<65 {
                            let seed = Double(i * 97)
                            let x = (seed * 37.0).truncatingRemainder(dividingBy: max(1, size.width))
                            let y = ((seed * 73.0) + t * (4.0 + Double(i % 4))).truncatingRemainder(dividingBy: max(1, size.height))
                            let alpha = 0.25 + 0.55 * abs(sin(t * 0.8 + seed))
                            let radius = CGFloat(0.8 + Double(i % 3) * 0.5)
                            let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(theme.isHangarLightPolarity ? .black.opacity(alpha * 0.3) : .white.opacity(alpha))
                            )
                        }
                    }
                }

                if !theme.isHangarLightPolarity {
                    ZStack {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white, theme.accent, .white, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 76, height: 1.5)
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white, theme.accent, .white, .clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 1.5, height: 76)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: theme.accent, radius: 12)
                    }
                    .position(x: geo.size.width * 0.82, y: 95)
                }

                sectorVectorArt(in: geo.size)
                    .opacity(theme.isHangarLightPolarity ? 0.14 : 0.16)
                    .animation(.easeInOut(duration: 0.6), value: activeSector)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sectorVectorArt(in size: CGSize) -> some View {
        let d = min(size.width * 0.72, 260.0)
        switch activeSector {
        case 1:
            ZStack {
                Circle()
                    .stroke(theme.fgPrimary, lineWidth: 1.8)
                    .frame(width: d, height: d)
                Circle()
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 1, dash: [6, 8]))
                    .frame(width: d + 18, height: d + 18)
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: d, height: 2)
                Circle()
                    .stroke(theme.accent, lineWidth: 2)
                    .frame(width: d * 0.28, height: d * 0.28)
                    .offset(x: -d * 0.15, y: -d * 0.18)
            }
        case 2:
            ZStack {
                Circle()
                    .stroke(theme.fgPrimary, lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                Ellipse()
                    .stroke(theme.accent, lineWidth: 1.8)
                    .frame(width: 240, height: 42)
                    .rotationEffect(.degrees(-18))
            }
        default:
            ZStack {
                Ellipse()
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [10, 6]))
                    .frame(width: min(size.width * 0.8, 280), height: 70)
                    .offset(y: 130)
            }
        }
    }
}

public struct LightsaberDividerView: View {
    @Environment(GalacticThemeManager.self) private var theme
    public let leftLabel: String
    public let centerCode: String
    @State private var isIgnited: Bool = false

    public init(leftLabel: String, centerCode: String) {
        self.leftLabel = leftLabel
        self.centerCode = centerCode
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(leftLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.fgMuted)
                    .lineLimit(1)
                Spacer()
                Text(centerCode)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .shadow(color: theme.accent, radius: 6)
                    .lineLimit(1)
            }

            GeometryReader { geo in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.gray.opacity(0.5), .white.opacity(0.8), .black, .gray], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 40, height: 8)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(theme.accent).frame(width: 3, height: 10)
                        }

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.hairline)
                            .frame(height: 4)

                        Capsule()
                            .fill(Color.white)
                            .frame(width: isIgnited ? max(16, geo.size.width - 40) : 14, height: 4)
                            .shadow(color: theme.accent, radius: 6)
                            .shadow(color: theme.accent, radius: 12)
                            .opacity(isIgnited ? 1.0 : 0.45)
                            .animation(.spring(response: 0.75, dampingFraction: 0.82), value: isIgnited)
                    }
                }
            }
            .frame(height: 12)
        }
        .padding(.vertical, 10)
        .onAppear { isIgnited = true }
        .onDisappear { isIgnited = false }
    }
}

public struct TransitionFXOverlayView: View {
    @Environment(GalacticThemeManager.self) private var theme
    @State private var animateFX: Bool = false

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if animateFX {
                    switch theme.fxMode {
                    case .flyby:
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(theme.accent)
                                .frame(width: 90, height: 3)
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: theme.accent, radius: 12)
                        }
                        .rotationEffect(.degrees(-15))
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.45)
                        .transition(.opacity)

                    case .saber:
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: geo.size.width * 0.9, height: 4)
                            .shadow(color: theme.accent, radius: 12)
                            .rotationEffect(.degrees(-16))
                            .position(x: geo.size.width * 0.5, y: geo.size.height * 0.45)
                            .transition(.opacity)

                    case .lightning:
                        Path { path in
                            path.move(to: CGPoint(x: 20, y: 200))
                            path.addLine(to: CGPoint(x: geo.size.width * 0.3, y: 160))
                            path.addLine(to: CGPoint(x: geo.size.width * 0.55, y: 230))
                            path.addLine(to: CGPoint(x: geo.size.width * 0.85, y: 150))
                        }
                        .stroke(Color.white, lineWidth: 2.5)
                        .shadow(color: theme.accent, radius: 12)
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: theme.activeFXTriggerID) { _, _ in
            withAnimation(.easeOut(duration: 0.28)) { animateFX = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                withAnimation(.easeIn(duration: 0.18)) { animateFX = false }
            }
        }
    }
}
