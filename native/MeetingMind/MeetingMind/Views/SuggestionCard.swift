//
//  SuggestionCard.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import SwiftUI

/// ParakeetAI-style suggestion card with Question/Answer format
struct SuggestionCard: View {
    let suggestion: Suggestion
    let onPin: () -> Void
    let onDismiss: () -> Void
    let onCopy: () -> Void

    @State private var isExpanded = true
    @State private var isHovering = false

    // MARK: - Design Constants (Phase 3E)
    private enum Design {
        static let cardPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static let inlineSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 10

        // Typography
        static let questionFont: Font = .system(size: 15, weight: .semibold)
        static let answerFont: Font = .system(size: 14)
        static let timestampFont: Font = .system(size: 11)
        static let buttonFont: Font = .system(size: 12, weight: .medium)

        // Colors (adapts to light/dark mode)
        static let questionBackground = Color.blue.opacity(0.05)
        static let questionBackgroundDark = Color.blue.opacity(0.15)
    }

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question header (if available)
            if let question = suggestion.triggerText, !question.isEmpty {
                questionHeader(question)
            }

            // Answer section
            answerSection

            // Footer with actions
            footerSection
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.1))
        .cornerRadius(Design.cornerRadius)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .opacity(suggestion.isDismissed ? 0.5 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private func questionHeader(_ question: String) -> some View {
        HStack(alignment: .top, spacing: Design.inlineSpacing) {
            Image(systemName: "bubble.left.fill")
                .foregroundColor(.blue)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 4) {
                Text("Question")
                    .font(Design.buttonFont)
                    .foregroundColor(.blue)

                Text(question)
                    .font(Design.questionFont)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(Design.cardPadding)
        .background(colorScheme == .dark ? Design.questionBackgroundDark : Design.questionBackground)
    }

    @ViewBuilder
    private var answerSection: some View {
        VStack(alignment: .leading, spacing: Design.sectionSpacing) {
            HStack(spacing: Design.inlineSpacing) {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 15))

                Text("Answer")
                    .font(Design.buttonFont)
                    .foregroundColor(.orange)

                Spacer()

                // Expand/collapse button for long answers
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                MarkdownText(text: suggestion.text)
                    .font(Design.answerFont)
            } else {
                Text(suggestion.text.prefix(150) + "...")
                    .font(Design.answerFont)
                    .foregroundColor(.secondary)
            }
        }
        .padding(Design.cardPadding)
    }

    @ViewBuilder
    private var footerSection: some View {
        HStack(spacing: Design.sectionSpacing) {
            // Copy button
            Button {
                onCopy()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
                .font(Design.buttonFont)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            // Pin button
            Button {
                onPin()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: suggestion.isPinned ? "pin.fill" : "pin")
                    Text(suggestion.isPinned ? "Pinned" : "Pin")
                }
                .font(Design.buttonFont)
            }
            .buttonStyle(.plain)
            .foregroundColor(suggestion.isPinned ? .orange : .secondary)

            Spacer()

            // Timestamp
            Text(suggestion.timestamp, style: .time)
                .font(Design.timestampFont)
                .foregroundColor(.secondary)

            // Dismiss button (visible on hover)
            if isHovering {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Design.buttonFont)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Design.cardPadding)
        .padding(.vertical, Design.inlineSpacing)
        .background(Color(NSColor.separatorColor).opacity(0.08))
    }
}

/// Compact suggestion card for streaming/current suggestion
struct StreamingSuggestionCard: View {
    let text: String
    let question: String?

    // Reuse design constants
    private enum Design {
        static let cardPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static let inlineSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 10
        static let questionFont: Font = .system(size: 15, weight: .semibold)
        static let answerFont: Font = .system(size: 14)
        static let buttonFont: Font = .system(size: 12, weight: .medium)
        static let questionBackground = Color.blue.opacity(0.05)
        static let questionBackgroundDark = Color.blue.opacity(0.15)
    }

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question header (if available)
            if let question = question, !question.isEmpty {
                HStack(alignment: .top, spacing: Design.inlineSpacing) {
                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 15))

                    Text(question)
                        .font(Design.questionFont)
                        .foregroundColor(.primary)
                }
                .padding(Design.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorScheme == .dark ? Design.questionBackgroundDark : Design.questionBackground)
            }

            // Streaming answer
            VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                HStack(spacing: Design.inlineSpacing) {
                    ProgressView()
                        .scaleEffect(0.7)

                    Text("Generating answer...")
                        .font(Design.buttonFont)
                        .foregroundColor(.secondary)
                }

                MarkdownText(text: text)
                    .font(Design.answerFont)
            }
            .padding(Design.cardPadding)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.1))
        .cornerRadius(Design.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Design.cornerRadius)
                .stroke(Color.orange.opacity(0.25), lineWidth: 2)
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        SuggestionCard(
            suggestion: Suggestion(
                text: """
                **Key Points:**
                - My biggest weakness is perfectionism
                - I sometimes spend extra time refining details
                - However, I've learned to balance quality with deadlines

                This is a common interview question designed to test self-awareness.
                """,
                triggerText: "What is your biggest weakness?"
            ),
            onPin: {},
            onDismiss: {},
            onCopy: {}
        )

        StreamingSuggestionCard(
            text: "The binary search approach works by...",
            question: "How do you search in a rotated sorted array?"
        )
    }
    .padding()
    .frame(width: 450)
}
