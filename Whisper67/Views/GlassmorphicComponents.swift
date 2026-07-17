import SwiftUI

// MARK: - Brand (cloud · black · liquid glass)

enum DengBrand {
    static let name = "Whisper67"
    static let tagline = "Voice to text, beautifully"
    
    /// Soft cloud white
    static let cloud = Color(red: 0.97, green: 0.97, blue: 0.975)
    /// Cool mist for depth
    static let mist = Color(red: 0.93, green: 0.935, blue: 0.94)
    /// Soft graphite (secondary ink)
    static let graphite = Color(red: 0.22, green: 0.22, blue: 0.24)
    /// Near-black primary accent
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.09)
    /// Mid gray for inactive chrome
    static let silver = Color(red: 0.55, green: 0.56, blue: 0.58)
    
    /// Primary interactive accent — soft black
    static let accent = ink
    /// Alias used across UI for active chrome
    static let aurora = ink
    static let violet = graphite
    static let teal = silver
    
    static var meshBackground: some View {
        ZStack {
            // Pure cloud base
            LinearGradient(
                colors: [
                    Color.white,
                    cloud,
                    mist
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Soft charcoal depth orbs (no color cast)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.04), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 240
                    )
                )
                .frame(width: 440, height: 440)
                .blur(radius: 50)
                .offset(x: -220, y: -180)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.035), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 200
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 55)
                .offset(x: 240, y: 140)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.7), .clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 30)
                .offset(x: 20, y: 220)
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.22)
        }
    }
    
    static var glassStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                Color.white.opacity(0.4),
                Color.black.opacity(0.06),
                Color.white.opacity(0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var primaryFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.14, green: 0.14, blue: 0.15),
                ink
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Liquid Glass Card

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.78),
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.plusLighter)
                            .opacity(0.5)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(DengBrand.glassStroke, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 22, y: 10)
                    .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
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
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DengBrand.ink.opacity(0.85))
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
                        .foregroundStyle(DengBrand.graphite.opacity(0.75))
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(DengBrand.silver)
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
                .foregroundStyle(DengBrand.graphite.opacity(0.65))
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
                    .foregroundStyle(DengBrand.graphite.opacity(0.65))
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
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? DengBrand.ink : DengBrand.silver)
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? DengBrand.ink : DengBrand.graphite.opacity(0.7))
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(DengBrand.ink)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected
                        ? Color.black.opacity(0.06)
                        : (isHovered ? Color.black.opacity(0.03) : Color.clear)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
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
            .foregroundStyle(isSelected ? Color.white : DengBrand.ink.opacity(0.85))
            .background {
                Capsule()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(DengBrand.primaryFill)
                            : AnyShapeStyle(Color.black.opacity(0.04))
                    )
                    .overlay {
                        if !isSelected {
                            Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .shadow(color: isSelected ? Color.black.opacity(0.18) : .clear, radius: 8, y: 3)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Key Badge

struct KeyBadge: View {
    let keys: [String]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DengBrand.ink.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                            }
                            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
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
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background {
                    Capsule()
                        .fill(
                            isDestructive
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color(white: 0.25), Color(white: 0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  ))
                                : AnyShapeStyle(DengBrand.primaryFill)
                        )
                        .shadow(color: Color.black.opacity(0.22), radius: 12, y: 4)
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
