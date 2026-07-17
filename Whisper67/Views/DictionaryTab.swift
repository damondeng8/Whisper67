import SwiftUI

struct DictionaryTab: View {
    @Bindable var appState: AppState
    @State private var newWord = ""
    @FocusState private var fieldFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(
                    title: "Custom words",
                    subtitle: "Names, jargon, and spellings Whisper should prefer — like Wispr Flow’s dictionary"
                )
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Add a word or phrase")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        
                        HStack(spacing: 10) {
                            TextField("e.g. Whisper67, SaaS, Yi Fa Deng", text: $newWord)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                }
                                .focused($fieldFocused)
                                .onSubmit { addWord() }
                            
                            Button(action: addWord) {
                                Label("Add", systemImage: "plus")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        
                        Text("These words are sent as a Whisper prompt hint so names and product terms land correctly.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                }
                
                if appState.customWords.isEmpty {
                    GlassCard {
                        VStack(spacing: 10) {
                            Image(systemName: "text.book.closed")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("No custom words yet")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text("Add people names, company names, and technical terms you dictate often.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    }
                } else {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("\(appState.customWords.count) words")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                            
                            ForEach(appState.customWords) { word in
                                HStack {
                                    Image(systemName: "character.textbox")
                                        .foregroundStyle(DengBrand.ink.opacity(0.75))
                                        .font(.system(size: 12))
                                    Text(word.word)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                    Spacer()
                                    Text(word.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 10, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            appState.removeCustomWord(word)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                
                                if word.id != appState.customWords.last?.id {
                                    Divider().padding(.leading, 40)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    
                    // Preview prompt
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompt preview")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(appState.dictionaryPrompt.isEmpty ? "—" : appState.dictionaryPrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                    }
                }
            }
            .padding(28)
        }
        .onAppear { fieldFocused = true }
    }
    
    private func addWord() {
        let value = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        withAnimation(.spring(response: 0.35)) {
            appState.addCustomWord(value)
        }
        newWord = ""
        fieldFocused = true
    }
}
