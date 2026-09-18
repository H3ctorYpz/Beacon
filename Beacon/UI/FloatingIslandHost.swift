import SwiftUI

struct FloatingIslandHost: View {
    @ObservedObject var store: ConversationStore
    @ObservedObject var session: IslandSession
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var accounts: AIAccountStore
    var notchInsetTop: CGFloat
    var onOpenSettings: () -> Void
    var onUserActivity: () -> Void

    @FocusState private var isKeyboardActive: Bool
    @StateObject private var dictation = SpeechDictationController()

    var body: some View {
        VStack(spacing: 8) {
            SiriStyleBubble(
                hasDynamicIsland: true,
                progress: session.progress,
                buttonSymbol: dictation.isListening ? "mic.fill" : "mic",
                hint: "Search or Ask",
                isListening: dictation.isListening,
                text: $store.draft
            ) {
                onUserActivity()
                dictation.toggle(
                    currentText: store.draft,
                    language: preferences.dictationLanguage,
                    onUpdate: { store.draft = $0 },
                    onActivity: onUserActivity,
                    onComplete: { text in
                        store.draft = text
                        onUserActivity()
                        Task { await store.sendDraft() }
                    }
                )
            }
            .focused($isKeyboardActive)
            .onSubmit {
                if dictation.isListening { dictation.stop() }
                onUserActivity()
                Task { await submit() }
            }
            .onChange(of: store.draft) { _, _ in
                onUserActivity()
            }
            .overlay {
                if session.progress < 1 {
                    Capsule()
                        .fill(Color.clear)
                        .contentShape(Capsule())
                        .onTapGesture {
                            onUserActivity()
                            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                                session.progress = 1
                                isKeyboardActive = true
                            }
                        }
                }
            }

            // Transient feedback only — no sticky liquid-glass reply panel.
            if session.progress > 0.85 {
                Group {
                    if preferences.showModelChip, let account = accounts.activeAccount {
                        Text(account.shortLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .transition(.opacity)
                    }

                    if store.isSending {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            if let status = store.statusLine {
                                Text(status)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .transition(.opacity)
                    } else if let error = store.lastError ?? dictation.lastError {
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 10)
                            .onTapGesture {
                                store.dismissError()
                                dictation.lastError = nil
                            }
                            .transition(.opacity)
                    } else if let reply = store.flashReply {
                        Text(reply)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                            .padding(.horizontal, 10)
                            .onTapGesture { store.dismissFlash() }
                            .transition(.opacity)
                    }
                }
                .animation(.smooth(duration: 0.3), value: store.flashReply)
                .animation(.smooth(duration: 0.3), value: store.lastError)
                .animation(.smooth(duration: 0.25), value: store.isSending)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
        .padding(.horizontal, 4)
        .background(Color.clear)
        .opacity(session.isChromeVisible ? 1 : 0)
        .scaleEffect(session.isChromeVisible ? 1 : 0.94, anchor: .top)
        // Keep hit-testing so the invisible pill still sits in place for hover revival.
        .allowsHitTesting(true)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: session.isChromeVisible)
        .onChange(of: session.progress) { _, value in
            if value >= 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isKeyboardActive = true
                }
                onUserActivity()
            } else {
                dictation.stop()
                store.dismissFlash()
                store.dismissError()
                dictation.lastError = nil
            }
        }
        .onExitCommand {
            dictation.stop()
            store.dismissFlash()
            store.dismissError()
            dictation.lastError = nil
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) { session.progress = 0 }
        }
        .contextMenu {
            Button("Settings…", action: onOpenSettings)
            Button("Clear") { store.clear() }
            Button(session.progress == 1 ? "Collapse" : "Expand") {
                dictation.stop()
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    session.progress = session.progress == 1 ? 0 : 1
                    isKeyboardActive = session.progress == 1
                }
            }
        }
    }

    private func submit() async {
        if session.progress < 1 {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                session.progress = 1
                isKeyboardActive = true
            }
            return
        }
        await store.sendDraft()
        onUserActivity()
    }
}
