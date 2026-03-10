//
//  MeetingMode.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import Foundation

enum MeetingMode: String, CaseIterable, Codable {
    case general = "General"
    case interview = "Interview"
    case parentTeacher = "Parent-Teacher"
    case financial = "Financial"
    case mockInterview = "Mock Interview"

    var icon: String {
        switch self {
        case .general: return "message"
        case .interview: return "briefcase"
        case .parentTeacher: return "graduationcap"
        case .financial: return "dollarsign.circle"
        case .mockInterview: return "mic.badge.plus"
        }
    }

    var description: String {
        switch self {
        case .general:
            return "General meeting with talking points and action items"
        case .interview:
            return "Job interview with STAR framework suggestions"
        case .parentTeacher:
            return "Parent-teacher conference with follow-up questions"
        case .financial:
            return "Financial meeting with jargon explanations"
        case .mockInterview:
            return "Practice interview with AI-generated questions"
        }
    }

    /// System prompt for Claude API based on meeting mode
    var systemPrompt: String {
        let formatInstructions = """

        Format your response clearly using markdown:
        - Use **bold** for emphasis
        - Use bullet points for lists
        - Use numbered lists for sequences/steps
        - Include code blocks with ``` if showing code
        Keep your response focused and actionable.
        """

        switch self {
        case .general:
            return """
            You are a meeting assistant helping capture key points. Based on the transcript, suggest:
            - Talking points to raise
            - Action items mentioned
            - Key decisions made
            - Questions to clarify
            Keep suggestions concise (2-3 bullet points max).
            """ + formatInstructions

        case .interview:
            return """
            You are an interview coach. Based on the transcript, help the candidate with a suggested response.

            **For behavioral questions**, structure using STAR:
            - **Situation**: Brief context
            - **Task**: Your responsibility
            - **Action**: What you did specifically
            - **Result**: Measurable outcome

            **For technical questions**, provide:
            - Key points to mention
            - Code examples if relevant
            - Follow-up questions to ask

            If context documents include company info, reference specific details.
            """ + formatInstructions

        case .parentTeacher:
            return """
            You are helping a parent navigate a parent-teacher conference. Suggest:
            - Clarifying questions about the child's progress
            - Follow-up items to track
            - Specific concerns to raise
            - Ways to support learning at home
            Be supportive and constructive.
            """ + formatInstructions

        case .financial:
            return """
            You are a financial meeting assistant. Help by:
            - Explaining financial jargon in plain terms
            - Flagging fee structures or costs mentioned
            - Suggesting questions about risks
            - Identifying key decision points
            Be precise and help the user understand implications.
            """ + formatInstructions

        case .mockInterview:
            return """
            You are an AI interviewer conducting a practice interview. Your role:
            1. Ask thoughtful interview questions based on the role/context
            2. Wait for the candidate to respond
            3. Provide specific, constructive feedback on their answer
            4. Ask follow-up questions when appropriate
            Start with a warm greeting and the first question.
            """ + formatInstructions
        }
    }
}
