import type { TranscriptSegment } from '../types';

/**
 * Scrapes Tactiq's transcript entries from the Google Meet page DOM.
 *
 * Tactiq renders directly into the Meet page (not in a shadow root or iframe).
 * DOM structure (as of Jan 2026):
 *
 *   <div class="...overflow-y-auto...">           ← scrollable transcript container
 *     <div class="flex flex-col px-2.5 py-0">    ← entry wrapper
 *       <div class="pt-2.5 ... text-[#6dcc6d]">  ← speaker name (green text)
 *         Jane Doe
 *       </div>
 *       <div class="group flex flex-row ... text-[#dcddde]">  ← text row
 *         <div class="flex-1 break-words ... font-medium">    ← actual text
 *           Testing one, two, three.
 *         </div>
 *         <div>emoji action buttons</div>
 *       </div>
 *     </div>
 *   </div>
 */
export class TactiqScraper {
  private observer: MutationObserver | null = null;
  private onSegment: (segment: TranscriptSegment) => void;
  private seenTexts = new Map<string, string>(); // key → last seen text
  private entryIds = new Map<string, string>(); // key → stable segment ID
  private lastSpeaker = '';
  private pollInterval: ReturnType<typeof setInterval> | null = null;
  private backupPollInterval: ReturnType<typeof setInterval> | null = null;
  private container: Element | null = null;

  constructor(onSegment: (segment: TranscriptSegment) => void) {
    this.onSegment = onSegment;
  }

  /**
   * Detect if Tactiq is present on the page.
   * Tactiq injects a <meta id="tactiq-rtc"> tag into the page.
   */
  static detect(): boolean {
    return !!document.querySelector('#tactiq-rtc, meta[name="tactiq-rtc"]');
  }

  start(): void {
    console.log('[MeetingMind] Starting Tactiq scraper');
    this.findContainerAndObserve();

    // Poll for container — Tactiq may not have rendered transcript yet
    if (!this.container) {
      this.pollInterval = setInterval(() => {
        this.findContainerAndObserve();
        if (this.container && this.pollInterval) {
          clearInterval(this.pollInterval);
          this.pollInterval = null;
          console.log('[MeetingMind] Tactiq transcript container found');
        }
      }, 2000);
    }
  }

  stop(): void {
    console.log('[MeetingMind] Stopping Tactiq scraper');
    this.observer?.disconnect();
    this.observer = null;
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
    if (this.backupPollInterval) {
      clearInterval(this.backupPollInterval);
      this.backupPollInterval = null;
    }
    this.seenTexts.clear();
    this.entryIds.clear();
    this.lastSpeaker = '';
    this.container = null;
  }

  private findContainerAndObserve(): void {
    const container = this.findTranscriptContainer();
    if (!container) return;

    this.container = container;
    this.attachObserver(container);
  }

  /**
   * Find Tactiq's scrollable transcript container.
   *
   * Strategy: Look for a scrollable div that contains entries with
   * the Tactiq speaker name color (#6dcc6d) or the known entry structure.
   */
  private findTranscriptContainer(): Element | null {
    // Strategy 1: Find a speaker element and walk up to the scroll container
    const speakerEl = document.querySelector('div[class*="text-[#6dcc6d]"]');
    if (speakerEl) {
      // Walk up ancestors until we find the overflow-y-auto scroll container
      // (can be 6+ levels up due to wrapper divs)
      let el: Element | null = speakerEl;
      for (let i = 0; i < 15 && el; i++) {
        el = el.parentElement;
        if (el?.className?.includes('overflow-y-auto')) {
          console.log(`[MeetingMind] Found scroll container at level ${i + 1}, children: ${el.children.length}`);
          return el;
        }
      }
    }

    // Strategy 2: Look for Tactiq's panel background and find scroll child
    const panel = document.querySelector('div[class*="bg-[#212225]"]');
    if (panel) {
      const scrollChild = panel.querySelector('[class*="overflow-y-auto"]');
      if (scrollChild) return scrollChild;
    }

    return null;
  }

  private attachObserver(container: Element): void {
    // Process any existing entries
    this.processAllEntries(container);

    this.observer = new MutationObserver(() => {
      this.processAllEntries(container);
    });

    this.observer.observe(container, {
      childList: true,
      subtree: true,
      characterData: true,
    });

    // Safety net: poll every 3s in case MutationObserver misses updates
    this.backupPollInterval = setInterval(() => {
      if (this.container) this.processAllEntries(this.container);
    }, 3000);
  }

  private processAllEntries(container: Element): void {
    // Find all entry wrappers that contain transcript text.
    // Entries are nested several levels deep in wrapper divs, so query
    // for all elements containing the text class, then use their closest
    // "flex flex-col" ancestor as the entry boundary.
    const textEls = container.querySelectorAll(
      'div[class*="flex-1"][class*="break-words"], div[class*="font-medium"][class*="break-words"]'
    );

    // Deduplicate: multiple text selectors might match the same element
    const seen = new Set<Element>();
    const candidates: Element[] = [];
    for (const textEl of textEls) {
      // Walk up to find the entry wrapper (has flex-col + px-2.5 or similar)
      let entry: Element | null = textEl;
      for (let i = 0; i < 5 && entry; i++) {
        entry = entry.parentElement;
        if (entry?.className?.includes('flex-col') && entry?.className?.includes('px-')) break;
      }
      if (entry && !seen.has(entry)) {
        seen.add(entry);
        candidates.push(entry);
      }
    }

    for (let i = 0; i < candidates.length; i++) {
      const entry = candidates[i];
      const parsed = this.parseEntry(entry, i);
      if (!parsed) continue;

      const key = `${parsed.index}`;
      const existing = this.seenTexts.get(key);

      // Skip if text hasn't changed (Tactiq updates in-place as speech continues)
      if (existing === parsed.text) continue;

      this.seenTexts.set(key, parsed.text);

      // Use stable ID per entry so the UI can upsert instead of duplicate
      let segId = this.entryIds.get(key);
      if (!segId) {
        segId = crypto.randomUUID();
        this.entryIds.set(key, segId);
      }

      const segment: TranscriptSegment = {
        id: segId,
        speaker: 0,
        speakerLabel: parsed.speaker,
        text: parsed.text,
        timestamp: Date.now(),
        isFinal: true,
        source: 'tactiq',
      };

      this.onSegment(segment);
    }
  }

  private parseEntry(
    el: Element,
    index: number
  ): { speaker: string; text: string; index: number } | null {
    const speakerEl = el.querySelector('div[class*="text-[#6dcc6d]"]');
    const textEl = el.querySelector('div[class*="flex-1"][class*="break-words"]') ||
                   el.querySelector('div[class*="font-medium"][class*="break-words"]');

    if (textEl) {
      const text = textEl.textContent?.trim() || '';
      if (!text) return null;

      let speaker = '';
      if (speakerEl) {
        speaker = speakerEl.textContent?.trim() || '';
        if (speaker) this.lastSpeaker = speaker;
      } else {
        speaker = this.lastSpeaker;
      }

      if (speaker && text) {
        return { speaker, text, index };
      }
    }

    return null;
  }
}
