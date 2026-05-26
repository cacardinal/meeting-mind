import { TactiqScraper } from '../../lib/tactiq-scraper';

type MeetingPlatform = 'google-meet' | 'zoom' | 'teams';

function detectPlatform(): MeetingPlatform {
  const host = window.location.hostname;
  if (host.includes('zoom.us')) return 'zoom';
  if (host.includes('teams.microsoft.com') || host.includes('teams.live.com')) return 'teams';
  return 'google-meet';
}

// Audio capture state
let mediaStream: MediaStream | null = null;
let mediaRecorder: MediaRecorder | null = null;
let audioContext: AudioContext | null = null;

async function startAudioCapture(): Promise<boolean> {
  try {
    console.log('[MeetingMind CS] Requesting tab audio capture...');

    // Use getDisplayMedia with preferCurrentTab to capture this tab's audio
    mediaStream = await navigator.mediaDevices.getDisplayMedia({
      video: true, // Required, but we only use audio
      audio: {
        // @ts-ignore - preferCurrentTab is valid but not in TS types
        suppressLocalAudioPlayback: false,
      },
      // @ts-ignore - preferCurrentTab hints to select current tab
      preferCurrentTab: true,
    });

    // Stop the video track immediately - we only want audio
    mediaStream.getVideoTracks().forEach(track => track.stop());

    const audioTracks = mediaStream.getAudioTracks();
    if (audioTracks.length === 0) {
      console.error('[MeetingMind CS] No audio track in captured stream');
      return false;
    }

    console.log('[MeetingMind CS] Got audio track:', audioTracks[0].label);

    // Keep audio playing to user via AudioContext
    audioContext = new AudioContext();
    const source = audioContext.createMediaStreamSource(mediaStream);
    source.connect(audioContext.destination);

    // Record and send chunks to background
    mediaRecorder = new MediaRecorder(mediaStream, {
      mimeType: 'audio/webm;codecs=opus',
    });

    mediaRecorder.ondataavailable = async (event) => {
      if (event.data.size > 0) {
        const buffer = await event.data.arrayBuffer();
        chrome.runtime.sendMessage({
          type: 'AUDIO_DATA',
          data: Array.from(new Uint8Array(buffer)),
        });
      }
    };

    mediaRecorder.start(250); // Chunk every 250ms
    chrome.runtime.sendMessage({ type: 'CAPTURE_STATUS', active: true });
    console.log('[MeetingMind CS] Audio capture started');
    return true;
  } catch (err) {
    console.error('[MeetingMind CS] Failed to capture audio:', err);
    chrome.runtime.sendMessage({
      type: 'CAPTURE_ERROR',
      error: 'Failed to capture tab audio. Make sure to select the current tab and enable audio sharing.',
    });
    return false;
  }
}

function stopAudioCapture() {
  console.log('[MeetingMind CS] Stopping audio capture');
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    mediaRecorder.stop();
  }
  if (mediaStream) {
    mediaStream.getTracks().forEach(t => t.stop());
    mediaStream = null;
  }
  if (audioContext) {
    audioContext.close();
    audioContext = null;
  }
  mediaRecorder = null;
  chrome.runtime.sendMessage({ type: 'CAPTURE_STATUS', active: false });
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

      if (message.type === 'START_AUDIO_CAPTURE') {
        startAudioCapture().then(success => {
          sendResponse({ ok: success });
        });
        return true; // Keep channel open for async response
      }

      if (message.type === 'STOP_AUDIO_CAPTURE') {
        stopAudioCapture();
        sendResponse({ ok: true });
      }

      return true;
    });
  },
});
