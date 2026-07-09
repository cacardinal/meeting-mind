# MeetingMind — Claude Code Configuration

Real-time meeting assistant Chrome extension (WXT + React + TypeScript). Transcribes Google Meet / Zoom / Teams calls and surfaces AI suggestions from loaded context. See README.md for full platform/transcription-source docs.

**Project status:** paused; core transcription + suggestion pipeline works (e2e test results in `test/e2e-results-*.md`).

## Architecture

- `src/entrypoints/background/` — MV3 service worker: tab capture, Deepgram WebSocket, message routing
- `src/entrypoints/content/` — injected into meeting pages; Tactiq DOM scraping
- `src/entrypoints/sidepanel/` — React UI (setup screen, live transcript, suggestions)
- `src/entrypoints/offscreen/` — offscreen document for audio processing
- `src/lib/` — `claude.ts` (Anthropic API), `deepgram.ts`/`deepgram-batch.ts`, `tactiq-scraper.ts`, `question-detector.ts` (+ unit test), `storage.ts`
- `src/stores/` — `meeting-store.ts`, `transcript-store.ts` (state management)
- `src/types/` — shared TypeScript types
- `native/` — experimental macOS Swift PoC (not the primary product)

## Commands

- `npm run dev` — WXT dev mode with HMR
- `npm run build` — production build to `.output/chrome-mv3/`
- Load unpacked from `.output/chrome-mv3/` at `chrome://extensions` (Developer Mode)

## Conventions

- Transcription source priority: Tactiq DOM scrape (free, auto-detected) over Deepgram tabCapture (paid)
- Question detection runs locally (`question-detector.ts`) before any LLM call — keep it dependency-free and unit-tested
- API keys (Deepgram, Anthropic) are user-supplied via the extension's settings UI, stored in extension storage — never hardcode
- E2E results are recorded as dated markdown in `test/` (`e2e-results-YYYY-MM-DD.md`)
