import SwiftUI
import AppKit

// MARK: - Adaptive color helper

extension Color {
    /// Resolves light/dark automatically from the current appearance.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
    
    static func adaptive(light: Color, dark: Color) -> Color {
        adaptive(light: NSColor(light), dark: NSColor(dark))
    }
}

// MARK: - Appearance preference

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    func applyToApp() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Brand (liquid glass · light + dark)

enum DengBrand {
    static let name = "Whisper67"
    static let tagline = "Voice to text, beautifully"
    
    // MARK: Adaptive palette
    
    /// Soft cloud (light) / deep void (dark)
    static let cloud = Color.adaptive(
        light: NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.978, alpha: 1),
        dark: NSColor(calibratedRed: 0.045, green: 0.048, blue: 0.065, alpha: 1)
    )
    
    /// Cool mist / elevated dark surface
    static let mist = Color.adaptive(
        light: NSColor(calibratedRed: 0.93, green: 0.935, blue: 0.945, alpha: 1),
        dark: NSColor(calibratedRed: 0.09, green: 0.095, blue: 0.12, alpha: 1)
    )
    
    /// Secondary ink
    static let graphite = Color.adaptive(
        light: NSColor(calibratedRed: 0.28, green: 0.29, blue: 0.32, alpha: 1),
        dark: NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.78, alpha: 1)
    )
    
    /// Primary text / accent
    static let ink = Color.adaptive(
        light: NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1),
        dark: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1)
    )
    
    /// Inactive chrome
    static let silver = Color.adaptive(
        light: NSColor(calibratedRed: 0.55, green: 0.56, blue: 0.58, alpha: 1),
        dark: NSColor(calibratedRed: 0.48, green: 0.50, blue: 0.55, alpha: 1)
    )
    
    /// Soft luminous accent (cyan-glass) — dark mode highlight
    static let glow = Color.adaptive(
        light: NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.65, alpha: 1),
        dark: NSColor(calibratedRed: 0.55, green: 0.72, blue: 1.0, alpha: 1)
    )
    
    /// Violet ambient for liquid orbs
    static let ambience = Color.adaptive(
        light: NSColor(calibratedRed: 0.55, green: 0.50, blue: 0.72, alpha: 1),
        dark: NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.95, alpha: 1)
    )
    
    // MARK: Surfaces (glass fills)
    
    /// Card fill — translucent glass
    static let surface = Color.adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 0.55)
    )
    
    /// Nested chip fill
    static let chip = Color.adaptive(
        light: NSColor(calibratedWhite: 0.97, alpha: 0.92),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.07)
    )
    
    /// Selected chip
    static let chipSelected = Color.adaptive(
        light: NSColor(calibratedWhite: 0.93, alpha: 1),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.14)
    )
    
    /// Icon well
    static let chipInset = Color.adaptive(
        light: NSColor(calibratedWhite: 0.95, alpha: 1),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )
    
    /// Subtle wash (info rows, etc.)
    static let wash = Color.adaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.04),
        dark: NSColor(calibratedWhite: 1, alpha: 0.06)
    )
    
    /// Uniform stroke
    static let stroke = Color.adaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1, alpha: 0.12)
    )
    
    static let strokeSelected = Color.adaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.14),
        dark: NSColor(calibratedWhite: 1, alpha: 0.22)
    )
    
    /// Specular rim highlight (top edge of glass)
    static let specular = Color.adaptive(
        light: NSColor(calibratedWhite: 1, alpha: 0.85),
        dark: NSColor(calibratedWhite: 1, alpha: 0.28)
    )
    
    static let shadow = Color.adaptive(
        light: NSColor(calibratedWhite: 0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 0, alpha: 0.45)
    )
    
    /// Primary interactive accent
    static let accent = ink
    static let aurora = ink
    static let violet = graphite
    static let teal = silver
    
    // MARK: Background mesh (liquid depth)
    
    static var meshBackground: some View {
        LiquidMeshBackground()
    }
    
    static var glassStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.adaptive(
                    light: NSColor(calibratedWhite: 1, alpha: 0.7),
                    dark: NSColor(calibratedWhite: 1, alpha: 0.28)
                ),
                Color.adaptive(
                    light: NSColor(calibratedWhite: 1, alpha: 0.15),
                    dark: NSColor(calibratedWhite: 1, alpha: 0.06)
                ),
                Color.adaptive(
                    light: NSColor(calibratedWhite: 0, alpha: 0.06),
                    dark: NSColor(calibratedWhite: 1, alpha: 0.04)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var primaryFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.adaptive(
                    light: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1),
                    dark: NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.98, alpha: 1)
                ),
                Color.adaptive(
                    light: NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1),
                    dark: NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.90, alpha: 1)
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Text on primary buttons (inverts with mode)
    static let onPrimary = Color.adaptive(
        light: NSColor.white,
        dark: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1)
    )
}

// MARK: - Liquid mesh background

struct LiquidMeshBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        ZStack {
            // Base
            Rectangle()
                .fill(baseGradient)
            
