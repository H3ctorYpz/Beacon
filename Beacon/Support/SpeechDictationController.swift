import AVFoundation
import Combine
import Foundation
import Speech

/// Dictation that stops on end-of-speech and delivers the best final transcript.
@MainActor
final class SpeechDictationController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var activeLocaleID: String = ""
    @Published var lastError: String?

    /// Wait for a real pause so mid-sentence hesitations don't cut off.
    private let silenceTimeout: TimeInterval = 1.55
    private let minSpokenCharacters = 2
    /// After silence, wait for Apple's final pass before sending.
    private let finalizeGrace: TimeInterval = 0.55

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var baseText = ""
    private var lastCombined = ""
    private var lastSpoken = ""
    private var lastTranscriptChange = Date()
    private var silenceTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var isFinishing = false

    private var onUpdate: ((String) -> Void)?
    private var onActivity: (() -> Void)?
    private var onComplete: ((String) -> Void)?

    var isAvailable: Bool {
        true
    }

    func toggle(
        currentText: String,
        language: AppPreferences.DictationLanguage,
        onUpdate: @escaping (String) -> Void,
        onActivity: @escaping () -> Void = {},
        onComplete: @escaping (String) -> Void = { _ in }
    ) {
        if isListening {
            beginFinalize()
        } else {
            Task {
                await start(
                    currentText: currentText,
                    language: language,
                    onUpdate: onUpdate,
                    onActivity: onActivity,
                    onComplete: onComplete
                )
            }
        }
    }

    func stop() {
        silenceTask?.cancel()
        silenceTask = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        isFinishing = false
        tearDownEngine(cancelRecognition: true)
        isListening = false
    }

    private func start(
        currentText: String,
        language: AppPreferences.DictationLanguage,
        onUpdate: @escaping (String) -> Void,
        onActivity: @escaping () -> Void,
        onComplete: @escaping (String) -> Void
    ) async {
        lastError = nil
        stop()

        guard let recognizer = resolveRecognizer(language: language) else {
            lastError = "No speech locale available. Pick another language in Settings › General."
            return
        }
        self.recognizer = recognizer
        activeLocaleID = recognizer.locale.identifier

        let speechOK = await requestSpeechAuth()
        guard speechOK else {
            lastError = "Allow Speech Recognition for Beacon in System Settings › Privacy."
            return
        }

        let micOK = await requestMicAuth()
        guard micOK else {
            lastError = "Allow Microphone access for Beacon in System Settings › Privacy."
            return
        }

        // Warm up recognizer (helps first utterance accuracy).
        _ = recognizer.isAvailable

        self.onUpdate = onUpdate
        self.onActivity = onActivity
        self.onComplete = onComplete
        baseText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastCombined = baseText
        lastSpoken = ""
        lastTranscriptChange = Date()
        isFinishing = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Cloud recognition is usually much more accurate than on-device.
        request.requiresOnDeviceRecognition = false
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = [
            "Beacon",
            "Ollama",
            "OpenAI",
            "Claude",
            "Gemini",
            "SwiftUI",
            "macOS",
        ]
        self.request = request

        let input = audioEngine.inputNode
        // Prefer hardware input format; fall back to output format.
        var format = input.inputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount == 0 {
            format = input.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = "No microphone input available."
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            lastError = error.localizedDescription
            return
        }

        isListening = true
        onActivity()
        startSilenceWatcher()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.isListening || self.isFinishing else { return }

                if let result {
                    let spoken = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let combined: String
                    if self.baseText.isEmpty {
                        combined = spoken
                    } else if spoken.isEmpty {
                        combined = self.baseText
                    } else {
                        combined = self.baseText + " " + spoken
                    }

                    if spoken != self.lastSpoken {
                        self.lastSpoken = spoken
                        self.lastTranscriptChange = Date()
                    }
                    self.lastCombined = combined
                    self.onUpdate?(combined)
                    self.onActivity?()

                    if result.isFinal {
                        self.deliverFinal()
                        return
                    }
                }

                if let error {
                    let code = (error as NSError).code
                    if code == 216 { return } // canceled
                    if self.isFinishing, self.lastSpoken.count >= self.minSpokenCharacters {
                        self.deliverFinal()
                        return
                    }
                    if self.isListening, self.lastSpoken.count < self.minSpokenCharacters {
                        self.lastError = self.friendlySpeechError(error)
                        self.stop()
                    } else if self.lastSpoken.count >= self.minSpokenCharacters {
                        self.deliverFinal()
                    } else {
                        self.stop()
                    }
                }
            }
        }
    }

    private func startSilenceWatcher() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, self.isListening, !self.isFinishing else { return }

                let spoken = self.lastSpoken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard spoken.count >= self.minSpokenCharacters else { continue }

                let quietFor = Date().timeIntervalSince(self.lastTranscriptChange)
                if quietFor >= self.silenceTimeout {
                    self.beginFinalize()
                    return
                }
            }
        }
    }

    /// Stop capturing and ask Apple for a final transcript pass, then send.
    private func beginFinalize() {
        guard isListening, !isFinishing else { return }
        isFinishing = true
        silenceTask?.cancel()
        silenceTask = nil

        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard let self, !Task.isCancelled else { return }
            // If isFinal never arrived, send best partial we have.
            self.deliverFinal()
        }
    }

    private func deliverFinal() {
        finalizeTask?.cancel()
        finalizeTask = nil
        silenceTask?.cancel()
        silenceTask = nil

        let text = lastCombined.trimmingCharacters(in: .whitespacesAndNewlines)
        let complete = onComplete

        tearDownEngine(cancelRecognition: true)
        isListening = false
        isFinishing = false
        onUpdate = nil
        onActivity = nil
        onComplete = nil

        guard !text.isEmpty else { return }
        complete?(text)
    }

    private func tearDownEngine(cancelRecognition: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        if cancelRecognition {
            request?.endAudio()
            task?.cancel()
            task = nil
            request = nil
        }
    }

    /// Pick the best available recognizer for the chosen language.
    private func resolveRecognizer(language: AppPreferences.DictationLanguage) -> SFSpeechRecognizer? {
        func make(_ id: String) -> SFSpeechRecognizer? {
            let normalized = id.replacingOccurrences(of: "_", with: "-")
            return SFSpeechRecognizer(locale: Locale(identifier: normalized))
        }

        if let forced = language.localeIdentifier {
            if let r = make(forced), r.isAvailable { return r }
            if let r = make(forced) { return r }
            let prefix = String(forced.prefix(2)).lowercased()
            if let match = SFSpeechRecognizer.supportedLocales().first(where: {
                $0.identifier.lowercased().replacingOccurrences(of: "_", with: "-").hasPrefix(prefix)
            }) {
                return SFSpeechRecognizer(locale: match)
            }
        }

        // Auto: preferred languages, then Spanish, then English, then current.
        var candidates: [String] = Locale.preferredLanguages
        candidates.append(contentsOf: ["es-MX", "es-ES", "es-US", "en-US", Locale.current.identifier])

        var seen = Set<String>()
        for raw in candidates {
            let id = raw.replacingOccurrences(of: "_", with: "-")
            if seen.contains(id) { continue }
            seen.insert(id)
            if let r = make(id), r.isAvailable { return r }
        }

        return SFSpeechRecognizer()
    }
    private func friendlySpeechError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "kAFAssistantErrorDomain" || ns.domain.contains("Speech") {
            return "Couldn’t hear clearly — try again closer to the mic, or set the dictation language in Settings."
        }
        return error.localizedDescription
    }

    private func requestSpeechAuth() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    cont.resume(returning: newStatus == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestMicAuth() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }
}
