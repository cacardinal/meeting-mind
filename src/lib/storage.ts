import type { Meeting, TranscriptSegment, Suggestion } from '../types';

const DB_NAME = 'meetingmind';
const DB_VERSION = 1;

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains('meetings')) {
        db.createObjectStore('meetings', { keyPath: 'id' });
      }
      if (!db.objectStoreNames.contains('transcripts')) {
        const store = db.createObjectStore('transcripts', { keyPath: 'id' });
        store.createIndex('meetingId', 'meetingId');
      }
      if (!db.objectStoreNames.contains('suggestions')) {
        const store = db.createObjectStore('suggestions', { keyPath: 'id' });
        store.createIndex('meetingId', 'meetingId');
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function saveMeeting(meeting: Meeting) {
  const db = await openDB();
  const tx = db.transaction('meetings', 'readwrite');
  tx.objectStore('meetings').put(meeting);
  return new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function saveTranscriptSegment(
  meetingId: string,
  segment: TranscriptSegment
) {
  const db = await openDB();
  const tx = db.transaction('transcripts', 'readwrite');
  tx.objectStore('transcripts').put({ ...segment, meetingId });
  return new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function getMeetings(): Promise<Meeting[]> {
  const db = await openDB();
  const tx = db.transaction('meetings', 'readonly');
  const request = tx.objectStore('meetings').getAll();
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function getTranscriptForMeeting(
  meetingId: string
): Promise<TranscriptSegment[]> {
  const db = await openDB();
  const tx = db.transaction('transcripts', 'readonly');
  const index = tx.objectStore('transcripts').index('meetingId');
  const request = index.getAll(meetingId);
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export function exportToMarkdown(
  meeting: Meeting,
  segments: TranscriptSegment[],
  suggestions: Suggestion[]
): string {
  const date = new Date(meeting.startTime).toISOString().split('T')[0];
  const lines: string[] = [
    `# ${meeting.title}`,
    `**Date:** ${date}`,
    `**Mode:** ${meeting.mode}`,
    '',
    '## Transcript',
    '',
  ];

  let currentSpeaker = -1;
  for (const seg of segments) {
    if (!seg.isFinal) continue;
    if (seg.speaker !== currentSpeaker) {
      currentSpeaker = seg.speaker;
      const label =
        meeting.speakers[seg.speaker] || `Speaker ${seg.speaker}`;
      lines.push('', `**${label}:**`);
    }
    lines.push(seg.text);
  }

  if (suggestions.length > 0) {
    lines.push('', '## AI Suggestions', '');
    for (const s of suggestions.filter((s) => s.pinned)) {
      lines.push(`- ${s.framework ? `[${s.framework}] ` : ''}${s.text}`, '');
    }
  }

  return lines.join('\n');
}
