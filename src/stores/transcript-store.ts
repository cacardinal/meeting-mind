import { create } from 'zustand';
import type { TranscriptSegment, Suggestion } from '../types';

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
}

export const useTranscriptStore = create<TranscriptState>((set) => ({
  segments: [],
  suggestions: [],
  isCapturing: false,
  speakers: {},

  addSegment: (segment) =>
    set((state) => {
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
    set((state) => ({ suggestions: [suggestion, ...state.suggestions] })),

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

  clear: () => set({ segments: [], suggestions: [] }),
}));
