//
//  ContentView.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import SwiftUI
import AVFoundation
import Combine
import ScreenCaptureKit
import UniformTypeIdentifiers
import AppKit

// Models are now in Models/TranscriptSegment.swift

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)
}

// MARK: - Editable Speaker Label

struct EditableSpeakerLabel: View {
    let emoji: String
    @Binding var label: String
    @Binding var isEditing: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)

            if isEditing {
                TextField("Name", text: $label)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($isFocused)
                    .onSubmit {
                        isEditing = false
                    }
                    .onAppear {
                        isFocused = true
                    }
                    .onChange(of: isFocused) { _, newValue in
                        if !newValue {
                            isEditing = false
                        }
                    }
            } else {
                Text(label)
                    .font(.headline)
                    .onTapGesture {
                        isEditing = true
                    }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Segment Row View

struct SegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("[\(segment.formattedTime)]")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(segment.text)
                .font(.body)
                .opacity(segment.isFinal ? 1.0 : 0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chat-style message bubble for combined transcript view
struct ChatBubble: View {
    let segment: TranscriptSegment
    let micLabel: String
    let systemLabel: String

    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.8

    private var speakerLabel: String {
        switch segment.source {
        case .mic: return micLabel
        case .system: return systemLabel
        case .interviewer: return segment.source.defaultLabel  // "Interviewer"
        }
    }

    private var speakerEmoji: String { segment.source.emoji }

    private var accentColor: Color {
        switch segment.source {
        case .mic: return .blue
        case .system: return .green
        case .interviewer: return .purple
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Speaker indicator
            Text(speakerEmoji)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                // Speaker name and timestamp
                HStack(spacing: 6) {
                    Text(speakerLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)

                    Text("[\(segment.formattedTime)]")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                // Message text
                Text(segment.text)
                    .font(.body)
                    .opacity(segment.isFinal ? 1.0 : 0.8)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(accentColor.opacity(backgroundOpacity))
        .cornerRadius(8)
    }
}

// MARK: - App State

enum AppState: Equatable {
    case setup
    case meeting
    case importing
    case summary
    case history
    case reviewMeeting(String)  // Meeting ID
}

// MARK: - Suggestion Manager

@MainActor
class SuggestionManager: ObservableObject {
    @Published var suggestions: [Suggestion] = []
    @Published var currentSuggestion: String = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var pendingQuestion: String?  // Question being asked for current suggestion

    // Mock interview state
    @Published var isMockInterviewActive = false
    @Published var mockInterviewHistory: [(role: String, content: String)] = []
    @Published var currentQuestion: String = ""
    @Published var feedbackPending = false

    // Callback for interviewer responses (to add to transcript)
    var onInterviewerResponse: ((String) -> Void)?

    private var claudeClient: ClaudeClient?
    private var claudeApiKey = ""
    private var lastTranscriptLength = 0
    private var silenceTimer: Timer?

    func setApiKey(_ key: String) {
        claudeApiKey = key
        claudeClient = ClaudeClient(apiKey: key)
        setupCallbacks()
    }

    private func setupCallbacks() {
        claudeClient?.onTextDelta = { [weak self] text in
            print("[Claude] onTextDelta: \(text.prefix(50))...")
            self?.currentSuggestion += text
        }

        claudeClient?.onComplete = { [weak self] fullText in
            guard let self = self else { return }
            print("[Claude] onComplete: \(fullText.prefix(100))...")
            print("[Claude] isMockInterviewActive: \(self.isMockInterviewActive)")
            self.isLoading = false

            if self.isMockInterviewActive {
                // In mock interview, add response to transcript (not suggestions)
                print("[MockInterview] Adding interviewer response to transcript")
                self.currentQuestion = fullText
                self.mockInterviewHistory.append((role: "assistant", content: fullText))
                self.feedbackPending = false
                self.onInterviewerResponse?(fullText)
                self.currentSuggestion = ""
            } else {
                // Normal mode: create and add suggestion
                let suggestion = Suggestion(text: fullText, triggerText: self.pendingQuestion)
                self.suggestions.insert(suggestion, at: 0)
                self.currentSuggestion = ""
                self.pendingQuestion = nil
            }
        }

        claudeClient?.onError = { [weak self] errorMsg in
            print("[Claude] onError: \(errorMsg)")
            self?.isLoading = false
            self?.error = errorMsg
            self?.currentSuggestion = ""
        }
    }

    func requestSuggestion(mode: MeetingMode, transcript: String, context: String?, detectedQuestion: String? = nil) {
        guard !claudeApiKey.isEmpty else {
            error = "Claude API key not set"
            return
        }

        isLoading = true
        error = nil
        currentSuggestion = ""
        pendingQuestion = detectedQuestion

        claudeClient?.generateSuggestion(
            systemPrompt: mode.systemPrompt,
            transcript: transcript,
            contextDocument: context
        )
    }

    /// Detect the most recent question from transcript text
    func detectQuestion(from transcript: String) -> String? {
        // Split into sentences and find the last question
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Look for the last sentence that looks like a question
        for sentence in sentences.reversed() {
            let lower = sentence.lowercased()
            // Check for question indicators
            if lower.contains("?") ||
               lower.hasPrefix("what ") ||
               lower.hasPrefix("how ") ||
               lower.hasPrefix("why ") ||
               lower.hasPrefix("when ") ||
               lower.hasPrefix("where ") ||
               lower.hasPrefix("who ") ||
               lower.hasPrefix("can you ") ||
               lower.hasPrefix("could you ") ||
               lower.hasPrefix("tell me ") ||
               lower.hasPrefix("describe ") ||
               lower.hasPrefix("explain ") {
                return sentence + (sentence.hasSuffix("?") ? "" : "?")
            }
        }
        return nil
    }

    // MARK: - Mock Interview Methods

    func startMockInterview(context: String?) {
        print("[MockInterview] startMockInterview called")
        guard !claudeApiKey.isEmpty else {
            print("[MockInterview] ERROR: Claude API key is empty")
            error = "Claude API key not set"
            return
        }
        print("[MockInterview] API key present: \(claudeApiKey.prefix(8))...")

        // Verify client exists
        guard claudeClient != nil else {
            print("[MockInterview] ERROR: claudeClient is nil")
            error = "Mock interview not ready - please wait and try again"
            return
        }

        // Verify callbacks are set (re-set if needed)
        if claudeClient?.onComplete == nil {
            print("[MockInterview] WARNING: callbacks not set, re-setting...")
            setupCallbacks()
        }

        isMockInterviewActive = true
        mockInterviewHistory = []
        currentQuestion = ""
        feedbackPending = false
        lastTranscriptLength = 0

        // Initial message to start the interview
        var initialMessage = "Start the mock interview. Ask the first question."
        if let context = context, !context.isEmpty {
            initialMessage = "Here is context about the role/company:\n\(context)\n\nStart the mock interview. Ask the first question."
        }

        mockInterviewHistory.append((role: "user", content: initialMessage))
        print("[MockInterview] History: \(mockInterviewHistory.count) messages")

        isLoading = true
        error = nil
        currentSuggestion = ""

        print("[MockInterview] Calling generateInterviewQuestion...")
        claudeClient?.generateInterviewQuestion(
            systemPrompt: MeetingMode.mockInterview.systemPrompt,
            conversationHistory: mockInterviewHistory
        )
        print("[MockInterview] generateInterviewQuestion called (claudeClient nil? \(claudeClient == nil))")

        // Add timeout for loading state
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self,
                  self.isLoading,
                  self.isMockInterviewActive,
                  self.currentQuestion.isEmpty else { return }
            print("[MockInterview] TIMEOUT: No response after 15 seconds")
            self.isLoading = false
            self.error = "Mock interview timed out - please try again"
        }
    }

    func submitAnswer(transcript: String) {
        guard isMockInterviewActive, !claudeApiKey.isEmpty else { return }

        // Add user's answer to history
        mockInterviewHistory.append((role: "user", content: transcript))
        feedbackPending = true

        isLoading = true
        error = nil
        currentSuggestion = ""

        // Request feedback and next question
        claudeClient?.generateInterviewQuestion(
            systemPrompt: MeetingMode.mockInterview.systemPrompt,
            conversationHistory: mockInterviewHistory
        )
    }

    func checkForAnswerCompletion(transcript: String) {
        // Detect when user has finished speaking (silence detection based on transcript)
        let currentLength = transcript.count

        if currentLength > lastTranscriptLength {
            // User is still speaking, reset timer
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self,
                          self.isMockInterviewActive,
                          !self.feedbackPending,
                          !self.isLoading,
                          transcript.count > (self.lastTranscriptLength + 20) else { return }

                    // User has been silent for 3 seconds and added significant text
                    self.submitAnswer(transcript: transcript)
                    self.lastTranscriptLength = transcript.count
                }
            }
        }

        lastTranscriptLength = currentLength
    }

    func stopMockInterview() {
        isMockInterviewActive = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        feedbackPending = false
    }

    func dismissSuggestion(_ suggestion: Suggestion) {
        if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
            suggestions[index].isDismissed = true
        }
    }

    func pinSuggestion(_ suggestion: Suggestion) {
        if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
            suggestions[index].isPinned.toggle()
        }
    }

    func cancel() {
        claudeClient?.cancel()
        isLoading = false
        currentSuggestion = ""
    }
}

