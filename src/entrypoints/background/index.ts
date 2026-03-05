export default defineBackground(() => {
  // Open side panel when extension icon is clicked
  browser.sidePanel
    .setPanelBehavior({ openPanelOnActionClick: true })
    .catch(console.error);

  let offscreenDocCreated = false;
  let tactiqAvailable = false;
  let activeSource: 'tactiq' | 'deepgram' | null = null;

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
    await ensureOffscreenDocument();

    // Get a MediaStream ID for the tab
    const streamId = await new Promise<string>((resolve) => {
      chrome.tabCapture.getMediaStreamId({ targetTabId: tabId }, (id) => {
        resolve(id);
      });
    });

    // Send the stream ID to the offscreen document for capture
    chrome.runtime.sendMessage({
      type: 'START_CAPTURE',
      target: 'offscreen',
      streamId,
    });
  }
});
