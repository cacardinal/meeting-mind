//
//  Meeting.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import Foundation

struct Meeting: Identifiable, Codable {
    let id: String
    var title: String
    var mode: MeetingMode
    var startTime: Date
    var endTime: Date?
    var contextDocument: String?

    /// Calculated duration in seconds
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    /// Formatted duration string (e.g., "45:23")
    var formattedDuration: String? {
        guard let d = duration else { return nil }
        let minutes = Int(d) / 60
        let seconds = Int(d) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    init(
        id: String = UUID().uuidString,
        title: String = "",
        mode: MeetingMode = .general,
        startTime: Date = Date(),
        endTime: Date? = nil,
        contextDocument: String? = nil
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.startTime = startTime
        self.endTime = endTime
        self.contextDocument = contextDocument
    }
}