            if !reduceTransparency {
                // Soft liquid orbs — create depth glass can refract against
                GeometryReader { geo in
                    ZStack {
                        // Top-left glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: orbColors.primary,
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: geo.size.width * 0.45
                                )
                            )
                            .frame(width: geo.size.width * 0.9, height: geo.size.width * 0.9)
                            .position(x: geo.size.width * 0.12, y: geo.size.height * 0.08)
                            .blur(radius: colorScheme == .dark ? 40 : 50)
                        
                        // Bottom-right ambience
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: orbColors.secondary,
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: geo.size.width * 0.4
                                )
                            )
                            .frame(width: geo.size.width * 0.85, height: geo.size.width * 0.85)
                            .position(x: geo.size.width * 0.92, y: geo.size.height * 0.88)
                            .blur(radius: colorScheme == .dark ? 50 : 60)
                        
                        // Mid accent (subtle)
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: orbColors.accent,
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: geo.size.width * 0.35
                                )
                            )
                            .frame(width: geo.size.width * 0.7, height: geo.size.height * 0.55)
                            .position(x: geo.size.width * 0.55, y: geo.size.height * 0.45)
                            .blur(radius: colorScheme == .dark ? 60 : 70)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private var baseGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.045, blue: 0.07),
                    Color(red: 0.055, green: 0.05, blue: 0.09),
                    Color(red: 0.03, green: 0.035, blue: 0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.975, blue: 0.985),
                    Color(red: 0.945, green: 0.95, blue: 0.965),
                    Color(red: 0.96, green: 0.96, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var orbColors: (primary: [Color], secondary: [Color], accent: [Color]) {
        if colorScheme == .dark {
            return (
                primary: [
                    Color(red: 0.35, green: 0.50, blue: 0.95).opacity(0.28),
                    Color(red: 0.25, green: 0.35, blue: 0.70).opacity(0.08),
                    .clear
                ],
                secondary: [
                    Color(red: 0.55, green: 0.30, blue: 0.95).opacity(0.22),
                    Color(red: 0.40, green: 0.20, blue: 0.65).opacity(0.06),
                    .clear
                ],
                accent: [
                    Color(red: 0.30, green: 0.75, blue: 0.90).opacity(0.10),
                    .clear
                ]
            )
        } else {
            return (
                primary: [
                    Color(red: 0.75, green: 0.82, blue: 0.95).opacity(0.45),
                    Color(red: 0.85, green: 0.88, blue: 0.96).opacity(0.15),
                    .clear
                ],
                secondary: [
                    Color(red: 0.88, green: 0.82, blue: 0.95).opacity(0.35),
                    Color(red: 0.92, green: 0.90, blue: 0.96).opacity(0.10),
                    .clear
                ],
                accent: [
                    Color(red: 0.80, green: 0.90, blue: 0.95).opacity(0.20),
                    .clear
                ]
            )
        }
    }
}

// MARK: - Liquid Glass Card

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        content()
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(reduceTransparency ? AnyShapeStyle(DengBrand.mist) : AnyShapeStyle(.ultraThinMaterial))
                    
                    // Tinted glass wash over material
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color(red: 0.12, green: 0.14, blue: 0.20).opacity(0.35)
                                : Color.white.opacity(0.28)
                        )
                    
                    // Specular top sheen
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.55),
                                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.08),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.55)
                            )
                        )
                        .allowsHitTesting(false)
                    
                    // Glass edge stroke
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.22 : 0.75),
                                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.20),
                                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08),
                    radius: colorScheme == .dark ? 24 : 14,
                    y: colorScheme == .dark ? 10 : 5
                )
                .shadow(
                    color: (colorScheme == .dark
                            ? Color(red: 0.3, green: 0.4, blue: 0.9)
                            : Color.clear).opacity(0.12),
                    radius: 30,
                    y: 8
                )
            }
    }
}

// MARK: - Uniform selectable chip (mode / segment)

/// Glass equal-weight chips — selected glows slightly more.
struct SelectChipBackground: View {
    var isSelected: Bool
    var cornerRadius: CGFloat = 12
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isSelected ? DengBrand.chipSelected : DengBrand.chip)
            .overlay {
                if isSelected && colorScheme == .dark {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DengBrand.glow.opacity(0.12),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? (colorScheme == .dark
                               ? DengBrand.glow.opacity(0.35)
                               : DengBrand.strokeSelected)
                            : DengBrand.stroke,
                        lineWidth: isSelected ? 1.2 : 1
                    )
            }
    }
}

// MARK: - Stat Tile

