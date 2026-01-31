import React, { useEffect, useState } from 'react';
import { useMeetingStore } from '../stores/meeting-store';

interface Props {
  onBack: () => void;
}

export function Settings({ onBack }: Props) {
  const { apiKeys, setApiKeys } = useMeetingStore();
  const [deepgram, setDeepgram] = useState(apiKeys.deepgram);
  const [anthropic, setAnthropic] = useState(apiKeys.anthropic);
  const [saved, setSaved] = useState(false);

  const handleSave = async () => {
    setApiKeys({ deepgram, anthropic });
    // Persist to chrome.storage.local
    await chrome.storage.local.set({
      apiKeys: { deepgram, anthropic },
    });
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  useEffect(() => {
    // Load saved keys
    chrome.storage.local.get('apiKeys', (result) => {
      if (result.apiKeys) {
        setDeepgram(result.apiKeys.deepgram || '');
        setAnthropic(result.apiKeys.anthropic || '');
        setApiKeys(result.apiKeys);
      }
    });
  }, []);

  return (
    <div className="flex-1 overflow-y-auto px-4 py-4 space-y-5">
      <button
        onClick={onBack}
        className="text-sm text-gray-400 hover:text-gray-200 transition-colors"
      >
        &larr; Back
      </button>

      <h2 className="text-sm font-medium text-gray-300">API Keys</h2>

      <div>
        <label className="block text-xs font-medium text-gray-400 mb-1.5">
          Deepgram API Key
          <span className="text-gray-600 font-normal ml-1">(optional with Tactiq)</span>
        </label>
        <input
          type="password"
          value={deepgram}
          onChange={(e) => setDeepgram(e.target.value)}
          placeholder="Enter Deepgram API key"
          className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded-md text-sm text-gray-100 placeholder:text-gray-600 focus:outline-none focus:border-blue-500"
        />
        <p className="text-xs text-gray-600 mt-1">
          Only needed if using Deepgram transcription. Get one at deepgram.com (200 free min/month)
        </p>
      </div>

      <div>
        <label className="block text-xs font-medium text-gray-400 mb-1.5">
          Anthropic API Key
        </label>
        <input
          type="password"
          value={anthropic}
          onChange={(e) => setAnthropic(e.target.value)}
          placeholder="Enter Anthropic API key"
          className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded-md text-sm text-gray-100 placeholder:text-gray-600 focus:outline-none focus:border-blue-500"
        />
      </div>

      <button
        onClick={handleSave}
        className="w-full py-2.5 bg-blue-600 hover:bg-blue-700 text-sm font-medium rounded-md transition-colors"
      >
        {saved ? 'Saved!' : 'Save Keys'}
      </button>
    </div>
  );
}
