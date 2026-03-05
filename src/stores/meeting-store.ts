import { create } from 'zustand';
import type { Meeting, MeetingMode, ContextDoc, TranscriptionSource, MockQA } from '../types';

interface MeetingState {
  currentMeeting: Meeting | null;
  mode: MeetingMode;
  contextDocs: ContextDoc[];
  frameworks: string[];
  apiKeys: { deepgram: string; anthropic: string };
  transcriptionSource: TranscriptionSource;
  tactiqAvailable: boolean;
  mockHistory: MockQA[];
  importFile: File | null;

  setMode: (mode: MeetingMode) => void;
  addContextDoc: (doc: ContextDoc) => void;
  removeContextDoc: (id: string) => void;
  setFrameworks: (frameworks: string[]) => void;
  startMeeting: (title: string) => void;
  startImportedMeeting: (title: string) => void;
  endMeeting: () => void;
  setApiKeys: (keys: Partial<MeetingState['apiKeys']>) => void;
  setTranscriptionSource: (source: TranscriptionSource) => void;
  setTactiqAvailable: (available: boolean) => void;
  addMockQA: (qa: MockQA) => void;
  clearMockHistory: () => void;
  setImportFile: (file: File | null) => void;
}

export const useMeetingStore = create<MeetingState>((set, get) => ({
  currentMeeting: null,
  mode: 'general',
  contextDocs: [],
  frameworks: [],
  apiKeys: { deepgram: '', anthropic: '' },
  transcriptionSource: 'tactiq',
  tactiqAvailable: false,
  mockHistory: [],
  importFile: null,

  setMode: (mode) => set({ mode }),

  addContextDoc: (doc) =>
    set((state) => ({ contextDocs: [...state.contextDocs, doc] })),

  removeContextDoc: (id) =>
    set((state) => ({
      contextDocs: state.contextDocs.filter((d) => d.id !== id),
    })),

  setFrameworks: (frameworks) => set({ frameworks }),

  startMeeting: (title) =>
    set((state) => ({
      currentMeeting: {
        id: crypto.randomUUID(),
        title,
        mode: state.mode,
        startTime: Date.now(),
        speakers: {},
        contextDocs: state.contextDocs,
        frameworks: state.frameworks,
      },
    })),

  endMeeting: () =>
    set((state) => ({
      currentMeeting: state.currentMeeting
        ? { ...state.currentMeeting, endTime: Date.now() }
        : null,
    })),

  setApiKeys: (keys) =>
    set((state) => ({
      apiKeys: { ...state.apiKeys, ...keys },
    })),

  setTranscriptionSource: (source) => set({ transcriptionSource: source }),
  setTactiqAvailable: (available) => set({ tactiqAvailable: available }),
  addMockQA: (qa) => set((state) => ({ mockHistory: [...state.mockHistory, qa] })),
  clearMockHistory: () => set({ mockHistory: [] }),
  setImportFile: (file) => set({ importFile: file }),

  startImportedMeeting: (title) =>
    set((state) => ({
      currentMeeting: {
        id: crypto.randomUUID(),
        title,
        mode: state.mode,
        startTime: Date.now(),
        speakers: {},
        contextDocs: state.contextDocs,
        frameworks: state.frameworks,
        isImported: true,
      },
    })),
}));
