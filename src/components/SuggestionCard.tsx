import React, { useMemo, useState } from 'react';
import { marked } from 'marked';
import type { Suggestion } from '../types';
import { useTranscriptStore } from '../stores/transcript-store';

// Configure marked for compact output
marked.setOptions({
  breaks: true,
  gfm: true,
});

interface Props {
  suggestion: Suggestion;
}

export function SuggestionCard({ suggestion }: Props) {
  const dismissSuggestion = useTranscriptStore((s) => s.dismissSuggestion);
  const pinSuggestion = useTranscriptStore((s) => s.pinSuggestion);
  const [collapsed, setCollapsed] = useState(false);

  const html = useMemo(() => {
    if (suggestion.text === 'Thinking...') return '';
    return marked.parse(suggestion.text, { async: false }) as string;
  }, [suggestion.text]);

  const copyToClipboard = () => {
    navigator.clipboard.writeText(suggestion.text);
  };

  const isLoading = suggestion.text === 'Thinking...';

  return (
    <div
      className={`mx-3 mb-2 rounded-lg border ${
        suggestion.pinned
          ? 'border-blue-600 bg-blue-950/30'
          : 'border-gray-800 bg-gray-900'
      }`}
    >
      {/* Header bar — always visible */}
      <div
        className="flex items-center gap-2 px-3 py-1.5 cursor-pointer select-none"
        onClick={() => !isLoading && setCollapsed(!collapsed)}
      >
        <span className="text-[10px] text-gray-600">{collapsed ? '▶' : '▼'}</span>
        {suggestion.framework && (
          <span className="text-[10px] font-medium text-emerald-400">
            {suggestion.framework}
          </span>
        )}
        <span className="text-[10px] text-gray-500 truncate flex-1">
          {isLoading ? 'Generating...' : suggestion.triggerText || 'Suggestion'}
        </span>
        <div className="flex gap-1.5 ml-auto" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={copyToClipboard}
            className="text-[10px] text-gray-600 hover:text-gray-300 transition-colors"
            title="Copy"
          >
            Copy
          </button>
          <button
            onClick={() => pinSuggestion(suggestion.id)}
            className={`text-[10px] transition-colors ${suggestion.pinned ? 'text-blue-400' : 'text-gray-600 hover:text-blue-400'}`}
            title={suggestion.pinned ? 'Unpin' : 'Pin'}
          >
            {suggestion.pinned ? 'Pinned' : 'Pin'}
          </button>
          <button
            onClick={() => dismissSuggestion(suggestion.id)}
            className="text-[10px] text-gray-600 hover:text-red-400 transition-colors"
            title="Dismiss"
          >
            ×
          </button>
        </div>
      </div>

      {/* Body — collapsible */}
      {!collapsed && (
        <div className="px-3 pb-2">
          {isLoading ? (
            <div className="text-xs text-gray-500 animate-pulse">Thinking...</div>
          ) : (
            <div
              className="suggestion-md text-xs text-gray-200 leading-relaxed"
              dangerouslySetInnerHTML={{ __html: html }}
            />
          )}
        </div>
      )}
    </div>
  );
}
