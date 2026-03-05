export type TranscriptionSource = 'tactiq' | 'deepgram';

export interface TranscriptSegment {
  id: string;
  speaker: number;
  speakerLabel?: string;
  text: string;
  timestamp: number;
  isFinal: boolean;
  source?: TranscriptionSource;
}

export interface Meeting {
  id: string;
  title: string;
  mode: MeetingMode;
  startTime: number;
  endTime?: number;
  speakers: Record<number, string>;
  contextDocs: ContextDoc[];
  frameworks: string[];
  isImported?: boolean;
}

export type MeetingMode = 'interview' | 'parent-teacher' | 'financial' | 'general' | 'mock-interview';

export interface MockQA {
  question: string;
  answer: string;
  feedback?: string;
}

export interface ContextDoc {
  id: string;
  title: string;
  content: string;
  source: 'manual' | 'lifeos';
}

export interface Suggestion {
  id: string;
  text: string;
  framework?: string;
  timestamp: number;
  pinned: boolean;
  dismissed: boolean;
  triggerText: string;
}

export type MessageType =
  | { type: 'START_CAPTURE'; tabId: number }
  | { type: 'STOP_CAPTURE' }
  | { type: 'AUDIO_DATA'; data: ArrayBuffer }
  | { type: 'TRANSCRIPT'; segment: TranscriptSegment }
  | { type: 'REQUEST_SUGGESTION'; transcript: string }
  | { type: 'SUGGESTION'; suggestion: Suggestion }
  | { type: 'CAPTURE_STATUS'; active: boolean }
  | { type: 'TACTIQ_AVAILABLE'; available: boolean }
  | { type: 'START_TACTIQ' }
  | { type: 'STOP_TACTIQ' }
  | { type: 'TRANSCRIBE_FILE'; fileData: number[]; apiKey: string }
  | { type: 'TRANSCRIBE_FILE_RESULT'; segments: TranscriptSegment[] }
  | { type: 'TRANSCRIBE_FILE_ERROR'; error: string }
  | { type: 'TRANSCRIBE_FILE_PROGRESS'; status: string }
  | { type: 'POP_OUT' };
