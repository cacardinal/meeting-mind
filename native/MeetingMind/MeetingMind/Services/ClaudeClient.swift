//
//  ClaudeClient.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import Foundation

/// Client for streaming responses from Claude API
class ClaudeClient: NSObject, URLSessionDataDelegate {
    private var apiKey: String
    private let model = "claude-sonnet-4-20250514"
    private let maxTokens = 500

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var buffer = ""

    // Callbacks
    var onTextDelta: ((String) -> Void)?
    var onComplete: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var fullResponse = ""
    private var hasCalledComplete = false  // Prevent double onComplete calls

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func setApiKey(_ key: String) {
        self.apiKey = key
    }

    /// Generate a suggestion based on transcript and context
    func generateSuggestion(
        systemPrompt: String,
        transcript: String,
        contextDocument: String? = nil
    ) {
        guard !apiKey.isEmpty else {
            onError?("Claude API key not set")
            return
        }

        // Build user message
        var userMessage = "Here is the meeting transcript so far:\n\n\(transcript)"
        if let context = contextDocument, !context.isEmpty {
            userMessage = "Context document:\n\(context)\n\n" + userMessage
        }
        userMessage += "\n\nBased on this, provide a helpful suggestion."

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            onError?("Failed to serialize request")
            return
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        fullResponse = ""
        buffer = ""
        hasCalledComplete = false

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    /// Generate a mock interview question
    func generateInterviewQuestion(
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)]
    ) {
        print("[ClaudeClient] generateInterviewQuestion called with \(conversationHistory.count) messages")
        guard !apiKey.isEmpty else {
            print("[ClaudeClient] ERROR: API key is empty")
            onError?("Claude API key not set")
            return
        }

        let messages = conversationHistory.map { ["role": $0.role, "content": $0.content] }
        print("[ClaudeClient] Messages: \(messages)")

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 600,
            "stream": true,
            "system": systemPrompt,
            "messages": messages
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("[ClaudeClient] ERROR: Failed to serialize request")
            onError?("Failed to serialize request")
            return
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData

        fullResponse = ""
        buffer = ""
        hasCalledComplete = false

        print("[ClaudeClient] Starting request to Claude API...")
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
        print("[ClaudeClient] Request task started")
    }

    func cancel() {
        dataTask?.cancel()
        dataTask = nil
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            print("[ClaudeClient] didReceive: Failed to decode data as UTF-8")
            return
        }

        print("[ClaudeClient] didReceive: \(text.prefix(100))...")
        buffer += text

        // Process complete SSE events
        let lines = buffer.components(separatedBy: "\n")

        // If buffer doesn't end with newline, last line is incomplete - save it
        let hasIncompleteLine = !buffer.hasSuffix("\n")
        if hasIncompleteLine {
            buffer = lines.last ?? ""
        } else {
            buffer = ""
        }

        // Process all complete lines (skip last if it's incomplete)
        let linesToProcess = hasIncompleteLine ? lines.dropLast() : lines.dropLast(0)
        for line in linesToProcess where !line.isEmpty {
            processSSELine(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("[ClaudeClient] didCompleteWithError: \(error?.localizedDescription ?? "nil")")
        if let error = error {
            DispatchQueue.main.async {
                self.onError?(error.localizedDescription)
            }
        } else {
            // Only call onComplete if message_stop didn't already call it
            guard !hasCalledComplete else {
                print("[ClaudeClient] Skipping duplicate onComplete call")
                return
            }
            hasCalledComplete = true
            DispatchQueue.main.async {
                self.onComplete?(self.fullResponse)
            }
        }
    }

    private func processSSELine(_ line: String) {
        guard line.hasPrefix("data: ") else {
            // Log non-data lines (skip empty and comment lines)
            if !line.isEmpty && !line.hasPrefix(":") {
                print("[ClaudeClient] Skipping non-data SSE line: \(line.prefix(50))")
            }
            return
        }

        let jsonString = String(line.dropFirst(6))
        guard jsonString != "[DONE]" else {
            print("[ClaudeClient] Received [DONE] event")
            return
        }

        guard let data = jsonString.data(using: .utf8) else {
            print("[ClaudeClient] ERROR: Failed to convert to UTF-8: \(jsonString.prefix(100))")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[ClaudeClient] ERROR: Invalid JSON: \(jsonString.prefix(100))")
            return
        }

        // Handle different event types
        if let type = json["type"] as? String {
            switch type {
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    fullResponse += text
                    DispatchQueue.main.async {
                        self.onTextDelta?(text)
                    }
                }

            case "message_stop":
                guard !hasCalledComplete else { return }
                hasCalledComplete = true
                DispatchQueue.main.async {
                    self.onComplete?(self.fullResponse)
                }

            case "error":
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    DispatchQueue.main.async {
                        self.onError?(message)
                    }
                }

            default:
                break
            }
        }
    }
}
