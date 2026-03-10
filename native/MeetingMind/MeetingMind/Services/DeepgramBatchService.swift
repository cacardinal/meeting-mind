//
//  DeepgramBatchService.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/19/26.
//

import Foundation
import Combine

// MARK: - Deepgram Pre-recorded API Response Models

struct DeepgramBatchResponse: Codable {
    let results: DeepgramBatchResults?
}

struct DeepgramBatchResults: Codable {
    let utterances: [DeepgramBatchUtterance]?
}

struct DeepgramBatchUtterance: Codable {
    let start: Double
    let end: Double
    let transcript: String
    let speaker: Int
    let channel: Int
    let confidence: Double?
}

// MARK: - Batch Transcription Service

@MainActor
class DeepgramBatchService: ObservableObject {
    @Published var isProcessing = false
    @Published var status: String = ""
    @Published var error: String?

    func transcribeFile(
        url: URL,
        apiKey: String
    ) async throws -> (micSegments: [TranscriptSegment], systemSegments: [TranscriptSegment], speakerLabels: [Int: String]) {
        isProcessing = true
        error = nil
        status = "Reading file..."

        defer { isProcessing = false }

        // Read file data
        guard url.startAccessingSecurityScopedResource() else {
            throw TranscriptionError.fileAccessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw TranscriptionError.fileReadFailed(error.localizedDescription)
        }

        status = "Uploading to Deepgram (\(formatFileSize(fileData.count)))..."

        // Build URL with query params
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData

        status = "Transcribing with Deepgram..."

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        status = "Processing transcript..."

        let batchResponse = try JSONDecoder().decode(DeepgramBatchResponse.self, from: data)

        guard let utterances = batchResponse.results?.utterances, !utterances.isEmpty else {
            throw TranscriptionError.noUtterances
        }

        // Map utterances to TranscriptSegments
        // Speaker 0 → .mic (first speaker), Speaker 1+ → .system (other speakers)
        var micSegments: [TranscriptSegment] = []
        var systemSegments: [TranscriptSegment] = []
        var speakerLabels: [Int: String] = [:]

        for utterance in utterances {
            speakerLabels[utterance.speaker] = "Speaker \(utterance.speaker)"

            let segment = TranscriptSegment(
                id: UUID().uuidString,
                text: utterance.transcript,
                startTime: utterance.start,
                duration: utterance.end - utterance.start,
                isFinal: true,
                source: utterance.speaker == 0 ? .mic : .system,
                speakerLabel: nil
            )

            if utterance.speaker == 0 {
                micSegments.append(segment)
            } else {
                systemSegments.append(segment)
            }
        }

        status = "Done — \(utterances.count) segments, \(speakerLabels.count) speakers"

        return (micSegments, systemSegments, speakerLabels)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case fileAccessDenied
    case fileReadFailed(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noUtterances

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return "Could not access the selected file"
        case .fileReadFailed(let detail):
            return "Failed to read file: \(detail)"
        case .invalidResponse:
            return "Invalid response from Deepgram"
        case .apiError(let code, let message):
            return "Deepgram API error (\(code)): \(message)"
        case .noUtterances:
            return "No speech detected in the audio file"
        }
    }
}
