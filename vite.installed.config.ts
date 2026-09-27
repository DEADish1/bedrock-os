import { fileURLToPath } from 'node:url';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/postcss';
import { defineConfig } from 'vite';

// Separate from the hosted preview: the image serves static assets through its
// own same-origin gateway, with no Cloudflare or Sites runtime dependency.
export default defineConfig({
  root: fileURLToPath(new URL('./management-ui', import.meta.url)),
  publicDir: fileURLToPath(new URL('./public', import.meta.url)),
  base: '/',
  plugins: [react()],
  css: { postcss: { plugins: [tailwindcss()] } },
  build: {
    outDir: fileURLToPath(new URL('./dist/management-ui', import.meta.url)),
    emptyOutDir: true,
    sourcemap: false,
  },
});
