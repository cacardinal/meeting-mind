import { defineConfig } from 'wxt';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  srcDir: 'src',
  modules: ['@wxt-dev/module-react'],
  vite: () => ({
    plugins: [tailwindcss()],
  }),
  manifest: {
    name: 'MeetingMind',
    description: 'Real-time meeting assistant with transcription and AI suggestions',
    version: '0.1.0',
    permissions: [
      'tabCapture',
      'offscreen',
      'sidePanel',
      'storage',
      'activeTab',
    ],
    host_permissions: ['https://api.deepgram.com/*'],
    action: {},
  },
});
