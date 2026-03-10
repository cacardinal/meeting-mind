//
//  Suggestion.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import Foundation

struct Suggestion: Identifiable, Codable {
    let id: String
    var text: String
    let timestamp: Date
    var isPinned: Bool
    var isDismissed: Bool
    let triggerText: String?  // What transcript text triggered this suggestion

    init(
        id: String = UUID().uuidString,
        text: String,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        isDismissed: Bool = false,
        triggerText: String? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.isDismissed = isDismissed
        self.triggerText = triggerText
    }
}
