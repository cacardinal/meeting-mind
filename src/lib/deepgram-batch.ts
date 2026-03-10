import type { TranscriptSegment } from '../types';

interface DeepgramUtterance {
  start: number;
  end: number;
  transcript: string;
  speaker: number;
  channel: number;
}

interface DeepgramBatchResponse {
  results?: {
    utterances?: DeepgramUtterance[];
  };
}

function formatTimestamp(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

export async function transcribeFile(
  fileData: ArrayBuffer,
  apiKey: string,
  onProgress?: (status: string) => void
): Promise<TranscriptSegment[]> {
  onProgress?.('Uploading to Deepgram...');

  const params = new URLSearchParams({
    model: 'nova-3',
    language: 'en',
    smart_format: 'true',
    diarize: 'true',
    utterances: 'true',
    punctuate: 'true',
  });

  const response = await fetch(
    `https://api.deepgram.com/v1/listen?${params}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Token ${apiKey}`,
        'Content-Type': 'application/octet-stream',
      },
      body: fileData,
    }
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Deepgram API error (${response.status}): ${text}`);
  }

  onProgress?.('Processing transcript...');

  const data: DeepgramBatchResponse = await response.json();
  const utterances = data.results?.utterances ?? [];

  if (utterances.length === 0) {
    throw new Error('Deepgram returned no utterances. The audio may be empty or unrecognizable.');
  }

  return utterances.map((u) => ({
    id: crypto.randomUUID(),
    speaker: u.speaker,
    speakerLabel: `Speaker ${u.speaker}`,
    text: u.transcript,
    timestamp: u.start * 1000, // Convert to milliseconds
    isFinal: true,
    source: 'deepgram' as const,
  }));
}
