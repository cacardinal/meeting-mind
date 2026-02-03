import { create } from 'zustand';
import type { TranscriptSegment, Suggestion } from '../types';
import { saveTranscriptSegment, saveSuggestion } from '../lib/storage';

// Current meeting ID for persistence (set by App.tsx)
let currentMeetingId: string | null = null;

export function setCurrentMeetingId(id: string | null) {
  currentMeetingId = id;
}

interface TranscriptState {
  segments: TranscriptSegment[];
  suggestions: Suggestion[];
  isCapturing: boolean;
  speakers: Record<number, string>;

  addSegment: (segment: TranscriptSegment) => void;
  updateSegment: (id: string, updates: Partial<TranscriptSegment>) => void;
  addSuggestion: (suggestion: Suggestion) => void;
  updateSuggestionText: (id: string, text: string) => void;
  dismissSuggestion: (id: string) => void;
  pinSuggestion: (id: string) => void;
  setCapturing: (active: boolean) => void;
  setSpeakerLabel: (speakerId: number, label: string) => void;
  clear: () => void;
  // Recovery functions
  restoreSegments: (segments: TranscriptSegment[]) => void;
  restoreSuggestions: (suggestions: Suggestion[]) => void;
}

export const useTranscriptStore = create<TranscriptState>((set) => ({
  segments: [],
  suggestions: [],
  isCapturing: false,
  speakers: {},

  addSegment: (segment) =>
    set((state) => {
      // Persist to IndexedDB if we have a meeting ID
      if (currentMeetingId) {
        saveTranscriptSegment(currentMeetingId, segment).catch(console.error);
      }
      // Upsert: if segment with same ID exists, update it (Tactiq in-place edits)
      const idx = state.segments.findIndex((s) => s.id === segment.id);
      if (idx >= 0) {
        const updated = [...state.segments];
        updated[idx] = segment;
        return { segments: updated };
      }
      return { segments: [...state.segments, segment] };
    }),

  updateSegment: (id, updates) =>
    set((state) => ({
      segments: state.segments.map((s) =>
        s.id === id ? { ...s, ...updates } : s
      ),
    })),

  addSuggestion: (suggestion) =>
    set((state) => {
      // Persist to IndexedDB if we have a meeting ID
      if (currentMeetingId) {
        saveSuggestion(currentMeetingId, suggestion).catch(console.error);
      }
      return { suggestions: [suggestion, ...state.suggestions] };
    }),

  updateSuggestionText: (id, text) =>
    set((state) => ({
      suggestions: state.suggestions.map((s) =>
        s.id === id ? { ...s, text } : s
      ),
    })),

  dismissSuggestion: (id) =>
    set((state) => ({
      suggestions: state.suggestions.map((s) =>
        s.id === id ? { ...s, dismissed: true } : s
      ),
    })),

  pinSuggestion: (id) =>
    set((state) => ({
      suggestions: state.suggestions.map((s) =>
        s.id === id ? { ...s, pinned: !s.pinned } : s
      ),
    })),

  setCapturing: (active) => set({ isCapturing: active }),

  setSpeakerLabel: (speakerId, label) =>
    set((state) => ({
      speakers: { ...state.speakers, [speakerId]: label },
    })),

  clear: () => set({ segments: [], suggestions: [], speakers: {} }),

  // Recovery functions
  restoreSegments: (segments) => set({ segments }),
  restoreSuggestions: (suggestions) => set({ suggestions }),
}));
