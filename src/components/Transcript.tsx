import React, { useEffect, useRef, useMemo } from 'react';
import { marked } from 'marked';
import type { TranscriptSegment } from '../types';
import { useTranscriptStore } from '../stores/transcript-store';

marked.setOptions({ breaks: true, gfm: true });

interface Props {
  segments: TranscriptSegment[];
}

export function Transcript({ segments }: Props) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const speakers = useTranscriptStore((s) => s.speakers);
  const setSpeakerLabel = useTranscriptStore((s) => s.setSpeakerLabel);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [segments]);

  if (segments.length === 0) {
    return (
      <div className="flex items-center justify-center h-full text-gray-600 text-sm">
        Waiting for speech...
      </div>
    );
  }

  // Group consecutive segments by speaker
  const grouped: { speaker: number; speakerLabel?: string; texts: string[]; isInterviewer: boolean }[] = [];
  for (const seg of segments) {
    if (!seg.isFinal) continue;
    const last = grouped[grouped.length - 1];
    const label = seg.speakerLabel || undefined;
    const isInterviewer = seg.speaker === -1 || seg.speakerLabel === 'Interviewer';
    const sameAsPrev = last && (
      label ? last.speakerLabel === label : last.speaker === seg.speaker
    );
    if (sameAsPrev) {
      // For interviewer, replace text (streaming updates same segment)
      if (isInterviewer) {
        last.texts = [seg.text];
      } else {
        last.texts.push(seg.text);
      }
    } else {
      grouped.push({ speaker: seg.speaker, speakerLabel: label, texts: [seg.text], isInterviewer });
    }
  }

  const handleSpeakerClick = (speakerId: number) => {
    if (speakerId === -1) return;
    const current = speakers[speakerId] || `Speaker ${speakerId}`;
    const label = prompt(`Label for Speaker ${speakerId}:`, current);
    if (label) setSpeakerLabel(speakerId, label);
  };

  return (
    <div className="px-4 py-3 space-y-3">
      {grouped.map((group, i) => {
        const label = group.speakerLabel || speakers[group.speaker] || `Speaker ${group.speaker}`;
        const joinedText = group.texts.join(' ');

        if (group.isInterviewer) {
          return <InterviewerBlock key={i} text={joinedText} />;
        }

        return (
          <div key={i}>
            <button
              onClick={() => handleSpeakerClick(group.speaker)}
              className="text-xs font-medium text-blue-400 hover:text-blue-300 transition-colors mb-0.5"
            >
              {label}
            </button>
            <p className="text-sm text-gray-200 leading-relaxed">
              {joinedText}
            </p>
          </div>
        );
      })}
      <div ref={bottomRef} />
    </div>
  );
}

function InterviewerBlock({ text }: { text: string }) {
  const html = useMemo(() => {
    if (text === 'Thinking...') return '';
    return marked.parse(text, { async: false }) as string;
  }, [text]);

  return (
    <div className="rounded-lg border border-purple-800/50 bg-purple-950/20 p-3">
      <div className="text-xs font-medium text-purple-400 mb-1">Interviewer</div>
      {text === 'Thinking...' ? (
        <div className="text-sm text-gray-400 animate-pulse">Thinking...</div>
      ) : (
        <div
          className="suggestion-md text-sm text-gray-200 leading-relaxed"
          dangerouslySetInnerHTML={{ __html: html }}
        />
      )}
    </div>
  );
}
