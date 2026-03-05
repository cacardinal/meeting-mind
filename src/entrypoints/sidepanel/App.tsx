import React, { useEffect, useCallback, useRef } from 'react';
import { useTranscriptStore, setCurrentMeetingId } from '../../stores/transcript-store';
import { useMeetingStore } from '../../stores/meeting-store';
import { Transcript } from '../../components/Transcript';
import { SuggestionCard } from '../../components/SuggestionCard';
import { MeetingSetup } from '../../components/MeetingSetup';
import { Settings } from '../../components/Settings';
import { generateSuggestion, generateInterviewQuestion } from '../../lib/claude';
import {
  saveMeeting,
  setInProgressMeeting,
  getInProgressMeetingId,
  getMeeting,
  getTranscriptForMeeting,
  getSuggestionsForMeeting,
} from '../../lib/storage';
import { transcribeFile } from '../../lib/deepgram-batch';
import type { Meeting } from '../../types';

type View = 'setup' | 'meeting' | 'summary' | 'settings' | 'importing';

function formatDuration(startTime: number, endTime?: number): string {
  const ms = (endTime || Date.now()) - startTime;
  const mins = Math.floor(ms / 60000);
  if (mins < 60) return `${mins} min`;
  const hrs = Math.floor(mins / 60);
  return `${hrs}h ${mins % 60}m`;
}

function formatTranscriptMarkdown(
  title: string,
  startTime: number,
  endTime: number | undefined,
  segments: { speakerLabel?: string; speaker: number; text: string; isFinal: boolean }[]
): string {
  const date = new Date(startTime).toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
  const duration = formatDuration(startTime, endTime);

  let md = `# Meeting: ${title}\n**Date:** ${date}  **Duration:** ${duration}\n\n---\n\n`;

  let lastSpeaker = '';
  for (const seg of segments) {
    if (!seg.isFinal) continue;
    const speaker = seg.speakerLabel || `Speaker ${seg.speaker}`;
    if (speaker !== lastSpeaker) {
      if (lastSpeaker) md += '\n\n';
      md += `**${speaker}**\n`;
      lastSpeaker = speaker;
    }
    md += seg.text + ' ';
  }

  return md.trimEnd();
}

