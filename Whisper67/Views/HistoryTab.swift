import SwiftUI
import AppKit

struct HistoryTab: View {
    @Bindable var appState: AppState
    @State private var copiedID: UUID?
    @State private var search = ""
    @State private var confirmClear = false
    
    private var filtered: [DictationHistoryEntry] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return appState.dictationHistory }
        return appState.dictationHistory.filter {
            $0.text.localizedCaseInsensitiveContains(q)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "History",
                    subtitle: "Past dictations — copy any entry back to the clipboard"
                )
                
                // Toolbar
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search history…", text: $search)
                            .textFieldStyle(.plain)
                        
                        Spacer()
                        
                        Text("\(appState.dictationHistory.count) saved")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        if !appState.dictationHistory.isEmpty {
                            Button(role: .destructive) {
                                confirmClear = true
                            } label: {
                                Label("Clear all", systemImage: "trash")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .buttonStyle(.bordered)
                            .confirmationDialog(
                                "Clear all dictation history?",
                                isPresented: $confirmClear,
                                titleVisibility: .visible
                            ) {
                                Button("Clear all", role: .destructive) {
                                    appState.clearDictationHistory()
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                        }
                    }
                    .padding(16)
                }
                
                if filtered.isEmpty {
                    GlassCard {
                        VStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.secondary)
                            Text(appState.dictationHistory.isEmpty
                                 ? "No dictations yet"
                                 : "No matches")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(appState.dictationHistory.isEmpty
                                 ? "When you dictate, finished text shows up here so you can copy it again."
                                 : "Try a different search.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
    
    private func historyRow(_ entry: DictationHistoryEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Text("·")
                        .foregroundStyle(.tertiary)
                    
                    Text("\(entry.wordCount) words")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                    
                    if entry.audioSeconds > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.1fs", entry.audioSeconds))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    
                    Text(entry.providerDisplayName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DengBrand.ink.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(Color.black.opacity(0.05))
                        }
                    
                    Spacer()
                    
                    Button {
                        copy(entry)
                    } label: {
                        Label(
                            copiedID == entry.id ? "Copied" : "Copy",
                            systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(copiedID == entry.id ? .green : DengBrand.ink)
                    
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            appState.removeHistoryEntry(entry)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from history")
                }
                
                Text(entry.text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DengBrand.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(8)
            }
            .padding(16)
        }
        .contextMenu {
            Button("Copy") { copy(entry) }
            Button("Delete", role: .destructive) {
                appState.removeHistoryEntry(entry)
            }
        }
    }
    
    private func copy(_ entry: DictationHistoryEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.text, forType: .string)
        copiedID = entry.id
        print("📋 History copied id=\(entry.id) len=\(entry.text.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}