// SuggestionCard is now in Views/SuggestionCard.swift

// MARK: - Meeting Setup View

struct MeetingSetupView: View {
    @Binding var meeting: Meeting
    @Binding var deepgramApiKey: String
    @Binding var claudeApiKey: String
    let onStart: () -> Void
    let onImport: (URL) -> Void

    @State private var showApiKeyFields = false
    @State private var contextFiles: [(name: String, content: String)] = []
    @State private var showFileImporter = false
    @State private var showAudioImporter = false
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.8

    var body: some View {
        VStack(spacing: 24) {
            Text("MeetingMind")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Mode selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting Type")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(MeetingMode.allCases, id: \.self) { mode in
                        Button {
                            meeting.mode = mode
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(.title2)
                                Text(mode.rawValue)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(meeting.mode == mode ? Color.accentColor : Color.clear)
                            .foregroundColor(meeting.mode == mode ? .white : .primary)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(10)

                Text(meeting.mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Meeting title
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting Title (optional)")
                    .font(.headline)

                TextField("e.g., Interview with Acme Corp", text: $meeting.title)
                    .textFieldStyle(.roundedBorder)
            }

            // Context document
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Context (optional)")
                        .font(.headline)

                    Spacer()

                    Button {
                        showFileImporter = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.badge.plus")
                            Text("Import File")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !contextFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(contextFiles.enumerated()), id: \.offset) { index, file in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.accentColor)
                                Text(file.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button {
                                    contextFiles.remove(at: index)
                                    updateCombinedContext()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if contextFiles.count > 1 {
                            Button("Clear All") {
                                contextFiles.removeAll()
                                meeting.contextDocument = nil
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.8))
                    .cornerRadius(6)
                }

                TextEditor(text: Binding(
                    get: { meeting.contextDocument ?? "" },
                    set: { meeting.contextDocument = $0.isEmpty ? nil : $0 }
                ))
                .font(.body)
                .frame(height: 100)
                .border(Color.gray.opacity(0.8))
                .cornerRadius(4)

                Text("Paste company info, job description, or talking points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // API Keys section
            if showApiKeyFields || deepgramApiKey.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("API Keys")
                            .font(.headline)

                        Spacer()

                        if !deepgramApiKey.isEmpty {
                            Button("Save Keys") {
                                saveApiKeys()
                                showApiKeyFields = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deepgram (required)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("Deepgram API Key", text: $deepgramApiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anthropic Claude (optional, for AI suggestions)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("Claude API Key", text: $claudeApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("API keys saved")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Change API Keys") {
                        showApiKeyFields = true
                    }
                    .buttonStyle(.link)
                }
            }

            // Start / Import buttons
            HStack(spacing: 12) {
                Button(action: {
                    saveApiKeys()
                    onStart()
                }) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Start Meeting")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(deepgramApiKey.isEmpty)

                Button(action: {
                    saveApiKeys()
                    showAudioImporter = true
                }) {
                    HStack {
                        Image(systemName: "doc.badge.arrow.up")
                        Text("Import Recording")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(deepgramApiKey.isEmpty)
            }
        }
        .padding(30)
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(NSColor.controlBackgroundColor).opacity(backgroundOpacity))
        .onAppear {
            loadApiKeys()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .pdf, .rtf, .html],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio, .mpeg4Movie, .movie, .wav, .mp3],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    saveApiKeys()
                    onImport(url)
                }
            case .failure(let error):
                print("Audio file selection failed: \(error)")
            }
        }
    }

    private func updateCombinedContext() {
        if contextFiles.isEmpty {
            meeting.contextDocument = nil
        } else if contextFiles.count == 1 {
            meeting.contextDocument = contextFiles[0].content
        } else {
            // Combine multiple files with headers
            var combined = ""
            for file in contextFiles {
                combined += "--- \(file.name) ---\n\n"
                combined += file.content
                combined += "\n\n"
            }
            meeting.contextDocument = combined
        }
    }

    private func loadApiKeys() {
        // First check Keychain
        if deepgramApiKey.isEmpty, let savedKey = KeychainManager.shared.get(type: .deepgram) {
            deepgramApiKey = savedKey
        }
        if claudeApiKey.isEmpty, let savedKey = KeychainManager.shared.get(type: .claude) {
            claudeApiKey = savedKey
        }

        // Fall back to environment variables
        if deepgramApiKey.isEmpty, let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], !envKey.isEmpty {
            deepgramApiKey = envKey
        }
        if claudeApiKey.isEmpty, let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            claudeApiKey = envKey
        }
    }

    private func saveApiKeys() {
        if !deepgramApiKey.isEmpty {
            _ = KeychainManager.shared.save(key: deepgramApiKey, type: .deepgram)
        }
        if !claudeApiKey.isEmpty {
            _ = KeychainManager.shared.save(key: claudeApiKey, type: .claude)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    print("Failed to access file: \(url)")
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    contextFiles.append((name: url.lastPathComponent, content: content))
                } catch {
                    print("Failed to read file: \(error)")
                    // Try alternative encoding
                    if let content = try? String(contentsOf: url, encoding: .ascii) {
                        contextFiles.append((name: url.lastPathComponent, content: content))
                    }
                }
            }
            updateCombinedContext()

        case .failure(let error):
            print("File import error: \(error)")
        }
    }
}

