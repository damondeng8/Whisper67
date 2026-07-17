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
    
    // MARK: Uniform surfaces (no fade hierarchy)
    
    /// Card / panel fill — solid, same everywhere
    static let surface = Color.white
    /// Nested chip / control fill — light gray (not heavy)
    static let chip = Color(red: 0.965, green: 0.965, blue: 0.968)
    /// Selected chip — slightly deeper than chip, still light
    static let chipSelected = Color(red: 0.93, green: 0.93, blue: 0.935)
    /// Icon well / subtle inset
    static let chipInset = Color(red: 0.95, green: 0.95, blue: 0.955)
    /// Uniform stroke for chips & cards
    static let stroke = Color.black.opacity(0.07)
    static let strokeSelected = Color.black.opacity(0.12)
    /// Uniform soft shadow
    static let shadow = Color.black.opacity(0.05)
    
    /// Primary interactive accent — soft black
    static let accent = ink
    /// Alias used across UI for active chrome
    static let aurora = ink
    static let violet = graphite
    static let teal = silver
    
    static var meshBackground: some View {
        // Flat uniform base — no gradient fade orbs
        Rectangle()
            .fill(cloud)
            .ignoresSafeArea()
    }
    
    static var glassStroke: LinearGradient {
        // Flat stroke (same color both ends) so cards don’t look graded
        LinearGradient(
            colors: [stroke, stroke],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var primaryFill: LinearGradient {
        LinearGradient(
            colors: [ink, ink],
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
                    .fill(DengBrand.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(DengBrand.stroke, lineWidth: 1)
                    }
                    .shadow(color: DengBrand.shadow, radius: 12, y: 4)
            }
    }
}

// MARK: - Uniform selectable chip (mode / segment)

/// Solid equal-weight chips — selected is darker fill, never “faded” siblings.
struct SelectChipBackground: View {
    var isSelected: Bool
    var cornerRadius: CGFloat = 12
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isSelected ? DengBrand.chipSelected : DengBrand.chip)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? DengBrand.strokeSelected : DengBrand.stroke,
                        lineWidth: 1
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
                        .foregroundStyle(DengBrand.graphite)
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
                    .foregroundStyle(DengBrand.ink)
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(DengBrand.ink)
                
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
