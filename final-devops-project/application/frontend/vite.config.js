import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// `npm run dev` proxies /api to a backend on localhost:8000
// (uvicorn app.main:app --port 8000). In containers nginx does the proxying.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { '/api': 'http://localhost:8000' },
  },
  build: { sourcemap: false },
});