// MARK: - Connection Diagnostics

struct ConnectionDiagnostics {
    var messagesReceived: Int = 0
    var errorsCount: Int = 0
    var lastMessageTime: Date?
    var connectionAttempts: Int = 0

    var errorRate: Double {
        guard messagesReceived > 0 else { return 0 }
        return Double(errorsCount) / Double(messagesReceived + errorsCount)
    }

    var isHealthy: Bool {
        errorRate < 0.1
    }

    var secondsSinceLastMessage: TimeInterval? {
        guard let last = lastMessageTime else { return nil }
        return Date().timeIntervalSince(last)
    }
}

// MARK: - Main View

struct ContentView: View {
    @EnvironmentObject var windowManager: WindowManager
    @StateObject private var transcriber = MeetingTranscriber()
    @StateObject private var suggestionManager = SuggestionManager()
    @StateObject private var batchService = DeepgramBatchService()
    @State private var apiKey: String = ""
    @State private var claudeApiKey: String = ""
    @State private var appState: AppState = .setup
    @State private var currentMeeting = Meeting()
    @State private var showDiagnostics = false
    @State private var showSuggestions = true
    @State private var editingMicLabel = false
    @State private var editingSystemLabel = false
    @State private var dividerPosition: CGFloat = 0.45  // 45% transcript, 55% suggestions
    @State private var showSettings = false
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.8

    var body: some View {
        mainContentView
    }

