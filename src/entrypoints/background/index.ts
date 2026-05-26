import { DeepgramClient } from '../../lib/deepgram';
import type { TranscriptSegment } from '../../types';

export default defineBackground(() => {
  // Open side panel when extension icon is clicked
  browser.sidePanel
    .setPanelBehavior({ openPanelOnActionClick: true })
    .catch(console.error);

  let offscreenDocCreated = false;
  let tactiqAvailable = false;
  let activeSource: 'tactiq' | 'deepgram' | null = null;
  let deepgramClient: DeepgramClient | null = null;

  async function ensureOffscreenDocument() {
    if (offscreenDocCreated) return;

    const existingContexts = await (chrome as any).runtime.getContexts({
      contextTypes: ['OFFSCREEN_DOCUMENT'],
    });

    if (existingContexts.length > 0) {
      offscreenDocCreated = true;
      return;
    }

    await (chrome as any).offscreen.createDocument({
      url: chrome.runtime.getURL('/offscreen.html'),
      reasons: ['USER_MEDIA'],
      justification: 'Capture tab audio for transcription',
    });
    offscreenDocCreated = true;
  }

  // Handle file transcription via Deepgram REST API
  async function handleTranscribeFile(fileData: number[], apiKey: string) {
    try {
      const { transcribeFile } = await import('../../lib/deepgram-batch');
      const buffer = new Uint8Array(fileData).buffer;

      const segments = await transcribeFile(buffer, apiKey, (status) => {
        chrome.runtime.sendMessage({
          type: 'TRANSCRIBE_FILE_PROGRESS',
          status,
        }).catch(() => {});
      });

      chrome.runtime.sendMessage({
        type: 'TRANSCRIBE_FILE_RESULT',
        segments,
      }).catch(() => {});
    } catch (err) {
      chrome.runtime.sendMessage({
        type: 'TRANSCRIBE_FILE_ERROR',
        error: err instanceof Error ? err.message : 'Transcription failed',
      }).catch(() => {});
    }
  }

  // Listen for messages from side panel, content scripts, and offscreen
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'TACTIQ_AVAILABLE') {
      tactiqAvailable = message.available;
      // Forward to side panel
      chrome.runtime.sendMessage({
        type: 'TACTIQ_AVAILABLE',
        available: message.available,
      }).catch(() => {});
      sendResponse({ ok: true });
    } else if (message.type === 'START_CAPTURE') {
      if (message.source === 'tactiq') {
        // Start Tactiq scraping via content script
        handleStartTactiq(message.tabId);
        sendResponse({ ok: true });
      } else {
        // Deepgram path: audio capture via offscreen doc
        handleStartDeepgram(message.tabId);
        sendResponse({ ok: true });
      }
    } else if (message.type === 'STOP_CAPTURE') {
      if (activeSource === 'tactiq') {
        // Tell content script to stop scraping
        chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
          if (tabs[0]?.id) {
            chrome.tabs.sendMessage(tabs[0].id, { type: 'STOP_TACTIQ' });
          }
        });
      } else {
        // Stop Deepgram client
        if (deepgramClient) {
          deepgramClient.disconnect();
          deepgramClient = null;
        }
        chrome.runtime.sendMessage({ type: 'STOP_CAPTURE' });
      }
      activeSource = null;
      sendResponse({ ok: true });
    } else if (message.type === 'GET_TACTIQ_STATUS') {
      sendResponse({ available: tactiqAvailable });
    } else if (message.type === 'POP_OUT') {
      chrome.windows.create({
        url: chrome.runtime.getURL('/sidepanel.html?popout=1'),
        type: 'popup',
        width: 420,
        height: 700,
      });
      sendResponse({ ok: true });
    } else if (message.type === 'TRANSCRIBE_FILE') {
      handleTranscribeFile(message.fileData, message.apiKey);
      sendResponse({ ok: true });
    } else if (message.type === 'AUDIO_DATA') {
      if (deepgramClient && message.data) {
        const audioData = new Uint8Array(message.data);
        deepgramClient.sendAudio(audioData);
      }
      sendResponse({ ok: true });
    } else if (message.type === 'TRANSCRIPT') {
      console.log('[MeetingMind BG] TRANSCRIPT segment from', message.segment?.speakerLabel);
      // Forward to side panel (content script sendMessage reaches extension pages,
      // but re-broadcast in case side panel missed it)
      chrome.runtime.sendMessage({ type: 'TRANSCRIPT', segment: message.segment }).catch(() => {});
    }
    return true;
  });

  async function handleStartTactiq(tabId: number) {
    activeSource = 'tactiq';
    console.log('[MeetingMind BG] Sending START_TACTIQ to tab', tabId);
    try {
      await chrome.tabs.sendMessage(tabId, { type: 'START_TACTIQ' });
      console.log('[MeetingMind BG] START_TACTIQ delivered');
    } catch (err) {
      console.error('[MeetingMind BG] Failed to send START_TACTIQ to tab:', err);
    }
    // Notify side panel directly — don't rely on content script echo
    chrome.runtime.sendMessage({ type: 'CAPTURE_STATUS', active: true }).catch(() => {});
  }

  async function handleStartDeepgram(tabId: number) {
    activeSource = 'deepgram';

    // Get Deepgram API key from storage
    const result = await chrome.storage.local.get('apiKeys');
    const apiKeys = result.apiKeys as { deepgram?: string; anthropic?: string } | undefined;
    const deepgramApiKey = apiKeys?.deepgram;

    if (!deepgramApiKey) {
      console.error('[MeetingMind] No Deepgram API key configured');
      chrome.runtime.sendMessage({ type: 'CAPTURE_STATUS', active: false }).catch(() => {});
      return;
    }

    // Initialize Deepgram client
    deepgramClient = new DeepgramClient(deepgramApiKey, (segment: TranscriptSegment) => {
      // Forward transcript segments to side panel
      chrome.runtime.sendMessage({ type: 'TRANSCRIPT', segment }).catch(() => {});
    });
    deepgramClient.connect();

    await ensureOffscreenDocument();

    // Get the tab object for desktopCapture (required when calling from service worker)
    const tab = await chrome.tabs.get(tabId);

    // Use desktopCapture API - shows a picker dialog for the user to select the tab
    const streamId = await new Promise<string | null>((resolve) => {
      // When called from service worker, must pass tab as second argument
      chrome.desktopCapture.chooseDesktopMedia(
        ['tab', 'audio'],
        tab,
        (id) => {
          if (chrome.runtime.lastError) {
            console.error('[MeetingMind] Desktop capture failed:', chrome.runtime.lastError.message);
            resolve(null);
          } else if (!id) {
            console.error('[MeetingMind] User cancelled capture dialog');
            resolve(null);
          } else {
            console.log('[MeetingMind] Desktop capture approved, streamId:', id);
            resolve(id);
          }
        }
      );
    });

    if (!streamId) {
      console.error('[MeetingMind] Failed to get stream ID - capture not started');
      chrome.runtime.sendMessage({
        type: 'CAPTURE_ERROR',
        error: 'Capture cancelled or failed. Click Start again and select the tab with your meeting.'
      }).catch(() => {});
      if (deepgramClient) {
        deepgramClient.disconnect();
        deepgramClient = null;
      }
      activeSource = null;
      return;
    }

    console.log('[MeetingMind] Got stream ID, sending to offscreen');

    // Send the stream ID to the offscreen document for capture
    chrome.runtime.sendMessage({
      type: 'START_CAPTURE',
      target: 'offscreen',
      streamId,
    });
  }
});
