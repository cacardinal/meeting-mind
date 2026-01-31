import { TactiqScraper } from '../../lib/tactiq-scraper';

type MeetingPlatform = 'google-meet' | 'zoom' | 'teams';

function detectPlatform(): MeetingPlatform {
  const host = window.location.hostname;
  if (host.includes('zoom.us')) return 'zoom';
  if (host.includes('teams.microsoft.com') || host.includes('teams.live.com')) return 'teams';
  return 'google-meet';
}

export default defineContentScript({
  matches: [
    '*://meet.google.com/*',
    '*://*.zoom.us/wc/*',        // Zoom Web Client
    '*://*.zoom.us/j/*',         // Zoom join links
    '*://teams.microsoft.com/*', // Microsoft Teams
    '*://teams.live.com/*',      // Teams free/personal
  ],

  main() {
    const platform = detectPlatform();
    console.log(`[MeetingMind] Detected ${platform} page`);

    let scraper: TactiqScraper | null = null;

    // Check for Tactiq after a short delay (it may load after page)
    const checkTactiq = () => {
      const available = TactiqScraper.detect();
      chrome.runtime.sendMessage({ type: 'TACTIQ_AVAILABLE', available });
      return available;
    };

    // Initial check + delayed retries
    checkTactiq();
    setTimeout(checkTactiq, 3000);
    setTimeout(checkTactiq, 8000);

    // Notify background that we're on a meeting page
    chrome.runtime.sendMessage({
      type: 'MEET_DETECTED',
      platform,
      tabId: undefined,
    });

    // Listen for start/stop commands from background
    chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
      console.log('[MeetingMind CS] Received message:', message.type);

      if (message.type === 'START_TACTIQ') {
        console.log('[MeetingMind CS] Starting Tactiq scraper');
        if (scraper) scraper.stop();
        scraper = new TactiqScraper((segment) => {
          console.log('[MeetingMind CS] Segment:', segment.speakerLabel, segment.text.substring(0, 50));
          chrome.runtime.sendMessage({ type: 'TRANSCRIPT', segment }).catch(() => {});
        });
        scraper.start();
        sendResponse({ ok: true });
      }

      if (message.type === 'STOP_TACTIQ') {
        scraper?.stop();
        scraper = null;
        sendResponse({ ok: true });
      }

      return true;
    });
  },
});
