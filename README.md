# MeetingMind

Real-time meeting assistant Chrome extension. Transcribes conversations on Google Meet, Zoom, and Microsoft Teams, providing AI-powered suggestions using loaded context.

## Quick Start

1. Install dependencies: `npm install`
2. Build: `npm run build`
3. Open `chrome://extensions` → Enable Developer Mode → Load Unpacked → select `.output/chrome-mv3/`
4. Open a Google Meet, Zoom, or Microsoft Teams call
5. Click the MeetingMind icon in toolbar to open side panel
6. Set meeting mode, load context, click Start Meeting

## Supported Platforms

| Platform | URL Pattern | Notes |
|----------|-------------|-------|
| Google Meet | `meet.google.com/*` | Full support |
| Zoom (Web Client) | `*.zoom.us/wc/*`, `*.zoom.us/j/*` | Web client only (not desktop app) |
| Microsoft Teams | `teams.microsoft.com/*`, `teams.live.com/*` | Web client only |

Tactiq scraping works identically across all platforms since Tactiq injects its transcript DOM into whatever page is hosting the meeting. Deepgram's tabCapture path also works across platforms.

## Transcription Sources

### Tactiq (Recommended — Free)

Install [Tactiq](https://tactiq.io) Chrome extension. MeetingMind auto-detects it and reads the transcript from the page DOM. No API key needed. Works on all supported platforms (Meet, Zoom, Teams) — Tactiq renders its transcript into the page DOM regardless of platform.

When Tactiq is detected, a green dot appears next to "Tactiq" in the setup screen.

### Deepgram (Optional — Paid)

For independent transcription without Tactiq:

1. Sign up at [deepgram.com](https://deepgram.com) — 200 free minutes/month on the pay-as-you-go plan
2. Open MeetingMind Settings → enter Deepgram API key
3. Select "Deepgram" as transcription source in meeting setup

Deepgram captures audio directly via Chrome's tabCapture API and streams to Deepgram Nova-3 with speaker diarization.

## AI Suggestions

Requires an Anthropic API key (Settings → Anthropic API Key).

**Auto mode:** Detects questions from other speakers and suggests responses based on your loaded context.

**Manual mode:** Press `Ctrl+Space` anytime for a suggestion based on recent transcript.

## Meeting Modes

| Mode | Best For | Context Source |
|------|----------|---------------|
| Interview | Job interviews | Company research, talking points, STAR frameworks |
| Parent-Teacher | School conferences | Kid notes, questions to ask |
| Financial | Advisory meetings | Account info, terms glossary |
| General | Any meeting | Custom notes |

## Context Loading

Before starting, paste or upload context documents:

- Company intel briefs, job descriptions
- Talking points, frameworks (STAR, Pyramid Principle)
- Any text files (.txt, .md, .json, .csv)

Context is sent to Claude with each suggestion request to ground responses in your prepared material.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+Space | Request AI suggestion |
| Ctrl+E | Export transcript |

## Development

```bash
npm run dev     # Dev mode with HMR
npm run build   # Production build
npm run zip     # Package for distribution
npx vitest run  # Run tests
```

## Architecture

- **WXT** — Manifest V3 Chrome extension framework
- **React 19 + Tailwind CSS 4** — Side panel UI
- **Zustand** — State management
- **IndexedDB** — Local transcript storage
- All data stays local. API calls (Deepgram/Claude) are for processing only.

### Extension Components

| Component | File | Purpose |
|-----------|------|---------|
| Background | `src/entrypoints/background/` | Service worker — message routing, tab capture orchestration |
| Content Script | `src/entrypoints/content/` | Runs on Meet/Zoom/Teams — Tactiq detection + DOM scraping |
| Side Panel | `src/entrypoints/sidepanel/` | Main UI — setup, transcript display, suggestions |
| Offscreen | `src/entrypoints/offscreen/` | Audio capture for Deepgram path (hidden document) |

### Transcription Flow

**Tactiq path (Meet, Zoom, Teams):**
```
Tactiq transcribes → Renders to meeting page DOM
  → Content script (MutationObserver) detects entries
  → Parses speaker + text → TranscriptSegment
  → chrome.runtime.sendMessage → Side panel displays
```

**Deepgram path:**
```
tabCapture → Offscreen document captures audio
  → MediaRecorder chunks (250ms) → Background
  → WebSocket to Deepgram Nova-3 → TranscriptSegment
  → Side panel displays
```

## Life-OS Integration

This is a code-heavy domain in [Life-OS](https://github.com/cacardinal/life-os). Symlinked at `domains/meetings/code/`.

Exported transcripts save to `domains/meetings/transcripts/YYYY-MM-DD-[name].md`.