    @ViewBuilder
    private var mainContentView: some View {
        switch appState {
        case .setup:
            MeetingSetupView(
                meeting: $currentMeeting,
                deepgramApiKey: $apiKey,
                claudeApiKey: $claudeApiKey,
                onStart: startMeeting,
                onImport: importRecording
            )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        appState = .history
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help("Meeting History")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(backgroundOpacity: $backgroundOpacity)
            }

        case .meeting:
            meetingView

        case .importing:
            importingView

        case .summary:
            summaryView

        case .history:
            MeetingHistoryView(
                onSelect: { meetingId in
                    appState = .reviewMeeting(meetingId)
                },
                onNewMeeting: {
                    newMeeting()
                },
                onBack: {
                    appState = .setup
                }
            )

        case .reviewMeeting(let meetingId):
            MeetingReviewView(
                meetingId: meetingId,
                onBack: {
                    appState = .history
                }
            )
        }
    }

    private func startMeeting() {
        currentMeeting.startTime = Date()
        transcriber.setApiKey(apiKey)
        transcriber.currentMeeting = currentMeeting
        transcriber.startListening()

        // Configure Claude if API key provided
        if !claudeApiKey.isEmpty {
            suggestionManager.setApiKey(claudeApiKey)

            // Wire up interviewer response callback for mock interviews
            suggestionManager.onInterviewerResponse = { [weak transcriber] text in
                Task { @MainActor in
                    transcriber?.addInterviewerSegment(text: text)
                }
            }
        }

        appState = .meeting
    }

    private func endMeeting() {
        transcriber.stopListening()
        currentMeeting.endTime = Date()

        // Save meeting to storage
        let saved = StorageService.shared.saveMeeting(
            currentMeeting,
            micSegments: transcriber.micSegments,
            systemSegments: transcriber.systemSegments,
            suggestions: suggestionManager.suggestions,
            micLabel: transcriber.micSpeakerLabel,
            systemLabel: transcriber.systemSpeakerLabel
        )

        if !saved {
            print("Warning: Failed to save meeting to storage")
        }

        appState = .summary
    }

    private func newMeeting() {
        transcriber.clearTranscripts()
        currentMeeting = Meeting()
        appState = .setup
    }

    private func importRecording(url: URL) {
        currentMeeting.startTime = Date()
        transcriber.clearTranscripts()
        appState = .importing

        Task {
            do {
                let result = try await batchService.transcribeFile(url: url, apiKey: apiKey)

                // Populate transcriber with imported segments
                transcriber.micSegments = result.micSegments
                transcriber.systemSegments = result.systemSegments

                // Set speaker labels from diarization
                if let label0 = result.speakerLabels[0] {
                    transcriber.micSpeakerLabel = label0
                }
                if let label1 = result.speakerLabels[1] {
                    transcriber.systemSpeakerLabel = label1
                }

                // Finalize meeting
                currentMeeting.endTime = Date()

                let saved = StorageService.shared.saveMeeting(
                    currentMeeting,
                    micSegments: transcriber.micSegments,
                    systemSegments: transcriber.systemSegments,
                    suggestions: [],
                    micLabel: transcriber.micSpeakerLabel,
                    systemLabel: transcriber.systemSpeakerLabel
                )

                if !saved {
                    print("Warning: Failed to save imported meeting to storage")
                }

                appState = .summary
            } catch {
                batchService.error = error.localizedDescription
            }
        }
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if batchService.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }

            Text(batchService.error != nil ? "Import Failed" : "Transcribing Recording...")
                .font(.title2)
                .fontWeight(.semibold)

            Text(batchService.error ?? batchService.status)
                .font(.body)
                .foregroundColor(batchService.error != nil ? .red : .secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if batchService.error != nil {
                Button("Back to Setup") {
                    batchService.error = nil
                    newMeeting()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.controlBackgroundColor).opacity(backgroundOpacity))
    }

    // MARK: - Meeting View

    private var meetingView: some View {
        VStack(spacing: 0) {
            // Fixed header section
            VStack(spacing: 12) {
                // Header with mode badge
                HStack {
                    Text("MeetingMind")
                        .font(.title)
                        .fontWeight(.bold)

                    Spacer()

                    // Mock interview controls
                    if currentMeeting.mode == .mockInterview && !claudeApiKey.isEmpty {
                        if suggestionManager.isMockInterviewActive {
                            Button("End Practice") {
                                suggestionManager.stopMockInterview()
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        } else {
                            Button("Start Practice") {
                                suggestionManager.startMockInterview(context: currentMeeting.contextDocument)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    // Mode badge
                    HStack(spacing: 4) {
                        Image(systemName: currentMeeting.mode.icon)
                        Text(currentMeeting.mode.rawValue)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.8))
                    .cornerRadius(8)
                }

                // Status with connection states + Controls
                HStack(spacing: 16) {
                    HStack {
                        Circle()
                            .fill(transcriber.isListening ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                        Text(transcriber.isListening ? "Listening" : "Stopped")
                            .font(.caption)
                    }

                    if transcriber.isListening {
                        HStack(spacing: 6) {
                            connectionBadge(label: "Mic", state: transcriber.micState)
                            connectionBadge(label: "Sys", state: transcriber.systemState)
                        }
                        .font(.caption2)
                    }

                    Spacer()

                    // Controls inline
                    Button(transcriber.isListening ? "Pause" : "Resume") {
                        if transcriber.isListening {
                            transcriber.stopListening()
                        } else {
                            transcriber.startListening()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("End Meeting") {
                        endMeeting()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)

                    if !claudeApiKey.isEmpty {
                        Button {
                            requestSuggestion()
                        } label: {
                            HStack(spacing: 4) {
                                if suggestionManager.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text("Suggest")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(suggestionManager.isLoading || transcriber.micTranscript.isEmpty && transcriber.systemTranscript.isEmpty)
                        .keyboardShortcut(" ", modifiers: .command)
                    }

                    Button("Copy") {
                        copyTranscriptToClipboard()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(transcriber.micSegments.isEmpty && transcriber.systemSegments.isEmpty)

                    Button(showDiagnostics ? "Debug" : "Debug") {
                        showDiagnostics.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Settings")
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Resizable content area (transcript + suggestions)
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Transcript section
                    transcriptSection
                        .frame(height: geo.size.height * dividerPosition)

                    // Draggable divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.8))
                        .frame(height: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.8))
                                .frame(width: 40, height: 4)
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newPos = (geo.size.height * dividerPosition + value.translation.height) / geo.size.height
                                    dividerPosition = max(0.15, min(0.85, newPos))
                                }
                        )
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeUpDown.push()
                            } else {
                                NSCursor.pop()
                            }
                        }

                    // Suggestions section (fills remaining space)
                    suggestionSection
                }
            }
            .padding(.horizontal, 20)

            // Footer (status + diagnostics)
            VStack(spacing: 8) {
                // Error display
                if let error = transcriber.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                // Status row
                HStack {
                    Text("Mic: \(transcriber.micStatus)")
                        .font(.caption2)
                    Text("·")
                    Text("Screen: \(transcriber.screenStatus)")
                        .font(.caption2)
                    Spacer()
                }
                .foregroundColor(.secondary)

                // Diagnostics panel
                if showDiagnostics {
                    diagnosticsPanel
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 700, minHeight: 550)
        .background(Color(NSColor.controlBackgroundColor).opacity(backgroundOpacity))
        .sheet(isPresented: $showSettings) {
            SettingsView(backgroundOpacity: $backgroundOpacity)
        }
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Speaker labels header
            HStack {
                EditableSpeakerLabel(
                    emoji: "🎤",
                    label: $transcriber.micSpeakerLabel,
                    isEditing: $editingMicLabel
                )

                Text("·")
                    .foregroundColor(.secondary)

                EditableSpeakerLabel(
                    emoji: "🔊",
                    label: $transcriber.systemSpeakerLabel,
                    isEditing: $editingSystemLabel
                )

                Spacer()
            }
            .padding(.horizontal, 8)

            // Combined transcript (merged and sorted by time)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        let combined = (transcriber.micSegments + transcriber.systemSegments)
                            .sorted { $0.startTime < $1.startTime }

                        if combined.isEmpty {
                            Text("Waiting for speech...")
                                .foregroundColor(.secondary)
                                .padding(12)
                        } else {
                            ForEach(combined) { segment in
                                ChatBubble(
                                    segment: segment,
                                    micLabel: transcriber.micSpeakerLabel,
                                    systemLabel: transcriber.systemSpeakerLabel
                                )
                                .id(segment.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: transcriber.micSegments.count + transcriber.systemSegments.count) { _, _ in
                    let combined = (transcriber.micSegments + transcriber.systemSegments)
                        .sorted { $0.startTime < $1.startTime }
                    if let last = combined.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.8))
            .cornerRadius(8)
        }
    }

    // MARK: - Suggestion Section

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // AI Suggestions (when available)
            if !claudeApiKey.isEmpty && (!suggestionManager.suggestions.isEmpty || !suggestionManager.currentSuggestion.isEmpty) {
                suggestionPanel
            } else if claudeApiKey.isEmpty {
                // Placeholder when no Claude API key
                VStack {
                    Spacer()
                    Text("Add Claude API key for AI suggestions")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
            } else {
                // Placeholder when no suggestions yet
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundColor(.secondary.opacity(0.8))
                        Text("Press ⌘ Space or click \"Suggest\" for AI coaching")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Summary View

    private var summaryView: some View {
        VStack(spacing: 24) {
            Text("Meeting Complete")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Meeting info
            VStack(spacing: 8) {
                if !currentMeeting.title.isEmpty {
                    Text(currentMeeting.title)
                        .font(.title2)
                }

                HStack {
                    Image(systemName: currentMeeting.mode.icon)
                    Text(currentMeeting.mode.rawValue)
                }
                .foregroundColor(.secondary)

                if let duration = currentMeeting.formattedDuration {
                    Text("Duration: \(duration)")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Transcript preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript")
                    .font(.headline)

                ScrollView {
                    Text(generateMarkdown())
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor).opacity(0.8))
                .cornerRadius(8)
            }

            // Actions
            HStack(spacing: 16) {
                Button("Copy Transcript") {
                    copyTranscriptToClipboard()
                }
                .buttonStyle(.bordered)

                Button("Save Transcript") {
                    saveTranscript()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("New Meeting") {
                    newMeeting()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor).opacity(backgroundOpacity))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(backgroundOpacity: $backgroundOpacity)
        }
    }

    // MARK: - Mock Interview Panel

    @ViewBuilder
    private var mockInterviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mic.badge.plus")
                    .foregroundColor(.accentColor)
                Text("Mock Interview")
                    .font(.headline)

                Spacer()

                if suggestionManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if suggestionManager.feedbackPending {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .foregroundColor(.orange)
                        Text("Listening...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Current question/feedback
            if !suggestionManager.currentQuestion.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interviewer:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(suggestionManager.currentQuestion)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.8))
                        .cornerRadius(8)
                }
            }

            // Streaming response
            if !suggestionManager.currentSuggestion.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Generating response...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(suggestionManager.currentSuggestion)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.8))
                        .cornerRadius(8)
                }
            }

            // Manual submit button (if auto-detection doesn't work well)
            if !suggestionManager.isLoading && !suggestionManager.feedbackPending && !transcriber.micTranscript.isEmpty {
                Button {
                    suggestionManager.submitAnswer(transcript: transcriber.micTranscript)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Submit Answer")
                    }
                }
                .buttonStyle(.bordered)
            }

            // Instructions
            Text("Answer the question out loud. Your response will be transcribed and evaluated.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .onChange(of: transcriber.micTranscript) { _, newValue in
            if suggestionManager.isMockInterviewActive {
                suggestionManager.checkForAnswerCompletion(transcript: newValue)
            }
        }
    }

    // MARK: - Suggestion Panel

    @ViewBuilder
    private var suggestionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("AI Suggestions")
                    .font(.headline)

                Spacer()

                // Overlay mode toggle (Interview mode feature)
                if currentMeeting.mode == .interview {
                    Button {
                        if windowManager.isInvisibleToScreenShare {
                            windowManager.disableInterviewMode()
                        } else {
                            windowManager.enableInterviewMode()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: windowManager.isInvisibleToScreenShare ? "eye.slash.fill" : "eye.fill")
                            Text(windowManager.isInvisibleToScreenShare ? "Hidden" : "Visible")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(windowManager.isInvisibleToScreenShare ? .green : .secondary)
                    .help(windowManager.isInvisibleToScreenShare
                          ? "App is invisible to screen share"
                          : "Click to hide from screen share")
                }

                if suggestionManager.isLoading {
                    Button("Cancel") {
                        suggestionManager.cancel()
                    }
                    .buttonStyle(.link)
                }
            }

            // Current streaming suggestion (uses new StreamingSuggestionCard)
            if !suggestionManager.currentSuggestion.isEmpty {
                StreamingSuggestionCard(
                    text: suggestionManager.currentSuggestion,
                    question: suggestionManager.pendingQuestion
                )
            }

            // Error display
            if let error = suggestionManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Completed suggestions (using new SuggestionCard from Views/)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(suggestionManager.suggestions.filter { !$0.isDismissed || $0.isPinned }) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            onPin: { suggestionManager.pinSuggestion(suggestion) },
                            onDismiss: { suggestionManager.dismissSuggestion(suggestion) },
                            onCopy: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(suggestion.text, forType: .string)
                            }
                        )
                    }
                }
            }
            // No fixed height - expands to fill available space
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(10)
    }

    private func requestSuggestion() {
        let transcript = """
        \(transcriber.micSpeakerLabel): \(transcriber.micTranscript)

        \(transcriber.systemSpeakerLabel): \(transcriber.systemTranscript)
        """

        // Detect question from the system audio (interviewer's speech)
        let detectedQuestion = suggestionManager.detectQuestion(from: transcriber.systemTranscript)

        suggestionManager.requestSuggestion(
            mode: currentMeeting.mode,
            transcript: transcript,
            context: currentMeeting.contextDocument,
            detectedQuestion: detectedQuestion
        )
    }

    // MARK: - Export Functions

    private func generateMarkdown() -> String {
        var md = "# Meeting Transcript\n\n"

        // Add date
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        md += "**Date:** \(formatter.string(from: Date()))\n\n"
        md += "---\n\n"

        // Combine and sort all segments by time
        let allSegments = (transcriber.micSegments + transcriber.systemSegments)
            .filter(\.isFinal)
            .sorted { $0.startTime < $1.startTime }

        var currentSource: TranscriptSegment.Source?

        for segment in allSegments {
            // Add speaker header when source changes
            if segment.source != currentSource {
                currentSource = segment.source
                let label = segment.source == .mic ? transcriber.micSpeakerLabel : transcriber.systemSpeakerLabel
                md += "\n**\(label)**\n"
            }

            md += "[\(segment.formattedTime)] \(segment.text)\n"
        }

        return md
    }

    private func copyTranscriptToClipboard() {
        let markdown = generateMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func saveTranscript() {
        let markdown = generateMarkdown()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "meeting-transcript.md"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try markdown.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save transcript: \(error)")
                }
            }
        }
    }

    @ViewBuilder
    private func connectionBadge(label: String, state: ConnectionState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForState(state))
                .frame(width: 8, height: 8)
            Text(label)
            if case .reconnecting(let attempt) = state {
                Text("(\(attempt))")
                    .foregroundColor(.orange)
            }
        }
    }

    private func colorForState(_ state: ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .reconnecting: return .orange
        case .disconnected: return .gray
        case .failed: return .red
        }
    }

    @ViewBuilder
    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Mic Client")
                        .font(.caption.bold())
                    if let diag = transcriber.micDiagnostics {
                        Text("Messages: \(diag.messagesReceived)")
                        Text("Errors: \(diag.errorsCount)")
                        Text("Error rate: \(String(format: "%.1f%%", diag.errorRate * 100))")
                        if let secs = diag.secondsSinceLastMessage {
                            Text("Last msg: \(String(format: "%.1fs", secs)) ago")
                        }
                    } else {
                        Text("Not connected")
                    }
                }
                .font(.caption)

                VStack(alignment: .leading) {
                    Text("System Client")
                        .font(.caption.bold())
                    if let diag = transcriber.systemDiagnostics {
                        Text("Messages: \(diag.messagesReceived)")
                        Text("Errors: \(diag.errorsCount)")
                        Text("Error rate: \(String(format: "%.1f%%", diag.errorRate * 100))")
                        if let secs = diag.secondsSinceLastMessage {
                            Text("Last msg: \(String(format: "%.1fs", secs)) ago")
                        }
                    } else {
                        Text("Not connected")
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
    }
}

