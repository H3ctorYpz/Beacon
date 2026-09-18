import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case island
    case ai
    case appearance
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .island: return "Island"
        case .ai: return "AI"
        case .appearance: return "Appearance"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .island: return "button.roundedtop.horizontal.fill"
        case .ai: return "sparkles"
        case .appearance: return "paintbrush.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .island: return BeaconPalette.accent
        case .ai: return .orange
        case .appearance: return .indigo
        case .about: return .blue
        }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var accounts: AIAccountStore
    @State private var section: SettingsSection = .ai

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.icon)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(item.tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch section {
                case .general: GeneralSettingsPane(preferences: preferences)
                case .island: IslandPlacementPane(preferences: preferences)
                case .ai: AISettingsPane(preferences: preferences, accounts: accounts)
                case .appearance: AppearanceSettingsPane()
                case .about: AboutSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(VisualEffectBackground())
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct GeneralSettingsPane: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: $preferences.launchAtLogin)
                Toggle("Show Dock icon", isOn: $preferences.showDockIcon)
            }
            Section("Agente macOS") {
                Toggle("Permitir herramientas del Mac", isOn: $preferences.agentModeEnabled)
                Text("Terminal, archivos, Finder, portapapeles, URLs y AppleScript. Las acciones sensibles piden permiso (Permitir / sesión / Denegar).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Dictado por voz") {
                Picker("Idioma", selection: $preferences.dictationLanguage) {
                    ForEach(AppPreferences.DictationLanguage.allCases) { lang in
                        Text(lang.title).tag(lang)
                    }
                }
                Text("El micrófono escribe en este idioma (no traduce). Coincide con el idioma que hablas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                LabeledContent("Toggle island", value: "⌘⇧B · menu bar · hover")
                LabeledContent("Settings", value: "⌘,")
            }
        }
        .formStyle(.grouped)
    }
}

