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
      'desktopCapture',
      'offscreen',
      'sidePanel',
      'storage',
      'tabs',
    ],
    // <all_urls> for tab capture; api.deepgram.com is covered by it
    host_permissions: ['<all_urls>', 'https://api.deepgram.com/*'],
    action: {},
  },
});