// MARK: - Meeting History View

struct MeetingHistoryView: View {
    let onSelect: (String) -> Void
    let onNewMeeting: () -> Void
    let onBack: () -> Void

    @State private var meetings: [MeetingSummary] = []
    @State private var showSettings = false
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.8

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Meeting History")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Button("New Meeting") {
                    onNewMeeting()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .help("Settings")
            }

            if meetings.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No meetings yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Your meeting history will appear here")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(meetings) { meeting in
                            MeetingHistoryRow(meeting: meeting) {
                                onSelect(meeting.id)
                            } onDelete: {
                                deleteMeeting(meeting.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(30)
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor).opacity(backgroundOpacity))
        .onAppear {
            loadMeetings()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(backgroundOpacity: $backgroundOpacity)
        }
    }

    private func loadMeetings() {
        meetings = StorageService.shared.getMeetings()
    }

    private func deleteMeeting(_ id: String) {
        _ = StorageService.shared.deleteMeeting(id: id)
        loadMeetings()
    }
}

struct MeetingHistoryRow: View {
    let meeting: MeetingSummary
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Mode icon
                Image(systemName: meeting.mode.icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 40)

                // Meeting info
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        // Date
                        let formatter = DateFormatter()
                        Text({
                            formatter.dateStyle = .medium
                            formatter.timeStyle = .short
                            return formatter.string(from: meeting.startTime)
                        }())
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Duration
                        if let duration = meeting.formattedDuration {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(duration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Segment count
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(meeting.segmentCount) segments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Delete button (visible on hover)
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(isHovering ? Color(NSColor.controlBackgroundColor).opacity(0.8) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Meeting Review View

struct MeetingReviewView: View {
    let meetingId: String
    let onBack: () -> Void

    @State private var meeting: Meeting?
    @State private var micSegments: [TranscriptSegment] = []
    @State private var systemSegments: [TranscriptSegment] = []
    @State private var suggestions: [Suggestion] = []
    @State private var micLabel = "You"
    @State private var systemLabel = "Others"
    @State private var showSettings = false
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.8

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let meeting = meeting {
                    VStack(spacing: 4) {
                        Text(meeting.title.isEmpty ? "Meeting Review" : meeting.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack(spacing: 8) {
                            Image(systemName: meeting.mode.icon)
                            Text(meeting.mode.rawValue)

                            if let duration = meeting.formattedDuration {
                                Text("•")
                                Text(duration)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Export buttons
                Button("Copy") {
                    copyToClipboard()
                }
                .buttonStyle(.bordered)

                Button("Export") {
                    exportTranscript()
                }
                .buttonStyle(.bordered)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .help("Settings")
            }

            if meeting == nil {
                Spacer()
                Text("Meeting not found")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                // Transcript display
                HStack(spacing: 12) {
                    // Mic transcript
                    VStack(alignment: .leading) {
                        HStack {
                            Text("🎤")
                            Text(micLabel)
                                .font(.headline)
                        }
                        .padding(.vertical, 2)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(micSegments) { segment in
                                    SegmentRow(segment: segment)
                                }
                            }
                            .padding(8)
                        }
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(8)
                    }

                    // System transcript
                    VStack(alignment: .leading) {
                        HStack {
                            Text("🔊")
                            Text(systemLabel)
                                .font(.headline)
                        }
                        .padding(.vertical, 2)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(systemSegments) { segment in
                                    SegmentRow(segment: segment)
                                }
                            }
                            .padding(8)
                        }
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(8)
                    }
                }

                // Suggestions (if any)
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Suggestions")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(suggestions.filter { $0.isPinned || !$0.isDismissed }) { suggestion in
                                    VStack(alignment: .leading, spacing: 4) {
                                        if suggestion.isPinned {
                                            HStack {
                                                Image(systemName: "pin.fill")
                                                    .foregroundColor(.orange)
                                                    .font(.caption)
                                                Text(suggestion.timestamp, style: .time)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Text(suggestion.text)
                                            .font(.caption)
                                            .lineLimit(4)
                                    }
                                    .padding(8)
                                    .frame(width: 200, alignment: .leading)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(30)
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor).opacity(backgroundOpacity))
        .onAppear {
            loadMeeting()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(backgroundOpacity: $backgroundOpacity)
        }
    }

    private func loadMeeting() {
        if let data = StorageService.shared.getMeeting(id: meetingId) {
            meeting = data.meeting
            micSegments = data.micSegments
            systemSegments = data.systemSegments
            suggestions = data.suggestions
            micLabel = data.micLabel
            systemLabel = data.systemLabel
        }
    }

    private func generateMarkdown() -> String {
        guard let meeting = meeting else { return "" }

        var md = "# Meeting Transcript\n\n"

        // Add meeting info
        if !meeting.title.isEmpty {
            md += "**Title:** \(meeting.title)\n"
        }
        md += "**Mode:** \(meeting.mode.rawValue)\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        md += "**Date:** \(formatter.string(from: meeting.startTime))\n"

        if let duration = meeting.formattedDuration {
            md += "**Duration:** \(duration)\n"
        }

        md += "\n---\n\n"

        // Combine and sort all segments by time
        let allSegments = (micSegments + systemSegments)
            .filter(\.isFinal)
            .sorted { $0.startTime < $1.startTime }

        var currentSource: TranscriptSegment.Source?

        for segment in allSegments {
            if segment.source != currentSource {
                currentSource = segment.source
                let label = segment.source == .mic ? micLabel : systemLabel
                md += "\n**\(label)**\n"
            }
            md += "[\(segment.formattedTime)] \(segment.text)\n"
        }

        // Add pinned suggestions
        let pinnedSuggestions = suggestions.filter(\.isPinned)
        if !pinnedSuggestions.isEmpty {
            md += "\n---\n\n## Pinned Suggestions\n\n"
            for suggestion in pinnedSuggestions {
                md += "- \(suggestion.text)\n"
            }
        }

        return md
    }

    private func copyToClipboard() {
        let markdown = generateMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func exportTranscript() {
        let markdown = generateMarkdown()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]

        let fileName = meeting?.title.isEmpty == false
            ? "\(meeting!.title).md"
            : "meeting-transcript.md"
        panel.nameFieldStringValue = fileName

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - Deepgram WebSocket Client (Enhanced)

class DeepgramClient {
    private var webSocket: URLSessionWebSocketTask?
    private let apiKey: String
    private let label: String

    // Callbacks - (text, isFinal, startTime, duration)
    var onSegment: ((String, Bool, Double?, Double?) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?
    var onError: ((String) -> Void)?

    // Connection management
    private var shouldAutoReconnect = true
    private var currentRetryAttempt = 0
    private let maxRetryAttempts = 10
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 30.0

    // Health monitoring
    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 15.0  // Was 30s, reduced for VPN stability
    private let staleThreshold: TimeInterval = 30.0     // Was 60s, reduced for faster detection

    // WebSocket keepalive ping
    private var pingTimer: Timer?
    private let pingInterval: TimeInterval = 10.0       // Send ping every 10 seconds

    // Diagnostics
    private(set) var diagnostics = ConnectionDiagnostics()
    private(set) var state: ConnectionState = .disconnected {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onStateChange?(self.state)
            }
        }
    }

    init(apiKey: String, label: String) {
        self.apiKey = apiKey
        self.label = label
    }

    func connect() {
        guard state != .connecting else { return }

        state = currentRetryAttempt > 0 ? .reconnecting(attempt: currentRetryAttempt) : .connecting
        diagnostics.connectionAttempts += 1

        let params = [
            "model=nova-3",
            "language=en",
            "smart_format=true",
            "interim_results=true",
            "utterance_end_ms=1000",
            "vad_events=true",
            "encoding=linear16",
            "sample_rate=16000",
            "channels=1"
        ].joined(separator: "&")

        guard let url = URL(string: "wss://api.deepgram.com/v1/listen?\(params)") else {
            state = .failed(reason: "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0  // Was 15s, increased for VPN

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()

        print("[\(label)] Connecting to Deepgram (attempt \(diagnostics.connectionAttempts))...")

        // Start receiving immediately
        receiveMessage()

        // Start heartbeat monitoring and keepalive pings
        startHeartbeat()
        startPingTimer()

        // Mark connected after short delay (WebSocket doesn't have explicit connected callback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, case .connecting = self.state else { return }
            self.state = .connected
            self.currentRetryAttempt = 0  // Reset on successful connect
            print("[\(self.label)] Connected")
        }
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.diagnostics.messagesReceived += 1
                self.diagnostics.lastMessageTime = Date()

                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                print("[\(self.label)] WebSocket error: \(error)")
                self.diagnostics.errorsCount += 1
                self.handleDisconnection(error: error.localizedDescription)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            diagnostics.errorsCount += 1
            return
        }

        // Use strongly-typed decoding
        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

            if let channel = response.channel,
               let alternatives = channel.alternatives,
               let first = alternatives.first,
               let transcript = first.transcript,
               !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let isFinal = response.is_final ?? false
                let startTime = response.start
                let duration = response.duration
                DispatchQueue.main.async {
                    self.onSegment?(transcript, isFinal, startTime, duration)
                }
            }
        } catch {
            // Not all messages are transcripts (metadata, VAD events, etc.)
            // Only count as error if it looks like it should be a transcript
            if text.contains("\"transcript\"") {
                diagnostics.errorsCount += 1
                print("[\(label)] Parse error: \(error)")
            }
        }
    }

    func sendAudio(_ data: Data) {
        guard case .connected = state else { return }

        webSocket?.send(.data(data)) { [weak self] error in
            if let error = error {
                print("[\(self?.label ?? "?")] Send error: \(error)")
                self?.diagnostics.errorsCount += 1
            }
        }
    }

    func disconnect() {
        shouldAutoReconnect = false
        stopHeartbeat()
        stopPingTimer()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        state = .disconnected
        print("[\(label)] Disconnected")
    }

    // MARK: - Reconnection with Exponential Backoff + Jitter

    private func handleDisconnection(error: String) {
        state = .disconnected
        stopHeartbeat()
        stopPingTimer()
        webSocket = nil

        guard shouldAutoReconnect, currentRetryAttempt < maxRetryAttempts else {
            if currentRetryAttempt >= maxRetryAttempts {
                state = .failed(reason: "Max reconnection attempts exceeded")
                onError?("Connection failed after \(maxRetryAttempts) attempts")
            }
            return
        }

        currentRetryAttempt += 1

        // Exponential backoff with jitter
        let delay = min(baseRetryDelay * pow(2.0, Double(currentRetryAttempt - 1)), maxRetryDelay)
        let jitter = Double.random(in: 0...0.1) * delay
        let finalDelay = delay + jitter

        print("[\(label)] Reconnecting in \(String(format: "%.1f", finalDelay))s (attempt \(currentRetryAttempt)/\(maxRetryAttempts))")
        state = .reconnecting(attempt: currentRetryAttempt)

        DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) { [weak self] in
            guard let self = self, self.shouldAutoReconnect else { return }
            self.connect()
        }
    }

    // MARK: - Heartbeat Monitoring

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.checkConnectionHealth()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - WebSocket Keepalive Ping

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        guard case .connected = state else { return }
        webSocket?.sendPing { [weak self] error in
            if let error = error {
                print("[\(self?.label ?? "Deepgram")] Ping failed: \(error)")
                self?.handleDisconnection(error: "Ping failed: \(error.localizedDescription)")
            } else {
                print("[\(self?.label ?? "Deepgram")] Ping successful")
            }
        }
    }

    private func checkConnectionHealth() {
        guard case .connected = state else { return }

        if let lastTime = diagnostics.lastMessageTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed > staleThreshold {
                print("[\(label)] Connection stale (\(String(format: "%.0f", elapsed))s since last message), reconnecting...")
                handleDisconnection(error: "Stale connection")
            }
        }
    }
}

