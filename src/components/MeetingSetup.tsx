import React, { useState } from 'react';
import { useMeetingStore } from '../stores/meeting-store';
import type { MeetingMode, ContextDoc, TranscriptionSource } from '../types';

interface Props {
  onStart: (title: string) => void;
}

const MODES: { value: MeetingMode; label: string; description: string }[] = [
  {
    value: 'interview',
    label: 'Interview',
    description: 'Job interviews with STAR frameworks and talking points',
  },
  {
    value: 'parent-teacher',
    label: 'Parent-Teacher',
    description: 'School conferences with questions and follow-ups',
  },
  {
    value: 'financial',
    label: 'Financial',
    description: 'Advisory meetings with clarifying questions',
  },
  {
    value: 'general',
    label: 'General',
    description: 'Any meeting with summarization and action items',
  },
  {
    value: 'mock-interview',
    label: 'Mock Interview',
    description: 'Practice with AI interviewer — get questions and feedback',
  },
];

export function MeetingSetup({ onStart }: Props) {
  const [title, setTitle] = useState('');
  const [contextText, setContextText] = useState('');
  const { mode, setMode, addContextDoc, contextDocs, removeContextDoc, transcriptionSource, setTranscriptionSource, tactiqAvailable, apiKeys } =
    useMeetingStore();

  const handleAddContext = () => {
    if (!contextText.trim()) return;
    addContextDoc({
      id: crypto.randomUUID(),
      title: `Context ${contextDocs.length + 1}`,
      content: contextText.trim(),
      source: 'manual',
    });
    setContextText('');
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files) return;
    for (const file of Array.from(files)) {
      const text = await file.text();
      addContextDoc({
        id: crypto.randomUUID(),
        title: file.name,
        content: text,
        source: 'manual',
      });
    }
    e.target.value = '';
  };

  return (
    <div className="flex-1 overflow-y-auto px-4 py-4 space-y-5">
      {/* Meeting title */}
      <div>
        <label className="block text-xs font-medium text-gray-400 mb-1.5">
          Meeting Title
        </label>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="e.g. Virta Health — Karthik Interview"
          className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded-md text-sm text-gray-100 placeholder:text-gray-600 focus:outline-none focus:border-blue-500"
        />
      </div>

      {/* Mode selection */}
      <div>
        <label className="block text-xs font-medium text-gray-400 mb-1.5">
          Meeting Mode
        </label>
        <div className="grid grid-cols-2 gap-2">
          {MODES.map((m) => (
            <button
              key={m.value}
              onClick={() => setMode(m.value)}
              className={`p-2.5 rounded-md border text-left transition-colors ${
                mode === m.value
                  ? 'border-blue-500 bg-blue-950/40'
                  : 'border-gray-700 bg-gray-900 hover:border-gray-600'
              }`}
            >
              <div className="text-sm font-medium">{m.label}</div>
              <div className="text-xs text-gray-500 mt-0.5">
                {m.description}
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* Transcription source */}
      <div>
        <label className="block text-xs font-medium text-gray-400 mb-1.5">
          Transcription Source
        </label>
        <div className="grid grid-cols-2 gap-2">
          <button
            onClick={() => setTranscriptionSource('tactiq')}
            className={`p-2.5 rounded-md border text-left transition-colors ${
              transcriptionSource === 'tactiq'
                ? 'border-blue-500 bg-blue-950/40'
                : 'border-gray-700 bg-gray-900 hover:border-gray-600'
            }`}
          >
            <div className="text-sm font-medium flex items-center gap-1.5">
              Tactiq
              {tactiqAvailable && (
                <span className="w-1.5 h-1.5 rounded-full bg-green-500" />
              )}
            </div>
            <div className="text-xs text-gray-500 mt-0.5">
              {tactiqAvailable ? 'Detected — ready' : 'Not detected'}
            </div>
          </button>
          <button
            onClick={() => setTranscriptionSource('deepgram')}
            className={`p-2.5 rounded-md border text-left transition-colors ${
              transcriptionSource === 'deepgram'
                ? 'border-blue-500 bg-blue-950/40'
                : 'border-gray-700 bg-gray-900 hover:border-gray-600'
            }`}
          >
            <div className="text-sm font-medium">Deepgram</div>
            <div className="text-xs text-gray-500 mt-0.5">
              {apiKeys.deepgram ? 'API key set' : 'Requires API key'}
            </div>
          </button>
        </div>
        {transcriptionSource === 'deepgram' && !apiKeys.deepgram && (
          <p className="text-xs text-amber-500 mt-1.5">
            Set a Deepgram API key in Settings first.
          </p>
        )}
      </div>

      {/* Context docs */}
      <div>
        <label className="block text-xs font-medium text-gray-400 mb-1.5">
          Context Documents
        </label>

        {contextDocs.length > 0 && (
          <div className="space-y-1.5 mb-3">
            {contextDocs.map((doc) => (
              <div
                key={doc.id}
                className="flex items-center justify-between px-3 py-2 bg-gray-900 rounded-md border border-gray-700"
              >
                <span className="text-sm text-gray-300 truncate">
                  {doc.title}
                </span>
                <button
                  onClick={() => removeContextDoc(doc.id)}
                  className="text-gray-500 hover:text-red-400 text-xs ml-2"
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        )}

        <textarea
          value={contextText}
          onChange={(e) => setContextText(e.target.value)}
          placeholder="Paste context here (company info, talking points, etc.)"
          rows={4}
          className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded-md text-sm text-gray-100 placeholder:text-gray-600 focus:outline-none focus:border-blue-500 resize-none"
        />
        <div className="flex gap-2 mt-2">
          <button
            onClick={handleAddContext}
            disabled={!contextText.trim()}
            className="px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 disabled:opacity-40 rounded-md transition-colors"
          >
            Add Text
          </button>
          <label className="px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 rounded-md transition-colors cursor-pointer">
            Upload File
            <input
              type="file"
              accept=".txt,.md,.json,.csv"
              multiple
              onChange={handleFileUpload}
              className="hidden"
            />
          </label>
        </div>
      </div>

      {/* Start button */}
      <button
        onClick={() => onStart(title || 'Untitled Meeting')}
        className="w-full py-2.5 bg-blue-600 hover:bg-blue-700 text-sm font-medium rounded-md transition-colors"
      >
        Start Meeting
      </button>
    </div>
  );
}
