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
    
    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            
            // Soft glass divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.15),
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
                            .fill(Color.black)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(DengBrand.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(DengBrand.tagline)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
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
            
            // Footer glass chip
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(manager.isTranscribing ? DengBrand.ink : DengBrand.silver.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(manager.isTranscribing ? "Listening" : "Ready")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DengBrand.ink)
                }
                
                Text("\(appState.usageStats.formattedWords) words · \(appState.provider.displayName)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DengBrand.graphite.opacity(0.65))
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    }
            }
            .padding(14)
        }
        .background {
            ZStack {
                Color.white.opacity(0.28)
                Rectangle().fill(.ultraThinMaterial).opacity(0.55)
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
}

#Preview {
    SettingsView()
}