export default function App() {
  const [view, setView] = React.useState<View>('setup');
  const [copyLabel, setCopyLabel] = React.useState('Copy Transcript');
  const [isGenerating, setIsGenerating] = React.useState(false);
  const [recoveryPrompt, setRecoveryPrompt] = React.useState<Meeting | null>(null);
  const [captureError, setCaptureError] = React.useState<string | null>(null);
  const [importStatus, setImportStatus] = React.useState<string | null>(null);
  const { isCapturing, setCapturing, segments, suggestions, clear: clearTranscript, restoreSegments, restoreSuggestions } =
    useTranscriptStore();
  const { currentMeeting, startMeeting, endMeeting, transcriptionSource, setTactiqAvailable, apiKeys, setApiKeys } = useMeetingStore();
  const suggestionRef = useRef<string | null>(null);
  const mockDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastSegmentCountRef = useRef(0);
  const isPopout = useRef(
    typeof window !== 'undefined' && window.location.search.includes('popout=1')
  );

  // Load API keys and listen for messages
  useEffect(() => {
    chrome.storage.local.get('apiKeys', (result) => {
      if (result.apiKeys) setApiKeys(result.apiKeys);
    });

    const listener = (message: any) => {
      if (message.type === 'CAPTURE_STATUS') {
        setCapturing(message.active);
      }
      if (message.type === 'TRANSCRIPT') {
        useTranscriptStore.getState().addSegment(message.segment);
      }
      if (message.type === 'SUGGESTION') {
        useTranscriptStore.getState().addSuggestion(message.suggestion);
      }
      if (message.type === 'TACTIQ_AVAILABLE') {
        setTactiqAvailable(message.available);
      }
      if (message.type === 'CAPTURE_ERROR') {
        setCaptureError(message.error);
        setCapturing(false);
      }
    };
    chrome.runtime.sendMessage({ type: 'GET_TACTIQ_STATUS' }, (resp) => {
      if (resp?.available) setTactiqAvailable(true);
    });
    chrome.runtime.onMessage.addListener(listener);
    return () => chrome.runtime.onMessage.removeListener(listener);
  }, []);

  // Check for in-progress meeting on mount (crash recovery)
  useEffect(() => {
    async function checkForRecovery() {
      try {
        const inProgressId = await getInProgressMeetingId();
        if (!inProgressId) return;

        const meeting = await getMeeting(inProgressId);
        if (!meeting) {
          // Stale ID, clear it
          await setInProgressMeeting(null);
          return;
        }

        // If meeting has endTime, it was properly ended
        if (meeting.endTime) {
          await setInProgressMeeting(null);
          return;
        }

        // Found an in-progress meeting - show recovery prompt
        setRecoveryPrompt(meeting);
      } catch (err) {
        console.error('[MeetingMind] Recovery check failed:', err);
      }
    }

    checkForRecovery();
  }, []);

  // Handle recovery action
  const handleRecover = useCallback(async () => {
    if (!recoveryPrompt) return;

    try {
      // Restore segments and suggestions from IndexedDB
      const [segments, suggestions] = await Promise.all([
        getTranscriptForMeeting(recoveryPrompt.id),
        getSuggestionsForMeeting(recoveryPrompt.id),
      ]);

      // Restore store state
      restoreSegments(segments);
      restoreSuggestions(suggestions);
      setCurrentMeetingId(recoveryPrompt.id);

      // Restore meeting in meeting store
      useMeetingStore.setState({ currentMeeting: recoveryPrompt });

      setRecoveryPrompt(null);
      setView('meeting');
    } catch (err) {
      console.error('[MeetingMind] Recovery failed:', err);
      setRecoveryPrompt(null);
    }
  }, [recoveryPrompt, restoreSegments, restoreSuggestions]);

  const handleDiscardRecovery = useCallback(async () => {
    await setInProgressMeeting(null);
    setRecoveryPrompt(null);
  }, []);

  // --- Mock Interview: auto-trigger on new speech ---
  const handleMockQuestion = useCallback(async (latestAnswer: string | null) => {
    const { apiKeys, contextDocs, mockHistory } = useMeetingStore.getState();
    if (!apiKeys.anthropic || isGenerating) return;

    setIsGenerating(true);
    const segmentId = crypto.randomUUID();
    suggestionRef.current = segmentId;

    // Add interviewer segment to transcript (streams in-place)
    useTranscriptStore.getState().addSegment({
      id: segmentId,
      speaker: -1,
      speakerLabel: 'Interviewer',
      text: 'Thinking...',
      timestamp: Date.now(),
      isFinal: true,
      source: 'tactiq',
    });

    try {
      const fullText = await generateInterviewQuestion(
        apiKeys.anthropic,
        contextDocs,
        mockHistory,
        latestAnswer,
        (streamedText) => {
          // Update the segment text in-place as it streams
          useTranscriptStore.getState().updateSegment(segmentId, { text: streamedText });
        }
      );

      // Final update with complete text
      useTranscriptStore.getState().updateSegment(segmentId, { text: fullText });

      // Store the Q&A pair
      if (latestAnswer) {
        useMeetingStore.getState().addMockQA({
          question: fullText,
          answer: latestAnswer,
        });
      }

      // Now generate a suggested response outline for the user
      setIsGenerating(false);
      suggestionRef.current = null;

      // Extract just the question part (after "**Question:**" if present)
      const questionMatch = fullText.match(/\*\*Question:\*\*\s*([\s\S]*)/i);
      const questionText = questionMatch ? questionMatch[1].trim() : fullText;

      const { frameworks } = useMeetingStore.getState();
      const allSegs = useTranscriptStore.getState().segments;
      const recentTranscript = allSegs
        .filter((s) => s.isFinal)
        .map((s) => `${s.speakerLabel || 'Speaker'}: ${s.text}`)
        .join('\n')
        .slice(-2000);

      setIsGenerating(true);
      const outlineId = crypto.randomUUID();
      suggestionRef.current = outlineId;
      useTranscriptStore.getState().addSuggestion({
        id: outlineId,
        text: 'Preparing response outline...',
        timestamp: Date.now(),
        pinned: false,
        dismissed: false,
        triggerText: questionText.slice(0, 100),
      });

      try {
        await generateSuggestion(
          apiKeys.anthropic,
          'interview',
          contextDocs,
          frameworks,
          recentTranscript,
          questionText,
          (streamedText) => {
            useTranscriptStore.getState().updateSuggestionText(outlineId, streamedText);
          }
        );
      } catch (suggErr) {
        console.error('[MeetingMind] Suggestion outline error:', suggErr);
      }

      return;
    } catch (err) {
      console.error('[MeetingMind] Mock interview error:', err);
      useTranscriptStore.getState().updateSegment(segmentId, {
        text: `Error: ${err instanceof Error ? err.message : 'Failed to generate question'}`,
      });
    } finally {
      setIsGenerating(false);
      suggestionRef.current = null;
    }
  }, [isGenerating]);

  // Watch for new USER transcript segments in mock-interview mode
  useEffect(() => {
    if (view !== 'meeting') return;
    const mode = useMeetingStore.getState().mode;
    if (mode !== 'mock-interview') return;

    // Only count user speech (not interviewer segments)
    const userSegments = segments.filter((s) => s.isFinal && s.speaker !== -1);
    if (userSegments.length === lastSegmentCountRef.current) return;
    lastSegmentCountRef.current = userSegments.length;

    if (isGenerating) return;

    // Find the last interviewer segment timestamp
    const lastInterviewer = [...segments].reverse().find(
      (s) => s.speaker === -1 && s.speakerLabel === 'Interviewer'
    );
    const lastInterviewerTime = lastInterviewer?.timestamp ?? 0;

    // Only trigger if there's user speech AFTER the last interviewer segment
    const userSpeechAfter = userSegments.filter((s) => s.timestamp > lastInterviewerTime);
    if (userSpeechAfter.length === 0) return;

    if (mockDebounceRef.current) clearTimeout(mockDebounceRef.current);
    mockDebounceRef.current = setTimeout(() => {
      const allSegs = useTranscriptStore.getState().segments;
      const freshLastInterviewer = [...allSegs].reverse().find(
        (s) => s.speaker === -1 && s.speakerLabel === 'Interviewer'
      );
      const freshInterviewerTime = freshLastInterviewer?.timestamp ?? 0;
      const freshUser = allSegs.filter(
        (s) => s.isFinal && s.speaker !== -1 && s.timestamp > freshInterviewerTime
      );
      const answerText = freshUser.map((s) => s.text).join(' ');
      if (answerText.trim()) {
        handleMockQuestion(answerText);
      }
    }, 3000);

    return () => {
      if (mockDebounceRef.current) clearTimeout(mockDebounceRef.current);
    };
  }, [view, segments, isGenerating, handleMockQuestion]);

  const handleRequestSuggestion = useCallback(async () => {
    const { apiKeys, mode, contextDocs, frameworks } = useMeetingStore.getState();
    console.log('[MeetingMind] Suggestion requested. Has API key:', !!apiKeys.anthropic, 'isGenerating:', isGenerating);
    if (!apiKeys.anthropic || isGenerating) return;

    // In mock-interview mode, Ctrl+Space is a nudge — send user speech after last interviewer
    if (mode === 'mock-interview') {
      const allSegs = useTranscriptStore.getState().segments;
      const lastInterviewer = [...allSegs].reverse().find(
        (s) => s.speaker === -1 && s.speakerLabel === 'Interviewer'
      );
      const lastInterviewerTime = lastInterviewer?.timestamp ?? 0;
      const userSpeech = allSegs.filter(
        (s) => s.isFinal && s.speaker !== -1 && s.timestamp > lastInterviewerTime
      );
      const answerText = userSpeech.map((s) => s.text).join(' ');
      return handleMockQuestion(answerText || null);
    }

    const currentSegments = useTranscriptStore.getState().segments;
    const finals = currentSegments.filter((s) => s.isFinal);
    console.log('[MeetingMind] Final segments:', finals.length);
    if (finals.length === 0) return;

    setIsGenerating(true);
    console.log('[MeetingMind] Calling Claude API with mode:', mode);

    const recentTranscript = finals
      .map((s) => `${s.speakerLabel || 'Speaker'}: ${s.text}`)
      .join('\n')
      .slice(-2000);

    const lastSegment = finals[finals.length - 1];
    const currentQuestion = lastSegment?.text || '';

    const suggestionId = crypto.randomUUID();
    suggestionRef.current = suggestionId;

    useTranscriptStore.getState().addSuggestion({
      id: suggestionId,
      text: 'Thinking...',
      timestamp: Date.now(),
      pinned: false,
      dismissed: false,
      triggerText: currentQuestion,
    });

    try {
      await generateSuggestion(
        apiKeys.anthropic,
        mode,
        contextDocs,
        frameworks,
        recentTranscript,
        currentQuestion,
        (streamedText) => {
          useTranscriptStore.getState().updateSuggestionText(suggestionId, streamedText);
        }
      );
    } catch (err) {
      console.error('[MeetingMind] Suggestion error:', err);
      useTranscriptStore.getState().updateSuggestionText(
        suggestionId,
        `Error: ${err instanceof Error ? err.message : 'Failed to generate suggestion'}`
      );
    } finally {
      setIsGenerating(false);
      suggestionRef.current = null;
    }
  }, [isGenerating, handleMockQuestion]);

  // Ctrl+Space keyboard shortcut
  useEffect(() => {
    if (view !== 'meeting') return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.ctrlKey && e.code === 'Space') {
        e.preventDefault();
        handleRequestSuggestion();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [view, handleRequestSuggestion]);

  const handleStart = useCallback(
    async (title: string) => {
      const mode = useMeetingStore.getState().mode;
      useMeetingStore.getState().clearMockHistory();
      setCaptureError(null);
      startMeeting(title);
      setView('meeting');

      // Get the meeting that was just created and persist it
      const meeting = useMeetingStore.getState().currentMeeting;
      if (meeting) {
        setCurrentMeetingId(meeting.id);
        await saveMeeting(meeting);
        await setInProgressMeeting(meeting.id);
      }

      const [tab] = await chrome.tabs.query({
        active: true,
        currentWindow: true,
      });
      if (tab?.id) {
        const source = useMeetingStore.getState().transcriptionSource;
        chrome.runtime.sendMessage({ type: 'START_CAPTURE', tabId: tab.id, source });
      }

      // In mock-interview mode, generate first question immediately
      if (mode === 'mock-interview') {
        setTimeout(() => handleMockQuestion(null), 500);
      }
    },
    [startMeeting, handleMockQuestion]
  );

  const handleImport = useCallback(
    async (title: string) => {
      const { importFile, apiKeys, startImportedMeeting } = useMeetingStore.getState();
      if (!importFile || !apiKeys.deepgram) return;

      clearTranscript();
      startImportedMeeting(title);
      setImportStatus('Reading file...');
      setView('importing');

      const meeting = useMeetingStore.getState().currentMeeting;
      if (meeting) {
        setCurrentMeetingId(meeting.id);
        await saveMeeting(meeting);
      }

      try {
        const buffer = await importFile.arrayBuffer();
        const segments = await transcribeFile(buffer, apiKeys.deepgram, (status) => {
          setImportStatus(status);
        });

        const store = useTranscriptStore.getState();
        for (const seg of segments) {
          store.addSegment(seg);
        }

        useMeetingStore.getState().endMeeting();
        const updatedMeeting = useMeetingStore.getState().currentMeeting;
        if (updatedMeeting) {
          await saveMeeting(updatedMeeting);
        }

        setImportStatus(null);
        setView('summary');
      } catch (err) {
        setImportStatus(`Error: ${err instanceof Error ? err.message : 'Transcription failed'}`);
      }
    },
    [clearTranscript]
  );

  const handleStop = useCallback(async () => {
    chrome.runtime.sendMessage({ type: 'STOP_CAPTURE' });
    endMeeting();

    // Save final meeting state and clear in-progress flag
    const meeting = useMeetingStore.getState().currentMeeting;
    if (meeting) {
      await saveMeeting(meeting);
    }
    await setInProgressMeeting(null);
    setCurrentMeetingId(null);

    setView('summary');
  }, [endMeeting]);

  const handleNewMeeting = useCallback(async () => {
    clearTranscript();
    useMeetingStore.getState().clearMockHistory();
    await setInProgressMeeting(null);
    setCurrentMeetingId(null);
    setView('setup');
    setCopyLabel('Copy Transcript');
  }, [clearTranscript]);

  const handleCopy = useCallback(() => {
    if (!currentMeeting) return;
    const md = formatTranscriptMarkdown(
      currentMeeting.title,
      currentMeeting.startTime,
      currentMeeting.endTime,
      segments
    );
    navigator.clipboard.writeText(md);
    setCopyLabel('Copied!');
    setTimeout(() => setCopyLabel('Copy Transcript'), 2000);
  }, [currentMeeting, segments]);

  const handleDownload = useCallback(() => {
    if (!currentMeeting) return;
    const md = formatTranscriptMarkdown(
      currentMeeting.title,
      currentMeeting.startTime,
      currentMeeting.endTime,
      segments
    );
    const dateStr = new Date(currentMeeting.startTime)
      .toISOString()
      .slice(0, 10);
    const slug = currentMeeting.title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '');
    const filename = `${dateStr}-${slug}.md`;

    const blob = new Blob([md], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }, [currentMeeting, segments]);

  const handlePopOut = useCallback(() => {
    chrome.runtime.sendMessage({ type: 'POP_OUT' });
  }, []);

  const activeSuggestions = suggestions.filter((s) => !s.dismissed);
  const hasAnthropicKey = !!apiKeys.anthropic;
  const isMockInterview = useMeetingStore((s) => s.mode) === 'mock-interview';

  return (
    <div className="h-screen flex flex-col bg-gray-950 text-gray-100">
      {/* Header */}
      <header className="flex items-center justify-between px-4 py-3 border-b border-gray-800">
        <h1 className="text-lg font-semibold tracking-tight">MeetingMind</h1>
        <div className="flex gap-1.5">
          {view === 'meeting' && (
            <button
              onClick={handleStop}
              className="px-3 py-1 text-sm bg-red-600 hover:bg-red-700 rounded-md transition-colors"
            >
              Stop
            </button>
          )}
          {/* Pop-out button (hide if already popped out) */}
          {!isPopout.current && (
            <button
              onClick={handlePopOut}
              className="p-1.5 text-gray-400 hover:text-gray-200 transition-colors"
              title="Pop out to window"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
              </svg>
            </button>
          )}
          <button
            onClick={() => setView(view === 'settings' ? 'setup' : 'settings')}
            className="p-1.5 text-gray-400 hover:text-gray-200 transition-colors"
            title="Settings"
          >
            <svg
              className="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
          </button>
        </div>
      </header>

      {/* Main content */}
      <div className="flex-1 overflow-hidden flex flex-col">
        {/* Recovery prompt */}
        {recoveryPrompt && (
          <div className="absolute inset-0 bg-gray-950/95 z-50 flex items-center justify-center p-4">
            <div className="bg-gray-900 border border-gray-700 rounded-lg p-6 max-w-sm">
              <h2 className="text-lg font-semibold mb-2">Recover Meeting?</h2>
              <p className="text-sm text-gray-400 mb-4">
                Found an interrupted meeting: <strong className="text-gray-200">{recoveryPrompt.title}</strong>
                <br />
                <span className="text-xs">
                  Started {new Date(recoveryPrompt.startTime).toLocaleString()}
                </span>
              </p>
              <div className="flex gap-2">
                <button
                  onClick={handleRecover}
                  className="flex-1 px-3 py-2 text-sm bg-blue-600 hover:bg-blue-700 rounded-md transition-colors"
                >
                  Recover
                </button>
                <button
                  onClick={handleDiscardRecovery}
                  className="flex-1 px-3 py-2 text-sm bg-gray-700 hover:bg-gray-600 rounded-md transition-colors"
                >
                  Discard
                </button>
              </div>
            </div>
          </div>
        )}

        {view === 'settings' && <Settings onBack={() => setView('setup')} />}
        {view === 'setup' && <MeetingSetup onStart={handleStart} onImport={handleImport} />}
        {view === 'meeting' && (
          <>
            {/* Capture error banner */}
            {captureError && (
              <div className="px-4 py-2 bg-red-900/50 border-b border-red-800 text-sm text-red-200">
                {captureError}
              </div>
            )}

            {/* Status bar */}
            <div className="px-4 py-2 border-b border-gray-800 flex items-center gap-2 text-sm">
              <span
                className={`w-2 h-2 rounded-full ${isCapturing ? 'bg-green-500 animate-pulse' : captureError ? 'bg-red-500' : 'bg-gray-600'}`}
              />
              <span className="text-gray-400">
                {isCapturing ? 'Recording' : captureError ? 'Capture failed' : 'Not recording'}
              </span>
              {isCapturing && (
                <span className="text-xs px-1.5 py-0.5 rounded bg-gray-800 text-gray-500">
                  {transcriptionSource === 'tactiq' ? 'Tactiq' : 'Deepgram'}
                </span>
              )}
              {isMockInterview && (
                <span className="text-xs px-1.5 py-0.5 rounded bg-purple-900/50 text-purple-300">
                  Mock Interview
                </span>
              )}
              {currentMeeting && (
                <span className="ml-auto text-gray-500 truncate">
                  {currentMeeting.title}
                </span>
              )}
            </div>

            {/* Transcript */}
            <div className="flex-1 overflow-y-auto">
              <Transcript segments={segments} />
            </div>

            {/* Suggestions */}
            {activeSuggestions.length > 0 && (
              <div className="border-t border-gray-800 max-h-[45%] overflow-y-auto">
                <div className="sticky top-0 bg-gray-950 px-3 py-1.5 flex items-center justify-between border-b border-gray-800/50">
                  <span className="text-[10px] font-medium text-gray-500 uppercase tracking-wider">
                    Suggestions ({activeSuggestions.length})
                  </span>
                </div>
                <div className="py-1.5">
                  {activeSuggestions.map((s) => (
                    <SuggestionCard key={s.id} suggestion={s} />
                  ))}
                </div>
              </div>
            )}

            {/* Suggestion trigger + hint */}
            <div className="px-4 py-2 border-t border-gray-800 flex items-center gap-2">
              {hasAnthropicKey ? (
                <>
                  <button
                    onClick={handleRequestSuggestion}
                    disabled={isGenerating || (!isMockInterview && segments.filter((s) => s.isFinal).length === 0)}
                    className="px-3 py-1.5 text-xs bg-emerald-700 hover:bg-emerald-600 disabled:opacity-40 disabled:cursor-not-allowed rounded-md transition-colors"
                  >
                    {isGenerating ? 'Generating...' : isMockInterview ? 'Next Question' : 'Get Suggestion'}
                  </button>
                  <span className="text-xs text-gray-600">Ctrl+Space</span>
                  {isMockInterview && !isGenerating && segments.filter((s) => s.isFinal).length > 0 && (
                    <span className="text-[10px] text-gray-600">Auto-triggers after you speak</span>
                  )}
                </>
              ) : (
                <span className="text-xs text-gray-600">
                  Set Anthropic API key in Settings for AI suggestions
                </span>
              )}
            </div>
          </>
        )}
        {view === 'importing' && (
          <div className="flex-1 flex flex-col items-center justify-center px-4">
            <div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin mb-4" />
            <p className="text-sm text-gray-300 mb-1">Transcribing recording...</p>
            {importStatus && (
              <p className={`text-xs ${importStatus.startsWith('Error') ? 'text-red-400' : 'text-gray-500'}`}>
                {importStatus}
              </p>
            )}
            {importStatus?.startsWith('Error') && (
              <button
                onClick={() => { setImportStatus(null); setView('setup'); }}
                className="mt-4 px-4 py-2 text-sm bg-gray-800 hover:bg-gray-700 rounded-md transition-colors"
              >
                Back to Setup
              </button>
            )}
          </div>
        )}
        {view === 'summary' && (
          <>
            {/* Summary header */}
            <div className="px-4 py-3 border-b border-gray-800">
              <h2 className="text-base font-medium">
                {currentMeeting?.title || 'Meeting'}
              </h2>
              {currentMeeting && (
                <p className="text-xs text-gray-500 mt-0.5">
                  {new Date(currentMeeting.startTime).toLocaleDateString()} &middot;{' '}
                  {formatDuration(currentMeeting.startTime, currentMeeting.endTime)} &middot;{' '}
                  {segments.filter((s) => s.isFinal).length} segments
                </p>
              )}
            </div>

            {/* Transcript (read-only) */}
            <div className="flex-1 overflow-y-auto">
              <Transcript segments={segments} />
            </div>

            {/* Action buttons */}
            <div className="px-4 py-3 border-t border-gray-800 flex gap-2">
              <button
                onClick={handleCopy}
                className="flex-1 px-3 py-2 text-sm bg-gray-800 hover:bg-gray-700 rounded-md transition-colors"
              >
                {copyLabel}
              </button>
              <button
                onClick={handleDownload}
                className="flex-1 px-3 py-2 text-sm bg-gray-800 hover:bg-gray-700 rounded-md transition-colors"
              >
                Download .md
              </button>
            </div>
            <div className="px-4 pb-3">
              <button
                onClick={handleNewMeeting}
                className="w-full px-3 py-2 text-sm bg-blue-600 hover:bg-blue-700 rounded-md transition-colors"
              >
                New Meeting
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