private struct IslandPlacementPane: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Edge") {
                Picker("Dock to", selection: $preferences.islandEdge) {
                    ForEach(AppPreferences.IslandEdge.allCases) { edge in
                        Label(edge.title, systemImage: edge.icon).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Millimetric nudge (points)") {
                OffsetRow(
                    label: "X",
                    value: $preferences.islandOffsetX,
                    hint: "+ right · − left"
                )
                OffsetRow(
                    label: "Y",
                    value: $preferences.islandOffsetY,
                    hint: yHint
                )
            }

            Section("Size") {
                HStack {
                    Text("Expanded width")
                    Slider(value: $preferences.islandMaxWidth, in: 280...420, step: 4)
                    Text("\(Int(preferences.islandMaxWidth))")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                Text("iPhone-like pill — not full Mac width. Collapsed stays ~120 pt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Activation") {
                Toggle("Expand on hover", isOn: $preferences.expandOnHover)
                Toggle("Show island pill", isOn: $preferences.pillVisibleOnLaunch)
                    .onChange(of: preferences.pillVisibleOnLaunch) { _, visible in
                        NotificationCenter.default.post(
                            name: .beaconPillVisibilityPreferenceChanged,
                            object: nil,
                            userInfo: ["visible": visible]
                        )
                    }
                HStack {
                    Text("Auto-hide after")
                    Slider(value: $preferences.autoHideSeconds, in: 0...30, step: 1)
                    Text(preferences.autoHideSeconds == 0 ? "Off" : "\(Int(preferences.autoHideSeconds))s")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                Text("⌘⇧H baja la opacidad a 0 (la píldora sigue en su sitio). Al pasar el cursor vuelve y se expande. ⌘⇧B expande.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Toggle("Show active model under island", isOn: $preferences.showModelChip)
                Text("Off by default. Turn on to see which model is active below the bubble.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dictado por voz") {
                Picker("Idioma", selection: $preferences.dictationLanguage) {
                    ForEach(AppPreferences.DictationLanguage.allCases) { lang in
                        Text(lang.title).tag(lang)
                    }
                }
                Text("El micrófono escribe en este idioma (no traduce). Elige el mismo en el que hablas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset placement") {
                    preferences.resetIslandPlacement()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var yHint: String {
        switch preferences.islandEdge {
        case .top:
            return "+ up (into menu bar/notch) · − down"
        case .bottom:
            return "+ up · − down (below dock)"
        case .leading, .trailing:
            return "+ up · − down"
        }
    }
}

/// Slider + text field that accepts negatives while typing (FormatStyle.number
/// often resets on intermediate "-").
private struct OffsetRow: View {
    let label: String
    @Binding var value: Double
    let hint: String
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .frame(width: 20, alignment: .leading)
                Slider(value: $value, in: -240...240, step: 1)
                    .onChange(of: value) { _, new in
                        text = String(Int(new.rounded()))
                    }
                TextField("", text: $text)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitText() }
                    .onChange(of: text) { _, new in
                        // Allow "-", "-0", empty while editing.
                        if new.isEmpty || new == "-" || new == "-0" { return }
                        if let parsed = Double(new) {
                            value = min(max(parsed, -240), 240)
                        }
                    }
                Text("pt")
                    .foregroundStyle(.secondary)
                Stepper("", value: $value, in: -240...240, step: 1)
                    .labelsHidden()
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            text = String(Int(value.rounded()))
        }
    }

    private func commitText() {
        if text.isEmpty || text == "-" {
            value = 0
            text = "0"
            return
        }
        if let parsed = Double(text) {
            value = min(max(parsed, -240), 240)
            text = String(Int(value.rounded()))
        } else {
            text = String(Int(value.rounded()))
        }
    }
}

private struct AISettingsPane: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var accounts: AIAccountStore
    @State private var editing: AIAccount?
    @State private var draftKey: String = ""
    @State private var isNew = false
    @State private var testStatus: String?
    @State private var isTesting = false
    @State private var showPresetPicker = false

    var body: some View {
        Form {
            Section {
                Text("No se puede iniciar sesión con ChatGPT Plus, Claude Pro, Gemini Advanced ni cuentas de apps. Solo API keys del console del proveedor, OpenRouter, o Ollama/LM Studio local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Accounts") {
                if accounts.accounts.isEmpty {
                    Text("No accounts yet. Add one below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(accounts.accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(account.name).font(.headline)
                                if account.id == accounts.activeAccountId {
                                    Text("Active")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(BeaconPalette.accent.opacity(0.25), in: Capsule())
                                }
                            }
                            Text("\(account.kind.title) · \(account.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") {
                            editing = account
                            draftKey = accounts.apiKey(for: account)
                            isNew = false
                        }
                        if account.id != accounts.activeAccountId {
                            Button("Use") { accounts.setActive(account.id) }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        accounts.delete(accounts.accounts[index].id)
                    }
                }

                Button("Add account…") { showPresetPicker = true }
            }

            Section("Behaviour") {
                TextEditor(text: $preferences.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 90)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { account in
            AccountEditorSheet(
                account: account,
                apiKey: $draftKey,
                isNew: isNew,
                testStatus: $testStatus,
                isTesting: $isTesting,
                onSave: { updated, key in
                    if isNew {
                        accounts.add(updated, apiKey: key)
                    } else {
                        accounts.update(updated)
                        accounts.setAPIKey(key, for: updated.id)
                    }
                    editing = nil
                },
                onCancel: { editing = nil },
                onTest: { account, key in
                    await runTest(account: account, key: key)
                },
                onDelete: isNew ? nil : {
                    accounts.delete(account.id)
                    editing = nil
                }
            )
        }
        .sheet(isPresented: $showPresetPicker) {
            PresetPickerSheet { preset in
                showPresetPicker = false
                let account = preset.makeAccount()
                editing = account
                draftKey = ""
                isNew = true
                testStatus = nil
            }
        }
    }

    private func runTest(account: AIAccount, key: String) async {
        isTesting = true
        testStatus = nil
        defer { isTesting = false }
        do {
            let reply = try await AIRouter.testConnection(
                account: account,
                apiKey: key,
                systemPrompt: preferences.systemPrompt
            )
            testStatus = "OK — \(reply.prefix(80))"
        } catch {
            testStatus = error.localizedDescription
        }
    }
}

private struct PresetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var onPick: (AIAccountPreset) -> Void

    private var filtered: [(String, [AIAccountPreset])] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return AIAccountPreset.grouped.compactMap { group, items in
            let list = q.isEmpty
                ? items
                : items.filter {
                    $0.title.lowercased().contains(q)
                        || $0.subtitle.lowercased().contains(q)
                        || $0.group.lowercased().contains(q)
                }
            guard !list.isEmpty else { return nil }
            return (group, list)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add AI account")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(20)

            Text("Solo proveedores con API oficial. No hay login de suscripción de chat.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            TextField("Search providers", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            List {
                ForEach(filtered, id: \.0) { group, items in
                    Section(group) {
                        ForEach(items) { preset in
                            Button {
                                onPick(preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title)
                                        .foregroundStyle(.primary)
                                    Text(preset.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 520, height: 560)
    }
}

private struct AccountEditorSheet: View {
    @State var account: AIAccount
    @Binding var apiKey: String
    var isNew: Bool
    @Binding var testStatus: String?
    @Binding var isTesting: Bool
    var onSave: (AIAccount, String) -> Void
    var onCancel: () -> Void
    var onTest: (AIAccount, String) async -> Void
    var onDelete: (() -> Void)?

    @State private var keyDraft: String = ""
    @State private var revealKey = true
    @FocusState private var keyFocused: Bool

    private static let geminiModels = [
        "gemini-3.8-flash",
        "gemini-3.5-flash",
        "gemini-3.1-flash-lite",
        "gemini-flash-latest",
        "gemini-2.5-flash",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New account" : "Edit account")
                .font(.title2.weight(.bold))

            Form {
                TextField("Name", text: $account.name)
                Picker("Kind", selection: $account.kind) {
                    ForEach(AIAccountKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                TextField("Base URL", text: $account.baseURL)
                if account.kind == .googleGemini {
                    Picker("Model", selection: $account.model) {
                        ForEach(Self.geminiModels, id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                    if !Self.geminiModels.contains(account.model) {
                        TextField("Custom model", text: $account.model)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Keys nuevas: Google bloquea gemini-2.5-*. Usa 3.5 o 3.8 Flash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Model", text: $account.model)
                }
            }
            .formStyle(.grouped)

            if account.kind.needsAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API key")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Group {
                            if revealKey {
                                TextField("Pega tu API key aquí", text: $keyDraft)
                            } else {
                                SecureField("Pega tu API key aquí", text: $keyDraft)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($keyFocused)
                        .onChange(of: keyDraft) { _, value in
                            apiKey = value
                        }

                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .help(revealKey ? "Ocultar" : "Mostrar")

                        Button("Pegar") {
                            pasteAPIKey()
                        }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                    }

                    Text("⌘V o botón Pegar. Es la key del console (AI Studio), no login de cuenta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Button {
                    Task { await onTest(account, keyDraft) }
                } label: {
                    if isTesting { ProgressView().controlSize(.small) }
                    else { Text("Test connection") }
                }
                .disabled(isTesting)

                if let testStatus {
                    Text(testStatus)
                        .font(.caption)
                        .foregroundStyle(testStatus.hasPrefix("OK") ? .green : .red)
                        .lineLimit(2)
                }

                Spacer()

                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Button("Cancel", action: onCancel)
                Button("Save") {
                    apiKey = keyDraft
                    onSave(account, keyDraft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
        .onAppear {
            keyDraft = apiKey
            if account.kind == .googleGemini,
               account.model == "gemini-2.5-flash" || account.model == "gemini-2.0-flash" {
                account.model = "gemini-3.5-flash"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                keyFocused = true
            }
        }
    }

    private func pasteAPIKey() {
        // Activate pasteboard read explicitly — SecureField often blocks ⌘V on macOS sheets.
        NSApp.activate(ignoringOtherApps: true)
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keyDraft = trimmed
        apiKey = trimmed
        keyFocused = true
    }
}

private struct AppearanceSettingsPane: View {
    var body: some View {
        Form {
            Section("Look") {
                LabeledContent("Accent") {
                    Circle()
                        .fill(BeaconPalette.accent)
                        .frame(width: 18, height: 18)
                }
                Text("Warm graphite + amber. Island size lives under Island.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BeaconPalette.accent, BeaconPalette.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "light.min")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Beacon")
                        .font(.title2.weight(.bold))
                    Text("Open-source macOS AI assistant")
                        .foregroundStyle(.secondary)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Copyright © 2026 Hector Ypz. MIT License.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Link("View LICENSE.md", destination: URL(string: "https://opensource.org/licenses/MIT")!)
            Spacer()
        }
    }
}
