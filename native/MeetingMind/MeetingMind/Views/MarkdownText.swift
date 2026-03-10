//
//  MarkdownText.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import SwiftUI
import AppKit

/// A view that renders markdown text with proper formatting, including code blocks
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    renderMarkdownText(content)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .header(let level, let headerText):
                    renderHeader(level: level, text: headerText)
                }
            }
        }
    }

    @ViewBuilder
    private func renderMarkdownText(_ content: String) -> some View {
        if let attributed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(content)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func renderHeader(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }

        Text(text)
            .font(font)
            .fontWeight(.semibold)
            .padding(.top, level == 1 ? 8 : 4)
            .textSelection(.enabled)
    }

    // MARK: - Parsing

    private enum ContentBlock {
        case text(String)
        case code(language: String?, code: String)
        case header(level: Int, text: String)
    }

    private func parseContent() -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage: String?
        var codeContent = ""

        let lines = text.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block
                    blocks.append(.code(language: codeLanguage, code: codeContent.trimmingCharacters(in: .whitespacesAndNewlines)))
                    codeContent = ""
                    codeLanguage = nil
                    inCodeBlock = false
                } else {
                    // Start of code block
                    if !currentText.isEmpty {
                        blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                        currentText = ""
                    }
                    let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeContent += (codeContent.isEmpty ? "" : "\n") + line
            } else if let headerMatch = parseHeader(line) {
                // Flush current text before header
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                blocks.append(.header(level: headerMatch.level, text: headerMatch.text))
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
        }

        // Handle any remaining content
        if inCodeBlock && !codeContent.isEmpty {
            blocks.append(.code(language: codeLanguage, code: codeContent.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else if !currentText.isEmpty {
            blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return blocks
    }

    /// Parse a line as a markdown header (# Header, ## Header, etc.)
    private func parseHeader(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        var level = 0
        var index = trimmed.startIndex

        // Count leading # characters (max 6 for h6)
        while index < trimmed.endIndex && trimmed[index] == "#" && level < 6 {
            level += 1
            index = trimmed.index(after: index)
        }

        // Must have at least one # and a space after
        guard level > 0,
              index < trimmed.endIndex,
              trimmed[index] == " " else { return nil }

        // Extract header text after the space
        let headerText = String(trimmed[trimmed.index(after: index)...])
            .trimmingCharacters(in: .whitespaces)

        guard !headerText.isEmpty else { return nil }

        return (level, headerText)
    }
}

/// A view for displaying code blocks with syntax highlighting style
struct CodeBlockView: View {
    let language: String?
    let code: String

    // MARK: - Design Constants (Phase 3E)
    private enum Design {
        static let cornerRadius: CGFloat = 8
        static let inlineSpacing: CGFloat = 8
        static let codePadding: CGFloat = 12
        static let codeFont: Font = .system(size: 13, design: .monospaced)
        static let labelFont: Font = .system(size: 11, weight: .medium)
        static let buttonFont: Font = .system(size: 12, weight: .medium)
        static let codeBackground = Color(NSColor.textBackgroundColor).opacity(0.5)
        static let codeBackgroundDark = Color.gray.opacity(0.2)
    }

    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.lowercased())
                        .font(Design.labelFont)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    copyCode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(Design.buttonFont)
                    .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || copied ? 1 : 0.6)
            }
            .padding(.horizontal, Design.codePadding)
            .padding(.vertical, Design.inlineSpacing)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Design.codeFont)
                    .textSelection(.enabled)
                    .padding(Design.codePadding)
            }
        }
        .background(colorScheme == .dark ? Design.codeBackgroundDark : Design.codeBackground)
        .cornerRadius(Design.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Design.cornerRadius)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        MarkdownText(text: """
        ## Current Situation Assessment
        You seem to be testing screen sharing or a technical system.

        ## Immediate Action Items

        **Stay Professional and Engaged:**
        - Acknowledge any technical setup positively
        - Be patient during technical setup

        **Be Ready to Transition:**
        - Have your materials ready (resume, portfolio, code examples)
        - Prepare for the interviewer to begin

        ```cpp
        class Solution {
        public:
            int search(vector<int>& nums, int target) {
                int left = 0, right = nums.size() - 1;
                return -1;
            }
        };
        ```

        This approach maintains O(log n) time complexity.
        """)
    }
    .padding()
    .frame(width: 500)
}
