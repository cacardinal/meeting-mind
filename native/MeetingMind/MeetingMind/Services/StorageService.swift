//
//  StorageService.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import Foundation
import SQLite3

/// SQLite-based storage for meetings and transcripts
class StorageService {
    static let shared = StorageService()

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        // Get Application Support directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MeetingMind", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)

        dbPath = appFolder.appendingPathComponent("meetings.sqlite").path
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func createTables() {
        let createMeetingsTable = """
        CREATE TABLE IF NOT EXISTS meetings (
            id TEXT PRIMARY KEY,
            title TEXT,
            mode TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL,
            context_document TEXT,
            mic_speaker_label TEXT,
            system_speaker_label TEXT
        );
        """

        let createSegmentsTable = """
        CREATE TABLE IF NOT EXISTS segments (
            id TEXT PRIMARY KEY,
            meeting_id TEXT NOT NULL,
            text TEXT NOT NULL,
            start_time REAL NOT NULL,
            duration REAL,
            is_final INTEGER NOT NULL,
            source TEXT NOT NULL,
            speaker_label TEXT,
            FOREIGN KEY (meeting_id) REFERENCES meetings(id) ON DELETE CASCADE
        );
        """

        let createSuggestionsTable = """
        CREATE TABLE IF NOT EXISTS suggestions (
            id TEXT PRIMARY KEY,
            meeting_id TEXT NOT NULL,
            text TEXT NOT NULL,
            timestamp REAL NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            is_dismissed INTEGER NOT NULL DEFAULT 0,
            trigger_text TEXT,
            FOREIGN KEY (meeting_id) REFERENCES meetings(id) ON DELETE CASCADE
        );
        """

        executeSQL(createMeetingsTable)
        executeSQL(createSegmentsTable)
        executeSQL(createSuggestionsTable)

        // Create index for faster lookups
        executeSQL("CREATE INDEX IF NOT EXISTS idx_segments_meeting ON segments(meeting_id);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_suggestions_meeting ON suggestions(meeting_id);")
    }

    private func executeSQL(_ sql: String) {
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQL Error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Meeting Operations

    func saveMeeting(_ meeting: Meeting, micSegments: [TranscriptSegment], systemSegments: [TranscriptSegment], suggestions: [Suggestion], micLabel: String, systemLabel: String) -> Bool {
        // Begin transaction
        executeSQL("BEGIN TRANSACTION;")

        // Insert meeting
        let insertMeeting = """
        INSERT OR REPLACE INTO meetings (id, title, mode, start_time, end_time, context_document, mic_speaker_label, system_speaker_label)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertMeeting, -1, &stmt, nil) == SQLITE_OK else {
            executeSQL("ROLLBACK;")
            return false
        }

        sqlite3_bind_text(stmt, 1, meeting.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, meeting.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, meeting.mode.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, meeting.startTime.timeIntervalSince1970)

        if let endTime = meeting.endTime {
            sqlite3_bind_double(stmt, 5, endTime.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 5)
        }

        if let context = meeting.contextDocument {
            sqlite3_bind_text(stmt, 6, context, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        sqlite3_bind_text(stmt, 7, micLabel, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, systemLabel, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            sqlite3_finalize(stmt)
            executeSQL("ROLLBACK;")
            return false
        }
        sqlite3_finalize(stmt)

        // Insert segments
        let allSegments = micSegments + systemSegments
        for segment in allSegments {
            if !saveSegment(segment, meetingId: meeting.id) {
                executeSQL("ROLLBACK;")
                return false
            }
        }

        // Insert suggestions
        for suggestion in suggestions {
            if !saveSuggestion(suggestion, meetingId: meeting.id) {
                executeSQL("ROLLBACK;")
                return false
            }
        }

        executeSQL("COMMIT;")
        return true
    }

    private func saveSegment(_ segment: TranscriptSegment, meetingId: String) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO segments (id, meeting_id, text, start_time, duration, is_final, source, speaker_label)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }

        sqlite3_bind_text(stmt, 1, segment.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, meetingId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, segment.text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, segment.startTime)

        if let duration = segment.duration {
            sqlite3_bind_double(stmt, 5, duration)
        } else {
            sqlite3_bind_null(stmt, 5)
        }

        sqlite3_bind_int(stmt, 6, segment.isFinal ? 1 : 0)
        sqlite3_bind_text(stmt, 7, segment.source.rawValue, -1, SQLITE_TRANSIENT)

        if let label = segment.speakerLabel {
            sqlite3_bind_text(stmt, 8, label, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 8)
        }

        let result = sqlite3_step(stmt) == SQLITE_DONE
        sqlite3_finalize(stmt)
        return result
    }

    private func saveSuggestion(_ suggestion: Suggestion, meetingId: String) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO suggestions (id, meeting_id, text, timestamp, is_pinned, is_dismissed, trigger_text)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }

        sqlite3_bind_text(stmt, 1, suggestion.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, meetingId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, suggestion.text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, suggestion.timestamp.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 5, suggestion.isPinned ? 1 : 0)
        sqlite3_bind_int(stmt, 6, suggestion.isDismissed ? 1 : 0)

        if let trigger = suggestion.triggerText {
            sqlite3_bind_text(stmt, 7, trigger, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        let result = sqlite3_step(stmt) == SQLITE_DONE
        sqlite3_finalize(stmt)
        return result
    }

    func getMeetings(limit: Int = 50) -> [MeetingSummary] {
        let sql = """
        SELECT m.id, m.title, m.mode, m.start_time, m.end_time,
               (SELECT COUNT(*) FROM segments WHERE meeting_id = m.id) as segment_count
        FROM meetings m
        ORDER BY m.start_time DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var meetings: [MeetingSummary] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let modeRaw = String(cString: sqlite3_column_text(stmt, 2))
            let mode = MeetingMode(rawValue: modeRaw) ?? .general
            let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))

