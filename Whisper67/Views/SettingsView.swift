import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case home
    case history
    case modes
    case api
    case dictionary
    case shortcuts
    case general
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .modes: return "Modes"
        case .api: return "API"
        case .dictionary: return "Dictionary"
        case .shortcuts: return "Shortcuts"
        case .general: return "General"
        }
    }
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.arrow.circlepath"
        case .modes: return "text.badge.checkmark"
        case .api: return "key.fill"
        case .dictionary: return "text.book.closed.fill"
        case .shortcuts: return "command"
        case .general: return "gearshape.fill"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .home
    @State private var appState = AppState.shared
    @State private var manager = TranscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            
            // Soft glass divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55),
                            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
                .padding(.vertical, 20)
            
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        .frame(idealWidth: 900, idealHeight: 640)
        .background { DengBrand.meshBackground }
        // Re-apply when switching Auto ↔ Light ↔ Dark (nil alone can stick after force)
        .preferredColorScheme(appState.appearance.colorScheme)
        .id("appearance-\(appState.appearance.rawValue)")
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand lockup
            HStack(spacing: 12) {
                Image("Whisper67Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(7)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [
                                            Color(red: 0.18, green: 0.20, blue: 0.28),
                                            Color(red: 0.08, green: 0.09, blue: 0.14)
                                          ]
                                        : [Color.black, Color(white: 0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.18),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: colorScheme == .dark
                            ? DengBrand.glow.opacity(0.25)
                            : Color.black.opacity(0.12),
                        radius: colorScheme == .dark ? 14 : 10,
                        y: 4
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(DengBrand.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DengBrand.ink)
                    Text(DengBrand.tagline)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DengBrand.graphite.opacity(0.85))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 22)
            
            VStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarItem(
                        title: tab.title,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            // Quick light / dark toggle
            appearanceToggle
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            
            // Footer glass chip
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            manager.isTranscribing
                                ? (colorScheme == .dark ? DengBrand.glow : DengBrand.ink)
                                : DengBrand.silver.opacity(0.55)
                        )
                        .frame(width: 7, height: 7)
                        .shadow(
                            color: manager.isTranscribing && colorScheme == .dark
                                ? DengBrand.glow.opacity(0.7)
                                : .clear,
                            radius: 5
                        )
                    Text(manager.isTranscribing ? "Listening" : "Ready")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DengBrand.ink)
                }
                
                Text("\(appState.usageStats.formattedWords) words · \(appState.provider.displayName)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DengBrand.graphite.opacity(0.7))
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55),
                                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .padding(14)
        }
        .background {
            ZStack {
                if colorScheme == .dark {
                    Color.white.opacity(0.03)
                    Rectangle().fill(.ultraThinMaterial).opacity(0.35)
                } else {
                    Color.white.opacity(0.28)
                    Rectangle().fill(.ultraThinMaterial).opacity(0.55)
                }
            }
        }
    }
    
    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .home:
            HomeDashboardView(appState: appState, manager: manager)
        case .history:
            HistoryTab(appState: appState)
        case .modes:
            ModesTab(appState: appState)
        case .api:
            APISettingsTab(appState: appState, manager: manager)
        case .dictionary:
            DictionaryTab(appState: appState)
        case .shortcuts:
            HotkeysTab(appState: appState, manager: manager)
        case .general:
            GeneralTab(appState: appState)
        }
    }
    
    /// Compact Light | Dark | Auto control in the sidebar.
    private var appearanceToggle: some View {
        HStack(spacing: 0) {
            appearanceSegment(mode: .light, icon: "sun.max.fill", label: "Light")
            appearanceSegment(mode: .dark, icon: "moon.fill", label: "Dark")
            appearanceSegment(mode: .system, icon: "circle.lefthalf.filled", label: "Auto")
        }
        .padding(3)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.4),
                            lineWidth: 1
                        )
                }
        }
    }
    
    private func appearanceSegment(mode: AppAppearance, icon: String, label: String) -> some View {
        let selected = appState.appearance == mode
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                appState.appearance = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(
                selected
                    ? (colorScheme == .dark && mode == .dark ? DengBrand.glow : DengBrand.ink)
                    : DengBrand.graphite.opacity(0.75)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule()
                        .fill(DengBrand.chipSelected)
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    colorScheme == .dark
                                        ? DengBrand.glow.opacity(0.35)
                                        : DengBrand.strokeSelected,
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Appearance: \(mode.title)")
    }
}

#Preview {
    SettingsView()
}
