// Offscreen document: captures tab audio via tabCapture stream
// and sends audio chunks to the service worker for transcription

let mediaRecorder: MediaRecorder | null = null;
let audioStream: MediaStream | null = null;

chrome.runtime.onMessage.addListener((message) => {
  if (message.type === 'START_CAPTURE' && message.target === 'offscreen') {
    startCapture(message.streamId);
  } else if (message.type === 'STOP_CAPTURE') {
    stopCapture();
  }
});

async function startCapture(streamId: string) {
  try {
    audioStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        mandatory: {
          chromeMediaSource: 'tab',
          chromeMediaSourceId: streamId,
        },
      } as any,
    });

    // Create AudioContext to keep audio playing to user
    const audioCtx = new AudioContext();
    const source = audioCtx.createMediaStreamSource(audioStream);
    source.connect(audioCtx.destination);

    // Record audio chunks for transcription
    mediaRecorder = new MediaRecorder(audioStream, {
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

    // Chunk every 250ms for streaming transcription
    mediaRecorder.start(250);

    chrome.runtime.sendMessage({ type: 'CAPTURE_STATUS', active: true });
    console.log('[MeetingMind] Audio capture started');
  } catch (err) {
    console.error('[MeetingMind] Failed to start capture:', err);
  }
}

function stopCapture() {
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    mediaRecorder.stop();
  }
  if (audioStream) {
    audioStream.getTracks().forEach((t) => t.stop());
    audioStream = null;
  }
  mediaRecorder = null;
  chrome.runtime.sendMessage({ type: 'CAPTURE_STATUS', active: false });
  console.log('[MeetingMind] Audio capture stopped');
}