// MARK: - Meeting Transcriber

@MainActor
class MeetingTranscriber: ObservableObject {
    // Segment-based transcripts
    @Published var micSegments: [TranscriptSegment] = []
    @Published var systemSegments: [TranscriptSegment] = []

    // Legacy string properties (computed from segments for backward compatibility)
    var micTranscript: String {
        micSegments.filter(\.isFinal).map(\.text).joined(separator: " ")
    }
    var systemTranscript: String {
        systemSegments.filter(\.isFinal).map(\.text).joined(separator: " ")
    }

    @Published var isListening = false
    @Published var error: String?
    @Published var micStatus = "Ready"
    @Published var screenStatus = "Ready"
    @Published var micState: ConnectionState = .disconnected
    @Published var systemState: ConnectionState = .disconnected
    @Published var micDiagnostics: ConnectionDiagnostics?
    @Published var systemDiagnostics: ConnectionDiagnostics?

    // Speaker labels (user-customizable)
    @Published var micSpeakerLabel: String = "You"
    @Published var systemSpeakerLabel: String = "Others"

    // Current meeting
    var currentMeeting: Meeting?

    // Meeting timing
    private var meetingStartTime: Date?

    private var apiKey = ""

    // Audio capture
    private var audioEngine: AVAudioEngine?
    private var scStream: SCStream?
    private var systemAudioHandler: SystemAudioHandler?

