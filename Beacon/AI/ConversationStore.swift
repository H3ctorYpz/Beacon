import Combine
import Foundation
import SwiftUI

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft: String = "" {
        didSet {
            if lastError != nil, !draft.isEmpty {
                withAnimation(.smooth(duration: 0.35)) {
                    lastError = nil
                }
            }
        }
    }
    @Published var isSending = false
    @Published var lastError: String?
    /// Ephemeral on-island reply — auto-clears; not a sticky glass panel.
    @Published var flashReply: String?
    @Published var statusLine: String?

    private let preferences: AppPreferences
    private let accounts: AIAccountStore
    private var errorDismissTask: Task<Void, Never>?
    private var flashDismissTask: Task<Void, Never>?

    init(preferences: AppPreferences = .shared, accounts: AIAccountStore = .shared) {
        self.preferences = preferences
        self.accounts = accounts
    }

    var activeModelLabel: String {
        accounts.activeAccount?.shortLabel ?? "No account"
    }

    func clear() {
        errorDismissTask?.cancel()
        flashDismissTask?.cancel()
        messages.removeAll()
        lastError = nil
        flashReply = nil
        statusLine = nil
        draft = ""
    }

    func dismissError() {
        errorDismissTask?.cancel()
        withAnimation(.smooth(duration: 0.4)) {
            lastError = nil
        }
    }

    func dismissFlash() {
        flashDismissTask?.cancel()
        withAnimation(.smooth(duration: 0.35)) {
            flashReply = nil
            statusLine = nil
        }
    }

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        dismissError()
        dismissFlash()
        draft = ""
        messages.append(ChatMessage(role: .user, content: text))
        isSending = true
        statusLine = "Thinking…"

        do {
            let reply = try await AgentOrchestrator.run(
                messages: messages,
                baseSystemPrompt: preferences.systemPrompt,
                agentEnabled: preferences.agentModeEnabled,
                accounts: accounts,
                onStatus: { [weak self] line in
                    self?.statusLine = line
                }
            )
            messages.append(ChatMessage(role: .assistant, content: reply))
            presentFlash(reply)
        } catch {
            presentError(error.localizedDescription)
        }

        statusLine = nil
        isSending = false
    }

    private func presentFlash(_ message: String) {
        flashDismissTask?.cancel()
        withAnimation(.smooth(duration: 0.35)) {
            flashReply = message
        }
        flashDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.4)) {
                if flashReply == message {
                    flashReply = nil
                }
            }
        }
    }

    private func presentError(_ message: String) {
        withAnimation(.smooth(duration: 0.4)) {
            lastError = message
            flashReply = nil
        }
        errorDismissTask?.cancel()
        errorDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            if lastError == message {
                withAnimation(.smooth(duration: 0.45)) {
                    lastError = nil
                }
            }
        }
    }
}