struct StatTile: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(DengBrand.chipInset)
                            .overlay {
                                Circle()
                                    .strokeBorder(DengBrand.stroke, lineWidth: 0.5)
                            }
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DengBrand.ink)
                    }
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(DengBrand.ink)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DengBrand.graphite)
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(DengBrand.graphite.opacity(0.8))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(DengBrand.ink)
            Text(subtitle)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(DengBrand.graphite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Glass Setting Row

struct GlassSettingRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DengBrand.ink)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(DengBrand.graphite.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(
                        isSelected && colorScheme == .dark
                            ? DengBrand.glow
                            : DengBrand.ink
                    )
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(DengBrand.ink)
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(colorScheme == .dark ? DengBrand.glow : DengBrand.ink)
                        .frame(width: 5, height: 5)
                        .shadow(
                            color: colorScheme == .dark ? DengBrand.glow.opacity(0.6) : .clear,
                            radius: 4
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            Group {
                if isSelected {
                    SelectChipBackground(isSelected: true, cornerRadius: 12)
                } else if isHovered {
                    SelectChipBackground(isSelected: false, cornerRadius: 12)
                }
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Live mic waves (Home preview — same shaper as pill)

struct AnimatedAudioWaves: View {
    let barCount: Int
    let maxHeight: CGFloat
    let spacing: CGFloat
    let color: Color
    let isActive: Bool
    /// Overall 0…1 mic level (preferred)
    let overallLevel: Float
    /// Optional texture bands
    let levels: [Float]
    
    @State private var display: [CGFloat] = []
    @State private var phase: Double = 0
    @State private var energy: CGFloat = 0
    @State private var timer: Timer?
    
    init(
        barCount: Int = 12,
        maxHeight: CGFloat = 40,
        spacing: CGFloat = 3,
        color: Color = DengBrand.ink,
        isActive: Bool = true,
        overallLevel: Float = 0,
        levels: [Float] = []
    ) {
        self.barCount = barCount
        self.maxHeight = maxHeight
        self.spacing = spacing
        self.color = color
        self.isActive = isActive
        self.overallLevel = overallLevel
        self.levels = levels
    }
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < display.count ? display[index] : 0.1
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(isActive ? 0.92 : 0.3),
                                color.opacity(isActive ? 0.35 : 0.14)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3.2, height: max(3.5, level * maxHeight))
            }
        }
        .onAppear {
            display = Array(repeating: 0.1, count: barCount)
            startTimer()
        }
        .onDisappear { stopTimer() }
        .onChange(of: isActive) { _, active in
            if active { startTimer() } else {
                energy = 0
                display = Array(repeating: 0.1, count: barCount)
            }
        }
        .onChange(of: overallLevel) { _, v in
            let g = WaveformShaper.gateAndCompress(v)
            let a: CGFloat = g > energy ? 0.4 : 0.18
            energy = energy + (g - energy) * a
        }
        .onChange(of: levels) { _, bands in
            if let peak = bands.max() {
                let g = WaveformShaper.gateAndCompress(peak * 0.85)
                if g > energy { energy = energy + (g - energy) * 0.25 }
            }
        }
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40.0, repeats: true) { _ in
            phase += 0.11
            if !isActive {
                energy *= 0.85
            }
            let target = WaveformShaper.bars(
                energy: energy,
                count: barCount,
                phase: phase,
                bandTexture: levels
            )
            display = WaveformShaper.smooth(current: display, target: target, attack: 0.4, release: 0.18)
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Provider Chip

struct ProviderChip: View {
    let provider: TranscriptionProvider
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: provider.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundStyle(DengBrand.ink)
            .background {
                Capsule()
                    .fill(isSelected ? DengBrand.chipSelected : DengBrand.chip)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isSelected ? DengBrand.strokeSelected : DengBrand.stroke,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Key Badge

struct KeyBadge: View {
    let keys: [String]
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DengBrand.ink.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55),
                                        lineWidth: 0.8
                                    )
                            }
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 2, y: 1)
                    }
            }
        }
    }
}

// MARK: - Primary glass button

struct DengPrimaryButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .foregroundStyle(isDestructive ? Color.white : DengBrand.onPrimary)
                .background {
                    Capsule()
                        .fill(
                            isDestructive
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [
                                        Color(red: 0.75, green: 0.22, blue: 0.22),
                                        Color(red: 0.55, green: 0.12, blue: 0.12)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  ))
                                : AnyShapeStyle(DengBrand.primaryFill)
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    Color.white.opacity(colorScheme == .dark ? 0.35 : 0.15),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(
                            color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.22),
                            radius: 12,
                            y: 4
                        )
                        .shadow(
                            color: colorScheme == .dark
                                ? DengBrand.glow.opacity(0.15)
                                : .clear,
                            radius: 16,
                            y: 2
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy helpers

struct GlassToggle: View {
    let label: String
    let subtitle: String?
    @Binding var isOn: Bool
    
    init(_ label: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.subtitle = subtitle
        self._isOn = isOn
    }
    
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium, design: .rounded))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(DengBrand.ink)
    }
}

struct GlassSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    
    init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0.1) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .tint(DengBrand.ink)
        }
    }
}

struct GlassButton: View {
    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void
    
    enum Style { case primary, secondary, accent }
    
    init(_ title: String, icon: String? = nil, style: Style = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .buttonStyle(.bordered)
    }
}
