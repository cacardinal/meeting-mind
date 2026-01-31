import type { TranscriptSegment } from '../types';

export class DeepgramClient {
  private ws: WebSocket | null = null;
  private apiKey: string;
  private onTranscript: (segment: TranscriptSegment) => void;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;

  constructor(
    apiKey: string,
    onTranscript: (segment: TranscriptSegment) => void
  ) {
    this.apiKey = apiKey;
    this.onTranscript = onTranscript;
  }

  connect() {
    const params = new URLSearchParams({
      model: 'nova-3',
      language: 'en',
      smart_format: 'true',
      diarize: 'true',
      interim_results: 'true',
      utterance_end_ms: '1000',
      vad_events: 'true',
      encoding: 'opus',
      sample_rate: '48000',
    });

    this.ws = new WebSocket(
      `wss://api.deepgram.com/v1/listen?${params}`,
      ['token', this.apiKey]
    );

    this.ws.onopen = () => {
      console.log('[MeetingMind] Deepgram connected');
      this.reconnectAttempts = 0;
    };

    this.ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'Results' && data.channel?.alternatives?.[0]) {
          const alt = data.channel.alternatives[0];
          if (!alt.transcript) return;

          const segment: TranscriptSegment = {
            id: crypto.randomUUID(),
            speaker: alt.words?.[0]?.speaker ?? 0,
            text: alt.transcript,
            timestamp: Date.now(),
            isFinal: data.is_final === true,
          };

          this.onTranscript(segment);
        }
      } catch (err) {
        console.error('[MeetingMind] Parse error:', err);
      }
    };

    this.ws.onerror = (err) => {
      console.error('[MeetingMind] Deepgram error:', err);
    };

    this.ws.onclose = () => {
      console.log('[MeetingMind] Deepgram disconnected');
      this.attemptReconnect();
    };
  }

  sendAudio(data: Uint8Array) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(data);
    }
  }

  disconnect() {
    this.reconnectAttempts = this.maxReconnectAttempts; // prevent reconnect
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) return;
    this.reconnectAttempts++;
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
    console.log(
      `[MeetingMind] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`
    );
    setTimeout(() => this.connect(), delay);
  }
}
