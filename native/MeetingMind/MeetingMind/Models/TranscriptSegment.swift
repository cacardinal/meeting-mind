//
//  TranscriptSegment.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import Foundation

/// Represents a single segment of transcribed speech
struct TranscriptSegment: Identifiable, Codable, Equatable {
    let id: String
    var text: String
    let startTime: Double       // Seconds from meeting start
    let duration: Double?
    let isFinal: Bool
    let source: Source
    var speakerLabel: String?   // User-assigned name (nil = use default)

    enum Source: String, Codable {
        case mic
        case system
        case interviewer  // Mock interview AI responses

        var defaultLabel: String {
            switch self {
            case .mic: return "You"
            case .system: return "Others"
            case .interviewer: return "Interviewer"
            }
        }

        var emoji: String {
            switch self {
            case .mic: return "🎤"
            case .system: return "🔊"
            case .interviewer: return "🎯"
            }
        }
    }

    /// Returns the display label (custom or default)
    var displayLabel: String {
        speakerLabel ?? source.defaultLabel
    }

    /// Formats the start time as MM:SS
    var formattedTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Deepgram Response Models

struct DeepgramResponse: Codable {
    let type: String?
    let channel: DeepgramChannel?
    let is_final: Bool?
    let speech_final: Bool?
    let start: Double?
    let duration: Double?
}

struct DeepgramChannel: Codable {
    let alternatives: [DeepgramAlternative]?
}

struct DeepgramAlternative: Codable {
    let transcript: String?
    let confidence: Double?
}