    // Deepgram clients
    private var micClient: DeepgramClient?
    private var systemClient: DeepgramClient?

    // Interim segment tracking (for in-progress speech)
    private var currentMicSegmentId: String?
    private var currentSystemSegmentId: String?

    // Diagnostics update timer
    private var diagnosticsTimer: Timer?

    func setApiKey(_ key: String) {
        print("[MeetingMind] setApiKey called with: \(key.prefix(8))...")
        self.apiKey = key
        print("[MeetingMind] apiKey is now: \(self.apiKey.prefix(8))...")
    }

    /// Add an interviewer response to the transcript (for mock interviews)
    func addInterviewerSegment(text: String) {
        let relativeStart = meetingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let segment = TranscriptSegment(
            id: UUID().uuidString,
            text: text,
            startTime: relativeStart,
            duration: nil,
            isFinal: true,
            source: .interviewer,
            speakerLabel: nil
        )
        systemSegments.append(segment)
        print("[MeetingMind] Added interviewer segment at \(relativeStart)s")
    }

    func startListening() {
        print("[MeetingMind] startListening called, apiKey length: \(apiKey.count)")
        guard !apiKey.isEmpty else {
            print("[MeetingMind] ERROR: apiKey is empty!")
            error = "API key not set"
            return
        }
        print("[MeetingMind] apiKey verified: \(apiKey.prefix(8))...")

        error = nil

        // Request mic permission
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.setupMicCapture()
                    self?.setupSystemCapture()
                    self?.startDiagnosticsUpdates()
                } else {
                    self?.error = "Microphone access denied"
                }
            }
        }
    }

    private func setupMicCapture() {
        do {
            let audioEngine = AVAudioEngine()
            self.audioEngine = audioEngine

            // Set meeting start time if not already set
            if meetingStartTime == nil {
                meetingStartTime = Date()
            }

            // Create Deepgram client for mic
            let client = DeepgramClient(apiKey: apiKey, label: "Mic")
            client.onSegment = { [weak self] text, isFinal, startTime, duration in
                guard let self = self else { return }

                // Calculate relative start time from meeting start
                let relativeStart: Double
                if let deepgramStart = startTime {
                    relativeStart = deepgramStart
                } else if let meetingStart = self.meetingStartTime {
                    relativeStart = Date().timeIntervalSince(meetingStart)
                } else {
                    relativeStart = 0
                }

                if isFinal {
                    // Remove interim segment if it exists
                    if let currentId = self.currentMicSegmentId {
                        self.micSegments.removeAll { $0.id == currentId }
                    }
                    // Create new final segment
                    let segment = TranscriptSegment(
                        id: UUID().uuidString,
                        text: text,
                        startTime: relativeStart,
                        duration: duration,
                        isFinal: true,
                        source: .mic,
                        speakerLabel: nil
                    )
                    self.micSegments.append(segment)
                    self.currentMicSegmentId = nil
                } else {
                    // Update or create interim segment
                    if let currentId = self.currentMicSegmentId,
                       let index = self.micSegments.firstIndex(where: { $0.id == currentId }) {
                        self.micSegments[index].text = text
                    } else {
                        let segment = TranscriptSegment(
                            id: UUID().uuidString,
                            text: text,
                            startTime: relativeStart,
                            duration: duration,
                            isFinal: false,
                            source: .mic,
                            speakerLabel: nil
                        )
                        self.micSegments.append(segment)
                        self.currentMicSegmentId = segment.id
                    }
                }
            }
            client.onStateChange = { [weak self] state in
                self?.micState = state
            }
            client.onError = { [weak self] err in
                self?.error = "Mic: \(err)"
            }
            self.micClient = client
            client.connect()

            // Setup audio tap - convert to 16kHz mono for Deepgram
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Target format: 16kHz, mono, 16-bit PCM
            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
                error = "Failed to create audio format"
                return
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                error = "Failed to create audio converter"
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                self?.convertAndSend(buffer: buffer, converter: converter, format: targetFormat, client: client)
            }

            audioEngine.prepare()
            try audioEngine.start()
            micStatus = "✓ Capturing"
            isListening = true

        } catch {
            self.error = "Mic setup failed: \(error.localizedDescription)"
            micStatus = "✗ Error"
        }
    }

    private func convertAndSend(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, format: AVAudioFormat, client: DeepgramClient) {
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if error == nil, let int16Data = convertedBuffer.int16ChannelData {
            let data = Data(bytes: int16Data[0], count: Int(convertedBuffer.frameLength) * 2)
            client.sendAudio(data)
        }
    }

    private func setupSystemCapture() {
        Task {
            do {
                print("[System] Requesting shareable content...")
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                print("[System] Found \(content.displays.count) displays, \(content.windows.count) windows")

                guard let display = content.displays.first else {
                    await MainActor.run {
                        self.error = "No display found"
                        self.screenStatus = "⚠ No display"
                    }
                    return
                }
                print("[System] Using display: \(display.displayID)")

                // Create Deepgram client for system audio
                let client = DeepgramClient(apiKey: apiKey, label: "System")
                client.onSegment = { [weak self] text, isFinal, startTime, duration in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        // Calculate relative start time from meeting start
                        let relativeStart: Double
                        if let deepgramStart = startTime {
                            relativeStart = deepgramStart
                        } else if let meetingStart = self.meetingStartTime {
                            relativeStart = Date().timeIntervalSince(meetingStart)
                        } else {
                            relativeStart = 0
                        }

                        if isFinal {
                            // Remove interim segment if it exists
                            if let currentId = self.currentSystemSegmentId {
                                self.systemSegments.removeAll { $0.id == currentId }
                            }
                            // Create new final segment
                            let segment = TranscriptSegment(
                                id: UUID().uuidString,
                                text: text,
                                startTime: relativeStart,
                                duration: duration,
                                isFinal: true,
                                source: .system,
                                speakerLabel: nil
                            )
                            self.systemSegments.append(segment)
                            self.currentSystemSegmentId = nil
                        } else {
                            // Update or create interim segment
                            if let currentId = self.currentSystemSegmentId,
                               let index = self.systemSegments.firstIndex(where: { $0.id == currentId }) {
                                self.systemSegments[index].text = text
                            } else {
                                let segment = TranscriptSegment(
                                    id: UUID().uuidString,
                                    text: text,
                                    startTime: relativeStart,
                                    duration: duration,
                                    isFinal: false,
                                    source: .system,
                                    speakerLabel: nil
                                )
                                self.systemSegments.append(segment)
                                self.currentSystemSegmentId = segment.id
                            }
                        }
                    }
                }
                client.onStateChange = { [weak self] state in
                    DispatchQueue.main.async { self?.systemState = state }
                }
                client.onError = { [weak self] err in
                    DispatchQueue.main.async {
                        if self?.error == nil { self?.error = "System: \(err)" }
                    }
                }
                await MainActor.run { self.systemClient = client }
                client.connect()

                print("[System] Creating stream filter and configuration...")
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 16000  // Match Deepgram expected rate
                config.channelCount = 1    // Mono
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

                print("[System] Creating SCStream...")
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                await MainActor.run { self.scStream = stream }

                let handler = SystemAudioHandler { [weak client] data in
                    client?.sendAudio(data)
                }
                await MainActor.run { self.systemAudioHandler = handler }

                print("[System] Adding stream output...")
                try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

                print("[System] Starting capture...")
                try await stream.startCapture()
                print("[System] Capture started successfully!")

                await MainActor.run {
                    self.screenStatus = "✓ Capturing"
                }

            } catch let error as NSError {
                await MainActor.run {
                    print("[System] Setup error: \(error)")
                    print("[System] Error domain: \(error.domain), code: \(error.code)")
                    if error.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
                        if error.code == -3801 {
                            self.screenStatus = "⚠ Screen Recording permission required"
                            self.error = "Grant Screen Recording permission in System Settings > Privacy & Security"
                        } else {
                            self.screenStatus = "⚠ SCStream error \(error.code)"
                        }
                    } else {
                        self.screenStatus = "⚠ \(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    print("[System] Setup error: \(error)")
                    self.screenStatus = "⚠ \(error.localizedDescription)"
                }
            }
        }
    }

    func stopListening() {
        // Stop diagnostics updates
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil

        // Stop mic
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        micClient?.disconnect()
        micClient = nil
        micStatus = "Stopped"
        micState = .disconnected
        micDiagnostics = nil

        // Stop system
        Task {
            try? await scStream?.stopCapture()
        }
        scStream = nil
        systemAudioHandler = nil
        systemClient?.disconnect()
        systemClient = nil
        screenStatus = "Stopped"
        systemState = .disconnected
        systemDiagnostics = nil

        isListening = false

        // Clear interim segment tracking
        currentMicSegmentId = nil
        currentSystemSegmentId = nil
        // Remove any non-final segments (interim speech that wasn't confirmed)
        micSegments.removeAll { !$0.isFinal }
        systemSegments.removeAll { !$0.isFinal }
    }

    func clearTranscripts() {
        micSegments.removeAll()
        systemSegments.removeAll()
        meetingStartTime = nil
        currentMicSegmentId = nil
        currentSystemSegmentId = nil
    }

    private func startDiagnosticsUpdates() {
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.micDiagnostics = self?.micClient?.diagnostics
                self?.systemDiagnostics = self?.systemClient?.diagnostics
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Binding var backgroundOpacity: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                Text("Background Opacity")
                    .font(.headline)

                HStack {
                    Text("Transparent")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(value: $backgroundOpacity, in: 0.3...1.0, step: 0.05)
                        .frame(width: 200)

                    Text("Opaque")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("\(Int(backgroundOpacity * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(backgroundOpacity))
            .cornerRadius(10)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(width: 350, height: 250)
    }
}

// MARK: - System Audio Handler

class SystemAudioHandler: NSObject, SCStreamOutput {
    private let onAudioData: (Data) -> Void

    init(onAudioData: @escaping (Data) -> Void) {
        self.onAudioData = onAudioData
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // Get raw audio data
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let data = dataPointer, totalLength > 0 else { return }

        // ScreenCaptureKit outputs Float32, need to convert to Int16 for Deepgram
        let floatCount = totalLength / MemoryLayout<Float32>.size
        let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float32.self, capacity: floatCount)

        var int16Data = [Int16](repeating: 0, count: floatCount)
        for i in 0..<floatCount {
            let sample = floatPointer[i]
            let clamped = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(clamped * Float(Int16.max))
        }

        let audioData = Data(bytes: &int16Data, count: int16Data.count * 2)
        onAudioData(audioData)
    }
}

#Preview {
    ContentView()
}