            var endTime: Date?
            if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            }

            let segmentCount = Int(sqlite3_column_int(stmt, 5))

            let summary = MeetingSummary(
                id: id,
                title: title,
                mode: mode,
                startTime: startTime,
                endTime: endTime,
                segmentCount: segmentCount
            )
            meetings.append(summary)
        }

        sqlite3_finalize(stmt)
        return meetings
    }

    func getMeeting(id: String) -> (meeting: Meeting, micSegments: [TranscriptSegment], systemSegments: [TranscriptSegment], suggestions: [Suggestion], micLabel: String, systemLabel: String)? {
        // Get meeting
        let meetingSql = "SELECT * FROM meetings WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, meetingSql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_finalize(stmt)
            return nil
        }

        let meetingId = String(cString: sqlite3_column_text(stmt, 0))
        let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let modeRaw = String(cString: sqlite3_column_text(stmt, 2))
        let mode = MeetingMode(rawValue: modeRaw) ?? .general
        let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))

        var endTime: Date?
        if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
            endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        }

        var contextDocument: String?
        if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
            contextDocument = String(cString: sqlite3_column_text(stmt, 5))
        }

        let micLabel = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "You"
        let systemLabel = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "Others"

        sqlite3_finalize(stmt)

        let meeting = Meeting(
            id: meetingId,
            title: title,
            mode: mode,
            startTime: startTime,
            endTime: endTime,
            contextDocument: contextDocument
        )

        // Get segments
        let segmentsSql = "SELECT * FROM segments WHERE meeting_id = ? ORDER BY start_time;"
        guard sqlite3_prepare_v2(db, segmentsSql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        var micSegments: [TranscriptSegment] = []
        var systemSegments: [TranscriptSegment] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let segId = String(cString: sqlite3_column_text(stmt, 0))
            let text = String(cString: sqlite3_column_text(stmt, 2))
            let segStartTime = sqlite3_column_double(stmt, 3)

            var duration: Double?
            if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                duration = sqlite3_column_double(stmt, 4)
            }

            let isFinal = sqlite3_column_int(stmt, 5) == 1
            let sourceRaw = String(cString: sqlite3_column_text(stmt, 6))
            let source = TranscriptSegment.Source(rawValue: sourceRaw) ?? .mic

            var speakerLabel: String?
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                speakerLabel = String(cString: sqlite3_column_text(stmt, 7))
            }

            let segment = TranscriptSegment(
                id: segId,
                text: text,
                startTime: segStartTime,
                duration: duration,
                isFinal: isFinal,
                source: source,
                speakerLabel: speakerLabel
            )

            if source == .mic {
                micSegments.append(segment)
            } else {
                systemSegments.append(segment)
            }
        }

        sqlite3_finalize(stmt)

        // Get suggestions
        let suggestionsSql = "SELECT * FROM suggestions WHERE meeting_id = ? ORDER BY timestamp;"
        guard sqlite3_prepare_v2(db, suggestionsSql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        var suggestions: [Suggestion] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let sugId = String(cString: sqlite3_column_text(stmt, 0))
            let text = String(cString: sqlite3_column_text(stmt, 2))
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let isPinned = sqlite3_column_int(stmt, 4) == 1
            let isDismissed = sqlite3_column_int(stmt, 5) == 1

            var triggerText: String?
            if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
                triggerText = String(cString: sqlite3_column_text(stmt, 6))
            }

            let suggestion = Suggestion(
                id: sugId,
                text: text,
                timestamp: timestamp,
                isPinned: isPinned,
                isDismissed: isDismissed,
                triggerText: triggerText
            )
            suggestions.append(suggestion)
        }

        sqlite3_finalize(stmt)

        return (meeting, micSegments, systemSegments, suggestions, micLabel, systemLabel)
    }

    func deleteMeeting(id: String) -> Bool {
        executeSQL("BEGIN TRANSACTION;")
        executeSQL("DELETE FROM segments WHERE meeting_id = '\(id)';")
        executeSQL("DELETE FROM suggestions WHERE meeting_id = '\(id)';")
        executeSQL("DELETE FROM meetings WHERE id = '\(id)';")
        executeSQL("COMMIT;")
        return true
    }
}

// MARK: - Meeting Summary (for list view)

struct MeetingSummary: Identifiable {
    let id: String
    let title: String
    let mode: MeetingMode
    let startTime: Date
    let endTime: Date?
    let segmentCount: Int

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var formattedDuration: String? {
        guard let d = duration else { return nil }
        let minutes = Int(d) / 60
        let seconds = Int(d) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var displayTitle: String {
        if title.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "\(mode.rawValue) - \(formatter.string(from: startTime))"
        }
        return title
    }
}

// MARK: - SQLite Helpers

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
